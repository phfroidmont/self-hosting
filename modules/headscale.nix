{ config, lib, ... }:
with lib;
let
  cfg = config.custom.services.headscale;
  domain = "hs.${config.networking.domain}";
in
{
  options.custom.services.headscale = {
    enable = mkEnableOption "headscale";
  };

  config = mkIf cfg.enable {

    services.headscale = {
      enable = true;
      port = 28080;
      settings = {
        server_url = "https://${domain}";
        derp = {
          server = {
            enabled = true;
            stun_listen_addr = "0.0.0.0:4478";
          };
          # urls = [ ];
          auto_update_enabled = false;
        };
        dns = {
          base_domain = "ts.net";
          nameservers = {
            global = [
              "9.9.9.10"
              "149.112.112.10"
            ];
            split = {
              "foyer.cloud" = "10.33.0.100";
              "foyer.lu" = "10.33.0.100";
              "lefoyer.lu" = "10.33.0.100";
            };
          };
        };
      };
    };

    services.nginx.virtualHosts.${domain} = {
      forceSSL = true;
      enableACME = true;
      locations."/" = {
        proxyPass = "http://127.0.0.1:${toString config.services.headscale.port}";
        proxyWebsockets = true;
      };
    };

    networking = {
      firewall.allowedUDPPorts = [
        4478
      ];
    };
  };
}
