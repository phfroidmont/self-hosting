{
  modulesPath,
  config,
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
  networking.firewall.allowedTCPPorts = [ 443 ];
  networking.usePredictableInterfaceNames = false;
  custom.services.openssh.enable = true;
  services.openssh.openFirewall = true;

  services.nscd.enableNsncd = true;
  zramSwap.enable = true;

  sops.secrets = {
    openvpnCa = {
      key = "openvpn/ca.crt";
    };
    openvpnServerCert = {
      key = "openvpn/server.crt";
    };
    openvpnServerKey = {
      key = "openvpn/server.key";
    };
    openvpnDh = {
      key = "openvpn/dh.pem";
    };
    openvpnTlsCrypt = {
      key = "openvpn/tls-crypt.key";
    };
  };

  systemd.tmpfiles.rules = [
    "d /etc/openvpn/ccd 0750 root root -"
  ];

  environment.etc."openvpn/ccd/wsl".text = ''
    iroute 10.33.0.0 255.255.0.0
    iroute 10.46.0.0 255.255.0.0
    iroute 10.133.0.0 255.255.0.0
    iroute 10.134.0.0 255.255.0.0
    iroute 10.161.0.0 255.255.0.0
    iroute 10.200.0.0 255.255.0.0
  '';

  services.openvpn.servers.relay.config = ''
    port 443
    proto tcp-server
    dev tun
    topology subnet

    user nobody
    group nogroup
    persist-key
    persist-tun
    keepalive 10 120

    ca ${config.sops.secrets.openvpnCa.path}
    cert ${config.sops.secrets.openvpnServerCert.path}
    key ${config.sops.secrets.openvpnServerKey.path}
    dh ${config.sops.secrets.openvpnDh.path}
    tls-crypt ${config.sops.secrets.openvpnTlsCrypt.path}

    server 10.8.0.0 255.255.255.0
    client-config-dir /etc/openvpn/ccd

    route 10.33.0.0 255.255.0.0
    route 10.46.0.0 255.255.0.0
    route 10.133.0.0 255.255.0.0
    route 10.134.0.0 255.255.0.0
    route 10.161.0.0 255.255.0.0
    route 10.200.0.0 255.255.0.0

    push "route 10.33.0.0 255.255.0.0"
    push "route 10.46.0.0 255.255.0.0"
    push "route 10.133.0.0 255.255.0.0"
    push "route 10.134.0.0 255.255.0.0"
    push "route 10.161.0.0 255.255.0.0"
    push "route 10.200.0.0 255.255.0.0"

    push "dhcp-option DNS 1.1.1.1"
    push "dhcp-option DNS 9.9.9.9"

    status /var/log/openvpn-relay-status.log
    log-append /var/log/openvpn-relay.log
    verb 3
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
