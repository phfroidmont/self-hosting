{ config, lib, pkgs, ... }:
{
  imports = [
    ../environment.nix
    ../hardware/hetzner-dedicated-storage1.nix
    ../modules/openssh.nix
    ../modules/mailserver.nix
    ../modules/nginx.nix
    ../modules/jellyfin.nix
    ../modules/stb.nix
    ../modules/monero.nix
    ../modules/torrents.nix
    ../modules/custom-backup-job.nix
    ../modules/custom-monit.nix
    ../modules/jitsi.nix
  ];

  sops.secrets = {
    borgSshKey = {
      owner = config.services.borgbackup.jobs.data.user;
      key = "borg/client_keys/storage1/private";
    };
  };

  networking.firewall.allowedTCPPorts = [ 80 443 18080 ];

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

  services.custom-backup-job = {
    readWritePaths = [ "/nix/var/data/backup" ];
    preHook = "${pkgs.docker}/bin/docker exec stb-mariadb sh -c 'mysqldump -u stb -pstb stb' > /nix/var/data/backup/stb_mariadb.sql";
    postHook = "touch /nix/var/data/backup/backup-ok";
    startAt = "04:00";
    sshKey = config.sops.secrets.borgSshKey.path;
  };

  services.custom-monit.additionalConfig = ''
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
  '';


  nixpkgs.config.allowUnfree = true;
  services.minecraft-server = {
    enable = true;
    eula = true;
    openFirewall = true;
    declarative = true;
    serverProperties = {
      online-mode = false;
      force-gamemode = true;
    };
  };
}
