{ config, lib, pkgs, ... }:
{

  sops.secrets = {
    paultrialPassword = {
      key = "email/accounts_passwords/paultrial";
    };
  };

  mailserver = {
    enable = true;
    fqdn = "mail2.banditlair.com";
    domains = [ "banditlair.com" "froidmont.org" "falbo.fr" ];
    # mailDirectory = "/nix/var/data/vmail";
    loginAccounts = {
      "paultrial@banditlair.com" = {
        # nix run nixpkgs.apacheHttpd -c htpasswd -nbB "" "super secret password" | cut -d: -f2 > /hashed/password/file/location
        hashedPasswordFile = config.sops.secrets.paultrialPassword.path;
      };
    };
    extraVirtualAliases = {
      "info@banditlair.com" = "paultrial@banditlair.com";
      "postmaster@banditlair.com" = "paultrial@banditlair.com";
      "abuse@banditlair.com" = "paultrial@banditlair.com";

      "info@froidmont.org" = "paultrial@banditlair.com";
      "postmaster@froidmont.org" = "paultrial@banditlair.com";
      "abuse@froidmont.org" = "paultrial@banditlair.com";

      "info@falbo.fr" = "paultrial@banditlair.com";
      "postmaster@falbo.fr" = "paultrial@banditlair.com";
      "abuse@falbo.fr" = "paultrial@banditlair.com";
    };


    # certificateScheme = 3;
  };

}
