{ config, lib, ... }:
with lib;
let
  cfg = config.custom.services.mastodon;
in
{
  options.custom.services.mastodon = {
    enable = mkEnableOption "mastodon";
  };


  config = mkIf cfg.enable {
    sops.secrets = {
      mastodonDbPassword = {
        owner = config.users.users.mastodon.name;
        key = "mastodon/db_password";
        restartUnits = [ "mastodon-init-db.service" ];
      };
      noreplyFroidmontPassword = {
        owner = config.users.users.mastodon.name;
        key = "email/accounts_passwords/noreply_froidmont_clear";
      };
    };

    services.mastodon = {
      enable = true;
      localDomain = "social.froidmont.org";
      configureNginx = true;
      database = {
        createLocally = false;
        host = "10.0.1.11";
        name = "mastodon";
        user = "mastodon";
        passwordFile = config.sops.secrets.mastodonDbPassword.path;
      };
      smtp = {
        createLocally = false;
        authenticate = true;
        host = "mail.banditlair.com";
        port = 465;
        fromAddress = "noreply@froidmont.org";
        user = "noreply@froidmont.org";
        passwordFile = config.sops.secrets.noreplyFroidmontPassword.path;
      };
      extraConfig = {
        SMTP_SSL = "true";
      };
    };
  };
}
