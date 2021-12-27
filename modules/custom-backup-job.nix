{ config, lib, pkgs, ... }:
with lib;
let
  cfg = config.services.custom-backup-job;
in
{
  options.services.custom-backup-job = {
    additionalPaths = mkOption {
      type = with types; listOf path;
      default = [ ];
    };

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

    sshKey = mkOption {
      type = with types; path;
    };
  };

  config = {

    sops.secrets = {
      borgPassphrase = {
        owner = config.services.borgbackup.jobs.data.user;
        key = "borg/passphrase";
      };
    };
    services.borgbackup.jobs.data = {
      paths = [ "/nix/var/data" cfg.sshKey ] ++ cfg.additionalPaths;
      doInit = false;
      repo = "backup@212.129.12.205:./";
      encryption = {
        mode = "repokey-blake2";
        passCommand = "cat ${config.sops.secrets.borgPassphrase.path}";
      };
      readWritePaths = cfg.readWritePaths;
      preHook = cfg.preHook;
      postHook = cfg.postHook;
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
