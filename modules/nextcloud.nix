{ config
, lib
, pkgs
, pkgs-unstable
, ...
}:
let
  cfg = config.custom.services.nextcloud;
in
{
  options.custom.services.nextcloud = {
    enable = lib.mkEnableOption "nextcloud";
  };

  config = lib.mkIf cfg.enable {
    systemd.services.nextcloud-setup = {
      after = [ "postgresql.target" ];
      requires = [ "postgresql.target" ];
    };

    systemd.services.nextcloud-update-db = {
      after = [ "postgresql.target" ];
      requires = [ "postgresql.target" ];
    };

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
      serverAliases = [ "cloud.froidmont.solutions" ];
    };

    # Can't change home dir for now, use bind mount as workaround
    # https://github.com/NixOS/nixpkgs/issues/356973
    fileSystems."/var/lib/nextcloud" = {
      device = "/nix/var/data/nextcloud";
      fsType = "none";
      options = [ "bind" ];
    };

    services.nextcloud = {
      enable = true;
      # home = "/nix/var/data/nextcloud";
      package = pkgs.nextcloud33;
      hostName = "cloud.${config.networking.domain}";
      https = true;
      maxUploadSize = "1G";
      configureRedis = true;
      # extraApps (added by notify_push) would otherwise disable the app store
      appstoreEnable = true;

      notify_push = {
        enable = true;
        # notify_push:setup fails unless binary and app share a minor version.
        # 26.05 ships 1.3 but the instance already runs app 1.4 from the store.
        package = pkgs-unstable.nextcloud-notify_push;
        # Lets the push server reach Nextcloud via localhost as a trusted proxy
        bendDomainToLocalhost = true;
      };
      extraApps.notify_push = lib.mkForce pkgs-unstable.nextcloud33Packages.apps.notify_push;

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
        serverid = 1;
        trusted_domains = [ "cloud.froidmont.solutions" ];
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
