{ config, lib, ... }:
let
  cfg = config.custom.services.nginx;
in
{
  options.custom.services.nginx = {
    enable = lib.mkEnableOption "nginx";
  };

  config = lib.mkIf cfg.enable {
    security.acme.defaults.email = "letsencrypt.account@banditlair.com";
    security.acme.defaults.webroot = "/var/lib/acme/acme-challenge";
    security.acme.acceptTerms = true;

    services.nginx = {
      enable = true;

      recommendedTlsSettings = true;
      recommendedOptimisation = true;
      recommendedGzipSettings = true;
      recommendedProxySettings = true;

      # Combined format plus the virtual host and timings, for per-site log metrics.
      commonHttpConfig = ''
        log_format main '$remote_addr - $remote_user [$time_local] "$request" $status $body_bytes_sent '
                        '"$http_referer" "$http_user_agent" "$server_name" $request_time $upstream_response_time';
        access_log /var/log/nginx/access.log main;
      '';

      appendHttpConfig = ''
        limit_req_zone $binary_remote_addr zone=perip:20m rate=20r/s;
        limit_conn_zone $binary_remote_addr zone=perip_conn:20m;

        limit_req_status 429;
        limit_req zone=perip burst=160 nodelay;
        limit_conn perip_conn 80;
      '';
    };
  };
}
