{ config
, modulesPath
, pkgs
, ...
}:
{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
    (modulesPath + "/profiles/qemu-guest.nix")
    ../environment.nix
    ../modules/openssh.nix
    ../modules/pangolin.nix
    ../modules/backup-job.nix
    ../modules/monit.nix
  ];

  networking.useDHCP = true;
  networking.usePredictableInterfaceNames = false;
  nixpkgs.hostPlatform = "x86_64-linux";

  boot.loader.grub = {
    efiSupport = true;
    efiInstallAsRemovable = true;
  };

  boot.tmp.cleanOnBoot = true;
  networking.firewall.allowPing = true;
  services.openssh.openFirewall = true;
  time.timeZone = "Europe/Amsterdam";

  programs.ssh.knownHosts.storagebox = {
    hostNames = [ "[u348077.your-storagebox.de]:23" ];
    publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIICf9svRenC/PLKIL9nk6K/pxQgoiFC41wTNvoIncOxs";
  };

  sops = {
    defaultSopsFile = ../secrets/pangolin.enc.yml;
    gnupg.sshKeyPaths = [ "/etc/ssh/ssh_host_rsa_key" ];
    age.sshKeyPaths = [ ];
    secrets = {
      pangolinEnvironment.key = "pangolin/environment";
      borgSshKey = {
        owner = config.services.borgbackup.jobs.data.user;
        key = "borg/ssh_key";
      };
    };
  };

  systemd.tmpfiles.rules = [
    "d /nix/var/data/backup 0700 root root -"
  ];

  custom.services = {
    openssh.enable = true;

    pangolin = {
      enable = true;
      environmentFile = config.sops.secrets.pangolinEnvironment.path;
    };

    backup-job = {
      enable = true;
      repoName = "pangolin1";
      sshKey = config.sops.secrets.borgSshKey.path;
      additionalPaths = [
        "/var/lib/pangolin"
        config.sops.secrets.pangolinEnvironment.path
        "/etc/ssh/ssh_host_rsa_key"
      ];
      patterns = [
        "- /var/lib/pangolin/.next"
        "- /var/lib/pangolin/config/db/db.sqlite"
        "- /var/lib/pangolin/config/db/db.sqlite-wal"
        "- /var/lib/pangolin/config/db/db.sqlite-shm"
      ];
      readWritePaths = [
        "/nix/var/data/backup"
        "/var/lib/pangolin/config/db"
      ];
      preHook = ''
        snapshot=/nix/var/data/backup/pangolin.sqlite
        rm -f "$snapshot"
        test -s /var/lib/pangolin/config/db/db.sqlite
        ${pkgs.sqlite}/bin/sqlite3 -cmd '.timeout 10000' /var/lib/pangolin/config/db/db.sqlite ".backup '$snapshot'"
        integrity="$(${pkgs.sqlite}/bin/sqlite3 "$snapshot" 'PRAGMA quick_check;')"
        test "$integrity" = ok
      '';
      restoreTestPaths = [
        "nix/var/data/backup/pangolin.sqlite"
        "run/secrets/pangolinEnvironment"
        "var/lib/pangolin/config/key"
        "var/lib/pangolin/config/letsencrypt/acme.json"
        "etc/ssh/ssh_host_rsa_key"
      ];
      restoreTestScript = ''
        integrity="$(${pkgs.sqlite}/bin/sqlite3 "$restore_dir/nix/var/data/backup/pangolin.sqlite" 'PRAGMA quick_check;')"
        test "$integrity" = ok
        ${pkgs.gnugrep}/bin/grep -q '^SERVER_SECRET=.' "$restore_dir/run/secrets/pangolinEnvironment"
        ${pkgs.jq}/bin/jq -e '.letsencrypt.Certificates | length > 0' "$restore_dir/var/lib/pangolin/config/letsencrypt/acme.json" > /dev/null
        ${pkgs.openssh}/bin/ssh-keygen -y -f "$restore_dir/etc/ssh/ssh_host_rsa_key" > /dev/null
      '';
    };

    monit = {
      enable = true;
      additionalConfig = ''
        check program pangolin-service with path "${pkgs.systemd}/bin/systemctl is-active pangolin.service"
          every 2 cycles
          if status != 0 for 3 cycles then alert

        check host pangolin-api with address 127.0.0.1
          if failed port 3001 protocol http request "/api/v1/" for 3 cycles then alert

        check file backup-archive-check with path /nix/var/data/backup/borg-check-ok
          if timestamp > 8 days then alert

        check file backup-restore-check with path /nix/var/data/backup/restore-test-ok
          if timestamp > 8 days then alert

        check program gerbil-service with path "${pkgs.systemd}/bin/systemctl is-active gerbil.service"
          every 2 cycles
          if status != 0 for 3 cycles then alert

        check program traefik-service with path "${pkgs.systemd}/bin/systemctl is-active traefik.service"
          every 2 cycles
          if status != 0 for 3 cycles then alert
      '';
    };
  };

  disko.devices = {
    disk.disk1 = {
      device = "/dev/sda";
      type = "disk";
      content = {
        type = "gpt";
        partitions = {
          boot = {
            name = "boot";
            size = "1M";
            type = "EF02";
          };
          esp = {
            name = "ESP";
            size = "500M";
            type = "EF00";
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot";
            };
          };
          root = {
            name = "root";
            size = "100%";
            content = {
              type = "lvm_pv";
              vg = "pool";
            };
          };
        };
      };
    };
    lvm_vg.pool = {
      type = "lvm_vg";
      lvs.root = {
        size = "100%FREE";
        content = {
          type = "filesystem";
          format = "ext4";
          mountpoint = "/";
          mountOptions = [ "defaults" ];
        };
      };
    };
  };
}
