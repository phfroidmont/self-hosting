{ pkgs, nixpkgs, ... }: {
  environment.systemPackages = with pkgs; [ htop nload tmux vim git ];

  nix = { nixPath = [ "nixpkgs=${nixpkgs}" ]; };

  services.nscd.enableNsncd = true;

  services.fail2ban.enable = true;

  zramSwap.enable = true;
}
