{ config, lib, pkgs, ... }:
with lib;
let cfg = config.custom.services.backup-job;
in {
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
      paths = [ "/nix/var/data" cfg.sshKey ] ++ cfg.additionalPaths;
      patterns = cfg.patterns;
      doInit = false;
      repo =
        "ssh://u348077@u348077.your-storagebox.de:23/home/repos/${cfg.repoName}";
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

      environment = { BORG_RSH = "ssh -i ${cfg.sshKey}"; };
      compression = "lz4";
      startAt = cfg.startAt;
      prune.keep = {
        within = "2d";
        daily = 14;
        weekly = 8;
        monthly = 12;
      };
    };
  };
}
