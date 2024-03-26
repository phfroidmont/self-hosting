{ pkgs, config, lib, ... }:
let cfg = config.custom.services.jitsi;
in {
  options.custom.services.jitsi = { enable = lib.mkEnableOption "jitsi"; };

  config = lib.mkIf cfg.enable {
    services.jitsi-meet = {
      enable = true;
      hostName = "jitsi.froidmont.org";
      interfaceConfig = { RECENT_LIST_ENABLED = false; };
    };
    services.jitsi-videobridge.openFirewall = true;
  };
}
