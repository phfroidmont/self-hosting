{ ... }:
{
  imports = [
    ./backup-job.nix
    ./monit.nix
    ./gitlab-runner.nix
    ./openssh.nix
    ./murmur.nix
    ./mastodon.nix
    ./nginx.nix
    ./jellyfin.nix
    ./stb.nix
    ./monero.nix
    ./torrents.nix
    ./jitsi.nix
    ./binary-cache.nix
    ./grafana.nix
    ./monitoring-exporters.nix
    ./synapse.nix
    ./nextcloud.nix
    ./roundcube.nix
    ./dokuwiki.nix
    ./postgresql.nix
    ./foundryvtt.nix
    ./immich.nix
  ];
}
