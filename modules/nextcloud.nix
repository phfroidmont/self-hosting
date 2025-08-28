{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.custom.services.nextcloud;
in
{
  options.custom.services.nextcloud = {
    enable = lib.mkEnableOption "nextcloud";
  };

  config = lib.mkIf cfg.enable {
    sops.secrets = {
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

    services.nginx.virtualHosts."${config.services.nextcloud.hostName}" = {
      enableACME = true;
      forceSSL = true;
    };

    # Can't change home dir for now, use bind mount as workaround
    # https://github.com/NixOS/nixpkgs/issues/356973
    fileSystems."/var/lib/nextcloud" = {
      device = "/nix/var/data/nextcloud";
      options = [ "bind" ];
    };

    services.nextcloud = {
      enable = true;
      # home = "/nix/var/data/nextcloud";
      package = pkgs.nextcloud31;
      hostName = "cloud.${config.networking.domain}";
      https = true;
      maxUploadSize = "1G";
      configureRedis = true;
      # notify_push.enable = true;

      config = {
        dbtype = "pgsql";
        dbuser = "nextcloud";
        dbhost = "127.0.0.1";
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
        "opcache.interned_strings_buffer" = "24";
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
