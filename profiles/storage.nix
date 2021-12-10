{ config, lib, pkgs, ... }:
{
  imports = [
    ../environment.nix
    ../hardware/hetzner-dedicated-storage1.nix
    ../modules/openssh.nix
    ../modules/mailserver.nix
    ../modules/nginx.nix
    ../modules/jellyfin.nix
    ../modules/stb.nix
    ../modules/monero.nix
    ../modules/torrents.nix
  ];

  networking.firewall.allowedTCPPorts = [ 80 443 18080 ];

  networking.nat.enable = true;
  networking.nat.internalInterfaces = [ "ve-+" ];
  networking.nat.externalInterface = "enp2s0";

  users.users.www-data = {
    uid = 993;
    isSystemUser = true;
    group = config.users.groups.www-data.name;
  };
  users.groups.www-data = { gid = 991; };
}
