{ config, lib, pkgs, ... }: {
  imports = [
    ../environment.nix
    ../hardware/hcloud.nix
    ../modules
    ../modules/postgresql.nix
    ../modules/monitoring-exporters.nix
  ];

  networking.firewall.interfaces."eth1".allowedTCPPorts = [
    config.services.prometheus.exporters.node.port
    config.services.postgresql.port
  ];

  sops.secrets = {
    borgSshKey = {
      owner = config.services.borgbackup.jobs.data.user;
      key = "borg/client_keys/db1/private";
    };
  };

  custom = {
    services.backup-job = {
      enable = true;
      repoName = "db1";
      readWritePaths = [ "/nix/var/data/postgresql" "/nix/var/data/backup/" ];
      preHook = ''
        ${config.services.postgresql.package}/bin/pg_dump -U synapse synapse > /nix/var/data/postgresql/synapse.dmp
        ${config.services.postgresql.package}/bin/pg_dump -U nextcloud nextcloud > /nix/var/data/postgresql/nextcloud.dmp
        ${config.services.postgresql.package}/bin/pg_dump -U roundcube roundcube > /nix/var/data/postgresql/roundcube.dmp
        ${config.services.postgresql.package}/bin/pg_dump -U mastodon mastodon > /nix/var/data/postgresql/mastodon.dmp
      '';
      startAt = "03:00";
      sshKey = config.sops.secrets.borgSshKey.path;
    };

    services.openssh.enable = true;
  };

}
