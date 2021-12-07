{ config, lib, pkgs, ... }:
{
  services.jellyfin = {
    enable = true;
  };

  systemd.services.jellyfin.serviceConfig.ExecStart =
    lib.mkOverride 10 "${config.services.jellyfin.package}/bin/jellyfin --datadir '/nix/var/data/jellyfin' --cachedir '/var/cache/jellyfin'";

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
    };
  };
}
