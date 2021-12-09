{ config, lib, pkgs, ... }:
let
  configureWiki = name: {

    sops.secrets."usersFile-${name}" = {
      owner = "dokuwiki";
      key = "wiki/${name}/users_file";
      restartUnits = [ "phpfpm-dokuwiki-${name}.${config.networking.domain}.service" ];
    };

    services.dokuwiki.sites = {
      "${name}.${config.networking.domain}" = {
        enable = true;
        stateDir = "/nix/var/data/dokuwiki/${name}/data";
        usersFile = config.sops.secrets."usersFile-${name}".path;
        disableActions = "register";
      };
    };

    services.phpfpm.pools."dokuwiki-${name}.${config.networking.domain}".phpPackage = lib.mkOverride 10 pkgs.php74;

    services.nginx.virtualHosts."${name}.${config.networking.domain}" = {
      forceSSL = true;
      enableACME = true;
    };
  };
in
lib.mkMerge [
  (configureWiki "anderia")
  (configureWiki "arkadia")
]
