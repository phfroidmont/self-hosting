{ modulesPath, pkgs, ... }:
{
  imports = [ (modulesPath + "/profiles/qemu-guest.nix") ];

  boot.loader.grub.device = "/dev/sda";
  fileSystems."/" = { device = "/dev/sda1"; fsType = "ext4"; };

  # Set NIX_PATH to be the same as the Terraform module
  # nix.nixPath = [ "nixpkgs=${pkgs}" ];

  environment.systemPackages = with pkgs; [
    htop
  ];
  boot.cleanTmpDir = true;
  networking.hostName = "db1";
  networking.domain = "banditlair.com";
  networking.firewall.allowPing = true;
  networking.firewall.interfaces."enp7s0".allowedTCPPorts = [ 5432 ];
  services.openssh.enable = true;
  users.users.root.openssh.authorizedKeys.keyFiles = [
     ./ssh_keys/phfroidmont-desktop.pub
  ];

  services.postgresql = {
    enable = true;
    package = pkgs.postgresql_12;
    initialScript = "/var/keys/postgres-init.sql";
    enableTCPIP = true;
    authentication = ''
      host all all 10.0.1.0/24 md5
    '';
  };
  users.users.postgres.extraGroups = [ "keys" ];
}
