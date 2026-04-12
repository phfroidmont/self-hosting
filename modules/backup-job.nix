{ config
, lib
, pkgs
, ...
}:
with lib;
let
  cfg = config.custom.services.backup-job;
  repo = "ssh://u348077@u348077.your-storagebox.de:23/home/repos/${cfg.repoName}";
in
{
  options.custom.services.backup-job = {
    enable = mkEnableOption "backup-job";

    additionalPaths = mkOption {
      type = with types; listOf path;
      default = [ ];
    };

    patterns = mkOption {
      type = with types; listOf str;
      default = [ ];
    };

    repoName = mkOption { type = types.str; };

    readWritePaths = mkOption {
      type = with types; listOf path;
      default = [ ];
    };

    preHook = mkOption {
      type = types.lines;
      default = "";
    };

    postHook = mkOption {
      type = types.lines;
      default = "";
    };

    startAt = mkOption {
      type = with types; either str (listOf str);
      default = "03:30";
    };

    checkStartAt = mkOption {
      type = with types; either str (listOf str);
      default = "Sun *-*-* 04:30:00";
    };

    restoreTestStartAt = mkOption {
      type = with types; either str (listOf str);
      default = "Wed *-*-* 04:30:00";
    };

    restoreTestPaths = mkOption {
      type = with types; listOf str;
      default = [
        "nix/var/data/murmur/murmur.sqlite"
        "nix/var/data/postgresql/forgejo.dmp"
        "nix/var/data/backup/stb_mariadb.sql"
      ];
    };

    sshKey = mkOption { type = with types; path; };
  };

  config = mkIf cfg.enable {

    sops.secrets = {
      borgPassphrase = {
        owner = config.services.borgbackup.jobs.data.user;
        key = "borg/passphrase";
      };
    };

    services.borgbackup.jobs.data = {
      paths = [
        "/nix/var/data"
        cfg.sshKey
      ]
      ++ cfg.additionalPaths;
      patterns = cfg.patterns;
      doInit = false;
      repo = repo;
      encryption = {
        mode = "repokey-blake2";
        passCommand = "cat ${config.sops.secrets.borgPassphrase.path}";
      };
      readWritePaths = cfg.readWritePaths;
      preHook = cfg.preHook;
      postHook = ''
        ${cfg.postHook}
        if [ $exitStatus -eq 0 ]; then
          touch /nix/var/data/backup/backup-ok
        fi
      '';

      environment = {
        BORG_RSH = "ssh -i ${cfg.sshKey}";
      };
      compression = "lz4";
      startAt = cfg.startAt;
      prune.keep = {
        within = "2d";
        daily = 14;
        weekly = 8;
        monthly = 12;
      };
    };

    systemd.services.borgbackup-check-data = {
      description = "Borg repository check (latest archive)";
      serviceConfig = {
        Type = "oneshot";
      };
      script = ''
        set -euo pipefail
        export BORG_RSH="ssh -i ${cfg.sshKey}"
        export BORG_PASSPHRASE="$(<${config.sops.secrets.borgPassphrase.path})"

        ${pkgs.borgbackup}/bin/borg check --archives-only --last 1 ${repo}
        touch /nix/var/data/backup/borg-check-ok
      '';
    };

    systemd.timers.borgbackup-check-data = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.checkStartAt;
        Persistent = true;
        Unit = "borgbackup-check-data.service";
      };
    };

    systemd.services.borgbackup-restore-test-data = {
      description = "Borg restore test (latest archive)";
      serviceConfig = {
        Type = "oneshot";
      };
      script = ''
        set -euo pipefail

        export BORG_RSH="ssh -i ${cfg.sshKey}"
        export BORG_PASSPHRASE="$(<${config.sops.secrets.borgPassphrase.path})"

        restore_dir="$(mktemp -d /run/backup-restore-test.XXXXXX)"
        cleanup() {
          rm -rf "$restore_dir"
        }
        trap cleanup EXIT

        archive="$(${pkgs.borgbackup}/bin/borg list --short --last 1 ${repo})"
        if [ -z "$archive" ]; then
          echo "No archive found in repository"
          exit 1
        fi

        (
          cd "$restore_dir"
          ${pkgs.borgbackup}/bin/borg extract "${repo}::$archive" ${escapeShellArgs cfg.restoreTestPaths}
        )

        for path in ${escapeShellArgs cfg.restoreTestPaths}; do
          normalized_path="''${path#/}"
          if [ ! -s "$restore_dir/$normalized_path" ]; then
            echo "Restore test failed for path: $path"
            exit 1
          fi
        done

        touch /nix/var/data/backup/restore-test-ok
      '';
    };

    systemd.timers.borgbackup-restore-test-data = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.restoreTestStartAt;
        Persistent = true;
        Unit = "borgbackup-restore-test-data.service";
      };
    };
  };
}
