{ config, lib, pkgs, ... }:
{
  imports = [
    ../environment.nix
    ../hardware/hcloud.nix
    ../modules/openssh.nix
    ../modules/nginx.nix
    ../modules/murmur.nix
    ../modules/synapse.nix
    ../modules/nextcloud.nix
    ../modules/custom-backup-job.nix
    ../modules/dokuwiki.nix
    ../modules/website-marie.nix
  ];

  sops.secrets = {
    borgSshKey = {
      owner = config.services.borgbackup.jobs.data.user;
      key = "borg/client_keys/backend1/private";
    };
  };

  services.custom-backup-job = {
    additionalPaths = [ "/var/lib/nextcloud/config" ];
    readWritePaths = [ "/nix/var/data/murmur" ];
    preHook = "cp /var/lib/murmur/murmur.sqlite /nix/var/data/murmur/murmur.sqlite";
    startAt = "03:30";
    sshKey = config.sops.secrets.borgPassphrase.path;
  };

  networking.interfaces.enp1s0 = {
    useDHCP = true;
    ipv4 = {
      addresses = [
        {
          address = "95.216.177.3";
          prefixLength = 32;
        }
      ];
    };
  };

  networking.firewall.allowedTCPPorts = [ 80 443 64738 ];
  networking.firewall.allowedUDPPorts = [ 64738 ];

  services.monit = {
    enable = true;
    config = ''
      set daemon 30
        with start delay 90

      set httpd
        port 2812
        use address 127.0.0.1
        allow localhost

      check file nextcloud-data-mounted with path /var/lib/nextcloud/data/index.html
        start = "${pkgs.systemd}/bin/systemctl start nextcloud-data-sshfs.service"
    '';
  };
}
