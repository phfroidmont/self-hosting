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
    nixpkgs.config.permittedInsecurePackages = [ "jitsi-meet-1.0.8792" ];
    services.jitsi-meet = {
      enable = true;
      hostName = "jitsi.froidmont.org";
      interfaceConfig = {
        RECENT_LIST_ENABLED = false;
      };
    };
    services.jitsi-videobridge.openFirewall = true;
    # JVB binds its ICE sockets only once at startup. Wait for dhcpcd's IPv4
    # address, otherwise the bridge stays unhealthy until it is restarted.
    systemd.services.jitsi-videobridge2 = {
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
    };
    # The default "*syslog" string sends debug messages too.
    services.prosody.log = ''{ info = "*syslog" }'';
  };
}
