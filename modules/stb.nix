{ config
, lib
, ...
}:
let
  cfg = config.custom.services.stb;
  websiteRoot = ../sites/stb;
in
{
  options.custom.services.stb = {
    enable = lib.mkEnableOption "stb";
  };

  config = lib.mkIf cfg.enable {
    services.nginx.virtualHosts."www.societe-de-tir-bertrix.com" = {
      serverAliases = [ "societe-de-tir-bertrix.com" ];
      forceSSL = true;
      enableACME = true;
      root = websiteRoot;
      locations."/".tryFiles = "$uri /index.html";
    };
  };
}
