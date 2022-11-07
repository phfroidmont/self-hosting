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
    turn_shared_secret: "TURN_SHARED_SECRET"
  '';
in
{
  services.nginx = {
    virtualHosts = {
      # This host section can be placed on a different host than the rest,
      # i.e. to delegate from the host being accessible as ${config.networking.domain}
      # to another host actually running the Matrix homeserver.
      "${config.networking.domain}" = {
        enableACME = true;
        forceSSL = true;
        # acmeFallbackHost = "storage1.banditlair.com";

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
    turnSharedSecret = {
      owner = config.systemd.services.matrix-synapse.serviceConfig.User;
      group = "turnserver";
      mode = "0440";
      key = "synapse/turn_shared_secret";
      restartUnits = [ "matrix-synapse-setup" "coturn" ];
    };
  };

  systemd.services.matrix-synapse-setup = {
    before = [ "matrix-synapse.service" ];

    script = ''
      set -euo pipefail
      install -m 600 ${synapseDbConfig} /run/synapse/synapse-db-config.yaml
      ${pkgs.replace-secret}/bin/replace-secret 'SYNAPSE_DB_PASSWORD' '${config.sops.secrets.synapseDbPassword.path}' /run/synapse/synapse-db-config.yaml
      ${pkgs.replace-secret}/bin/replace-secret 'MACAROON_SECRET_KEY' '${config.sops.secrets.macaroonSecretKey.path}' /run/synapse/synapse-db-config.yaml
      ${pkgs.replace-secret}/bin/replace-secret 'TURN_SHARED_SECRET' '${config.sops.secrets.turnSharedSecret.path}' /run/synapse/synapse-db-config.yaml
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

  services.matrix-synapse = with config.services.coturn; {
    enable = true;
    settings = {
      server_name = config.networking.domain;

      enable_metrics = true;

      listeners = [
        {
          port = 8008;
          bind_addresses = [ "::1" "127.0.0.1" ];
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
        {
          port = 9000;
          bind_addresses = [ "0.0.0.0" ];
          type = "metrics";
          tls = false;
          resources = [ ];
        }
      ];

      database = {
        name = "psycopg2";
        args = {
          host = "fake"; # This section is overriden by "extraConfigFiles"
        };
      };

      turn_uris = [ "turn:${realm}:3478?transport=udp" "turn:${realm}:3478?transport=tcp" ];
      turn_user_lifetime = "1h";
    };
    dataDir = "/nix/var/data/matrix-synapse";
    extraConfigFiles = [ "/run/synapse/synapse-db-config.yaml" ];
  };

  services.coturn = rec {
    enable = true;
    no-cli = true;
    no-tcp-relay = true;
    min-port = 49000;
    max-port = 50000;
    use-auth-secret = true;
    static-auth-secret-file = config.sops.secrets.turnSharedSecret.path;
    realm = "turn.${config.networking.domain}";
    cert = "${config.security.acme.certs.${realm}.directory}/full.pem";
    pkey = "${config.security.acme.certs.${realm}.directory}/key.pem";
    extraConfig = ''
      # for debugging
      verbose
      # ban private IP ranges
      no-multicast-peers
      denied-peer-ip=0.0.0.0-0.255.255.255
      denied-peer-ip=10.0.0.0-10.255.255.255
      denied-peer-ip=100.64.0.0-100.127.255.255
      denied-peer-ip=127.0.0.0-127.255.255.255
      denied-peer-ip=169.254.0.0-169.254.255.255
      denied-peer-ip=172.16.0.0-172.31.255.255
      denied-peer-ip=192.0.0.0-192.0.0.255
      denied-peer-ip=192.0.2.0-192.0.2.255
      denied-peer-ip=192.88.99.0-192.88.99.255
      denied-peer-ip=192.168.0.0-192.168.255.255
      denied-peer-ip=198.18.0.0-198.19.255.255
      denied-peer-ip=198.51.100.0-198.51.100.255
      denied-peer-ip=203.0.113.0-203.0.113.255
      denied-peer-ip=240.0.0.0-255.255.255.255
      denied-peer-ip=::1
      denied-peer-ip=64:ff9b::-64:ff9b::ffff:ffff
      denied-peer-ip=::ffff:0.0.0.0-::ffff:255.255.255.255
      denied-peer-ip=100::-100::ffff:ffff:ffff:ffff
      denied-peer-ip=2001::-2001:1ff:ffff:ffff:ffff:ffff:ffff:ffff
      denied-peer-ip=2002::-2002:ffff:ffff:ffff:ffff:ffff:ffff:ffff
      denied-peer-ip=fc00::-fdff:ffff:ffff:ffff:ffff:ffff:ffff:ffff
      denied-peer-ip=fe80::-febf:ffff:ffff:ffff:ffff:ffff:ffff:ffff
    '';
  };

  networking.firewall =
    let
      range = with config.services.coturn; [{
        from = min-port;
        to = max-port;
      }];
    in
    {
      allowedUDPPortRanges = range;
      allowedUDPPorts = [ 3478 ];
      allowedTCPPortRanges = range;
      allowedTCPPorts = [ 3478 ];
    };


  security.acme.certs.${config.services.coturn.realm} = {
    postRun = "systemctl restart coturn.service";
    group = "turnserver";
  };
}
