{ config, lib, pkgs, ... }:
let
  uploadWordpressConfig = pkgs.writeText "upload.ini" ''
    file_uploads = On
    memory_limit = 64M
    upload_max_filesize = 64M
    post_max_size = 64M
    max_execution_time = 600
  '';
in
{
  systemd.services.init-stb-network = {
    description = "Create the network bridge stb-br for wordpress.";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig.Type = "oneshot";
    script =
      let dockercli = "${config.virtualisation.docker.package}/bin/docker";
      in
      ''
        # Put a true at the end to prevent getting non-zero return code, which will
        # crash the whole service.
        check=$(${dockercli} network ls | grep "stb-br" || true)
        if [ -z "$check" ]; then
          ${dockercli} network create stb-br
        else
          echo "stb-br already exists in docker"
        fi
      '';
  };

  virtualisation.oci-containers.containers = {
    "stb-mariadb" = {
      image = "mariadb:10.7";
      environment = {
        "MYSQL_ROOT_PASSWORD" = "root";
        "MYSQL_USER" = "stb";
        "MYSQL_PASSWORD" = "stb";
        "MYSQL_DATABASE" = "stb";
      };
      volumes = [ "/var/lib/mariadb/stb:/var/lib/mysql" ];
      extraOptions = [ "--network=stb-br" ];
    };

    "stb-wordpress" = {
      image = "wordpress:5.8-php7.4-apache";
      volumes = [
        "/nix/var/data/stb-wordpress:/var/www/html"
        "${uploadWordpressConfig}:/usr/local/etc/php/conf.d/uploads.ini"
      ];
      ports = [ "8080:80" ];
      extraOptions = [ "--network=stb-br" ];
    };
  };

  services.nginx.virtualHosts."www.societe-de-tir-bertrix.com" = {
    serverAliases = [ "societe-de-tir-bertrix.com" ];
    forceSSL = true;
    enableACME = true;

    locations."/" = {
      proxyPass = "http://127.0.0.1:8080";
    };
  };
}
