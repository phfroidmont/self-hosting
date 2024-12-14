{
  config,
  lib,
  ...
}:
let
  cfg = config.custom.services.jitsi;
in
{
  options.custom.services.jitsi = {
    enable = lib.mkEnableOption "jitsi";
  };

  config = lib.mkIf cfg.enable {
    nixpkgs.config.permittedInsecurePackages = [ "jitsi-meet-1.0.8043" ];
    services.jitsi-meet = {
      enable = true;
      hostName = "jitsi.froidmont.org";
      interfaceConfig = {
        RECENT_LIST_ENABLED = false;
      };
    };
    services.jitsi-videobridge.openFirewall = true;
  };
}
