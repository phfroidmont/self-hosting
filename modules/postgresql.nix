{ config, lib, pkgs, ... }:
{

  services.postgresql = {
    enable = true;
    package = pkgs.postgresql_12;
    initialScript = pkgs.writeText "postgres-init.sql" ''
      CREATE ROLE "synapse";
      CREATE ROLE "nextcloud";
    '';
    enableTCPIP = true;
    identMap = ''
      root_as_others         root                  postgres
      root_as_others         root                  synapse
      root_as_others         root                  nextcloud
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
  };

  systemd.services.postgresql-setup = let pgsql = config.services.postgresql; in
    {
      after = [ "postgresql.service" ];
      bindsTo = [ "postgresql.service" ];
      wantedBy = [ "postgresql.service" ];
      path = [
        pgsql.package
        pkgs.util-linux
      ];
      script = ''
        set -eu
        PSQL() {
            psql --port=${toString pgsql.port} "$@"
        }
        PSQL -tAc "SELECT 1 FROM pg_database WHERE datname = 'synapse'" | grep -q 1 || PSQL -tAc 'CREATE DATABASE "synapse" OWNER "synapse" TEMPLATE template0 LC_COLLATE = "C" LC_CTYPE = "C"'
        PSQL -tAc "SELECT 1 FROM pg_database WHERE datname = 'nextcloud'" | grep -q 1 || PSQL -tAc 'CREATE DATABASE "nextcloud" OWNER "nextcloud"'

        synapse_password="$(<'${config.sops.secrets.synapseDbPassword.path}')"
        PSQL -tAc  "ALTER ROLE synapse WITH PASSWORD '$synapse_password'"
        nextcloud_password="$(<'${config.sops.secrets.nextcloudDbPassword.path}')"
        PSQL -tAc  "ALTER ROLE nextcloud WITH PASSWORD '$nextcloud_password'"
      '';

      serviceConfig = {
        User = pgsql.superUser;
        Type = "oneshot";
        RemainAfterExit = true;
      };
    };
}
