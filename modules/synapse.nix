{
  pkgs,
  config,
  lib,
  ...
}:
let
  cfg = config.custom.services.synapse;
  join = hostName: domain: hostName + lib.optionalString (domain != null) ".${domain}";
  fqdn = join "matrix" config.networking.domain;
  rtcFqdn = join "matrix-rtc" config.networking.domain;
  livekitServiceUrl = "https://${rtcFqdn}/livekit/jwt";
  createMatrixUser = pkgs.writeShellScriptBin "create-matrix-user" ''
    set -euo pipefail
    export PATH="${pkgs.python3}/bin:${pkgs.curl}/bin:$PATH"
    exec "${pkgs.bash}/bin/bash" "${../scripts/create-matrix-user.sh}" \
      --homeserver-url "http://127.0.0.1:8008" \
      --server-name "${config.networking.domain}" \
      --admin-user "paultrial" \
      "$@"
  '';
  getMatrixAccessToken = pkgs.writeShellScriptBin "get-matrix-access-token" ''
    set -euo pipefail
    export PATH="${pkgs.python3}/bin:${pkgs.curl}/bin:$PATH"
    exec "${pkgs.bash}/bin/bash" "${../scripts/get-matrix-access-token.sh}" \
      --homeserver-url "http://127.0.0.1:8008" \
      --server-name "${config.networking.domain}" \
      "$@"
  '';
  synapseDbConfig = pkgs.writeText "synapse-db-config.yaml" ''
    database:
        name: psycopg2
        args:
          database: synapse
          host: "127.0.0.1"
          user: "synapse"
          password: "SYNAPSE_DB_PASSWORD"
    email:
        smtp_host: "mail.banditlair.com"
        smtp_port: 465
        smtp_user: "noreply@banditlair.com"
        force_tls: true
        enable_tls: true
        notif_from: "noreply@banditlair.com"
        smtp_pass: "SMTP_PASSWORD"
    macaroon_secret_key: "MACAROON_SECRET_KEY"
    turn_shared_secret: "TURN_SHARED_SECRET"
  '';
