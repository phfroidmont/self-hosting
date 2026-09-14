{ config
, lib
, pkgs
, ...
}:
{
  imports = [
    ../environment.nix
    ../hardware/hetzner-dedicated-hel1.nix
    ../modules
  ];

  sops.secrets = {
    borgSshKey = {
      owner = config.services.borgbackup.jobs.data.user;
      key = "borg/client_keys/storage1/private";
    };
    runnerRegistrationConfig = {
      owner = config.users.users.gitlab-runner.name;
      key = "gitlab/runner_registration_config/hel1";
    };
    dmarcExporterPassword = {
      key = "dmarc_exporter/password";
    };
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
    noreplyBanditlairPassword = {
      key = "email/accounts_passwords/noreply_banditlair";
    };
    noreplyFroidmontPassword = {
      key = "email/accounts_passwords/noreply_froidmont";
    };
    nixCacheKey = {
      key = "nix/cache_secret_key";
    };
    chiselAuthFile = {
      key = "chisel/auth.json";
    };
    scaliveDocsTokenSecret = {
      key = "scalive/docs/token_secret";
    };
    newtHel1Environment = {
      key = "newt/hel1/environment";
      restartUnits = [ "newt.service" ];
    };
  };

  time.timeZone = "Europe/Amsterdam";

  # Prevent mdmon from crashing
  boot.swraid.mdadmConf = ''
    HOMEHOST <ignore>
    PROGRAM true
  '';

  networking = {
    firewall.allowedTCPPorts = [
      80
      443
    ];
    nat = {
      enable = true;
      internalInterfaces = [ "ve-+" ];
      externalInterface = "enp41s0";
    };
    interfaces.enp41s0 = {
      ipv6.addresses = [
        {
          address = "2a01:4f9:3100:1202::2";
          prefixLength = 64;
        }
      ];
    };
    defaultGateway6 = {
      address = "fe80::1";
      interface = "enp41s0";
    };
  };

  disko.devices = {
    disk = {
      nvme0 = {
        device = "/dev/nvme0n1";
        type = "disk";
        content = {
          type = "gpt";
          partitions = {
            boot = {
              name = "boot";
              size = "1M";
              type = "EF02";
            };
            mdadm = {
              size = "100%";
              content = {
                type = "mdraid";
                name = "root";
              };
            };
          };
        };
      };
      nvme1 = {
        device = "/dev/nvme1n1";
        type = "disk";
        content = {
          type = "gpt";
          partitions = {
            boot = {
              name = "boot";
              size = "1M";
              type = "EF02";
            };
            mdadm = {
              size = "100%";
              content = {
                type = "mdraid";
                name = "root";
              };
            };
          };
        };
      };
      sda = {
        device = "/dev/sda";
        type = "disk";
        content = {
          type = "gpt";
          partitions = {
            mdadm = {
              size = "100%";
              content = {
                type = "mdraid";
                name = "data";
              };
            };
          };
        };
      };
      sdb = {
        device = "/dev/sdb";
        type = "disk";
        content = {
          type = "gpt";
          partitions = {
            mdadm = {
              size = "100%";
              content = {
                type = "mdraid";
                name = "data";
              };
            };
          };
        };
      };
      sdc = {
        device = "/dev/sdc";
        type = "disk";
        content = {
          type = "gpt";
          partitions = {
            mdadm = {
              size = "100%";
              content = {
                type = "mdraid";
                name = "data";
              };
            };
          };
        };
      };
      sdd = {
        device = "/dev/sdd";
        type = "disk";
        content = {
          type = "gpt";
          partitions = {
            mdadm = {
              size = "100%";
              content = {
                type = "mdraid";
                name = "data";
              };
            };
          };
        };
      };
    };
    mdadm = {
      root = {
        type = "mdadm";
        level = 1;
        content = {
          type = "gpt";
          partitions.primary = {
            size = "100%";
            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/";
            };
          };
        };
      };
      data = {
        type = "mdadm";
        level = 10;
        content = {
          type = "gpt";
          partitions.primary = {
            size = "100%";
            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/nix/var/data";
            };
          };
        };
      };
    };
  };

  services.openssh = {
    # CI, Borg and Nix clients still need public SSH; root uses Newt's loopback path.
    openFirewall = true;
    settings.PermitRootLogin = lib.mkForce "no";
    extraConfig = ''
      Match User root Address 127.0.0.1,::1
        PermitRootLogin prohibit-password
      Match all
    '';
  };

  custom.services = {
    nginx.enable = true;
    postgresql.enable = true;
    dokuwiki.enable = true;
    openssh.enable = true;
    gitlab-runner = {
      enable = true;
      runnerRegistrationConfigFile = config.sops.secrets.runnerRegistrationConfig.path;
    };
    jellyfin.enable = true;
    torrents.enable = true;
    foundryvtt.enable = true;
    jitsi.enable = true;
    stb.enable = true;
    murmur.enable = true;
    synapse.enable = true;
    nextcloud.enable = true;
    roundcube.enable = true;
    monero.enable = true;
    grafana.enable = true;
    immich.enable = true;
    minecraft-server.enable = true;
    monitoring-exporters.enable = true;
    forgejo.enable = true;
    kots-libramont.enable = true;
    scalive-docs = {
      enable = true;
      port = 4006;
      signingSecretFile = config.sops.secrets.scaliveDocsTokenSecret.path;
      deployAuthorizedKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEIbGHQedFV0L87e12h5wFbHVvxXOye2JHSQ8HiUkFaQ scalive-docs-github-actions";
    };

    backup-job = {
      enable = true;
      repoName = "bl";
      additionalPaths = [
        "/var/lib/acme"
        "/var/vmail"
        "/var/dkim"
        "/var/sieve"
        "/var/lib/nextcloud"
        config.services.minecraft-server.dataDir
      ];
      patterns = [
        "- /nix/var/data/media"
        "- /nix/var/data/slskd"
        "- /nix/var/data/transmission/downloads"
        "- /nix/var/data/transmission/.incomplete"
        "- /nix/var/data/dokuwiki/*/data/locks"
      ];
      readWritePaths = [
        "/nix/var/data/murmur"
        "/nix/var/data/postgresql"
        "/nix/var/data/backup/"
        "/run"
      ];
      preHook = ''
        cp /var/lib/murmur/murmur.sqlite /nix/var/data/murmur/murmur.sqlite
        ${config.services.postgresql.package}/bin/pg_dump -U synapse synapse > /nix/var/data/postgresql/synapse.dmp
        ${config.services.postgresql.package}/bin/pg_dump -U nextcloud nextcloud > /nix/var/data/postgresql/nextcloud.dmp
        ${config.services.postgresql.package}/bin/pg_dump -U roundcube roundcube > /nix/var/data/postgresql/roundcube.dmp
        ${config.services.postgresql.package}/bin/pg_dump -U immich immich > /nix/var/data/postgresql/immich.dmp
        ${config.services.postgresql.package}/bin/pg_dump -U forgejo forgejo > /nix/var/data/postgresql/forgejo.dmp
        ${pkgs.systemd}/bin/systemctl start --wait stb-mariadb-dump.service
        ${pkgs.systemd}/bin/systemctl stop jellyfin.service
        ${pkgs.systemd}/bin/systemctl --machine=torrents stop transmission.service
        ${pkgs.systemd}/bin/systemctl --machine=torrents stop slskd.service
        ${pkgs.systemd}/bin/systemctl --machine=torrents stop jackett.service
        ${pkgs.systemd}/bin/systemctl --machine=torrents stop sonarr.service
        ${pkgs.systemd}/bin/systemctl --machine=torrents stop radarr.service
        ${pkgs.systemd}/bin/systemctl --machine=torrents stop lidarr.service
      '';
      postHook = ''
        ${pkgs.systemd}/bin/systemctl --machine=torrents start lidarr.service
        ${pkgs.systemd}/bin/systemctl --machine=torrents start radarr.service
        ${pkgs.systemd}/bin/systemctl --machine=torrents start sonarr.service
        ${pkgs.systemd}/bin/systemctl --machine=torrents start jackett.service
        ${pkgs.systemd}/bin/systemctl --machine=torrents start slskd.service
        ${pkgs.systemd}/bin/systemctl --machine=torrents start transmission.service
        ${pkgs.systemd}/bin/systemctl start jellyfin.service
      '';
      startAt = "02:00";
      sshKey = config.sops.secrets.borgSshKey.path;
    };

    monit = {
      enable = true;
      additionalConfig = ''
        check host nextcloud with address cloud.banditlair.com
          if failed port 443 protocol https with timeout 20 seconds then alert
        check host anderia-wiki with address anderia.banditlair.com
          if failed port 443 protocol https with timeout 20 seconds then alert
        check host arkadia-wiki with address arkadia.banditlair.com
          if failed port 443 protocol https with timeout 20 seconds then alert
        check host website-marie with address osteopathie.froidmont.org
          if failed port 443 protocol https with timeout 20 seconds then alert
        check host scalive-docs with address scalive.dev
          if failed
              port 443
              protocol https
              status = 200
              request "/health"
              with timeout 20 seconds
          then alert
        check host webmail with address webmail.banditlair.com
          if failed port 443 protocol https with timeout 20 seconds then alert
        check host jellyfin with address jellyfin.banditlair.com
          if failed port 443 protocol https with timeout 20 seconds then alert
        check host stb with address www.societe-de-tir-bertrix.com
          if failed port 443 protocol https with timeout 20 seconds then alert
        check host transmission with address transmission.banditlair.com
          if failed
              port 443
              protocol https
              status = 401
              with timeout 20 seconds
              for 10 cycles
          then alert

        check file borg-check-done with path /nix/var/data/backup/borg-check-ok
          if changed timestamp then alert
          if timestamp > 8 days then alert

        check file restore-test-done with path /nix/var/data/backup/restore-test-ok
          if changed timestamp then alert
          if timestamp > 8 days then alert

        check program raid-md126 with path "${pkgs.mdadm}/bin/mdadm --misc --detail --test /dev/md126"
          if status != 0 then alert
        check program raid-md127 with path "${pkgs.mdadm}/bin/mdadm --misc --detail --test /dev/md127"
          if status != 0 then alert

        check filesystem data with path /nix/var/data
          if SPACE usage > 90% then alert

        check host osteoview with address osteoview.app
          if failed
              port 443
              protocol https
              status = 200
              request "/api/_health"
              with timeout 5 seconds
              content = "Healthy"
          then alert

        check host osteoview-demo with address demo.osteoview.app
          if failed
              port 443
              protocol https
              status = 200
              request "/api/_health"
              with timeout 5 seconds
              content = "Healthy"
          then alert
      '';
    };
  };

  services.uptime-kuma = {
    enable = true;
    settings = {
      HOST = "127.0.0.1";
      PORT = "3001";
    };
  };

  services.newt = {
    enable = true;
    package = pkgs.callPackage ../packages/pangolin/newt.nix { };
    settings = {
      endpoint = "https://pangolin.banditlair.com";
      disable-ssh = true;
    };
    environmentFile = config.sops.secrets.newtHel1Environment.path;
    blueprint.private-resources.hel1-ssh = {
      name = "hel1 SSH";
      mode = "host";
      destination = "127.0.0.1";
      alias = "hel1.bl.internal";
      tcp-ports = "22";
      udp-ports = "";
      disable-icmp = true;
      roles = [ "Personal" ];
      users = [ ];
    };
    blueprint.private-resources.grafana = {
      name = "Grafana";
      mode = "http";
      destination = "127.0.0.1";
      destination-port = config.services.grafana.settings.server.http_port;
      scheme = "http";
      full-domain = config.services.grafana.settings.server.domain;
      ssl = true;
      roles = [ "Personal" ];
      users = [ ];
    };
    blueprint.private-resources.monero = {
      name = "Monero RPC";
      mode = "http";
      destination = config.services.monero.rpc.address;
      destination-port = config.services.monero.rpc.port;
      scheme = "http";
      full-domain = "monero.${config.networking.domain}";
      ssl = true;
      roles = [ "Personal" ];
      users = [ ];
    };
    blueprint.private-resources.uptime-kuma = {
      name = "Uptime Kuma";
      mode = "http";
      destination = "127.0.0.1";
      destination-port = 3001;
      scheme = "http";
      full-domain = "uptime.banditlair.com";
      ssl = true;
      roles = [ "Personal" "Member" ];
      users = [ ];
    };
  };

  services.nginx.virtualHosts = {

    "froidmont.org" = {
      enableACME = true;
      forceSSL = true;
    };

    "osteopathie.froidmont.org" = {
      enableACME = true;
      forceSSL = true;
      root = "/nix/var/data/website-marie";
    };
    "www.fautlfer.com" = {
      enableACME = true;
      forceSSL = true;

      locations."= /".extraConfig = ''
        return 302 https://blogz.zaclys.com/faut-l-fer/;
      '';
    };
    "fautlfer.com" = {
      enableACME = true;
      forceSSL = true;

      locations."= /".extraConfig = ''
        return 302 https://blogz.zaclys.com/faut-l-fer/;
      '';
    };
  };

  # virtualisation.oci-containers.containers = {
  #   "minecraft" = {
  #     image = "itzg/minecraft-server";
  #     environment = {
  #       EULA = "TRUE";
  #       VERSION = "1.18.2";
  #       TYPE = "AUTO_CURSEFORGE";
  #       MEMORY = "4G";
  #       CF_SLUG = "modecube"; # https://www.curseforge.com/minecraft/modpacks/modecube/files
  #     };
  #     ports = [ "25565:25565" ];
  #     volumes = [ "/nix/var/data/minecraft-modded:/data" ];
  #     autoStart = true;
  #   };
  # };

  users.users.www-data = {
    uid = 993;
    group = config.users.groups.www-data.name;
  };

  users.groups.www-data = {
    gid = 991;
  };

  mailserver = {
    enable = true;
    fqdn = "mail.banditlair.com";
    domains = [
      "banditlair.com"
      "froidmont.org"
      "falbo.fr"
    ];
    localDnsResolver = false;
    enableManageSieve = true;
    lmtpSaveToDetailMailbox = false;
    # policydSPFExtraConfig = ''
    #   Domain_Whitelist = skynet.be
    # '';
    accounts = {
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
          "kots-libramont@froidmont.org"
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
        ];
      };
      "monit@banditlair.com" = {
        hashedPasswordFile = config.sops.secrets.monitPassword.path;
        sendOnly = true;
      };
      "noreply@banditlair.com" = {
        hashedPasswordFile = config.sops.secrets.noreplyBanditlairPassword.path;
        sendOnly = true;
      };
      "noreply@froidmont.org" = {
        hashedPasswordFile = config.sops.secrets.noreplyFroidmontPassword.path;
        sendOnly = true;
      };
    };
    aliases = {
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

    x509.useACMEHost = "mail.banditlair.com";

    stateVersion = 5;
  };

  services.rspamd.extraConfig = ''
    actions {
      reject = null; # Disable rejects, default is 15
      add_header = 6; # Add header when reaching this score
      greylist = null; # Disable greylist
    }
  '';

  nix = {
    settings = {
      trusted-users = [ "nix-ssh" ];
      secret-key-files = [ config.sops.secrets.nixCacheKey.path ];
    };
    sshServe = {
      enable = true;
      write = true;
      keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIODEuNOPisaBoF+7CGpWO80n0v5kg1LNMN4yD/wr4cCL root@nixos-desktop"
      ];
    };
  };

  services.borgbackup.repos = {
    epicerie_du_cellier = {
      authorizedKeys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJDbiI5UOGpVbaV+xihLqKP0B3UehboMMzOy3HhjjbSz backend1@epicerieducellier.be"
      ];
      path = "/nix/var/data/epicerie_du_cellier_backup";
    };
  };

  services.chisel-server = {
    enable = true;
    reverse = true;
    socks5 = true;
    port = 34220;
    host = "127.0.0.1";
    authfile = "/run/credentials/chisel-server.service/authfile";
  };

  systemd.services.chisel-server.serviceConfig.LoadCredential =
    "authfile:${config.sops.secrets.chiselAuthFile.path}";

  services.nginx.virtualHosts."ch.${config.networking.domain}" = {
    enableACME = true;
    forceSSL = true;
    locations."/" = {
      proxyPass = "http://127.0.0.1:${toString config.services.chisel-server.port}";
      proxyWebsockets = true;
    };
  };
}
