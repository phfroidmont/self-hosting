{ config, ... }:
{

  sops.secrets = {
    nixCacheKey = {
      key = "nix/cache_secret_key";
    };
  };


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
          proxy_pass http://localhost:${toString config.services.nix-serve.port};
          proxy_set_header Host $host;
          proxy_set_header X-Real-IP $remote_addr;
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        '';
      };
    };
  };
}
