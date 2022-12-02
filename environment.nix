{ pkgs, nixpkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    htop
    nload
    tmux
    vim
  ];

  nix = {
    nixPath = [
      "nixpkgs=${nixpkgs}"
    ];
  };

  services.nscd.enableNsncd = true;
}
