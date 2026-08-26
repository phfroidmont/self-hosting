{ pkgs
, config
, lib
, ...
}:
let
  cfg = config.custom.services.stb;
  stbUser = "stb";
  stbUid = 5001;
  stbHome = "/var/lib/stb";
  stbNetwork = "stb";
  mariadbDataDir = "${stbHome}/mariadb";
  wordpressDataDir = "/nix/var/data/stb-wordpress";
  databaseDumpFile = "/nix/var/data/backup/stb_mariadb.sql";
  maintenanceFile = "/var/lib/stb-maintenance";
  databasePasswordFile = config.sops.secrets.stbDatabasePassword.path;
  rootPasswordFile = config.sops.secrets.stbDatabaseRootPassword.path;
  wordpressDatabasePasswordFile = "/run/user/${toString stbUid}/stb-secrets/database-password";
  staticHeroFile = ./stb/static-hero.php;
  uploadWordpressConfig = pkgs.writeText "upload.ini" ''
    file_uploads = On
    memory_limit = 64M
    upload_max_filesize = 64M
    post_max_size = 64M
    max_execution_time = 600
  '';
  commonHardeningOptions = [
    "--userns=keep-id:uid=0,gid=0"
    "--read-only"
    "--read-only-tmpfs=true"
    "--security-opt=no-new-privileges"
    "--cap-drop=all"
    "--cap-add=chown"
    "--cap-add=dac_override"
    "--cap-add=fowner"
    "--cap-add=setgid"
    "--cap-add=setuid"
  ];
