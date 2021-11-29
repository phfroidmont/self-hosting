{ config, lib, pkgs, ... }:
{
  imports = [
    ../environment.nix
    ../hardware/hetzner-dedicated-storage1.nix
    ../modules/openssh.nix
    ../modules/mailserver.nix
  ];

  security.acme.email = "letsencrypt.account@banditlair.com";
  security.acme.acceptTerms = true;

  networking.firewall.allowedTCPPorts = [ 80 ];
}
