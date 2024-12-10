{
  inputs,
  pkgs,
  config,
  lib,
  ...
}:
let
  cfg = config.custom.services.foundryvtt;
in
{
  options.custom.services.foundryvtt = {
    enable = lib.mkEnableOption "foundryvtt";
  };

  config = lib.mkIf cfg.enable {
    services.foundryvtt = {
      enable = true;
      package = inputs.foundryvtt.packages.${pkgs.system}.foundryvtt_12;
      hostName = "vtt.${config.networking.domain}";
      language = "fr.core";
      proxyPort = 443;
      proxySSL = true;
      upnp = false;
      dataDir = "/nix/var/data/foundryvtt";
    };
    systemd.services.foundryvtt.serviceConfig = {
      StateDirectory = lib.mkForce null;
      ReadWritePaths = config.services.foundryvtt.dataDir;
    };
    services.nginx.virtualHosts."vtt.${config.networking.domain}" = {
      forceSSL = true;
      enableACME = true;

      locations."/" = {
        proxyPass = "http://127.0.0.1:${toString config.services.foundryvtt.port}";
        extraConfig = ''
          proxy_set_header Upgrade $http_upgrade;
          proxy_set_header Connection "upgrade";
        '';
      };
    };
  };
}
