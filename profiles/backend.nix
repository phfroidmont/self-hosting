{ config, lib, pkgs, ... }: {
  imports = [ ../environment.nix ../hardware/hcloud.nix ../modules ];

  sops.secrets = {
    borgSshKey = {
      owner = config.services.borgbackup.jobs.data.user;
      key = "borg/client_keys/backend1/private";
    };
  };

  custom = {

    services.backup-job = {
      enable = true;
      repoName = "bk1";
      additionalPaths = [ "/var/lib/nextcloud/config" "/var/lib/mastodon" ];
      readWritePaths = [ "/nix/var/data/murmur" "/nix/var/data/backup/" ];
      preHook = ''
        cp /var/lib/murmur/murmur.sqlite /nix/var/data/murmur/murmur.sqlite
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

        check host osteoview with address osteoview.app
          if failed
              port 443
              protocol https
              status = 200
              request "/api/_health"
              with timeout 5 seconds
              content = '[{"]Healthy["]:[{}}]'
          then alert
      '';
    };

    services.nginx.enable = true;
    services.dokuwiki.enable = true;
    services.openssh.enable = true;
    services.murmur.enable = true;
    services.mastodon.enable = false;
    services.synapse.enable = true;
    services.nextcloud.enable = true;
    services.roundcube.enable = true;
    services.monitoring-exporters.enable = true;
  };

  services.uptime-kuma = {
    enable = true;
    settings = { PORT = "3001"; };
  };

  services.nginx.virtualHosts = {
    "osteopathie.froidmont.org" = {
      enableACME = true;
      forceSSL = true;
      root = "/nix/var/data/website-marie";
    };

    "uptime.froidmont.org" = {
      serverAliases = [ "status.${config.networking.domain}" ];
      forceSSL = true;
      enableACME = true;

      locations."/" = {
        proxyPass =
          "http://127.0.0.1:${config.services.uptime-kuma.settings.PORT}";
        proxyWebsockets = true;
      };
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

  networking.firewall.allowedTCPPorts = [ 80 443 64738 ];
  networking.firewall.allowedUDPPorts = [ 64738 ];
  networking.firewall.interfaces."eth1".allowedTCPPorts =
    [ config.services.prometheus.exporters.node.port 9000 ];

}
