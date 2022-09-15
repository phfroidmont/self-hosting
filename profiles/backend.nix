{ config, lib, pkgs, ... }:
{
  imports = [
    ../environment.nix
    ../hardware/hcloud.nix
    ../modules
    ../modules/nginx.nix
    ../modules/synapse.nix
    ../modules/nextcloud.nix
    ../modules/dokuwiki.nix
    ../modules/website-marie.nix
    ../modules/roundcube.nix
    ../modules/monitoring-exporters.nix
  ];

  sops.secrets = {
    borgSshKey = {
      owner = config.services.borgbackup.jobs.data.user;
      key = "borg/client_keys/backend1/private";
    };
  };

  custom = {
    services.backup-job = {
      enable = true;
      additionalPaths = [ "/var/lib/nextcloud/config" ];
      readWritePaths = [ "/nix/var/data/murmur" "/nix/var/data/backup/" ];
      preHook = ''
        cp /var/lib/murmur/murmur.sqlite /nix/var/data/murmur/murmur.sqlite
      '';
      postHook = ''
        touch /nix/var/data/backup/backup-ok
      '';
      startAt = "03:30";
      sshKey = config.sops.secrets.borgSshKey.path;
    };

    services.monit = {
      enable = true;
      additionalConfig = ''
        check file nextcloud-data-mounted with path /var/lib/nextcloud/data/index.html
          start = "${pkgs.systemd}/bin/systemctl start nextcloud-data-sshfs.service"

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
          then alert
      '';
    };

    services.dokuwiki.enable = true;

    services.openssh.enable = true;

    services.murmur.enable = true;
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
  networking.firewall.interfaces."enp7s0".allowedTCPPorts = [ config.services.prometheus.exporters.node.port ];

}
