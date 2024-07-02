{ config, lib, pkgs, ... }:
let
  cfg = config.custom.services.nextcloud;
  uidFile = pkgs.writeText "uidfile" ''
    nextcloud:993
  '';
  gidFile = pkgs.writeText "gidfile" ''
    nextcloud:991
  '';
in {
  options.custom.services.nextcloud = {
    enable = lib.mkEnableOption "nextcloud";
  };

  config = lib.mkIf cfg.enable {
    sops.secrets = {
      sshfsKey = { key = "sshfs_keys/private"; };
      nextcloudDbPassword = {
        owner = config.users.users.nextcloud.name;
        key = "nextcloud/db_password";
        restartUnits = [ "nextcloud-setup.service" ];
      };
      nextcloudAdminPassword = {
        owner = config.users.users.nextcloud.name;
        key = "nextcloud/admin_password";
        restartUnits = [ "nextcloud-setup.service" ];
      };
    };

    environment.systemPackages = with pkgs; [ sshfs ];

    systemd.services.nextcloud-data-sshfs = {
      wantedBy = [ "multi-user.target" "nextcloud-setup.service" ];
      before = [ "phpfpm-nextcloud.service" ];
      restartIfChanged = false;
      serviceConfig = {
        ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p /var/lib/nextcloud/data";
        ExecStart = let
          options = builtins.concatStringsSep "," [
            "identityfile=${config.sops.secrets.sshfsKey.path}"
            "ServerAliveInterval=15"
            "idmap=file"
            "uidfile=${uidFile}"
            "gidfile=${gidFile}"
            "allow_other"
            "default_permissions"
            "nomap=ignore"
          ];
        in "${pkgs.sshfs}/bin/mount.fuse.sshfs www-data@10.0.2.3:/nix/var/data/nextcloud/data "
        + "/var/lib/nextcloud/data -o ${options}";
        ExecStopPost =
          "-${pkgs.fuse}/bin/fusermount -u /var/lib/nextcloud/data";
        KillMode = "process";
      };
    };

    services.nginx.virtualHosts."${config.services.nextcloud.hostName}" = {
      enableACME = true;
      forceSSL = true;
    };

    services.nextcloud = {
      enable = true;
      package = pkgs.nextcloud29;
      hostName = "cloud.${config.networking.domain}";
      https = true;
      maxUploadSize = "1G";

      config = {
        dbtype = "pgsql";
        dbuser = "nextcloud";
        dbhost = "10.0.1.11";
        dbname = "nextcloud";
        dbpassFile = "${config.sops.secrets.nextcloudDbPassword.path}";
        adminpassFile = "${config.sops.secrets.nextcloudAdminPassword.path}";
        adminuser = "root";
      };

      settings = {
        overwriteProtocol = "https";
        default_phone_region = "BE";
        maintenance_window_start = 1;
      };

      phpOptions = {
        short_open_tag = "Off";
        expose_php = "Off";
        error_reporting = "E_ALL & ~E_DEPRECATED & ~E_STRICT";
        display_errors = "stderr";
        "opcache.enable_cli" = "1";
        "opcache.interned_strings_buffer" = "12";
        "opcache.max_accelerated_files" = "10000";
        "opcache.memory_consumption" = "128";
        "opcache.revalidate_freq" = "1";
        "opcache.fast_shutdown" = "1";
        "openssl.cafile" = "/etc/ssl/certs/ca-certificates.crt";
        catch_workers_output = "yes";
      };
    };
  };
}
