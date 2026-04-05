{
  config,
  lib,
  ...
}:
let
  cfg = config.custom.services.kots-libramont;
  websiteRoot = ../sites/kots-libramont;
in
{
  options.custom.services.kots-libramont = {
    enable = lib.mkEnableOption "kots-libramont";
  };

  config = lib.mkIf cfg.enable {
    services.nginx.virtualHosts."kots-libramont.froidmont.org" = {
      forceSSL = true;
      enableACME = true;
      root = websiteRoot;
    };
  };
}
