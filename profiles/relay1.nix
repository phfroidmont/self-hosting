{ config
, modulesPath
, lib
, pkgs
, ...
}:
let
  alertingState = builtins.fromJSON (builtins.readFile ../telemetry-alerting.json);
  alertsPrepared = alertingState == { schemaVersion = 1; prepared = true; };
  enrollment = builtins.fromJSON (builtins.readFile ../telemetry-enrollment.json);
in
{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
    (modulesPath + "/profiles/qemu-guest.nix")
    ../environment.nix
    ../modules/openssh.nix
    ../modules/telemetry-watchdog.nix
  ];

  assertions = [{
    assertion = alertingState == { } || alertsPrepared;
    message = "Invalid telemetry-alerting.json; prepare the dedicated ciphertext with the operator helper.";
  }];
  custom.services.telemetryWatchdog = lib.mkIf alertsPrepared {
    enable = true;
    mode = "receiver";
    secretsFile = ../secrets/telemetry-alerts.enc.yml;
    collectorNiceId = enrollment.machines.hel1.niceId;
  };

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
      port = 61335;
    };
    environmentFile = config.sops.secrets.newtRelay1Environment.path;
    blueprint.private-resources = {
      relay1-ssh = {
        name = "relay1 SSH";
        mode = "host";
        destination = "127.0.0.1";
        alias = "relay1.bl.internal";
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
        alias = "dns.bl.internal";
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
        alias = "wsl.foyer.internal";
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
    ips = [
      "10.250.250.1/30"
      "10.250.251.1/24"
    ];
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
      {
        publicKey = "vi85E2q83PMXW6o9ffB+cKiFHqx0wZf8fqqf6hznDGM=";
        allowedIPs = [ "10.250.251.2/32" ];
      }
    ];
  };

  boot.kernel.sysctl."net.ipv4.ip_forward" = true;

  # Forward only Stellaris's fallback IPv4 address to the public interface. The
  # final drop keeps the existing WSL peer and every other interface routed off.
  networking.firewall.extraCommands = ''
    # Newt's wildcard UDP socket replies from wg-relay's primary 10.250.250.1.
    # DNAT the public target there so conntrack restores the public source on
    # replies. Only accept packets translated from the public destination.
    iptables -w -t nat -D PREROUTING -i wg-relay -s 10.250.251.2/32 -d 195.201.112.227/32 -p udp --dport 61335 -j DNAT --to-destination 10.250.250.1:61335 2>/dev/null || true
    iptables -w -t nat -A PREROUTING -i wg-relay -s 10.250.251.2/32 -d 195.201.112.227/32 -p udp --dport 61335 -j DNAT --to-destination 10.250.250.1:61335
    # Insert ahead of NixOS's INPUT rejection; direct private-target probes
    # have no DNAT state and must not be allowed through.
    iptables -w -D INPUT -i wg-relay -s 10.250.251.2/32 -d 10.250.250.1/32 -p udp --dport 61335 -m conntrack --ctstate DNAT --ctorigdst 195.201.112.227 --ctorigdstport 61335 -j ACCEPT 2>/dev/null || true
    iptables -w -I INPUT 1 -i wg-relay -s 10.250.251.2/32 -d 10.250.250.1/32 -p udp --dport 61335 -m conntrack --ctstate DNAT --ctorigdst 195.201.112.227 --ctorigdstport 61335 -j ACCEPT

    # Keep forwarding closed during rule replacement and if the firewall stops.
    iptables -w -P FORWARD DROP
    iptables -w -D FORWARD -j stellaris-fallback 2>/dev/null || true
    iptables -w -F stellaris-fallback 2>/dev/null || true
    iptables -w -X stellaris-fallback 2>/dev/null || true
    iptables -w -N stellaris-fallback

    iptables -w -A stellaris-fallback -i wg-relay -s 10.250.251.2/32 -o eth0 -d 0.0.0.0/8 -j DROP
    iptables -w -A stellaris-fallback -i wg-relay -s 10.250.251.2/32 -o eth0 -d 10.0.0.0/8 -j DROP
    iptables -w -A stellaris-fallback -i wg-relay -s 10.250.251.2/32 -o eth0 -d 100.64.0.0/10 -j DROP
    iptables -w -A stellaris-fallback -i wg-relay -s 10.250.251.2/32 -o eth0 -d 127.0.0.0/8 -j DROP
    iptables -w -A stellaris-fallback -i wg-relay -s 10.250.251.2/32 -o eth0 -d 169.254.0.0/16 -j DROP
    iptables -w -A stellaris-fallback -i wg-relay -s 10.250.251.2/32 -o eth0 -d 172.16.0.0/12 -j DROP
    iptables -w -A stellaris-fallback -i wg-relay -s 10.250.251.2/32 -o eth0 -d 192.0.0.0/24 -j DROP
    iptables -w -A stellaris-fallback -i wg-relay -s 10.250.251.2/32 -o eth0 -d 192.0.2.0/24 -j DROP
    iptables -w -A stellaris-fallback -i wg-relay -s 10.250.251.2/32 -o eth0 -d 192.88.99.0/24 -j DROP
    iptables -w -A stellaris-fallback -i wg-relay -s 10.250.251.2/32 -o eth0 -d 192.168.0.0/16 -j DROP
    iptables -w -A stellaris-fallback -i wg-relay -s 10.250.251.2/32 -o eth0 -d 198.18.0.0/15 -j DROP
    iptables -w -A stellaris-fallback -i wg-relay -s 10.250.251.2/32 -o eth0 -d 198.51.100.0/24 -j DROP
    iptables -w -A stellaris-fallback -i wg-relay -s 10.250.251.2/32 -o eth0 -d 203.0.113.0/24 -j DROP
    iptables -w -A stellaris-fallback -i wg-relay -s 10.250.251.2/32 -o eth0 -d 224.0.0.0/4 -j DROP
    iptables -w -A stellaris-fallback -i wg-relay -s 10.250.251.2/32 -o eth0 -d 240.0.0.0/4 -j DROP
    iptables -w -A stellaris-fallback -i wg-relay -s 10.250.251.2/32 -o eth0 -j ACCEPT
    iptables -w -A stellaris-fallback -i eth0 -o wg-relay -d 10.250.251.2/32 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
    iptables -w -A stellaris-fallback -j DROP
    iptables -w -I FORWARD 1 -j stellaris-fallback

    iptables -w -t nat -D POSTROUTING -s 10.250.251.2/32 -o eth0 -j MASQUERADE 2>/dev/null || true
    iptables -w -t nat -A POSTROUTING -s 10.250.251.2/32 -o eth0 -j MASQUERADE
  '';

  networking.firewall.extraStopCommands = ''
    iptables -w -D INPUT -i wg-relay -s 10.250.251.2/32 -d 10.250.250.1/32 -p udp --dport 61335 -m conntrack --ctstate DNAT --ctorigdst 195.201.112.227 --ctorigdstport 61335 -j ACCEPT 2>/dev/null || true
    iptables -w -t nat -D PREROUTING -i wg-relay -s 10.250.251.2/32 -d 195.201.112.227/32 -p udp --dport 61335 -j DNAT --to-destination 10.250.250.1:61335 2>/dev/null || true
    iptables -w -D FORWARD -j stellaris-fallback 2>/dev/null || true
    iptables -w -F stellaris-fallback 2>/dev/null || true
    iptables -w -X stellaris-fallback 2>/dev/null || true
    iptables -w -t nat -D POSTROUTING -s 10.250.251.2/32 -o eth0 -j MASQUERADE 2>/dev/null || true
  '';

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
