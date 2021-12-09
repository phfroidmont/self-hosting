{ config, lib, pkgs, ... }:
{

  services.monero = {
    enable = true;
    rpc.restricted = true;
  };

  services.nginx.virtualHosts."monero.${config.networking.domain}" = {
    forceSSL = true;
    enableACME = true;

    locations."/" = {
      proxyPass = "http://127.0.0.1:18081";
      extraConfig = ''
        proxy_http_version 1.1;
      '';
    };
  };

}
