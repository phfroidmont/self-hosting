{ modulesPath, config, pkgs, ... }:
{
  imports = [ (modulesPath + "/profiles/qemu-guest.nix") ];

  boot.loader.grub.device = "/dev/sda";
  fileSystems."/" = { device = "/dev/sda1"; fsType = "ext4"; };

  time.timeZone = "Europe/Amsterdam";

  boot.cleanTmpDir = true;
  networking.firewall.allowPing = true;
}
