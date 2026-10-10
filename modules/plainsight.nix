{ config, lib, pkgs, ... }:

let
  cfg = config.custom.services.plainsight;
  dataRoot = "/nix/var/data/plainsight";
  names = lib.attrNames cfg.instances;

  unitName = name: "plainsight-${name}";
  directory = name: "${dataRoot}/${name}";

  hardening = {
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

  # Clones the books once, keeps the remote and its key current, and snapshots the databases
  # before a new release migrates them, keeping the three newest snapshots.
  prepare = name: instance: pkgs.writeShellScript "${unitName name}-prepare" ''
    set -euo pipefail
    dir=${directory name}
    ssh_command="${pkgs.openssh}/bin/ssh -i $CREDENTIALS_DIRECTORY/deploy-key -o IdentitiesOnly=yes -o BatchMode=yes"

    if [[ ! -e "$dir/pta/.git" ]]; then
      GIT_SSH_COMMAND="$ssh_command" git clone --quiet \
        --branch ${lib.escapeShellArg instance.books.branch} \
        -- ${lib.escapeShellArg instance.books.url} "$dir/pta"
    fi
    git -C "$dir/pta" remote set-url origin ${lib.escapeShellArg instance.books.url}
    git -C "$dir/pta" config core.sshCommand "$ssh_command"

    release=${cfg.package}
    if [[ "$(cat "$dir/release" 2>/dev/null || true)" != "$release" ]]; then
      databases=("$dir"/data/*.sqlite)
      if [[ -e "''${databases[0]}" ]]; then
        snapshot="$dir/upgrades/$(date -u +%Y%m%dT%H%M%SZ)"
        mkdir -p "$snapshot"
        cp "$dir/release" "$snapshot/release" 2>/dev/null || true
        for database in "''${databases[@]}"; do
          sqlite3 "$database" ".backup '$snapshot/''${database##*/}'"
        done
        find "$dir/upgrades" -mindepth 1 -maxdepth 1 -type d | sort | head -n -3 | xargs -r rm -rf --
      fi
      printf '%s\n' "$release" > "$dir/release"
    fi
  '';

  start = name: instance: pkgs.writeShellScript "${unitName name}-start" ''
    set -euo pipefail
    PLAINSIGHT_TOKEN_SECRET="$(< "$CREDENTIALS_DIRECTORY/signing-secret")"
    export PLAINSIGHT_TOKEN_SECRET
    if [[ -e "$CREDENTIALS_DIRECTORY/openai-api-key" ]]; then
      OPENAI_API_KEY="$(< "$CREDENTIALS_DIRECTORY/openai-api-key")"
      export OPENAI_API_KEY
    fi
    exec ${pkgs.jre}/bin/java -Xmx${instance.maxHeap} -XX:+ExitOnOutOfMemoryError -jar ${cfg.package}
  '';

  # A start that never becomes ready fails, so a deployment rolls back.
  ready = name: instance: pkgs.writeShellScript "${unitName name}-ready" ''
    for _ in $(seq 120); do
      if curl --fail --silent --max-time 2 --output /dev/null \
        http://127.0.0.1:${toString instance.port}/_health/ready; then
        exit 0
      fi
      sleep 1
    done
    printf '%s\n' "PlainSight ${name} did not become ready." >&2
    exit 1
  '';

  # Consistent copies of the live SQLite databases, which Borg backs up instead of them.
  snapshot = name: ''
    set -euo pipefail
    dir=${directory name}
    mkdir -p "$dir/backup"
    for database in "$dir"/data/*.sqlite; do
      [[ -s "$database" ]] || continue
      target="$dir/backup/''${database##*/}"
      rm -f "$target.partial"
      timeout 120s sqlite3 -readonly -cmd '.timeout 10000' "$database" ".backup '$target.partial'"
      integrity="$(sqlite3 -readonly "$target.partial" 'PRAGMA quick_check;')"
      if [[ "$integrity" != ok ]]; then
        printf 'Snapshot of %s failed its integrity check: %s\n' "$database" "$integrity" >&2
        exit 1
      fi
      mv -f "$target.partial" "$target"
    done
  '';

  instanceOptions = { name, ... }: {
    options = {
      domain = lib.mkOption {
        type = lib.types.str;
        description = "Domain of the private Pangolin resource serving this instance.";
      };

      port = lib.mkOption {
        type = lib.types.port;
        description = "Loopback port on which the instance listens.";
      };

      books = {
        url = lib.mkOption {
          type = lib.types.str;
          example = "forgejo@forge.froidmont.org:owner/pta.git";
          description = "Git repository of the books, cloned once and pushed to with the deploy key.";
        };

        branch = lib.mkOption {
          type = lib.types.str;
          default = "master";
        };

        journal = lib.mkOption {
          type = lib.types.str;
          default = "all.journal";
          description = "Entry journal, relative to the repository.";
        };
      };

      deployKeyFile = lib.mkOption {
        type = lib.types.path;
        description = "SSH private key with write access to the books repository.";
      };

      signingSecretFile = lib.mkOption {
        type = lib.types.path;
        description = "File containing the session signing secret, at least 32 bytes.";
      };

      openaiApiKeyFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "File containing the OpenAI API key; without one, the assistant is off.";
      };

      maxHeap = lib.mkOption {
        type = lib.types.str;
        default = "1g";
        description = "Maximum Java heap.";
      };

      settings = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { };
        example = { PLAINSIGHT_AI_DAILY_ATTEMPT_LIMIT = "500"; };
        description = "Further PlainSight settings, as its environment variables.";
      };
    };
  };
