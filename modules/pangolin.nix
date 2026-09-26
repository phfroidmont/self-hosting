{ config, lib, pkgs, utils, ... }:
let
  cfg = config.custom.services.pangolin;
  package = pkgs.callPackage ../packages/pangolin { };
  gerbilPackage = pkgs.callPackage ../packages/pangolin/gerbil.nix { };
  acmeSource = config.services.traefik.staticConfigOptions.certificatesResolvers.letsencrypt.acme.storage;
  acmeSyncDir = "${config.services.pangolin.dataDir}/config/acme-sync";
  acmeDestination = "${acmeSyncDir}/acme.json";
  acmeCertSync = pkgs.writeShellApplication {
    name = "pangolin-acme-cert-sync";
    runtimeInputs = with pkgs; [ coreutils diffutils jq ];
    text = ''
      source=${lib.escapeShellArg acmeSource}
      destination=${lib.escapeShellArg acmeDestination}

      if [ ! -f "$source" ]; then
        [ ! -e "$destination" ] && exit 0
        echo "ACME source is missing; preserving the last good copy" >&2
        exit 1
      fi

      temporary="$(mktemp ${lib.escapeShellArg "${acmeSyncDir}/.acme.json.XXXXXX"})"
      trap 'rm -f "$temporary"' EXIT

      valid=false
      for attempt in 1 2 3; do
        if install -m 0600 "$source" "$temporary" \
          && jq -e 'type == "object"' "$temporary" > /dev/null 2>&1; then
          valid=true
          break
        fi

        if [ ! -e "$source" ]; then
          [ ! -e "$destination" ] && exit 0
          echo "ACME source disappeared; preserving the last good copy" >&2
          exit 1
        fi
        [ "$attempt" -eq 3 ] || sleep 1
      done
      if [ "$valid" != true ]; then
        echo "ACME source remained invalid after three attempts" >&2
        exit 1
      fi

      if [ -f "$destination" ] && cmp -s "$temporary" "$destination"; then
        exit 0
      fi

      chown pangolin:fossorial "$temporary"
      chmod 0600 "$temporary"
      mv -f "$temporary" "$destination"
    '';
  };
  gerbilWgFix = pkgs.writeShellApplication {
    name = "gerbil-wg0-fix";
    runtimeInputs = with pkgs; [
      coreutils
      iproute2
      systemd
    ];
    text = ''
      if [ ! -f ${config.services.pangolin.dataDir}/config/wg0 ]; then
        found=false
        for _ in $(seq 1 30); do
          if ip link delete wg0; then
            found=true
            break
          fi
          sleep 1
        done
        if [ "$found" != true ]; then
          echo "wg0 did not appear within 30 seconds" >&2
          exit 1
        fi
        touch ${config.services.pangolin.dataDir}/config/wg0
        systemctl restart gerbil.service --no-block
      fi
    '';
  };
in
{
  options.custom.services.pangolin = {
    enable = lib.mkEnableOption "Pangolin gateway";

    environmentFile = lib.mkOption {
      type = lib.types.path;
      description = "Environment file containing SERVER_SECRET";
      example = "/run/secrets/pangolin-environment";
    };
  };

  config = lib.mkIf cfg.enable {
    services.pangolin = {
      enable = true;
      inherit package;
      baseDomain = "banditlair.com";
      dashboardDomain = "pangolin.banditlair.com";
      letsEncryptEmail = "letsencrypt.account@banditlair.com";
      environmentFile = cfg.environmentFile;
      openFirewall = true;

      settings = {
        app.telemetry.anonymous_usage = false;
        flags = {
          disable_signup_without_invite = true;
          disable_user_create_org = true;
          enable_acme_cert_sync = true;
          enable_integration_api = true;
        };
        acme.acme_json_path = acmeDestination;
        gerbil.clients_start_port = 21820;
        server.integration_port = 3003;
      };
    };

    systemd.tmpfiles.rules = [
      "d ${acmeSyncDir} 0700 pangolin fossorial -"
    ];

    systemd.services.pangolin-acme-cert-sync = {
      description = "Copy Traefik's ACME certificates for Pangolin";
      after = [ "traefik.service" ];
      serviceConfig = {
        Type = "oneshot";
        User = "root";
        Group = "root";
        ExecStart = lib.getExe acmeCertSync;
        CapabilityBoundingSet = [
          "CAP_CHOWN"
          "CAP_DAC_OVERRIDE"
          "CAP_FOWNER"
        ];
        NoNewPrivileges = true;
        PrivateDevices = true;
        PrivateNetwork = true;
        PrivateTmp = true;
        ProtectHome = true;
        ProtectSystem = "strict";
        ReadOnlyPaths = [ "-${acmeSource}" ];
        ReadWritePaths = [ acmeSyncDir ];
        RestrictAddressFamilies = [ "AF_UNIX" ];
        UMask = "0077";
      };
    };

    systemd.timers.pangolin-acme-cert-sync = {
      description = "Periodically copy Traefik's ACME certificates for Pangolin";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "0";
        OnUnitActiveSec = "1min";
        Unit = "pangolin-acme-cert-sync.service";
      };
    };

    networking.firewall.allowedUDPPorts = [ 21820 ];

    # Upstream denies all IPv4 TCP binds; allow only the patched loopback API port.
    systemd.services.pangolin.serviceConfig.SocketBindAllow = [ "ipv4:tcp:3003" ];

    # Badger 1.7 is the plugin released for Pangolin 1.22.
    services.traefik.staticConfigOptions = {
      experimental.plugins.badger.version = lib.mkForce "v1.7.0";
      entryPoints.websecure.http.encodedCharacters = {
        allowEncodedSlash = true;
        allowEncodedQuestionMark = true;
      };
    };

    # The integration API is private to IPv4 loopback (for SSH forwarding).
    # Do not expose upstream's integration routers or request an unused
    # api.<base-domain> certificate.
    services.traefik.dynamicConfigOptions.http.routers = lib.mkForce {
      main-app-router-redirect = {
        rule = "Host(`${config.services.pangolin.dashboardDomain}`)";
        service = "next-service";
        entryPoints = [ "web" ];
        middlewares = [ "redirect-to-https" ];
      };
      next-router = {
        rule = "Host(`${config.services.pangolin.dashboardDomain}`) && !PathPrefix(`/api/v1`)";
        service = "next-service";
        entryPoints = [ "websecure" ];
        tls.certResolver = "letsencrypt";
      };
      api-router = {
        rule = "Host(`${config.services.pangolin.dashboardDomain}`) && PathPrefix(`/api/v1`)";
        service = "api-service";
        entryPoints = [ "websecure" ];
        tls.certResolver = "letsencrypt";
      };
    };

    systemd.services.gerbil.serviceConfig = {
      ExecStart = lib.mkForce (utils.escapeSystemdExecArgs [
        (lib.getExe gerbilPackage)
        "--reachableAt=http://localhost:${toString config.services.gerbil.port}"
        "--generateAndSaveKeyTo=${config.services.pangolin.dataDir}/config/key"
        "--remoteConfig=http://localhost:${toString (config.services.pangolin.settings.server.internal_port or 3001)}/api/v1/gerbil/get-config"
      ]);

      # The pinned module runs systemctl as the unprivileged gerbil user.
      ExecStartPost = lib.mkForce "+${lib.getExe gerbilWgFix}";
      RestartSec = "5s";
      TimeoutStartSec = "60s";
      TimeoutStopSec = "30s";
    };
  };
}
