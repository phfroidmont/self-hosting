{ config, lib, ... }:
let
  cfg = config.custom.services.immich;
  externalDomain = "photos.${config.networking.domain}";
in
{
  options.custom.services.immich = {
    enable = lib.mkEnableOption "immich";
  };

  config = lib.mkIf cfg.enable {
    sops.secrets.immichSecretsFile = {
      owner = config.systemd.services.immich-server.serviceConfig.User;
      key = "immich/secrets_file";
      restartUnits = [ "immich-server.service" ];
    };

    services = {
      immich = {
        enable = true;
        host = "127.0.0.1";
        group = "nextcloud";
        secretsFile = config.sops.secrets.immichSecretsFile.path;
        database.host = "127.0.0.1";
        settings = {
          server.externalDomain = "https://${externalDomain}";
        };
      };
      nginx = {
        virtualHosts = {
          ${externalDomain} = {
            enableACME = true;
            forceSSL = true;
            locations."/" = {
              proxyPass = "http://127.0.0.1:${toString config.services.immich.port}";
              proxyWebsockets = true;
            };
          };
        };
      };
    };
  };
}
