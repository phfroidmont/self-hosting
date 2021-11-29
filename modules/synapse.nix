{ pkgs, lib, config, ... }:
let
  fqdn =
    let
      join = hostName: domain: hostName + lib.optionalString (domain != null) ".${domain}";
    in
    join "matrix" config.networking.domain;
  synapseDbConfig = pkgs.writeText "synapse-db-config.yaml" ''
    database:
        name: psycopg2
        args:
          database: synapse
          host: "10.0.1.11"
          user: "synapse"
          password: "SYNAPSE_DB_PASSWORD"
    macaroon_secret_key: "MACAROON_SECRET_KEY"
  '';
in
{
  security.acme.email = "letsencrypt.account@banditlair.com";
  security.acme.acceptTerms = true;

  services.nginx = {
    virtualHosts = {
      # This host section can be placed on a different host than the rest,
      # i.e. to delegate from the host being accessible as ${config.networking.domain}
      # to another host actually running the Matrix homeserver.
      "${config.networking.domain}" = {
        enableACME = true;
        forceSSL = true;
        acmeFallbackHost = "storage1.banditlair.com";

        locations."= /.well-known/matrix/server".extraConfig =
          let
            # use 443 instead of the default 8448 port to unite
            # the client-server and server-server port for simplicity
            server = { "m.server" = "${fqdn}:443"; };
          in
          ''
            add_header Content-Type application/json;
            return 200 '${builtins.toJSON server}';
          '';
        locations."= /.well-known/matrix/client".extraConfig =
          let
            client = {
              "m.homeserver" = { "base_url" = "https://${fqdn}"; };
              "m.identity_server" = { "base_url" = "https://vector.im"; };
            };
            # ACAO required to allow element-web on any URL to request this json file
          in
          ''
            add_header Content-Type application/json;
            add_header Access-Control-Allow-Origin *;
            return 200 '${builtins.toJSON client}';
          '';
      };

      # Reverse proxy for Matrix client-server and server-server communication
      ${fqdn} = {
        enableACME = true;
        forceSSL = true;

        # Or do a redirect instead of the 404, or whatever is appropriate for you.
        # But do not put a Matrix Web client here! See the Element web section below.
        locations."/".extraConfig = ''
          return 404;
        '';

        # forward all Matrix API calls to the synapse Matrix homeserver
        locations."/_matrix" = {
          proxyPass = "http://[::1]:8008"; # without a trailing /
        };
      };
    };
  };

  sops.secrets = {
    synapseDbPassword = {
      owner = config.systemd.services.matrix-synapse.serviceConfig.User;
      key = "synapse/db_password";
      restartUnits = [ "matrix-synapse-setup" ];
    };
    macaroonSecretKey = {
      owner = config.systemd.services.matrix-synapse.serviceConfig.User;
      key = "synapse/macaroon_secret_key";
      restartUnits = [ "matrix-synapse-setup" ];
    };
  };

  systemd.services.matrix-synapse-setup = {
    before = [ "matrix-synapse.service" ];

    script = ''
      set -euo pipefail
      install -m 600 ${synapseDbConfig} /run/synapse/synapse-db-config.yaml
      ${pkgs.replace-secret}/bin/replace-secret 'SYNAPSE_DB_PASSWORD' '${config.sops.secrets.synapseDbPassword.path}' /run/synapse/synapse-db-config.yaml
      ${pkgs.replace-secret}/bin/replace-secret 'MACAROON_SECRET_KEY' '${config.sops.secrets.macaroonSecretKey.path}' /run/synapse/synapse-db-config.yaml
    '';

    serviceConfig = {
      User = config.systemd.services.matrix-synapse.serviceConfig.User;
      Group = config.systemd.services.matrix-synapse.serviceConfig.Group;
      Type = "oneshot";
      RemainAfterExit = true;
      RuntimeDirectory = "synapse";
    };
  };

  systemd.services.matrix-synapse = {
    after = [ "matrix-synapse-setup.service" "network.target" ];
    bindsTo = [ "matrix-synapse-setup.service" ];
  };

  services.matrix-synapse = {
    enable = true;
    server_name = config.networking.domain;
    listeners = [
      {
        port = 8008;
        bind_address = "::1";
        type = "http";
        tls = false;
        x_forwarded = true;
        resources = [
          {
            names = [ "client" "federation" ];
            compress = false;
          }
        ];
      }
    ];
    database_type = "psycopg2";
    database_args = {
      host = "fake"; # This section is overriden in deploy_nixos keys
    };
    dataDir = "/nix/var/data/matrix-synapse";
    extraConfigFiles = [ "/run/synapse/synapse-db-config.yaml" ];
  };
}
