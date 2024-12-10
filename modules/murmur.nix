{ config, lib, ... }:
let
  cfg = config.custom.services.murmur;
in
{
  options.custom.services.murmur = {
    enable = lib.mkEnableOption "murmur";
  };

  config = lib.mkIf cfg.enable {
    sops.secrets.murmurEnvFile = {
      owner = config.systemd.services.murmur.serviceConfig.User;
      key = "murmur.env";
      restartUnits = [ "murmur.service" ];
    };

    services.murmur = {
      enable = true;
      bandwidth = 128000;
      password = "$MURMURD_PASSWORD";
      environmentFile = config.sops.secrets.murmurEnvFile.path;
      imgMsgLength = 13107200;
      openFirewall = true;
    };
  };
}
