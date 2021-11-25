{ pkgs, lib, config, ... }:
{
  services.openssh.enable = true;
  services.openssh.permitRootLogin = "prohibit-password";
  users.users.root.openssh.authorizedKeys.keyFiles = [
    ../ssh_keys/phfroidmont-desktop.pub
    ../ssh_keys/froidmpa-laptop.pub
  ];
}
