{ config, lib, pkgs, ... }:
{
  services.postgresql = {
    enable = true;
    package = pkgs.postgresql_12;
    initialScript = "/var/keys/postgres-init.sql";
    enableTCPIP = true;
    authentication = ''
      host all all 10.0.1.0/24 md5
    '';
  };
  users.users.postgres.extraGroups = [ "keys" ];
}