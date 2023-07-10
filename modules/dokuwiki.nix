{ config, lib, pkgs, ... }:
with lib;
let
  cfg = config.custom.services.dokuwiki;

  template-chippedsnow = pkgs.stdenv.mkDerivation {
    name = "chippedsnow";
    src = builtins.fetchGit {
      url = "ssh://git@gitlab.com/desbest/Chipped-Snow-Dokuwiki-Template.git";
      ref = "master";
      rev = "61e525236063714cade90beb1401cde2c75e4c88";
    };
    installPhase = "mkdir -p $out; cp -R * $out/";
  };

  configureWiki = name: {

    sops.secrets."usersFile-${name}" = {
      owner = "dokuwiki";
      key = "wiki/${name}/users_file";
      restartUnits =
        [ "phpfpm-dokuwiki-${name}.${config.networking.domain}.service" ];
    };

    services.dokuwiki.sites = {
      "${name}.${config.networking.domain}" = {
        enable = true;
        stateDir = "/nix/var/data/dokuwiki/${name}/data";
        usersFile = config.sops.secrets."usersFile-${name}".path;
        templates = [ template-chippedsnow ];
        settings = {
          useacl = true;
          title = "Chroniques d`Arkadia";
          template = "chippedsnow";
          disableactions = "register";
        };
      };
    };

    services.nginx.virtualHosts."${name}.${config.networking.domain}" = {
      forceSSL = true;
      enableACME = true;
    };
  };
in {
  options.custom.services.dokuwiki = {

    enable = mkEnableOption "dokuwiki";

    secretKeyFile = mkOption { type = types.path; };
  };

  config = mkIf cfg.enable
    (lib.mkMerge [ (configureWiki "anderia") (configureWiki "arkadia") ]);
}