in
{
  options.custom.services.stb = {
    enable = lib.mkEnableOption "stb";
  };

  config = lib.mkIf cfg.enable {
    users.groups.${stbUser}.gid = stbUid;
    users.users.${stbUser} = {
      uid = stbUid;
      group = stbUser;
      isSystemUser = true;
      home = stbHome;
      createHome = true;
      homeMode = "0700";
      linger = true;
      autoSubUidGidRange = true;
    };

    sops.secrets = {
      stbDatabasePassword = {
        key = "stb/database_password";
        owner = stbUser;
        mode = "0400";
      };
      stbDatabaseRootPassword = {
        key = "stb/database_root_password";
        owner = stbUser;
        mode = "0400";
      };
    };

    systemd.services = {
      linger-users.serviceConfig.RemainAfterExit = true;

      init-stb-data = {
        description = "Create the rootless STB data directories";
        requires = [ "user@${toString stbUid}.service" ];
        after = [ "user@${toString stbUid}.service" ];
        before = [ "podman-stb-mariadb.service" ];

        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          User = stbUser;
          Group = stbUser;
        };
        script = ''
          ${pkgs.coreutils}/bin/install -d -m 0700 ${lib.escapeShellArg mariadbDataDir}
        '';
      };

      init-stb-network = {
        description = "Create the rootless STB container network";
        wants = [ "network-online.target" ];
        after = [
          "network-online.target"
          "linger-users.service"
          "user@${toString stbUid}.service"
        ];
        requires = [ "user@${toString stbUid}.service" ];
        before = [
          "podman-stb-mariadb.service"
          "podman-stb-wordpress.service"
        ];
        wantedBy = [ "multi-user.target" ];

        environment.HOME = stbHome;
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          User = stbUser;
          Group = stbUser;
        };
        script = ''
          export XDG_RUNTIME_DIR="/run/user/$(${pkgs.coreutils}/bin/id -u)"
          ${pkgs.podman}/bin/podman network exists ${lib.escapeShellArg stbNetwork} \
            || ${pkgs.podman}/bin/podman network create ${lib.escapeShellArg stbNetwork}
        '';
      };

      podman-stb-mariadb = {
        requires = [
          "init-stb-data.service"
          "init-stb-network.service"
        ];
        after = [
          "init-stb-data.service"
          "init-stb-network.service"
        ];
      };

      podman-stb-wordpress = {
        requires = [
          "init-stb-network.service"
          "prepare-stb-wordpress-secret.service"
        ];
        after = [
          "init-stb-network.service"
          "prepare-stb-wordpress-secret.service"
        ];
      };

      prepare-stb-wordpress-secret = {
        description = "Prepare the STB WordPress database secret";
        requires = [ "user@${toString stbUid}.service" ];
        after = [
          "linger-users.service"
          "user@${toString stbUid}.service"
        ];
        before = [ "podman-stb-wordpress.service" ];

        environment.HOME = stbHome;
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          User = stbUser;
          Group = stbUser;
        };
        script = ''
          export XDG_RUNTIME_DIR=/run/user/${toString stbUid}
          secret_dir="$XDG_RUNTIME_DIR/stb-secrets"
          ${pkgs.coreutils}/bin/install -d -m 0700 "$secret_dir"
          ${pkgs.coreutils}/bin/install -m 0444 \
            ${lib.escapeShellArg databasePasswordFile} \
            ${lib.escapeShellArg wordpressDatabasePasswordFile}
        '';
      };

      stb-mariadb-dump = {
        description = "Create an atomic STB MariaDB dump";
        requires = [ "podman-stb-mariadb.service" ];
        after = [ "podman-stb-mariadb.service" ];

        serviceConfig = {
          Type = "oneshot";
          UMask = "0077";
        };
        script = ''
          set -euo pipefail

          dump_file=${lib.escapeShellArg databaseDumpFile}
          dump_tmp="$(${pkgs.coreutils}/bin/mktemp "$dump_file.XXXXXX")"
          trap '${pkgs.coreutils}/bin/rm -f "$dump_tmp"' EXIT

          ${pkgs.util-linux}/bin/runuser --user ${lib.escapeShellArg stbUser} -- \
            ${pkgs.coreutils}/bin/env \
              HOME=${lib.escapeShellArg stbHome} \
              XDG_RUNTIME_DIR=/run/user/${toString stbUid} \
              ${pkgs.podman}/bin/podman exec stb-mariadb sh -ceu '
                credentials="$(mktemp)"
                trap "rm -f \"$credentials\"" EXIT
                {
                  printf "[client]\nuser=stb\npassword="
                  cat /run/secrets/stb-database-password
                  printf "\n"
                } > "$credentials"
                mariadb-dump \
                  --defaults-extra-file="$credentials" \
                  --single-transaction \
                  --quick \
                  --skip-lock-tables \
                  stb
              ' > "$dump_tmp"

          ${pkgs.coreutils}/bin/chmod 0600 "$dump_tmp"
          ${pkgs.coreutils}/bin/mv -f "$dump_tmp" "$dump_file"
          trap - EXIT
        '';
      };
    };

    virtualisation.oci-containers = {
      backend = "podman";
      containers = {
        stb-mariadb = {
          image = "docker.io/library/mariadb:11.4.13@sha256:611a2fcc5fa7c6ceb8644c6f74b25ede004ff6c3a6b38c8f8c23d3bbf6c26430";
          pull = "missing";
          podman = {
            user = stbUser;
            sdnotify = "healthy";
          };
          environment = {
            MARIADB_ROOT_PASSWORD_FILE = "/run/secrets/stb-database-root-password";
            MARIADB_ROOT_HOST = "localhost";
            MARIADB_DATABASE = "stb";
            MARIADB_USER = "stb";
            MARIADB_PASSWORD_FILE = "/run/secrets/stb-database-password";
            MARIADB_AUTO_UPGRADE = "1";
          };
          volumes = [
            "${mariadbDataDir}:/var/lib/mysql:rw"
            "${databasePasswordFile}:/run/secrets/stb-database-password:ro"
            "${rootPasswordFile}:/run/secrets/stb-database-root-password:ro"
          ];
          networks = [ stbNetwork ];
          extraOptions = commonHardeningOptions ++ [
            "--network-alias=stb-mariadb"
            "--health-cmd=healthcheck.sh --connect --innodb_initialized"
            "--health-interval=10s"
            "--health-timeout=5s"
            "--health-start-period=60s"
            "--health-retries=30"
          ];
          autoStart = true;
        };

        stb-wordpress = {
          image = "docker.io/library/wordpress:7.1-php8.3-apache@sha256:8801a1239d7ba9fb340a5fc5ba0bf7f8d3652adbd64893e3fba7992ba618108e";
          pull = "missing";
          podman.user = stbUser;
          dependsOn = [ "stb-mariadb" ];
          environment = {
            WORDPRESS_DB_HOST = "stb-mariadb:3306";
            WORDPRESS_DB_NAME = "stb";
            WORDPRESS_DB_USER = "stb";
            WORDPRESS_DB_PASSWORD_FILE = "/run/secrets/stb-database-password";
          };
          ports = [ "127.0.0.1:8180:80" ];
          volumes = [
            "${wordpressDataDir}:/var/www/html:rw"
            "${wordpressDataDir}/wp-config.php:/var/www/html/wp-config.php:ro"
            "${wordpressDatabasePasswordFile}:/run/secrets/stb-database-password:ro"
            "${staticHeroFile}:/var/www/html/wp-content/mu-plugins/stb-static-hero.php:ro"
            "${uploadWordpressConfig}:/usr/local/etc/php/conf.d/uploads.ini:ro"
          ];
          networks = [ stbNetwork ];
          extraOptions = commonHardeningOptions ++ [ "--cap-add=net_bind_service" ];
          autoStart = true;
        };
      };
    };

    services.nginx.virtualHosts."www.societe-de-tir-bertrix.com" = {
      serverAliases = [ "societe-de-tir-bertrix.com" ];
      forceSSL = true;
      enableACME = true;
      extraConfig = ''
        if (-f ${maintenanceFile}) {
          return 503;
        }
      '';

      locations = {
        "= /xmlrpc.php".return = "404";
        "/".proxyPass = "http://127.0.0.1:8180";
      };
    };
  };
}
