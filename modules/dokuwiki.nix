{ config, lib, pkgs, ... }:
let
  configureWiki = name: {
    services.dokuwiki.sites = {
      "${name}.${config.networking.domain}" = {
        enable = true;
        stateDir = "/nix/var/data/dokuwiki/${name}/data";
      };
    };

    services.phpfpm.pools."dokuwiki-${name}.${config.networking.domain}".phpPackage = lib.mkOverride 10 pkgs.php74;

    services.nginx.virtualHosts."${name}.${config.networking.domain}" = {
      forceSSL = true;
      enableACME = true;
    };
  };
in
configureWiki "anderia" // configureWiki "arkadia"
