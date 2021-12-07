{ config, lib, pkgs, ... }:
{
  services.nginx.virtualHosts."osteopathie.froidmont.org" = {
    enableACME = true;
    forceSSL = true;
    root = "/nix/var/data/website-marie";
  };
}
