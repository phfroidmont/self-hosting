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
  ];

  networking.firewall.allowedTCPPorts = [ 80 443 ];
}
