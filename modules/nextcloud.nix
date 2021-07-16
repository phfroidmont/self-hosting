{ config, lib, pkgs, ... }:
let
  uidFile = pkgs.writeText "uidfile" ''
    nextcloud:33
  '';
  gidFile = pkgs.writeText "gidfile" ''
    nextcloud:33
  '';
  sshfsOptions = [
    "nofail"
    "identityfile=/var/keys/sshfs-ssh-key"
    "ServerAliveInterval=15"
    "idmap=file"
    "uidfile=${uidFile}"
    "gidfile=${gidFile}"
    "allow_other"
    "default_permissions"
    "nomap=ignore"
  ];
in
{
  environment.systemPackages = with pkgs; [
    sshfs
  ];

  fileSystems."/var/lib/nextcloud/data" =
    {
      device = " www-data@10.0.2.2:/var/lib/nextcloud/data";
      fsType = "fuse.sshfs";
      options = sshfsOptions;
    };

  fileSystems."/run/mount/media" =
    {
      device = " www-data@10.0.2.2:/data";
      fsType = "fuse.sshfs";
      options = sshfsOptions;
    };

  services.nginx = {
    virtualHosts = {
      "${config.services.nextcloud.hostName}" = {
        enableACME = true;
        forceSSL = true;
      };
    };
  };

  services.nextcloud = {
    enable = true;
    package = pkgs.nextcloud21;
    hostName = "cloud.${config.networking.domain}";
    config = {
      dbtype = "pgsql";
      dbuser = "nextcloud";
      dbhost = "10.0.1.11";
      dbname = "nextcloud";
      dbpassFile = "/var/keys/nextcloud-db-pass";
      adminpassFile = "/var/keys/nextcloud-admin-pass";
      adminuser = "root";
    };
  };
  users.users.nextcloud.extraGroups = [ "keys" ];
}
