{ config
, modulesPath
, pkgs
, ...
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
  # Newt reaches OpenSSH over loopback; recovery uses provider rescue access.
  services.openssh.openFirewall = false;

  services.nscd.enableNsncd = true;
  zramSwap.enable = true;

  services.unbound = {
    enable = true;
    resolveLocalQueries = false;
    settings = {
      server = {
        # Newt reaches this listener locally; do not expose recursive DNS publicly.
        interface = [ "127.0.0.1" ];
        access-control = [ "127.0.0.0/8 allow" ];
        # Trust Foyer's split-horizon answers rather than public DNSSEC delegations.
        domain-insecure = [ "foyer.cloud." "foyer.lu." "lefoyer.lu." "internal." ];
      };
      forward-zone = [
        {
          name = ".";
          forward-addr = [ "9.9.9.10" "149.112.112.10" ];
        }
        {
          name = "foyer.cloud.";
          forward-addr = [ "10.33.0.100" ];
        }
        {
          name = "foyer.lu.";
          forward-addr = [ "10.33.0.100" ];
        }
        {
          name = "lefoyer.lu.";
          forward-addr = [ "10.33.0.100" ];
        }
        {
          name = "internal.";
          forward-addr = [ "10.33.0.100" ];
        }
      ];
    };
  };

  sops.secrets.newtRelay1Environment = {
    key = "newt/relay1/environment";
    restartUnits = [ "newt.service" ];
  };

  services.newt = {
    enable = true;
    package = pkgs.callPackage ../packages/pangolin/newt.nix { };
    settings = {
      endpoint = "https://pangolin.banditlair.com";
      disable-ssh = true;
    };
    environmentFile = config.sops.secrets.newtRelay1Environment.path;
    blueprint.private-resources = {
      relay1-ssh = {
        name = "relay1 SSH";
        mode = "host";
        destination = "127.0.0.1";
        alias = "relay1.internal";
        tcp-ports = "22";
        udp-ports = "";
        disable-icmp = true;
        roles = [ "Personal" ];
        users = [ ];
      };
      conditional-dns = {
        name = "Conditional DNS";
        mode = "host";
        destination = "127.0.0.1";
        alias = "dns.internal";
        tcp-ports = "53";
        udp-ports = "53";
        disable-icmp = true;
        roles = [ "Personal" ];
        users = [ ];
      };
      wsl-ssh = {
        name = "Foyer WSL";
        mode = "host";
        destination = "10.250.250.2";
        alias = "foyer-wsl.internal";
        tcp-ports = "22,2345";
        udp-ports = "";
        disable-icmp = true;
        # Pangolin also retains its automatic Admin grant.
        roles = [ "Personal" ];
        users = [ ];
      };
      foyer-10-33 = {
        name = "Foyer 10.33.0.0/16";
        mode = "cidr";
        destination = "10.33.0.0/16";
        tcp-ports = "*";
        udp-ports = "*";
        disable-icmp = false;
        roles = [ "Personal" ];
        users = [ ];
      };
      foyer-10-46 = {
        name = "Foyer 10.46.0.0/16";
        mode = "cidr";
        destination = "10.46.0.0/16";
        tcp-ports = "*";
        udp-ports = "*";
        disable-icmp = false;
        roles = [ "Personal" ];
        users = [ ];
      };
      foyer-10-133 = {
        name = "Foyer 10.133.0.0/16";
        mode = "cidr";
        destination = "10.133.0.0/16";
        tcp-ports = "*";
        udp-ports = "*";
        disable-icmp = false;
        roles = [ "Personal" ];
        users = [ ];
      };
      foyer-10-134 = {
        name = "Foyer 10.134.0.0/16";
        mode = "cidr";
        destination = "10.134.0.0/16";
        tcp-ports = "*";
        udp-ports = "*";
        disable-icmp = false;
        roles = [ "Personal" ];
        users = [ ];
      };
      foyer-10-161 = {
        name = "Foyer 10.161.0.0/16";
        mode = "cidr";
        destination = "10.161.0.0/16";
        tcp-ports = "*";
        udp-ports = "*";
        disable-icmp = false;
        roles = [ "Personal" ];
        users = [ ];
      };
      foyer-10-200 = {
        name = "Foyer 10.200.0.0/16";
        mode = "cidr";
        destination = "10.200.0.0/16";
        tcp-ports = "*";
        udp-ports = "*";
        disable-icmp = false;
        roles = [ "Personal" ];
        users = [ ];
      };
    };
  };

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

  # Newt originates connections locally instead of forwarding client IP packets.
  boot.kernel.sysctl."net.ipv4.ip_forward" = false;

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