in
{
  options.custom.services.plainsight = {
    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ../packages/plainsight { };
      description = "The PlainSight jar every instance runs.";
    };

    instances = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule instanceOptions);
      default = { };
      description = "PlainSight instances, each with its own books, state, user and port.";
    };
  };

  config = lib.mkIf (cfg.instances != { }) {
    assertions = [
      {
        assertion = lib.allUnique (lib.mapAttrsToList (_: instance: instance.port) cfg.instances);
        message = "custom.services.plainsight.instances must use distinct ports";
      }
      {
        assertion = lib.allUnique (lib.mapAttrsToList (_: instance: instance.domain) cfg.instances);
        message = "custom.services.plainsight.instances must use distinct domains";
      }
    ];

    users.groups = lib.genAttrs (map unitName names) (_: { });
    users.users = lib.genAttrs (map unitName names) (user: {
      isSystemUser = true;
      group = user;
    });

    systemd.tmpfiles.rules = [ "d ${dataRoot} 0755 root root - -" ]
      ++ map (name: "d ${directory name} 0700 ${unitName name} ${unitName name} - -") names;

    systemd.services = lib.mkMerge (lib.mapAttrsToList
      (name: instance: {
        ${unitName name} = {
          description = "PlainSight (${name})";
          wantedBy = [ "multi-user.target" ];
          wants = [ "network-online.target" ];
          after = [ "network-online.target" ];
          path = with pkgs; [ git hledger poppler-utils openssh sqlite curl ];
          environment = {
            PLAINSIGHT_ENV = "production";
            PLAINSIGHT_BIND_ADDRESS = "127.0.0.1";
            PLAINSIGHT_PORT = toString instance.port;
            PLAINSIGHT_DATA_DIR = "${directory name}/data";
            PLAINSIGHT_PTA_DIR = "${directory name}/pta";
            PLAINSIGHT_PTA_JOURNAL = instance.books.journal;
            PLAINSIGHT_PTA_REMOTE = "origin";
            PLAINSIGHT_ALLOWED_ORIGINS = "https://${instance.domain}";
            PLAINSIGHT_SECURE_COOKIES = "true";
            PLAINSIGHT_AI_ENABLED = lib.boolToString (instance.openaiApiKeyFile != null);
          } // instance.settings;
          serviceConfig = hardening // {
            Type = "simple";
            User = unitName name;
            Group = unitName name;
            WorkingDirectory = directory name;
            ReadWritePaths = [ (directory name) ];
            LoadCredential = [
              "signing-secret:${instance.signingSecretFile}"
              "deploy-key:${instance.deployKeyFile}"
            ] ++ lib.optional (instance.openaiApiKeyFile != null)
              "openai-api-key:${instance.openaiApiKeyFile}";
            ExecStartPre = prepare name instance;
            ExecStart = start name instance;
            ExecStartPost = ready name instance;
            Restart = "on-failure";
            RestartSec = "10s";
            TimeoutStartSec = "5min";
            TimeoutStopSec = "30s";
          };
        };

        "${unitName name}-snapshot" = {
          description = "Snapshot PlainSight (${name}) databases for backups";
          path = with pkgs; [ sqlite coreutils ];
          script = snapshot name;
          serviceConfig = hardening // {
            Type = "oneshot";
            User = unitName name;
            Group = unitName name;
            ReadWritePaths = [ (directory name) ];
          };
        };
      })
      cfg.instances);

    custom.services.backup-job = {
      # A failed snapshot keeps the previous one rather than stopping every other backup.
      preHook = lib.concatMapStrings
        (name: ''
          ${pkgs.systemd}/bin/systemctl start ${unitName name}-snapshot.service \
            || echo "PlainSight ${name} snapshot failed; backing up the previous one" >&2
        '')
        names;
      patterns = lib.concatMap
        (name: [
          "- ${directory name}/data/*.sqlite*"
          "- ${directory name}/upgrades"
        ])
        names;
      # The snapshot service checks each copy before keeping it.
      restoreTestPaths = map (name: "${lib.removePrefix "/" (directory name)}/backup/sessions.sqlite") names;
    };

    custom.services.monit.additionalConfig = lib.concatMapStrings
      (name: ''
        check host plainsight-${name} with address 127.0.0.1
          if failed
              port ${toString cfg.instances.${name}.port}
              protocol http
              request "/_health/ready"
              with timeout 10 seconds
          then alert
      '')
      names;
  };
}
