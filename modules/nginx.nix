{ pkgs, lib, config, ... }:
{
  security.acme.defaults.email = "letsencrypt.account@banditlair.com";
  security.acme.acceptTerms = true;

  services.nginx = {
    enable = true;

    recommendedTlsSettings = true;
    recommendedOptimisation = true;
    recommendedGzipSettings = true;
    recommendedProxySettings = true;
  };
}
