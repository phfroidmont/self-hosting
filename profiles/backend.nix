{ config, lib, pkgs, ... }:
{
  imports = [
    ../environment.nix
    ../hardware/hcloud.nix
    ../modules/openssh.nix
    ../modules/nginx.nix
    ../modules/murmur.nix
    ../modules/synapse.nix
    ../modules/nextcloud.nix
    ../modules/custom-backup-job.nix
  ];

  services.custom-backup-job = {
    additionalPaths = [ "/var/lib/nextcloud/config" ];
    additionalReadWritePaths = [ "/nix/var/data/murmur" ];
    additionalPreHook = "cp /var/lib/murmur/murmur.sqlite /nix/var/data/murmur/murmur.sqlite";
    startAt = "03:30";
  };

  networking.localCommands = "ip addr add 95.216.177.3/32 dev enp1s0";
  networking.firewall.allowedTCPPorts = [ 80 443 64738 ];
  networking.firewall.allowedUDPPorts = [ 64738 ];

  services.monit = {
    enable = true;
    config = ''
      set daemon 30
        with start delay 90

      set httpd
        port 2812
        use address 127.0.0.1
        allow localhost

      check file nextcloud-data-mounted with path /var/lib/nextcloud/data/index.html
        start = "${pkgs.systemd}/bin/systemctl start var-lib-nextcloud-data.mount"
    '';
  };

  networking.firewall.interfaces."ens10".allowedTCPPorts = [ 80 ];
}
