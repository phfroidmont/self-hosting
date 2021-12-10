{ config, lib, pkgs, ... }:
let
  vpnServer = "89.249.65.115";
  vpnConfig = builtins.fetchurl {
    url = "https://downloads.nordcdn.com/configs/files/ovpn_udp/servers/de948.nordvpn.com.udp.ovpn";
    sha256 = "07z4xxs4nxg44c3d19rnqg6iq2f7i8yjy28rwbz312z4axqgkcxn";
  };
in
{

  sops.secrets = {
    vpnCredentials = {
      key = "openvpn/credentials";
    };
    transmissionRpcCredentials = {
      key = "transmission/rpc_config.json";
    };
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
          config ${vpnConfig}
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

  services.nginx.virtualHosts."transmission.${config.networking.domain}" = {
    forceSSL = true;
    enableACME = true;
    locations."/" = {
      proxyPass = "http://192.168.1.2:9091";
    };
  };
  services.nginx.virtualHosts."jackett.${config.networking.domain}" = {
    forceSSL = true;
    enableACME = true;
    locations."/" = {
      proxyPass = "http://192.168.1.2:9117";
    };
  };
  services.nginx.virtualHosts."sonarr.${config.networking.domain}" = {
    forceSSL = true;
    enableACME = true;
    locations."/" = {
      proxyPass = "http://192.168.1.2:8989";
    };
  };
  services.nginx.virtualHosts."radarr.${config.networking.domain}" = {
    forceSSL = true;
    enableACME = true;
    locations."/" = {
      proxyPass = "http://192.168.1.2:7878";
    };
  };
}
