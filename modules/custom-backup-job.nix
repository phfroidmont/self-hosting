{ config, lib, pkgs, ... }:
with lib;
let
  cfg = config.services.custom-backup-job;
in {
  options.services.custom-backup-job = {
    additionalReadWritePaths = mkOption {
      type = with types; listOf path;
      default = [];
    };

    additionalPreHook = mkOption {
      type = types.lines;
      default = "";
    };

    startAt = mkOption {
      type = with types; either str (listOf str);
      default = "03:30";
    };
  };

  config = {
   services.borgbackup.jobs.data = {
     paths = [ "/nix/var/data" ];
     doInit = false;
     repo =  "backup@212.129.12.205:./";
     encryption = {
       mode = "repokey-blake2";
       passCommand = "cat /var/keys/borgbackup-passphrase";
     };
     readWritePaths = [
       "/var/keys/borgbackup-ssh-key"
     ] ++ cfg.additionalReadWritePaths;
     preHook = ''
       #There is no way to specify the permissions on keys so we fix them here
       chmod 0600 /var/keys/borgbackup-ssh-key
     '' + cfg.additionalPreHook;
     environment = { BORG_RSH = "ssh -i /var/keys/borgbackup-ssh-key"; };
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
