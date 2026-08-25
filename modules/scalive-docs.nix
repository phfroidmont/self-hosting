{ config, lib, pkgs, ... }:

let
  cfg = config.custom.services.scalive-docs;
  runtimeUser = "scalive-docs";
  deployUser = "scalive-docs-deploy";
  stateDir = "/var/lib/scalive-docs";
  releasesDir = "${stateDir}/releases";
  currentJar = "${stateDir}/current/scalive-docs.jar";
  stagingDir = "/var/lib/scalive-docs-deploy/staging";
  lockFile = "/run/lock/scalive-docs-deploy.lock";
  generationFile = "${stateDir}/deployment-generation";
  maxUploadSize = 268435456;

  serviceWrapper = pkgs.writeShellScript "scalive-docs-start" ''
    set -eu
    SCALIVE_TOKEN_SECRET="$(${pkgs.coreutils}/bin/cat "$CREDENTIALS_DIRECTORY/token-secret")"
    export SCALIVE_TOKEN_SECRET
    exec ${pkgs.jre}/bin/java -jar ${currentJar}
  '';

  activateHelper = pkgs.writeShellScript "scalive-docs-activate" ''
    set -euo pipefail

    revision="''${1-}"
    generation="''${2-}"
    if [[ $# -ne 2 || ! "$revision" =~ ^[0-9a-f]{40}$ || ! "$generation" =~ ^[1-9][0-9]*$ || ''${#generation} -gt 18 ]]; then
      ${pkgs.coreutils}/bin/printf '%s\n' "invalid revision or deployment generation" >&2
      exit 64
    fi

    exec 9>${lockFile}
    ${pkgs.util-linux}/bin/flock -x 9
    ${pkgs.findutils}/bin/find ${releasesDir} -mindepth 1 -maxdepth 1 -type d -name '.*.new' \
      -exec ${pkgs.coreutils}/bin/rm -rf -- {} +

    switch_to() {
      local release=$1
      ${pkgs.coreutils}/bin/rm -f -- ${stateDir}/current.next
      ${pkgs.coreutils}/bin/ln -s -- "$release" ${stateDir}/current.next
      ${pkgs.coreutils}/bin/mv -Tf -- ${stateDir}/current.next ${stateDir}/current
    }

    wait_for_revision() {
      local expected_revision=$1
      ${pkgs.coreutils}/bin/printf %s "$expected_revision" > /run/scalive-docs-expected-health
      for (( attempt = 1; attempt <= 30; attempt++ )); do
        if ${pkgs.curl}/bin/curl --fail --silent --show-error --connect-timeout 1 --max-time 2 \
          --output /run/scalive-docs-health "http://127.0.0.1:${toString cfg.port}/health" \
          && ${pkgs.diffutils}/bin/cmp -s /run/scalive-docs-expected-health /run/scalive-docs-health; then
          return 0
        fi
        ${pkgs.coreutils}/bin/sleep 1
      done
      return 1
    }

    source_jar=${stagingDir}/$revision.jar
    checksum_file=${stagingDir}/$revision.sha256
    target=${releasesDir}/$revision
    target_jar=$target/scalive-docs.jar

    previous_target=""
    if [[ -L ${stateDir}/current ]]; then
      previous_target=$(${pkgs.coreutils}/bin/readlink -- ${stateDir}/current)
      if [[ ! "$previous_target" =~ ^${releasesDir}/[0-9a-f]{40}$ ]]; then
        ${pkgs.coreutils}/bin/printf '%s\n' "current release link is invalid" >&2
        exit 65
      fi
    elif [[ -e ${stateDir}/current ]]; then
      ${pkgs.coreutils}/bin/printf '%s\n' "current release is not a symlink" >&2
      exit 65
    fi

    if [[ -e ${generationFile} ]]; then
      if [[ ! -f ${generationFile} || -L ${generationFile} ]]; then
        ${pkgs.coreutils}/bin/printf '%s\n' "deployment generation file is invalid" >&2
        exit 65
      fi
      current_generation=$(${pkgs.coreutils}/bin/cat -- ${generationFile})
      if [[ ! "$current_generation" =~ ^[1-9][0-9]*$ || ''${#current_generation} -gt 18 ]]; then
        ${pkgs.coreutils}/bin/printf '%s\n' "recorded deployment generation is invalid" >&2
        exit 65
      fi
      if (( generation < current_generation )); then
        ${pkgs.coreutils}/bin/printf '%s\n' "deployment generation is stale" >&2
        exit 65
      fi
      if (( generation == current_generation )); then
        if [[ "$previous_target" == "$target" ]] && wait_for_revision "$revision"; then
          ${pkgs.coreutils}/bin/rm -f -- "$source_jar" "$checksum_file"
          exit 0
        fi
        ${pkgs.coreutils}/bin/printf '%s\n' "deployment generation was already used" >&2
        exit 65
      fi
    fi

    new_target=${releasesDir}/.$revision.new
    created_target=0
    switched=0
    committed=0

    cleanup_on_exit() {
      local status=$?
      local current_target=""
      trap - EXIT
      set +e
      ${pkgs.coreutils}/bin/rm -rf -- "$new_target"
      ${pkgs.coreutils}/bin/rm -f -- ${generationFile}.new
      if (( status != 0 )); then
        if (( switched && !committed )); then
          if [[ -n "$previous_target" ]]; then
            previous_revision=''${previous_target##*/}
            if ! switch_to "$previous_target"; then
              ${pkgs.coreutils}/bin/printf '%s\n' "unable to restore previous release link" >&2
            elif ! ${pkgs.systemd}/bin/systemctl restart scalive-docs.service || ! wait_for_revision "$previous_revision"; then
              ${pkgs.coreutils}/bin/printf '%s\n' "rollback health check failed" >&2
            fi
          else
            ${pkgs.coreutils}/bin/rm -f -- ${stateDir}/current
            ${pkgs.systemd}/bin/systemctl stop scalive-docs.service
          fi
        fi
        if [[ -L ${stateDir}/current ]]; then
          current_target=$(${pkgs.coreutils}/bin/readlink -- ${stateDir}/current)
        fi
        if (( created_target )) && [[ "$current_target" != "$target" ]]; then
          ${pkgs.coreutils}/bin/rm -rf -- "$target"
        fi
        ${pkgs.coreutils}/bin/rm -f -- "$source_jar" "$checksum_file"
      fi
      exit "$status"
    }
    trap cleanup_on_exit EXIT

    if [[ ! -f "$source_jar" || -L "$source_jar" || ! -f "$checksum_file" || -L "$checksum_file" ]]; then
      ${pkgs.coreutils}/bin/printf '%s\n' "staged release is missing or invalid" >&2
      exit 65
    fi
    if [[ $(${pkgs.coreutils}/bin/stat -c %s -- "$checksum_file") -ne 65 ]]; then
      ${pkgs.coreutils}/bin/printf '%s\n' "invalid recorded checksum" >&2
      exit 65
    fi
    recorded_checksum=$(${pkgs.coreutils}/bin/cat -- "$checksum_file")
    if [[ ! "$recorded_checksum" =~ ^[0-9a-f]{64}$ ]]; then
      ${pkgs.coreutils}/bin/printf '%s\n' "invalid recorded checksum" >&2
      exit 65
    fi
    source_checksum=$(${pkgs.coreutils}/bin/sha256sum -- "$source_jar")
    source_checksum=''${source_checksum%% *}
    if [[ "$source_checksum" != "$recorded_checksum" ]]; then
      ${pkgs.coreutils}/bin/printf '%s\n' "staged checksum mismatch" >&2
      exit 65
    fi

    if [[ -e "$target" || -L "$target" ]]; then
      if [[ ! -d "$target" || -L "$target" || ! -f "$target_jar" || -L "$target_jar" ]]; then
        ${pkgs.coreutils}/bin/printf '%s\n' "existing release is invalid" >&2
        exit 65
      fi
      target_checksum=$(${pkgs.coreutils}/bin/sha256sum -- "$target_jar")
      target_checksum=''${target_checksum%% *}
      if [[ "$target_checksum" != "$recorded_checksum" ]]; then
        ${pkgs.coreutils}/bin/printf '%s\n' "revision already exists with different bytes" >&2
        exit 65
      fi
    else
      ${pkgs.coreutils}/bin/rm -rf -- "$new_target"
      ${pkgs.coreutils}/bin/install -d -o root -g ${runtimeUser} -m 0750 -- "$new_target"
      ${pkgs.coreutils}/bin/install -o root -g ${runtimeUser} -m 0640 -- "$source_jar" "$new_target/scalive-docs.jar"
      installed_checksum=$(${pkgs.coreutils}/bin/sha256sum -- "$new_target/scalive-docs.jar")
      installed_checksum=''${installed_checksum%% *}
      if [[ "$installed_checksum" != "$recorded_checksum" ]]; then
        ${pkgs.coreutils}/bin/rm -rf -- "$new_target"
        ${pkgs.coreutils}/bin/printf '%s\n' "copied checksum mismatch" >&2
        exit 65
      fi
      ${pkgs.coreutils}/bin/mv -T -- "$new_target" "$target"
      created_target=1
    fi

    switch_to "$target"
    switched=1
    if ! ${pkgs.systemd}/bin/systemctl restart scalive-docs.service || ! wait_for_revision "$revision"; then
      ${pkgs.coreutils}/bin/printf '%s\n' "activation failed" >&2
      exit 69
    fi
    if ! {
      ${pkgs.coreutils}/bin/printf '%s\n' "$generation" > ${generationFile}.new \
        && ${pkgs.coreutils}/bin/chown root:root ${generationFile}.new \
        && ${pkgs.coreutils}/bin/chmod 0640 ${generationFile}.new \
        && ${pkgs.coreutils}/bin/mv -Tf -- ${generationFile}.new ${generationFile}
    }; then
      ${pkgs.coreutils}/bin/printf '%s\n' "unable to persist deployment generation" >&2
      exit 69
    fi
    committed=1
    ${pkgs.coreutils}/bin/rm -f -- "$source_jar" "$checksum_file"

    retained_count=1
    if [[ -n "$previous_target" && "$previous_target" != "$target" ]]; then
      retained_count=2
    fi
    while IFS= read -r release_path; do
      release_name=''${release_path##*/}
      if [[ ! "$release_name" =~ ^[0-9a-f]{40}$ || ! -d "$release_path" || -L "$release_path" ]]; then
        continue
      fi
      if [[ "$release_path" == "$target" || "$release_path" == "$previous_target" ]]; then
        continue
      fi
      if (( retained_count < 5 )); then
        retained_count=$((retained_count + 1))
      else
        ${pkgs.coreutils}/bin/rm -rf -- "$release_path"
      fi
    done < <(
      ${pkgs.findutils}/bin/find ${releasesDir} -mindepth 1 -maxdepth 1 -type d -printf '%T@ %p\n' \
        | ${pkgs.coreutils}/bin/sort -nr \
        | ${pkgs.coreutils}/bin/cut -d ' ' -f 2-
    )
  '';

  deployCommand = pkgs.writeShellScript "scalive-docs-deploy" ''
    set -euo pipefail

    command="''${SSH_ORIGINAL_COMMAND-}"
    if [[ "$command" =~ ^upload\ ([0-9a-f]{40})\ (0|[1-9][0-9]*)\ ([0-9a-f]{64})$ ]]; then
      revision=''${BASH_REMATCH[1]}
      size=''${BASH_REMATCH[2]}
      expected_checksum=''${BASH_REMATCH[3]}
      if (( ''${#size} > 9 || size > ${toString maxUploadSize} )); then
        ${pkgs.coreutils}/bin/printf '%s\n' "upload is too large" >&2
        exit 64
      fi

      exec 9>${lockFile}
      ${pkgs.util-linux}/bin/flock -x 9
      partial=${stagingDir}/$revision.upload
      trailing=${stagingDir}/$revision.trailing
      checksum_partial=${stagingDir}/$revision.sha256.new
      trap '${pkgs.coreutils}/bin/rm -f -- "$partial" "$trailing" "$checksum_partial"' EXIT

      ${pkgs.findutils}/bin/find ${stagingDir} -mindepth 1 -maxdepth 1 \( -type f -o -type l \) -delete

      if ! ${pkgs.coreutils}/bin/timeout 300s ${pkgs.coreutils}/bin/dd \
        iflag=count_bytes,fullblock bs=1M count="$size" of="$partial" status=none; then
        ${pkgs.coreutils}/bin/printf '%s\n' "upload timed out" >&2
        exit 65
      fi
      if [[ $(${pkgs.coreutils}/bin/stat -c %s -- "$partial") -ne "$size" ]]; then
        ${pkgs.coreutils}/bin/printf '%s\n' "short upload" >&2
        exit 65
      fi
      if ! ${pkgs.coreutils}/bin/timeout 5s ${pkgs.coreutils}/bin/dd bs=1 count=1 of="$trailing" status=none; then
        ${pkgs.coreutils}/bin/printf '%s\n' "upload stream did not end" >&2
        exit 65
      fi
      if [[ $(${pkgs.coreutils}/bin/stat -c %s -- "$trailing") -ne 0 ]]; then
        ${pkgs.coreutils}/bin/printf '%s\n' "trailing upload data" >&2
        exit 65
      fi

      actual_checksum=$(${pkgs.coreutils}/bin/sha256sum -- "$partial")
      actual_checksum=''${actual_checksum%% *}
      if [[ "$actual_checksum" != "$expected_checksum" ]]; then
        ${pkgs.coreutils}/bin/printf '%s\n' "upload checksum mismatch" >&2
        exit 65
      fi
      ${pkgs.coreutils}/bin/chmod 0600 -- "$partial"
      ${pkgs.coreutils}/bin/printf '%s\n' "$actual_checksum" > "$checksum_partial"
      ${pkgs.coreutils}/bin/mv -f -- "$partial" "${stagingDir}/$revision.jar"
      ${pkgs.coreutils}/bin/mv -f -- "$checksum_partial" "${stagingDir}/$revision.sha256"
      ${pkgs.coreutils}/bin/printf '%s\n' "uploaded $revision"
    elif [[ "$command" =~ ^activate\ ([0-9a-f]{40})\ ([1-9][0-9]*)$ ]]; then
      revision=''${BASH_REMATCH[1]}
      generation=''${BASH_REMATCH[2]}
      if (( ''${#generation} > 18 )); then
        ${pkgs.coreutils}/bin/printf '%s\n' "invalid deployment generation" >&2
        exit 64
      fi
      exec ${pkgs.sudo}/bin/sudo ${activateHelper} "$revision" "$generation"
    else
      ${pkgs.coreutils}/bin/printf '%s\n' "unsupported command" >&2
      exit 64
    fi
  '';
in
{
  options.custom.services.scalive-docs = {
    enable = lib.mkEnableOption "Scalive Docs";

    domain = lib.mkOption {
      type = lib.types.str;
      default = "scalive.dev";
      description = "Public domain serving Scalive Docs.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 8080;
      description = "Loopback port on which Scalive Docs listens.";
    };

    signingSecretFile = lib.mkOption {
      type = lib.types.path;
      description = "File containing the token signing secret.";
    };

    deployAuthorizedKey = lib.mkOption {
      type = lib.types.str;
      description = "SSH public key authorized to upload and activate releases.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.deployAuthorizedKey != "";
        message = "custom.services.scalive-docs.deployAuthorizedKey must not be empty";
      }
    ];

    users.groups.${runtimeUser} = { };
    users.groups.${deployUser} = { };
    users.users.${runtimeUser} = {
      isSystemUser = true;
      group = runtimeUser;
      home = stateDir;
    };
    users.users.${deployUser} = {
      isSystemUser = true;
      group = deployUser;
      home = "/var/lib/scalive-docs-deploy";
      shell = "${pkgs.bashInteractive}/bin/bash";
      openssh.authorizedKeys.keys = [
        ''restrict,no-pty,no-port-forwarding,no-agent-forwarding,no-X11-forwarding,command="${deployCommand}" ${cfg.deployAuthorizedKey}''
      ];
    };

    systemd.tmpfiles.rules = [
      "d ${stateDir} 0750 root ${runtimeUser} - -"
      "d ${releasesDir} 0750 root ${runtimeUser} - -"
      "d /var/lib/scalive-docs-deploy 0710 root ${deployUser} - -"
      "d ${stagingDir} 0700 ${deployUser} ${deployUser} - -"
      "f ${lockFile} 0660 root ${deployUser} - -"
    ];

    systemd.services.scalive-docs = {
      description = "Scalive Docs";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
      unitConfig.ConditionPathExists = currentJar;
      environment = {
        SCALIVE_SERVER_PORT = toString cfg.port;
        SCALIVE_PUBLIC_ORIGIN = "https://${cfg.domain}";
      };
      serviceConfig = {
        Type = "simple";
        User = runtimeUser;
        Group = runtimeUser;
        WorkingDirectory = "${stateDir}/current";
        ExecStart = serviceWrapper;
        LoadCredential = "token-secret:${cfg.signingSecretFile}";
        Restart = "on-failure";
        RestartSec = "5s";
        TimeoutStopSec = "20s";
        NoNewPrivileges = true;
        PrivateDevices = true;
        PrivateTmp = true;
        ProtectClock = true;
        ProtectControlGroups = true;
        ProtectHome = true;
        ProtectHostname = true;
        ProtectKernelLogs = true;
        ProtectKernelModules = true;
        ProtectKernelTunables = true;
        ProtectSystem = "strict";
        IPAddressDeny = "any";
        IPAddressAllow = [
          "127.0.0.1/32"
          "::1/128"
        ];
        RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" ];
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        LockPersonality = true;
        RemoveIPC = true;
        CapabilityBoundingSet = "";
        AmbientCapabilities = "";
        SystemCallArchitectures = "native";
        UMask = "0077";
      };
    };

    security.sudo.extraRules = [
      {
        users = [ deployUser ];
        runAs = "root";
        commands = [
          {
            command = toString activateHelper;
            options = [ "NOPASSWD" ];
          }
        ];
      }
    ];

    services.nginx.virtualHosts = {
      "${cfg.domain}" = {
        enableACME = true;
        forceSSL = true;
        locations."/" = {
          proxyPass = "http://127.0.0.1:${toString cfg.port}";
          proxyWebsockets = true;
          extraConfig = ''
            proxy_read_timeout 1h;
            proxy_send_timeout 1h;
          '';
        };
      };
      "www.${cfg.domain}" = {
        enableACME = true;
        forceSSL = true;
        globalRedirect = cfg.domain;
      };
    };
  };
}
