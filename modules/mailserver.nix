{ config, lib, pkgs, ... }:
{

  sops.secrets = {
    paultrialPassword = {
      key = "email/accounts_passwords/paultrial";
    };
    eliosPassword = {
      key = "email/accounts_passwords/elios";
    };
    mariePassword = {
      key = "email/accounts_passwords/marie";
    };
    alicePassword = {
      key = "email/accounts_passwords/alice";
    };
    monitPassword = {
      key = "email/accounts_passwords/monit";
    };
  };

  mailserver = {
    enable = true;
    fqdn = "mail.banditlair.com";
    domains = [ "banditlair.com" "froidmont.org" "falbo.fr" ];
    enableManageSieve = true;
    mailDirectory = "/nix/var/data/vmail";
    sieveDirectory = "/nix/var/data/sieve";
    lmtpSaveToDetailMailbox = "no";
    loginAccounts = {
      "paultrial@banditlair.com" = {
        # nix run nixpkgs.apacheHttpd -c htpasswd -nbB "" "super secret password" | cut -d: -f2 > /hashed/password/file/location
        hashedPasswordFile = config.sops.secrets.paultrialPassword.path;
        aliases = [
          "contact@froidmont.org"
          "account@banditlair.com"
        ];
      };
      "marie-alice@froidmont.org" = {
        hashedPasswordFile = config.sops.secrets.mariePassword.path;
        aliases = [
          "osteopathie@froidmont.org"
          "communication@froidmont.org"
          "crelan.communication@froidmont.org"
          "kerger.communication@froidmont.org"
          "3arcs.communication@froidmont.org"
          "7days.communication@froidmont.org"
          "ulb.communication@froidmont.org"
          "baijot.communication@froidmont.org"
          "alltrails.communication@froidmont.org"
          "alltricks.communication@froidmont.org"
          "amazon.communication@froidmont.org"
          "athletv.communication@froidmont.org"
          "bebecenter.communication@froidmont.org"
          "canyon.communication@froidmont.org"
          "cbc.communication@froidmont.org"
          "coursulb.communication@froidmont.org"
          "decathlon.communication@froidmont.org"
          "degiro.communication@froidmont.org"
          "delogne.communication@froidmont.org"
          "diagnosteo.communication@froidmont.org"
          "haptis.communication@froidmont.org"
          "fortis.communication@froidmont.org"
          "fox.communication@froidmont.org"
          "vandenborre.communication@froidmont.org"
          "swissquote.communication@froidmont.org"
          "belso.communication@froidmont.org"
          "hibike.communication@froidmont.org"
          "giromedical.communication@froidmont.org"
          "gymna.communication@froidmont.org"
          "hotmail.communication@froidmont.org"
          "hubo.communication@froidmont.org"
          "infopixel.communication@froidmont.org"
          "jysk.communication@froidmont.org"
          "kerger.communication@froidmont.org"
          "ldlc.communication@froidmont.org"
          "location.communication@froidmont.org"
          "mainslibres.communication@froidmont.org"
          "vistaprint.communication@froidmont.org"
          "solidaris.communication@froidmont.org"
          "coulon.communication@froidmont.org"
          "vlan.communication@froidmont.org"
          "hotel.communication@froidmont.org"
          "medipost.communication@froidmont.org"
          "proximus.communication@froidmont.org"
          "marie.communication@froidmont.org"
          "tuxedo.communication@froidmont.org"
          "corine.wallaux.communication@froidmont.org"
          "maziers.communication@froidmont.org"
          "miliboo.communication@froidmont.org"
          "nike.communication@froidmont.org"
          "partena.communication@froidmont.org"
          "payconiq.communication@froidmont.org"
          "plumart.communication@froidmont.org"
          "probikeshop.communication@froidmont.org"
          "ring.communication@froidmont.org"
          "teams.communication@froidmont.org"
          "trail.communication@froidmont.org"
          "wikiloc.communication@froidmont.org"
          "udemy.communication@froidmont.org"
        ];
      };
      "alice@froidmont.org" = {
        hashedPasswordFile = config.sops.secrets.alicePassword.path;
      };
      "elios@banditlair.com" = {
        hashedPasswordFile = config.sops.secrets.eliosPassword.path;
        aliases = [
          "webshit@banditlair.com"
          "outlook-pascal@banditlair.com"
          "nexusmods.webshit@banditlair.com"
          "pizza.webshit@banditlair.com"
          "fnac.webshit@banditlair.com"
          "paypal.webshit@banditlair.com"
          "zooplus.webshit@banditlair.com"
          "event.webshit@banditlair.com"
          "reservation.webshit@banditlair.com"
          "netflix.webshit@banditlair.com"
          "jvc.webshit@banditlair.com"
          "kickstarter.webshit@banditlair.com"
          "vpn.webshit@banditlair.com"
          "VOO.WEBSHIT@banditlair.com"
          "proximus.webshit@banditlair.com"
          "post.webshit@banditlair.com"
          "ikea.webshit@banditlair.com"
          "microsoft.webshit@banditlair.com"
          "zerotier.webshit@banditlair.com"
          "athome.webshit@banditlair.com"
          "nordvpn.webshit@banditlair.com"
          "sncf.webshit@banditlair.com"
          "paradox.webshit@banditlair.com"
          "oracle.webshit@banditlair.com"
          "kinepolis.webshit@banditlair.com"
          "leboncoin.webshit@banditlair.com"
          "wondercraft.webshit@banditlair.com"
          "petitvapoteur.webshit@banditlair.com"
          "ryanair.webshit@banditlair.com"
          "europapark.webshit@banditlair.com"
          "Tricount.webshit@banditlair.com"
          "huawei.webshit@banditlair.com"
          "facebook.webshit@banditlair.com"
          "roll20.webshit@banditlair.com"
          "drivethrurpg.webshit@banditlair.com"
          "chrono24.webshit@banditlair.com"
          "emby.webshit@banditlair.com"
          "amazon.webshit@banditlair.com"
          "steam.webshit@banditlair.com"
          "tinder.webshit@banditlair.com"
        ];
      };
      "monit@banditlair.com" = {
        hashedPasswordFile = config.sops.secrets.monitPassword.path;
        sendOnly = true;
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

      #Catch all
      "@banditlair.com" = "paultrial@banditlair.com";
      "@froidmont.org" = "paultrial@banditlair.com";
      "@falbo.fr" = "elios@banditlair.com";
    };


    certificateScheme = 3;
  };

}
