{ config, lib, pkgs, ... }:
{
  services.postgresql = {
    enable = true;
    package = pkgs.postgresql_12;
    initialScript = "/var/keys/postgres-init.sql";
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
  users.users.postgres.extraGroups = [ "keys" ];
}
