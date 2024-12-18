{
  config,
  pkgs,
  pkgs-unstable,
  ...
}:
{
  imports = [
    ../environment.nix
    ../hardware/hetzner-dedicated-storage1.nix
    ../modules
  ];

  sops.secrets = {
    nixCacheKey = {
      key = "nix/cache_secret_key";
    };
  };

  custom = {
    services.binary-cache = {
      enable = true;
      secretKeyFile = config.sops.secrets.nixCacheKey.path;
    };

    services.monit = {
      enable = false;
      additionalConfig = ''
        check program raid-md127 with path "${pkgs.mdadm}/bin/mdadm --misc --detail --test /dev/md127"
          if status != 0 then alert
      '';
    };

    services.nginx.enable = true;
    services.openssh.enable = true;
  };

  networking.firewall.allowedTCPPorts = [
    80
    443
  ];

  services.borgbackup.repos = {
    epicerie_du_cellier = {
      authorizedKeys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJDbiI5UOGpVbaV+xihLqKP0B3UehboMMzOy3HhjjbSz backend1@epicerieducellier.be"
      ];
      path = "/var/lib/epicerie_du_cellier_backup";
    };
  };
}
