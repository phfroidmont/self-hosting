{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.custom.services.dokuwiki;

  template-chippedsnow = pkgs.stdenv.mkDerivation {
    name = "chippedsnow";
    src = fetchGit {
      url = "ssh://git@gitlab.com/desbest/Chipped-Snow-Dokuwiki-Template.git";
      ref = "master";
      rev = "61e525236063714cade90beb1401cde2c75e4c88";
    };
    installPhase = "mkdir -p $out; cp -R * $out/";
  };

  template-darkblue = pkgs.stdenv.mkDerivation {
    name = "darkblue";
    src = fetchGit {
      url = "https://github.com/ms101/dokuwiki-template-darkblue.git";
      ref = "main";
      rev = "14f8e738c83c16f2633d23fe30b7c6031551fa77";
    };
    installPhase = "mkdir -p $out; cp -R darkblue/* $out/";
  };

  template-bootstrap3 = pkgs.stdenv.mkDerivation {
    name = "bootstrap3";
    src = fetchGit {
      url = "https://github.com/giterlizzi/dokuwiki-template-bootstrap3.git";
      ref = "master";
      rev = "b5cec1c82345f23e4e9faa325b88ba407e2924e4";
    };
    installPhase = "mkdir -p $out; cp -R * $out/";
  };

  configureWiki = name: title: templatePackage: templateName: {

    sops.secrets."usersFile-${name}" = {
      owner = "dokuwiki";
      key = "wiki/${name}/users_file";
      restartUnits = [ "phpfpm-dokuwiki-${name}.${config.networking.domain}.service" ];
    };

    services.dokuwiki.sites = {
      "${name}.${config.networking.domain}" = {
        stateDir = "/nix/var/data/dokuwiki/${name}/data";
        usersFile = config.sops.secrets."usersFile-${name}".path;
        templates = [ templatePackage ];
        settings = {
          useacl = true;
          title = title;
          template = templateName;
          disableactions = "register";
          dontlog = [
            "debug"
            "deprecated"
          ];
        };
      };
    };

    services.nginx.virtualHosts."${name}.${config.networking.domain}" = {
      forceSSL = true;
      enableACME = true;
      extraConfig = "client_max_body_size 25M;";
    };
  };
in
{
  options.custom.services.dokuwiki = {

    enable = lib.mkEnableOption "dokuwiki";

    secretKeyFile = lib.mkOption { type = lib.types.path; };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      (configureWiki "anderia" "Chroniques d`Arkadia" template-chippedsnow "chippedsnow")
      (configureWiki "arkadia" "Chroniques d`Arkadia" template-chippedsnow "chippedsnow")
      (configureWiki "scifirpg" "2324" template-darkblue "darkblue")
      (configureWiki "chroniques" "Chroniques d`Arkadia" template-bootstrap3 "bootstrap3")
    ]
  );
}
