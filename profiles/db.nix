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

  services.custom-backup-job = {
    additionalReadWritePaths = [ "/nix/var/data/postgresql" ];
    additionalPreHook = ''
      ${pkgs.postgresql_12}/bin/pg_dump -U synapse synapse > /nix/var/data/postgresql/synapse.dmp
      ${pkgs.postgresql_12}/bin/pg_dump -U nextcloud nextcloud > /nix/var/data/postgresql/nextcloud.dmp
    '';
    startAt = "03:00";
  };

  networking.firewall.interfaces."ens10".allowedTCPPorts = [ 80 ];
}
