{
  config,
  pkgs,
  pkgs-unstable,
  ...
}:
{
  imports = [
    ../environment.nix
    ../hardware/hetzner-dedicated-storage1.nix
    ../modules
  ];

  sops.secrets = {
    borgSshKey = {
      owner = config.services.borgbackup.jobs.data.user;
      key = "borg/client_keys/storage1/private";
    };
    nixCacheKey = {
      key = "nix/cache_secret_key";
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
  };

  custom = {
    services.binary-cache = {
      enable = true;
      secretKeyFile = config.sops.secrets.nixCacheKey.path;
    };

    services.backup-job = {
      enable = true;
      repoName = "bl";
      patterns = [
        "- /nix/var/data/media"
        "- /nix/var/data/transmission/downloads"
        "- /nix/var/data/transmission/.incomplete"
      ];
      readWritePaths = [ "/nix/var/data/backup" ];
      startAt = "04:00";
      sshKey = config.sops.secrets.borgSshKey.path;
    };

    services.monit = {
      enable = true;
      additionalConfig = ''
        check program raid-md127 with path "${pkgs.mdadm}/bin/mdadm --misc --detail --test /dev/md127"
          if status != 0 then alert
      '';
    };

    services.nginx.enable = true;
    services.openssh.enable = true;

    services.monero.enable = false;
    services.grafana.enable = true;
    services.monitoring-exporters.enable = true;
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
    mailDirectory = "/nix/var/data/vmail";
    sieveDirectory = "/nix/var/data/sieve";
    lmtpSaveToDetailMailbox = "no";
    policydSPFExtraConfig = ''
      Domain_Whitelist = skynet.be
    '';
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

    certificateScheme = "acme-nginx";
  };

  services.prometheus.exporters.dmarc = {
    enable = true;
    debug = true;
    imap = {
      host = "mail.banditlair.com";
      username = "paultrial@banditlair.com";
      passwordFile = "/run/credentials/prometheus-dmarc-exporter.service/password";
    };
    folders = {
      inbox = "dmarc_reports";
      done = "Archives.dmarc_report_processed";
      error = "Archives.dmarc_report_error";
    };
  };
  systemd.services.prometheus-dmarc-exporter.serviceConfig.LoadCredential = "password:${config.sops.secrets.dmarcExporterPassword.path}";

  networking.firewall.allowedTCPPorts = [
    80
    443
    18080
    23363 # Minecraft
  ];
  networking.firewall.allowedUDPPorts = [
    23363 # Minecraft
  ];
  networking.firewall.interfaces.vlan4001.allowedTCPPorts = [
    config.services.loki.configuration.server.http_listen_port
  ];

  networking.nat.enable = true;
  networking.nat.internalInterfaces = [ "ve-+" ];
  networking.nat.externalInterface = "enp2s0";

  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDQKmE04ZeXN65PTt5cc0YAgBeFukwhP39Ccq9ZxlCkovUMcm9q1Gqgb1tw0hfHCUYK9D6In/qLgNQ6h0Etnesi9HUncl6GC0EE89kNOANZVLuPir0V9Rm7zo55UUUM/qlZe1L7b19oO4qT5tIUlM1w4LfduZuyaag2RDpJxh4xBontftZnCS6O2OI4++/6OKLkn4qtsepxPWb9M6lY/sb6w75LqyUXyjxxArrQMHpE4RQHTCEJiK9t+z5xpfI4WfTnIRQaCw6LxZhE9Kh/pOSVbLU6c5VdBHfCOPk6xrB3TbuUvMpR0cRtn5q0nJQHGhL0A709UXR1fnPm7Xs4GTIf2LWXch6mcrjkTocz8qmKDuMxQzY76QXy6A+rvghhOxnrZTEhLKExZxNqag72MIeippPFNbyOJgke3htHy74b9WjM1vZJ9VRYnmhxpGz0af//GF6LZQy7gOxBasSOv5u5r//1Ow7FNf2K5xYPGYzWRIDx+abMa+JwOyPHdZ9bR+jmB5R9VohFECFLgjm+O5Ed1LJgRX/6vYlB+8gZeeflbZpYYsSY/EcpsUKgtOmIBJT1svdjVTDdplihdFUzWfjL+n2O30K7yniNz6dGbXhxfqOVlp9R6ZsEdbGTX0IGpG+0ZgkUkLrgROAH1xiOYNhpXuD3l6rNXLw4HP3Mqjp3Fw== root@hel1"
  ];

  users.users.www-data = {
    uid = 993;
    createHome = true;
    home = "/home/www-data";
    useDefaultShell = true;
    group = config.users.groups.www-data.name;
    openssh.authorizedKeys.keys = [
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDc7kX8riTSxRNwqIwZ/XwTKHzl1C786TbeU5qx2gTidR4H56+GxA5jrpWLZrcu0MRBu11/URzyGrJGxdBps6Hu/Arp482Y5OxZeDUzD+tZJa79NylG9GQFMTmGLjH3IqBbmgx91WdYsLmgXjz0f+NxANzmgvzRt2IolHc4hxIkrDickfT2dT3uVtaJOGBsLC2BxVT0rCHFmvjB7+qnJ4jvC8b/V+F6+hijom1kUq9zhZzWEg8H5imR0UoXrXLetxY+PGAqKkDLm/pNQ/cUSX4FaKZ5bpGYed7ioSeRHW3xIh4zHhWbiyBPsrjyOmEnxNL5f4o4KgHfUDY0DpVrhs+6JPJTsMfsyb0GciqSYR5PCL73zY+IEo+ZHdGubib4G5+t1UqaK+ZZGqW+a7DLHMFR6tr3I/b/Jz8KHjYztdx/ZHS3CA2+17JgLG/ycq+a3ETBkIGSta5I4BUfcbVvkxKq7A99aODDyYc+jMp7gbQlwKhdHcAoVcWRKqck/sL0Qnb4e+BoUm+ajxRo6DNcpGL5LLtD/i1NuWjFugh6q1KcgXP/Bc11Owhqg3nlIUMUoVc2/h/9Er9Eaplv27rw180ItGR1UEQ4gQHCGQB6vCF5NRPjAS5y515UcDu+rceFIr1W15IZvhMrcphb8clu8E2us68ghas7ZgXKU2xypsaGPw== sshfs-2021-07-16"
    ];
  };
  users.groups.www-data = {
    gid = 991;
  };

  services.openssh.settings.Macs = [
    "hmac-sha2-512-etm@openssh.com"
    "hmac-sha2-256-etm@openssh.com"
    "umac-128-etm@openssh.com"
    "hmac-sha2-256" # Needed for Nextcloud sshfs
  ];

  users.users.steam = {
    isNormalUser = true;
    group = config.users.groups.steam.name;
  };
  users.groups.steam = { };

  services.minecraft-server = {
    enable = false;
    package = pkgs-unstable.minecraft-server;
    eula = true;
    openFirewall = false;
    declarative = true;
    serverProperties = {
      enable-rcon = true;
      "rcon.port" = 25575;
      "rcon.password" = "password";
      server-port = 23363;
      online-mode = true;
      force-gamemode = true;
      white-list = true;
      diffuculty = "hard";
    };
    whitelist = {
      paulplay15 = "1d5abc95-2fdb-4dcb-98e8-4fb5a0fba953";
      Xavier1258 = "e9059cf3-00ef-47a3-92ee-4e4a3fea0e6d";
      denisjulien3333 = "3c93e1a2-42d8-4a51-9fe3-924c8e8d5b07";
    };
    dataDir = "/nix/var/data/minecraft";
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

  # services.rustdesk-server = {
  #   enable = true;
  #   openFirewall = true;
  # };

  services.borgbackup.repos = {
    epicerie_du_cellier = {
      authorizedKeys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJDbiI5UOGpVbaV+xihLqKP0B3UehboMMzOy3HhjjbSz backend1@epicerieducellier.be"
      ];
      path = "/var/lib/epicerie_du_cellier_backup";
    };
  };
}
