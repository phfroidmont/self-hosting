{ pkgs, lib, config, ... }: {
  services.jitsi-meet = {
    enable = true;
    hostName = "jitsi.froidmont.org";
    interfaceConfig = { RECENT_LIST_ENABLED = false; };
  };
  services.jitsi-videobridge.openFirewall = true;
}
