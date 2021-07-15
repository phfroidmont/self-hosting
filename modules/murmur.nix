{ config, lib, pkgs, ... }:
{
  services.murmur = {
    enable = true;
    bandwidth = 128000;
    password = "$MURMURD_PASSWORD";
    environmentFile = "/var/keys/murmur.env";
  };

  users.users.murmur.extraGroups = [ "keys" ];
}
