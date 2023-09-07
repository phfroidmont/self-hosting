{ config, lib, pkgs, ... }: {

  sops.secrets = {
    vpnCredentials = { key = "openvpn/credentials"; };
    transmissionRpcCredentials = { key = "transmission/rpc_config.json"; };
  };

  containers.torrents = {
    ephemeral = true;
    autoStart = true;
    enableTun = true;

    privateNetwork = true;
    hostAddress = "192.168.1.1";
    localAddress = "192.168.1.2";

    bindMounts = {
      "${config.sops.secrets.vpnCredentials.path}" = {
        hostPath = config.sops.secrets.vpnCredentials.path;
      };
      "${config.sops.secrets.transmissionRpcCredentials.path}" = {
        hostPath = config.sops.secrets.transmissionRpcCredentials.path;
      };
      "/nix/var/data/media" = {
        hostPath = "/nix/var/data/media";
        isReadOnly = false;
      };
      "/nix/var/data/jackett" = {
        hostPath = "/nix/var/data/jackett";
        isReadOnly = false;
      };
      "/nix/var/data/sonarr" = {
        hostPath = "/nix/var/data/sonarr";
        isReadOnly = false;
      };
      "/nix/var/data/radarr" = {
        hostPath = "/nix/var/data/radarr";
        isReadOnly = false;
      };
      "/nix/var/data/headphones" = {
        hostPath = "/nix/var/data/headphones";
        isReadOnly = false;
      };
      "/nix/var/data/transmission" = {
        hostPath = "/nix/var/data/transmission";
        isReadOnly = false;
      };
    };

    config = {
      time.timeZone = "Europe/Amsterdam";
      users.users.www-data = {
        uid = 993;
        isSystemUser = true;
        group = config.users.groups.www-data.name;
      };
      users.groups.www-data = { gid = 991; };
      services.openvpn.servers.client = {
        updateResolvConf = true;
        config = ''
          client
          dev tun
          resolv-retry infinite
          nobind
          persist-key
          persist-tun
          verb 3
          remote-cert-tls server
          ping 10
          ping-restart 60
          sndbuf 524288
          rcvbuf 524288
          cipher AES-256-CBC
          tls-cipher TLS-DHE-RSA-WITH-AES-256-GCM-SHA384:TLS-DHE-RSA-WITH-AES-256-CBC-SHA
          proto udp
          <ca>
          -----BEGIN CERTIFICATE-----
          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
          -----END CERTIFICATE-----
          </ca>
          tun-ipv6
          script-security 2
          fast-io
          remote-random
          remote de-fra-101.mullvad.net 1194
          remote de-fra-201.mullvad.net 1194
          remote de-fra-009.mullvad.net 1194
          remote de-fra-002.mullvad.net 1194
          remote de-fra-202.mullvad.net 1194
          remote de-fra-005.mullvad.net 1194
          remote de-fra-203.mullvad.net 1194
          remote de-fra-003.mullvad.net 1194
          remote de-fra-004.mullvad.net 1194
          remote de-fra-008.mullvad.net 1194
          remote de-fra-006.mullvad.net 1194
          remote de-fra-007.mullvad.net 1194
          remote de-fra-102.mullvad.net 1194
          auth-user-pass ${config.sops.secrets.vpnCredentials.path}
        '';
      };
      services.transmission = {
        enable = true;
        openRPCPort = true;
        user = config.users.users.www-data.name;
        group = config.users.groups.www-data.name;
        credentialsFile = config.sops.secrets.transmissionRpcCredentials.path;
        home = "/nix/var/data/transmission";
        settings = {
          rpc-bind-address = "0.0.0.0";
          rpc-whitelist = "127.0.0.1,192.168.1.1";
          rpc-authentication-required = true;
          rpc-host-whitelist-enabled = false;
          incomplete-dir = "/nix/var/data/transmission/.incomplete";
          watch-dir = "/nix/var/data/transmission/watchdir";
          download-dir = "/nix/var/data/transmission/downloads";
        };
      };
      services.jackett = {
        enable = true;
        openFirewall = true;
        user = config.users.users.www-data.name;
        group = config.users.groups.www-data.name;
        dataDir = "/nix/var/data/jackett";
      };
      services.sonarr = {
        enable = true;
        openFirewall = true;
        user = config.users.users.www-data.name;
        group = config.users.groups.www-data.name;
        dataDir = "/nix/var/data/sonarr";
      };
      services.radarr = {
        enable = true;
        openFirewall = true;
        user = config.users.users.www-data.name;
        group = config.users.groups.www-data.name;
        dataDir = "/nix/var/data/radarr";
      };
      services.headphones = {
        enable = true;
        user = config.users.users.www-data.name;
        group = config.users.groups.www-data.name;
        dataDir = "/nix/var/data/headphones";
        host = "192.168.1.2";
      };

      networking.firewall.allowedTCPPorts = [ config.services.headphones.port ];

      system.stateVersion = "21.11";
    };
  };

  virtualisation.oci-containers.containers.flaresolverr = {
    image = "ghcr.io/flaresolverr/flaresolverr:v2.0.2";
    environment = {
      "LOG_LEVEL" = "debug";
      "CAPTCHA_SOLVER" = "hcaptcha-solver";
    };
    ports = [ "192.168.1.1:8191:8191" ];
    autoStart = true;
  };

  services.nginx.virtualHosts = {
    "transmission.${config.networking.domain}" = {
      forceSSL = true;
      enableACME = true;
      locations."/" = { proxyPass = "http://192.168.1.2:9091"; };
    };
    "jackett.${config.networking.domain}" = {
      forceSSL = true;
      enableACME = true;
      locations."/" = { proxyPass = "http://192.168.1.2:9117"; };
    };
    "sonarr.${config.networking.domain}" = {
      forceSSL = true;
      enableACME = true;
      locations."/" = { proxyPass = "http://192.168.1.2:8989"; };
    };
    "radarr.${config.networking.domain}" = {
      forceSSL = true;
      enableACME = true;
      locations."/" = { proxyPass = "http://192.168.1.2:7878"; };
    };
    "headphones.${config.networking.domain}" = {
      forceSSL = true;
      enableACME = true;
      locations."/" = {
        proxyPass =
          "http://192.168.1.2:${toString config.services.headphones.port}";
      };
    };
  };
}
