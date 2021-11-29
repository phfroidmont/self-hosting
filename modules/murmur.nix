{ config, lib, pkgs, ... }:
{
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
  };
}
