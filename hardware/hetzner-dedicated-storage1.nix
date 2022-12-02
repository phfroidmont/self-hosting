{ modulesPath, config, lib, pkgs, ... }:

{
  imports =
    [
      (modulesPath + "/installer/scan/not-detected.nix")
    ];

  boot.initrd.availableKernelModules = [ "ahci" "sd_mod" ];
  boot.initrd.kernelModules = [ "dm-snapshot" ];
  boot.initrd.services.swraid.mdadmConf = config.environment.etc."mdadm.conf".text;
  boot.kernelModules = [ "kvm-intel" ];
  boot.extraModulePackages = [ ];
  boot.loader.systemd-boot.enable = false;
  boot.loader.grub = {
    enable = true;
    efiSupport = false;
    devices = [ "/dev/sda" "/dev/sdb" "/dev/sdc" "/dev/sdd" ];
  };

  fileSystems."/" =
    {
      device = "/dev/disk/by-uuid/e5c27021-ce34-4680-ba6f-233070cb944f";
      fsType = "ext4";
    };

  swapDevices = [ ];

  time.timeZone = "Europe/Amsterdam";

  environment.etc."mdadm.conf".text = ''
    HOMEHOST <ignore>
  '';

  nix.settings.max-jobs = lib.mkDefault 8;
  powerManagement.cpuFreqGovernor = lib.mkDefault "ondemand";

  networking = {
    useDHCP = false;
    defaultGateway = "78.46.96.225";
    defaultGateway6 = { address = "fe80::1"; interface = "enp2s0"; };
    nameservers = [
      "213.133.100.100"
      "213.133.99.99"
      "213.133.98.98"
    ];
    interfaces = {
      enp2s0 = {
        ipv4.addresses = [
          {
            address = "78.46.96.243";
            prefixLength = 24;
          }
        ];
        ipv6.addresses = [
          {
            address = "2a01:4f8:120:8233::1";
            prefixLength = 64;
          }
        ];
      };
      vlan4001 = {
        mtu = 1400;
        ipv4 = {
          addresses = [{
            address = "10.0.2.3";
            prefixLength = 24;
          }];
          routes = [{
            address = "10.0.0.0";
            prefixLength = 16;
            via = "10.0.2.1";
          }];
        };
      };
    };
    vlans.vlan4001 = { id = 4001; interface = "enp2s0"; };
  };


}
