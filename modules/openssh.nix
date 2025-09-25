{ config, lib, ... }:
with lib;
let
  cfg = config.custom.services.openssh;
in
{
  options.custom.services.openssh = {
    enable = mkEnableOption "openssh";
  };

  config = mkIf cfg.enable {
    services.openssh.enable = true;
    services.openssh.settings.PermitRootLogin = "prohibit-password";
    users.users.root.openssh.authorizedKeys.keyFiles = [
      ../ssh_keys/froidmpa-desktop.pub
      ../ssh_keys/froidmpa-laptop.pub
      ../ssh_keys/phfroidmont-stellaris.pub
      ../ssh_keys/elios-desktop.pub
    ];
  };
}
