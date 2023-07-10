{ modulesPath, config, pkgs, ... }: {
  imports = [ (modulesPath + "/profiles/qemu-guest.nix") ];

  boot.loader.grub.device = "/dev/sda";
  fileSystems."/" = {
    device = "/dev/sda1";
    fsType = "ext4";
  };

  time.timeZone = "Europe/Amsterdam";

  boot.tmp.cleanOnBoot = true;
  networking.firewall.allowPing = true;
  networking.usePredictableInterfaceNames = false;

  networking.dhcpcd.enable = false;

  systemd.network = {
    enable = true;
    networks."10-wan" = {
      matchConfig.Name = "eth0";
      networkConfig.DHCP = "ipv4";
      # make routing on this interface a dependency for network-online.target
      linkConfig.RequiredForOnline = "routable";
    };
    networks."20-lan" = {
      matchConfig.Name = "eth1";
      networkConfig.DHCP = "ipv4";
      linkConfig.RequiredForOnline = "routable";
    };
  };
}
