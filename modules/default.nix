{ config, pkgs, ... }:
{
  imports = [
    ./backup-job.nix
    ./monit.nix
    ./gitlab-runner.nix
    ./openssh.nix
    ./murmur.nix
    ./mastodon.nix
  ];
}
