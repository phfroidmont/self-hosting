{ modulesPath, config, lib, pkgs, ... }:

{
  imports =
    [
      (modulesPath + "/installer/scan/not-detected.nix")
    ];

  boot.initrd.availableKernelModules = [ "ahci" "sd_mod" ];
  boot.initrd.kernelModules = [ "dm-snapshot" ];
  boot.initrd.mdadmConf = config.environment.etc."mdadm.conf".text;
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

  environment.etc."mdadm.conf".text = ''
    HOMEHOST <ignore>
  '';

  nix.maxJobs = lib.mkDefault 8;
  powerManagement.cpuFreqGovernor = lib.mkDefault "ondemand";


  networking.useDHCP = false;
  networking.interfaces."enp2s0".ipv4.addresses = [
    {
      address = "78.46.96.243";
      prefixLength = 24;
    }
  ];
  networking.interfaces."enp2s0".ipv6.addresses = [
    {
      address = "2a01:4f8:120:8233::1";
      prefixLength = 64;
    }
  ];
  networking.defaultGateway = "78.46.96.225";
  networking.defaultGateway6 = { address = "fe80::1"; interface = "enp2s0"; };
  networking.nameservers = [ "8.8.8.8" ];
}
