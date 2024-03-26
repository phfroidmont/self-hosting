{ config, lib, ... }:
let cfg = config.custom.services.nginx;
in {
  options.custom.services.nginx = { enable = lib.mkEnableOption "nginx"; };

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
    };
  };
}
