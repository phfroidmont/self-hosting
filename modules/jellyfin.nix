{ config, lib, ... }:
let
  cfg = config.custom.services.jellyfin;
in
{
  options.custom.services.jellyfin = {
    enable = lib.mkEnableOption "jellyfin";
  };

  config = lib.mkIf cfg.enable {
    services.jellyfin = {
      enable = true;
      dataDir = "/nix/var/data/jellyfin";
    };

    services.nginx.virtualHosts."jellyfin.${config.networking.domain}" = {
      enableACME = true;
      forceSSL = true;

      locations."= /".extraConfig = ''
        return 302 https://$host/web/;
      '';

      locations."/" = {
        proxyPass = "http://127.0.0.1:8096";
        extraConfig = ''
          proxy_buffering off;
        '';
      };

      locations."= /web/" = {
        proxyPass = "http://127.0.0.1:8096/web/index.html";
      };

      locations."/socket" = {
        proxyPass = "http://127.0.0.1:8096";
        extraConfig = ''
          proxy_http_version 1.1;
          proxy_set_header Upgrade $http_upgrade;
          proxy_set_header Connection "upgrade";
        '';
      };
    };
  };
}
