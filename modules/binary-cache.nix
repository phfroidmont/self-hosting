{ config, lib, ... }:
let cfg = config.custom.services.binary-cache;
in {
  options.custom.services.binary-cache = {

    enable = lib.mkEnableOption "binary-cache";

    secretKeyFile = lib.mkOption { type = lib.types.path; };
  };

  config = lib.mkIf cfg.enable {
    services.nix-serve = {
      enable = true;
      port = 1500;
      secretKeyFile = config.sops.secrets.nixCacheKey.path;
    };

    services.nginx = {
      virtualHosts = {
        "cache.${config.networking.domain}" = {

          enableACME = true;
          forceSSL = true;

          locations."/".extraConfig = ''
            proxy_pass http://localhost:${
              toString config.services.nix-serve.port
            };
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
          '';
        };
      };
    };
  };
}
