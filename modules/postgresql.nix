{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.custom.services.postgresql;
in
{
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
        root_as_others         root                  immich
        root_as_others         root                  forgejo
      '';
      authentication = ''
        local  all     postgres               peer
        local  all     all                    peer map=root_as_others
        host   all     all     10.0.1.0/24    md5
      '';
    };

    sops.secrets = {
      synapseDbPasswordPg = {
        owner = config.services.postgresql.superUser;
        key = "synapse/db_password";
        restartUnits = [ "postgresql-setup.service" ];
      };
      nextcloudDbPasswordPg = {
        owner = config.services.postgresql.superUser;
        key = "nextcloud/db_password";
        restartUnits = [ "postgresql-setup.service" ];
      };
      roundcubeDbPasswordPg = {
        owner = config.services.postgresql.superUser;
        key = "roundcube/db_password";
        restartUnits = [ "postgresql-setup.service" ];
      };
      immichDbPasswordPg = {
        owner = config.services.postgresql.superUser;
        key = "immich/db_password";
        restartUnits = [ "postgresql-setup.service" ];
      };
      forgejoDbPasswordPg = {
        owner = config.services.postgresql.superUser;
        key = "forgejo/db_password";
        restartUnits = [ "postgresql-setup.service" ];
      };
    };

    systemd.services.postgresql-setup =
      let
        pgsql = config.services.postgresql;
      in
      {
        after = [ "postgresql.service" ];
        bindsTo = [ "postgresql.service" ];
        wantedBy = [ "postgresql.service" ];
        path = [
          pgsql.package
          pkgs.util-linux
        ];
        script = ''
          set -u
          PSQL() {
              psql --port=${toString pgsql.settings.port} "$@"
          }

          PSQL -tAc "SELECT 1 FROM pg_roles WHERE rolname = 'synapse'" | grep -q 1 || PSQL -tAc 'CREATE ROLE "synapse"'
          PSQL -tAc "SELECT 1 FROM pg_roles WHERE rolname = 'nextcloud'" | grep -q 1 || PSQL -tAc 'CREATE ROLE "nextcloud"'
          PSQL -tAc "SELECT 1 FROM pg_roles WHERE rolname = 'roundcube'" | grep -q 1 || PSQL -tAc 'CREATE ROLE "roundcube"'
          PSQL -tAc "SELECT 1 FROM pg_roles WHERE rolname = 'immich'" | grep -q 1 || PSQL -tAc 'CREATE ROLE "immich"'
          PSQL -tAc "SELECT 1 FROM pg_roles WHERE rolname = 'forgejo'" | grep -q 1 || PSQL -tAc 'CREATE ROLE "forgejo"'

          PSQL -tAc "SELECT 1 FROM pg_database WHERE datname = 'synapse'" | grep -q 1 || PSQL -tAc 'CREATE DATABASE "synapse" OWNER "synapse" TEMPLATE template0 LC_COLLATE = "C" LC_CTYPE = "C"'
          PSQL -tAc "SELECT 1 FROM pg_database WHERE datname = 'nextcloud'" | grep -q 1 || PSQL -tAc 'CREATE DATABASE "nextcloud" OWNER "nextcloud"'
          PSQL -tAc "SELECT 1 FROM pg_database WHERE datname = 'roundcube'" | grep -q 1 || PSQL -tAc 'CREATE DATABASE "roundcube" OWNER "roundcube"'
          PSQL -tAc "SELECT 1 FROM pg_database WHERE datname = 'immich'" | grep -q 1 || PSQL -tAc 'CREATE DATABASE "immich" OWNER "immich"'
          PSQL -tAc "SELECT 1 FROM pg_database WHERE datname = 'forgejo'" | grep -q 1 || PSQL -tAc 'CREATE DATABASE "forgejo" OWNER "forgejo"'

          PSQL -tAc  "ALTER ROLE synapse LOGIN"
          PSQL -tAc  "ALTER ROLE nextcloud LOGIN"
          PSQL -tAc  "ALTER ROLE roundcube LOGIN"
          PSQL -tAc  "ALTER ROLE immich LOGIN"
          PSQL -tAc  "ALTER ROLE forgejo LOGIN"

          synapse_password="$(<'${config.sops.secrets.synapseDbPasswordPg.path}')"
          PSQL -tAc  "ALTER ROLE synapse WITH PASSWORD '$synapse_password'"
          nextcloud_password="$(<'${config.sops.secrets.nextcloudDbPasswordPg.path}')"
          PSQL -tAc  "ALTER ROLE nextcloud WITH PASSWORD '$nextcloud_password'"
          roundcube_password="$(<'${config.sops.secrets.roundcubeDbPasswordPg.path}')"
          PSQL -tAc  "ALTER ROLE roundcube WITH PASSWORD '$roundcube_password'"
          immich_password="$(<'${config.sops.secrets.immichDbPasswordPg.path}')"
          PSQL -tAc  "ALTER ROLE immich WITH PASSWORD '$immich_password'"
          forgejo_password="$(<'${config.sops.secrets.forgejoDbPasswordPg.path}')"
          PSQL -tAc  "ALTER ROLE forgejo WITH PASSWORD '$forgejo_password'"
        '';

        serviceConfig = {
          User = pgsql.superUser;
          Type = "oneshot";
          RemainAfterExit = true;
        };
      };
  };
}
