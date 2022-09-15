{ config, lib, pkgs, ... }:
{
  imports = [
    ../environment.nix
    ../hardware/hcloud.nix
    ../modules/openssh.nix
    ../modules/postgresql.nix
    ../modules/custom-backup-job.nix
    ../modules/custom-monit.nix
    ../modules/monitoring-exporters.nix
  ];

  networking.firewall.interfaces."enp7s0".allowedTCPPorts = [ config.services.prometheus.exporters.node.port config.services.postgresql.port ];

  sops.secrets = {
    borgSshKey = {
      owner = config.services.borgbackup.jobs.data.user;
      key = "borg/client_keys/db1/private";
    };
  };

  services.custom-backup-job = {
    readWritePaths = [ "/nix/var/data/postgresql" "/nix/var/data/backup/" ];
    preHook = ''
      ${pkgs.postgresql_12}/bin/pg_dump -U synapse synapse > /nix/var/data/postgresql/synapse.dmp
      ${pkgs.postgresql_12}/bin/pg_dump -U nextcloud nextcloud > /nix/var/data/postgresql/nextcloud.dmp
      ${pkgs.postgresql_12}/bin/pg_dump -U roundcube roundcube > /nix/var/data/postgresql/roundcube.dmp
    '';
    postHook = "touch /nix/var/data/backup/backup-ok";
    startAt = "03:00";
    sshKey = config.sops.secrets.borgSshKey.path;
  };

}