in
{
  options.custom.services.synapse = {
    enable = lib.mkEnableOption "synapse";
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      createMatrixUser
      getMatrixAccessToken
    ];

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
              server = {
                "m.server" = "${fqdn}:443";
              };
            in
            ''
              add_header Content-Type application/json;
              return 200 '${builtins.toJSON server}';
            '';
          locations."= /.well-known/matrix/client".extraConfig =
            let
              client = {
                "m.homeserver" = {
                  "base_url" = "https://${fqdn}";
                };
                "m.identity_server" = {
                  "base_url" = "https://vector.im";
                };
                "org.matrix.msc4143.rtc_foci" = [
                  {
                    "type" = "livekit";
                    "livekit_service_url" = livekitServiceUrl;
                  }
                ];
              };
            in
            # ACAO required to allow element-web on any URL to request this json file
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

          # Match Synapse's default max_upload_size
          extraConfig = ''
            client_max_body_size 50M;
          '';

          # Or do a redirect instead of the 404, or whatever is appropriate for you.
          # But do not put a Matrix Web client here! See the Element web section below.
          locations."/".extraConfig = ''
            return 404;
          '';

          # forward all Matrix API calls to the synapse Matrix homeserver
          locations."~ ^(/_matrix|/_synapse/client|/health)" = {
            proxyPass = "http://[::1]:8008"; # without a trailing /
          };
        };

        # MatrixRTC backend used by Element Call (Element X, Element Web)
        ${rtcFqdn} = {
          enableACME = true;
          forceSSL = true;

          locations."/".extraConfig = ''
            return 404;
          '';

          locations."^~ /livekit/jwt/" = {
            proxyPass = "http://127.0.0.1:${toString config.services.lk-jwt-service.port}/";
          };

          locations."^~ /livekit/sfu/" = {
            proxyPass = "http://127.0.0.1:${toString config.services.livekit.settings.port}/";
            proxyWebsockets = true;
            extraConfig = ''
              proxy_send_timeout 120s;
              proxy_read_timeout 120s;
              proxy_buffering off;
            '';
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
      noreplySmtpPassword = {
        owner = config.systemd.services.matrix-synapse.serviceConfig.User;
        key = "email/accounts_passwords/noreply_banditlair_clear";
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
        restartUnits = [
          "matrix-synapse-setup"
          "coturn"
        ];
      };
      livekitKeys = {
        key = "synapse/livekit_keys";
        restartUnits = [
          "livekit.service"
          "lk-jwt-service.service"
        ];
      };
    };

    systemd.services.matrix-synapse-setup = {
      before = [ "matrix-synapse.service" ];

      script = ''
        set -euo pipefail
        install -m 600 ${synapseDbConfig} /run/synapse/synapse-db-config.yaml
        ${pkgs.replace-secret}/bin/replace-secret 'SYNAPSE_DB_PASSWORD' '${config.sops.secrets.synapseDbPassword.path}' /run/synapse/synapse-db-config.yaml
        ${pkgs.replace-secret}/bin/replace-secret 'SMTP_PASSWORD' '${config.sops.secrets.noreplySmtpPassword.path}' /run/synapse/synapse-db-config.yaml
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
      after = [
        "matrix-synapse-setup.service"
        "network.target"
      ];
      bindsTo = [ "matrix-synapse-setup.service" ];
    };

    services.matrix-synapse = with config.services.coturn; {
      enable = true;
      settings = {
        server_name = config.networking.domain;
        public_baseurl = "https://${fqdn}/";

        enable_metrics = true;

        listeners = [
          {
            port = 8008;
            bind_addresses = [
              "::1"
              "127.0.0.1"
            ];
            type = "http";
            tls = false;
            x_forwarded = true;
            resources = [
              {
                names = [
                  "client"
                  "federation"
                ];
                compress = false;
              }
            ];
          }
          {
            port = 9000;
            bind_addresses = [ "127.0.0.1" ];
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

        turn_uris = [
          "turn:${realm}:${toString listening-port}?transport=udp"
          "turn:${realm}:${toString listening-port}?transport=tcp"
          "turns:${realm}:${toString tls-listening-port}?transport=tcp"
        ];
        turn_user_lifetime = "1h";

        # MatrixRTC (Element Call) requirements, see
        # https://github.com/element-hq/element-call/blob/livekit/docs/self_hosting.md
        experimental_features = {
          msc4143_enabled = true;
          msc4222_enabled = true;
        };
        max_event_delay_duration = "24h";
        rc_message = {
          per_second = 0.5;
          burst_count = 30;
        };
        rc_delayed_event_mgmt = {
          per_second = 1;
          burst_count = 20;
        };
        # Only livekit_service_url: the nixpkgs lk-jwt-service does not support
        # the application service mode required by the newer `url` transport.
        matrix_rtc.transports = [
          {
            type = "livekit";
            livekit_service_url = livekitServiceUrl;
          }
        ];
      };
      dataDir = "/nix/var/data/matrix-synapse";
      extraConfigFiles = [ "/run/synapse/synapse-db-config.yaml" ];
    };

    services.livekit = {
      enable = true;
      keyFile = config.sops.secrets.livekitKeys.path;
      settings = {
        # Room creation is gated by lk-jwt-service
        room.auto_create = false;
        rtc = {
          tcp_port = 7881;
          port_range_start = 50100;
          port_range_end = 50300;
        };
      };
    };

    services.lk-jwt-service = {
      enable = true;
      # 8080 is used by jitsi-videobridge
      port = 8089;
      livekitUrl = "wss://${rtcFqdn}/livekit/sfu";
      keyFile = config.sops.secrets.livekitKeys.path;
    };

    systemd.services.lk-jwt-service.environment.LIVEKIT_FULL_ACCESS_HOMESERVERS =
      config.services.matrix-synapse.settings.server_name;

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
        coturn = config.services.coturn;
        livekitRtc = config.services.livekit.settings.rtc;
      in
      {
        allowedUDPPortRanges = [
          {
            from = coturn.min-port;
            to = coturn.max-port;
          }
          {
            from = livekitRtc.port_range_start;
            to = livekitRtc.port_range_end;
          }
        ];
        allowedUDPPorts = [ coturn.listening-port ];
        allowedTCPPorts = [
          coturn.listening-port
          coturn.tls-listening-port
          livekitRtc.tcp_port
        ];
      };

    security.acme.certs.${config.services.coturn.realm} = {
      postRun = "systemctl restart coturn.service";
      group = "turnserver";
    };
  };
}
