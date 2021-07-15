{ pkgs, lib, config, ... }:
{
  services.openssh.enable = true;
  users.users.root.openssh.authorizedKeys.keyFiles = [
     ../ssh_keys/phfroidmont-desktop.pub
  ];
}
