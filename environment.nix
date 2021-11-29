{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    htop
    nload
    tmux
    vim
  ];
}
