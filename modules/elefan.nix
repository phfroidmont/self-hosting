{ config, lib, pkgs, ... }:
let
  composer = pkgs.php81Packages.composer.overrideDerivation (old: {
    version = "2.2.18";
    src = pkgs.fetchurl {
      url = "https://getcomposer.org/download/2.2.18/composer.phar";
      sha256 = "sha256-KKjZdA1hUTeowB0yrvkYTbFvVD/KNtsDhQGilNjpWyQ=";
    };
  });
in
{

  containers.elefan-test = {
    ephemeral = false;
    autoStart = true;

    privateNetwork = true;
    hostAddress = "192.168.101.1";
    localAddress = "192.168.101.2";


    config = {
      time.timeZone = "Europe/Amsterdam";

      environment.systemPackages = with pkgs; [ php74 git composer tmux vim ];

      networking.firewall.allowedTCPPorts = [ 80 ];

      users.groups.php = { };
      users.users.php = {
        isNormalUser = true;
        group = config.containers.elefan-test.config.users.groups.php.name;
      };

      services.mysql = {
        enable = true;
        package = pkgs.mariadb_108;
        initialDatabases = [{
          name = "symfony";
        }];
        ensureUsers = [
          {
            name = "symfony";
            ensurePermissions = {
              "symfony.*" = "ALL PRIVILEGES";
            };
          }
          {
            name = "root";
            ensurePermissions = {
              "*.*" = "ALL PRIVILEGES";
            };
          }
        ];
      };

      services.nginx = {
        enable = true;
        virtualHosts."elefan-test.froidmont.org" = {
          default = true;

          root = "/var/www/elefan-test/web";

          locations."/" = {
            extraConfig = ''
              try_files $uri /app.php$is_args$args;
            '';
          };

          locations."~ ^/app\\.php(/|$)" = {
            extraConfig = ''
              fastcgi_pass unix:${config.containers.elefan-test.config.services.phpfpm.pools.elefan-test.socket};
              fastcgi_intercept_errors on;
              fastcgi_split_path_info ^(.+\.php)(/.*)$;
              include ${config.services.nginx.package}/conf/fastcgi.conf;
              fastcgi_param SCRIPT_FILENAME $realpath_root$fastcgi_script_name;
              fastcgi_param DOCUMENT_ROOT $realpath_root;
              internal;
            '';
          };

          locations."~* ^/sw/(.*)/(qr|br)\\.png$" = {
            extraConfig = ''
              rewrite ^/sw/(.*)/(qr|br)\.png$ /app.php/sw/$1/$2.png last;
            '';
          };

          extraConfig = ''
            location ~ \.php$ {
              return 404;
            }
          '';
        };
      };

      services.phpfpm.pools.elefan-test = {
        user = "nginx";
        settings = {
          pm = "dynamic";
          "listen.owner" = config.containers.elefan-test.config.services.nginx.user;
          "pm.max_children" = 5;
          "pm.start_servers" = 2;
          "pm.min_spare_servers" = 1;
          "pm.max_spare_servers" = 3;
          "pm.max_requests" = 500;
        };
      };

      system.stateVersion = "22.05";
    };
  };

  services.nginx.virtualHosts."elefan-test.froidmont.org" = {
    forceSSL = true;
    enableACME = true;

    locations."/" = {
      proxyPass = "http://192.168.101.2";
    };
  };
}
