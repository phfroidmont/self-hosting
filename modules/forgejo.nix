{ config, lib, ... }:
with lib;
let
  cfg = config.custom.services.forgejo;
  domain = "forge.froidmont.org";
in
{
  options.custom.services.forgejo = {
    enable = mkEnableOption "forgejo";
  };

  config = mkIf cfg.enable {
    sops.secrets = {
      forgejoDbPassword = {
        owner = config.users.users.forgejo.name;
        key = "forgejo/db_password";
        restartUnits = [ "forgejo.service" ];
      };
    };

    services.forgejo = {
      enable = true;
      stateDir = "/nix/var/data/forgejo";
      database = {
        createDatabase = false;
        type = "postgres";
        host = "127.0.0.1";
        name = "forgejo";
        user = "forgejo";
        passwordFile = config.sops.secrets.forgejoDbPassword.path;
      };
      settings = {
        server = {
          PROTOCOL = "http+unix";
          DOMAIN = domain;
          ROOT_URL = "https://${domain}/";
        };
        session = {
          COOKIE_SECURE = true;
        };
        DEFAULT = {
          RUN_MODE = "prod";
        };
        mailer = {
          ENABLED = true;
          PROTOCOL = "sendmail";
          FROM = "noreply@froidmont.org";
          SENDMAIL_PATH = "/run/wrappers/bin/sendmail";
          SENDMAIL_ARGS = "--";
        };
        service = {
          DISABLE_REGISTRATION = true;
        };
      };
    };

    services.nginx.virtualHosts.${domain} = {
      forceSSL = true;
      enableACME = true;
      locations."/" = {
        proxyPass = "http://unix:${config.services.forgejo.settings.server.HTTP_ADDR}";
        extraConfig = ''
          client_max_body_size 512M;
        '';
      };
    };
  };
}
