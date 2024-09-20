{
  config,
  lib,
  pkgs,
  pkgs-unstable,
  ...
}:
{
  imports = [
    ../environment.nix
    ../hardware/hcloud.nix
    ../modules
  ];

  sops.secrets = {
    borgSshKey = {
      owner = config.services.borgbackup.jobs.data.user;
      key = "borg/client_keys/backend1/private";
    };
    dolibarrDbPassword = {
      owner = config.users.users.dolibarr.name;
      key = "dolibarr/db_password";
      restartUnits = [ "phpfpm-dolibarr.service" ];
    };
  };

  custom = {

    services.backup-job = {
      enable = true;
      repoName = "bk1";
      additionalPaths = [
        "/var/lib/nextcloud/config"
        "/var/lib/mastodon"
      ];
      readWritePaths = [
        "/nix/var/data/murmur"
        "/nix/var/data/backup/"
      ];
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
              content = "Healthy"
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
    settings = {
      PORT = "3001";
    };
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
        proxyPass = "http://127.0.0.1:${config.services.uptime-kuma.settings.PORT}";
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

  services.dolibarr = {
    enable = true;
    domain = "dolibarr.froidmont.solutions";
    stateDir = "/nix/var/data/dolibarr";
    database = {
      createLocally = false;
      host = "10.0.1.11";
      port = 5432;
      name = "dolibarr";
      user = "dolibarr";
      passwordFile = config.sops.secrets.dolibarrDbPassword.path;
    };
    settings = {
      dolibarr_main_db_type = lib.mkForce "pgsql";
    };
    nginx = {
      # https://wiki.dolibarr.org/index.php/Module_Web_Services_API_REST_(developer)#Nginx_setup
      locations."~ [^/]\\.php(/|$)".extraConfig = ''
        fastcgi_param  SCRIPT_FILENAME $document_root$fastcgi_script_name;
        include        ${config.services.nginx.package}/conf/fastcgi_params;
        # Dolibarr Rest API path support
        fastcgi_param  PATH_INFO       $fastcgi_path_info;
        fastcgi_param  PATH_TRANSLATED $document_root$fastcgi_script_name;
      '';
    };
  };

  nixpkgs.config.permittedInsecurePackages = [ "qtwebkit-5.212.0-alpha4" ];
  services.odoo = {
    enable = false;
    package = pkgs-unstable.odoo.override {
      python310 = pkgs.python310.override {
        packageOverrides = final: prev: {
          furl = prev.furl.overridePythonAttrs (old: {
            doCheck = false;
          });
        };
      };
    };
    domain = "odoo.froidmont.solutions";
    settings = {
      options = {
        db_host = "10.0.1.11";
        db_port = 5432;
        db_name = "odoo";
        db_user = "odoo";
        db_password = "odoo";
        data_dir = "/var/lib/private/odoo/data";
      };
    };
  };
  services.nginx.virtualHosts = {
    ${config.services.odoo.domain} = {
      forceSSL = true;
      enableACME = true;
    };
  };
  services.postgresql.enable = lib.mkForce false;
  # systemd.services.odoo = {
  #   after = lib.mkForce [ "network.target" ];
  #   requires = lib.mkForce [ ];
  # };

  networking.firewall.allowedTCPPorts = [
    80
    443
    64738
  ];
  networking.firewall.allowedUDPPorts = [ 64738 ];
  networking.firewall.interfaces."eth1".allowedTCPPorts = [
    config.services.prometheus.exporters.node.port
    9000
  ];

}
