{
  modulesPath,
  ...
}:
{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
    (modulesPath + "/profiles/qemu-guest.nix")
    ../environment.nix
    ../modules/openssh.nix
  ];

  networking.useDHCP = true;
  nixpkgs.hostPlatform = "x86_64-linux";

  boot.loader.grub = {
    efiSupport = true;
    efiInstallAsRemovable = true;
  };

  time.timeZone = "Europe/Amsterdam";

  boot.tmp.cleanOnBoot = true;
  networking.firewall.allowPing = true;
  networking.firewall.allowedTCPPorts = [
    80
    443
  ];
  networking.usePredictableInterfaceNames = false;
  custom.services.openssh.enable = true;
  services.openssh.openFirewall = true;

  services.nscd.enableNsncd = true;
  zramSwap.enable = true;

  security.acme = {
    acceptTerms = true;
    defaults.email = "letsencrypt.account@banditlair.com";
    certs."ws.banditlair.com" = {
      listenHTTP = "0.0.0.0:80";
      reloadServices = [ "wstunnel-server-relay.service" ];
    };
  };

  services.wstunnel = {
    enable = true;
    servers.relay = {
      listen = {
        host = "0.0.0.0";
        port = 443;
        enableHTTPS = true;
      };
      useACMEHost = "ws.banditlair.com";
      settings = {
        log-lvl = "INFO";
        restrict-to = [
          {
            host = "127.0.0.1";
            port = 51820;
          }
        ];
      };
    };
  };

  systemd.services.wstunnel-server-relay = {
    after = [ "acme-ws.banditlair.com.service" ];
    wants = [ "acme-ws.banditlair.com.service" ];
  };

  networking.wireguard.enable = true;
  networking.wireguard.interfaces.wg-relay = {
    ips = [ "10.250.250.1/30" ];
    listenPort = 51820;
    privateKeyFile = "/var/lib/wireguard/wg-relay.key";
    generatePrivateKeyFile = true;
    peers = [
      {
        publicKey = "EX3QEJYNzs3sA3FUEIc9YGAhEup20qOCzUe+nMRrljQ=";
        allowedIPs = [
          "10.250.250.2/32"
          "10.33.0.0/16"
          "10.46.0.0/16"
          "10.133.0.0/16"
          "10.134.0.0/16"
          "10.161.0.0/16"
          "10.200.0.0/16"
        ];
      }
    ];
  };

  services.tailscale = {
    enable = true;
    useRoutingFeatures = "server";
    extraSetFlags = [
      "--advertise-routes=10.250.250.2/32,10.33.0.0/16,10.46.0.0/16,10.133.0.0/16,10.134.0.0/16,10.161.0.0/16,10.200.0.0/16"
    ];
  };

  boot.kernel.sysctl."net.ipv4.ip_forward" = true;

  networking.nat = {
    enable = true;
    internalInterfaces = [ "tailscale0" ];
    externalInterface = "wg-relay";
  };

  disko.devices = {
    disk.disk1 = {
      device = "/dev/sda";
      type = "disk";
      content = {
        type = "gpt";
        partitions = {
          boot = {
            name = "boot";
            size = "1M";
            type = "EF02";
          };
          esp = {
            name = "ESP";
            size = "500M";
            type = "EF00";
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot";
            };
          };
          root = {
            name = "root";
            size = "100%";
            content = {
              type = "lvm_pv";
              vg = "pool";
            };
          };
        };
      };
    };
    lvm_vg = {
      pool = {
        type = "lvm_vg";
        lvs = {
          root = {
            size = "100%FREE";
            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/";
              mountOptions = [
                "defaults"
              ];
            };
          };
        };
      };
    };
  };
}
