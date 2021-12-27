{ pkgs, lib, config, ... }:
{
  services.jitsi-meet = {
    enable = true;
    hostName = "jitsi.froidmont.org";
  };
  services.jitsi-videobridge.openFirewall = true;
}
