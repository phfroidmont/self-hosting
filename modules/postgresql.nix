{ config, lib, pkgs, ... }:
let cfg = config.custom.services.postgresql;
in {
  options.custom.services.postgresql = {
    enable = lib.mkEnableOption "postgresql";
  };

  config = lib.mkIf cfg.enable {
    services.postgresql = {
      enable = true;
      package = pkgs.postgresql_15;
      enableTCPIP = true;
      identMap = ''
        root_as_others         root                  postgres
        root_as_others         root                  synapse
        root_as_others         root                  nextcloud
        root_as_others         root                  roundcube
        root_as_others         root                  mastodon
      '';
      authentication = ''
        local  all     postgres               peer
        local  all     all                    peer map=root_as_others
        host   all     all     10.0.1.0/24    md5
      '';
    };

    sops.secrets = {
      synapseDbPassword = {
        owner = config.services.postgresql.superUser;
        key = "synapse/db_password";
        restartUnits = [ "postgresql-setup.service" ];
      };
      nextcloudDbPassword = {
        owner = config.services.postgresql.superUser;
        key = "nextcloud/db_password";
        restartUnits = [ "postgresql-setup.service" ];
      };
      roundcubeDbPassword = {
        owner = config.services.postgresql.superUser;
        key = "roundcube/db_password";
        restartUnits = [ "postgresql-setup.service" ];
      };
      mastodonDbPassword = {
        owner = config.services.postgresql.superUser;
        key = "mastodon/db_password";
        restartUnits = [ "postgresql-setup.service" ];
      };
    };

    systemd.services.postgresql-setup = let pgsql = config.services.postgresql;
    in {
      after = [ "postgresql.service" ];
      bindsTo = [ "postgresql.service" ];
      wantedBy = [ "postgresql.service" ];
      path = [ pgsql.package pkgs.util-linux ];
      script = ''
        set -u
        PSQL() {
            psql --port=${toString pgsql.settings.port} "$@"
        }

        PSQL -tAc "SELECT 1 FROM pg_roles WHERE rolname = 'synapse'" | grep -q 1 || PSQL -tAc 'CREATE ROLE "synapse"'
        PSQL -tAc "SELECT 1 FROM pg_roles WHERE rolname = 'nextcloud'" | grep -q 1 || PSQL -tAc 'CREATE ROLE "nextcloud"'
        PSQL -tAc "SELECT 1 FROM pg_roles WHERE rolname = 'roundcube'" | grep -q 1 || PSQL -tAc 'CREATE ROLE "roundcube"'
        PSQL -tAc "SELECT 1 FROM pg_roles WHERE rolname = 'mastodon'" | grep -q 1 || PSQL -tAc 'CREATE ROLE "mastodon"'

        PSQL -tAc "SELECT 1 FROM pg_database WHERE datname = 'synapse'" | grep -q 1 || PSQL -tAc 'CREATE DATABASE "synapse" OWNER "synapse" TEMPLATE template0 LC_COLLATE = "C" LC_CTYPE = "C"'
        PSQL -tAc "SELECT 1 FROM pg_database WHERE datname = 'nextcloud'" | grep -q 1 || PSQL -tAc 'CREATE DATABASE "nextcloud" OWNER "nextcloud"'
        PSQL -tAc "SELECT 1 FROM pg_database WHERE datname = 'roundcube'" | grep -q 1 || PSQL -tAc 'CREATE DATABASE "roundcube" OWNER "roundcube"'
        PSQL -tAc "SELECT 1 FROM pg_database WHERE datname = 'mastodon'" | grep -q 1 || PSQL -tAc 'CREATE DATABASE "mastodon" OWNER "mastodon"'

        PSQL -tAc  "ALTER ROLE synapse LOGIN"
        PSQL -tAc  "ALTER ROLE nextcloud LOGIN"
        PSQL -tAc  "ALTER ROLE roundcube LOGIN"
        PSQL -tAc  "ALTER ROLE mastodon LOGIN"

        synapse_password="$(<'${config.sops.secrets.synapseDbPassword.path}')"
        PSQL -tAc  "ALTER ROLE synapse WITH PASSWORD '$synapse_password'"
        nextcloud_password="$(<'${config.sops.secrets.nextcloudDbPassword.path}')"
        PSQL -tAc  "ALTER ROLE nextcloud WITH PASSWORD '$nextcloud_password'"
        roundcube_password="$(<'${config.sops.secrets.roundcubeDbPassword.path}')"
        PSQL -tAc  "ALTER ROLE roundcube WITH PASSWORD '$roundcube_password'"
        mastodon_password="$(<'${config.sops.secrets.mastodonDbPassword.path}')"
        PSQL -tAc  "ALTER ROLE mastodon WITH PASSWORD '$mastodon_password'"
      '';

      serviceConfig = {
        User = pgsql.superUser;
        Type = "oneshot";
        RemainAfterExit = true;
      };
    };
  };
}
