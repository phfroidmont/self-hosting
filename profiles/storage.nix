{ config, lib, pkgs, pkgs-unstable, ... }:
{
  imports = [
    ../environment.nix
    ../hardware/hetzner-dedicated-storage1.nix
    ../modules
    ../modules/openssh.nix
    ../modules/mailserver.nix
    ../modules/nginx.nix
    ../modules/jellyfin.nix
    ../modules/stb.nix
    ../modules/monero.nix
    ../modules/torrents.nix
    ../modules/jitsi.nix
    ../modules/binary-cache.nix
    ../modules/grafana.nix
    ../modules/monitoring-exporters.nix
    ../modules/elefan.nix
  ];

  sops.secrets = {
    borgSshKey = {
      owner = config.services.borgbackup.jobs.data.user;
      key = "borg/client_keys/storage1/private";
    };
    nixCacheKey = {
      key = "nix/cache_secret_key";
    };
  };

  custom = {
    services.binary-cache = {
      enable = true;
      secretKeyFile = config.sops.secrets.nixCacheKey.path;
    };

    services.backup-job = {
      enable = true;
      readWritePaths = [ "/nix/var/data/backup" ];
      preHook = "${pkgs.docker}/bin/docker exec stb-mariadb sh -c 'mysqldump -u stb -pstb stb' > /nix/var/data/backup/stb_mariadb.sql";
      postHook = "touch /nix/var/data/backup/backup-ok";
      startAt = "04:00";
      sshKey = config.sops.secrets.borgSshKey.path;
    };

    services.monit = {
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
        check host webmail with address webmail.banditlair.com
          if failed port 443 protocol https with timeout 20 seconds then alert

        check program raid-md127 with path "${pkgs.mdadm}/bin/mdadm --misc --detail --test /dev/md127"
          if status != 0 then alert

        check host osteoview with address osteoview.app
          if failed port 443 protocol https with timeout 5 seconds then alert
      '';
    };

    services.gitlab-runner.enable = true;
    services.openssh.enable = true;
  };

  networking.firewall.allowedTCPPorts = [ 80 443 18080 ];
  networking.firewall.interfaces.vlan4001.allowedTCPPorts = [ config.services.loki.configuration.server.http_listen_port ];

  networking.nat.enable = true;
  networking.nat.internalInterfaces = [ "ve-+" ];
  networking.nat.externalInterface = "enp2s0";

  users.users.www-data = {
    uid = 993;
    isNormalUser = true;
    group = config.users.groups.www-data.name;
    openssh.authorizedKeys.keys = [
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDc7kX8riTSxRNwqIwZ/XwTKHzl1C786TbeU5qx2gTidR4H56+GxA5jrpWLZrcu0MRBu11/URzyGrJGxdBps6Hu/Arp482Y5OxZeDUzD+tZJa79NylG9GQFMTmGLjH3IqBbmgx91WdYsLmgXjz0f+NxANzmgvzRt2IolHc4hxIkrDickfT2dT3uVtaJOGBsLC2BxVT0rCHFmvjB7+qnJ4jvC8b/V+F6+hijom1kUq9zhZzWEg8H5imR0UoXrXLetxY+PGAqKkDLm/pNQ/cUSX4FaKZ5bpGYed7ioSeRHW3xIh4zHhWbiyBPsrjyOmEnxNL5f4o4KgHfUDY0DpVrhs+6JPJTsMfsyb0GciqSYR5PCL73zY+IEo+ZHdGubib4G5+t1UqaK+ZZGqW+a7DLHMFR6tr3I/b/Jz8KHjYztdx/ZHS3CA2+17JgLG/ycq+a3ETBkIGSta5I4BUfcbVvkxKq7A99aODDyYc+jMp7gbQlwKhdHcAoVcWRKqck/sL0Qnb4e+BoUm+ajxRo6DNcpGL5LLtD/i1NuWjFugh6q1KcgXP/Bc11Owhqg3nlIUMUoVc2/h/9Er9Eaplv27rw180ItGR1UEQ4gQHCGQB6vCF5NRPjAS5y515UcDu+rceFIr1W15IZvhMrcphb8clu8E2us68ghas7ZgXKU2xypsaGPw== sshfs-2021-07-16"
    ];
  };
  users.groups.www-data = { gid = 991; };

  users.users.steam = {
    isNormalUser = true;
    group = config.users.groups.steam.name;
  };
  users.groups.steam = { };

  services.minecraft-server = {
    enable = true;
    package = pkgs-unstable.minecraft-server;
    eula = true;
    openFirewall = true;
    declarative = true;
    serverProperties = {
      online-mode = true;
      force-gamemode = true;
      white-list = true;
    };
    whitelist = {
      paulplay15 = "1d5abc95-2fdb-4dcb-98e8-4fb5a0fba953";
      Nixo = "ec79d755-c3c9-4307-bb66-b58b7c74422c";
      Xavier1258 = "e9059cf3-00ef-47a3-92ee-4e4a3fea0e6d";
      denisjulien3333 = "3c93e1a2-42d8-4a51-9fe3-924c8e8d5b07";
    };
    dataDir = "/nix/var/data/minecraft";
  };
}
