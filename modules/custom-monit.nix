{ config, lib, pkgs, ... }:
with lib;
let
  cfg = config.services.custom-monit;
in
{
  options.services.custom-monit = {
    additionalConfig = mkOption {
      type = types.lines;
      default = "";
    };
  };

  config = {

    sops.secrets = {
      monitMailserverConfig = {
        owner = config.services.borgbackup.jobs.data.user;
        key = "monit/mailserver_config";
      };
    };

    services.monit = {
      enable = true;
      config = ''
        set daemon 30
          with start delay 90

        set httpd
          port 2812
          use address 127.0.0.1
          allow localhost

        set ssl {
          verify     : enable,
        }

        include ${config.sops.secrets.monitMailserverConfig.path}

        set mail-format { from: monit@banditlair.com }
        set alert alerts@banditlair.com with reminder on 120 cycles

        check system $HOST
          if cpu usage > 95% for 10 cycles then alert
          if memory usage > 75% for 5 times within 15 cycles then alert
          if swap usage > 25% then alert

        check filesystem root with path /
          if SPACE usage > 90% then alert

        check file daily-backup-done with path /nix/var/data/backup/backup-ok
          if changed timestamp then alert
          if timestamp > 26 hours then alert
        
        ${cfg.additionalConfig}
      '';
    };
  };
}
