{ config, lib, pkgs, ... }:
{
  imports = [
    ../environment.nix
    ../hardware/hcloud.nix
    ../modules/openssh.nix
    ../modules/postgresql.nix
    ../modules/custom-backup-job.nix
  ];

  networking.firewall.interfaces."enp7s0".allowedTCPPorts = [ 5432 ];

  sops.secrets = {
    borgSshKey = {
      owner = config.services.borgbackup.jobs.data.user;
      key = "borg/client_keys/db1/private";
    };
  };

  services.custom-backup-job = {
    readWritePaths = [ "/nix/var/data/postgresql" ];
    preHook = ''
      ${pkgs.postgresql_12}/bin/pg_dump -U synapse synapse > /nix/var/data/postgresql/synapse.dmp
      ${pkgs.postgresql_12}/bin/pg_dump -U nextcloud nextcloud > /nix/var/data/postgresql/nextcloud.dmp
    '';
    startAt = "03:00";
    sshKey = config.sops.secrets.borgSshKey.path;
  };

  networking.firewall.interfaces."ens10".allowedTCPPorts = [ 80 ];
}
