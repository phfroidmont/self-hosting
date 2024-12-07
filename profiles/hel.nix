{
  config,
  ...
}:
{
  imports = [
    ../environment.nix
    ../hardware/hetzner-dedicated-hel1.nix
    ../modules
  ];

  sops.secrets = {
    runnerRegistrationConfig = {
      owner = config.users.users.gitlab-runner.name;
      key = "gitlab/runner_registration_config/hel1";
    };
  };

  time.timeZone = "Europe/Amsterdam";

  networking.nat = {
    enable = true;
    internalInterfaces = [ "ve-+" ];
    externalInterface = "enp41s0";
  };

  disko.devices = {
    disk = {
      nvme0 = {
        device = "/dev/nvme0n1";
        type = "disk";
        content = {
          type = "gpt";
          partitions = {
            boot = {
              name = "boot";
              size = "1M";
              type = "EF02";
            };
            mdadm = {
              size = "100%";
              content = {
                type = "mdraid";
                name = "root";
              };
            };
          };
        };
      };
      nvme1 = {
        device = "/dev/nvme1n1";
        type = "disk";
        content = {
          type = "gpt";
          partitions = {
            boot = {
              name = "boot";
              size = "1M";
              type = "EF02";
            };
            mdadm = {
              size = "100%";
              content = {
                type = "mdraid";
                name = "root";
              };
            };
          };
        };
      };
      sda = {
        device = "/dev/sda";
        type = "disk";
        content = {
          type = "gpt";
          partitions = {
            mdadm = {
              size = "100%";
              content = {
                type = "mdraid";
                name = "data";
              };
            };
          };
        };
      };
      sdb = {
        device = "/dev/sdb";
        type = "disk";
        content = {
          type = "gpt";
          partitions = {
            mdadm = {
              size = "100%";
              content = {
                type = "mdraid";
                name = "data";
              };
            };
          };
        };
      };
      sdc = {
        device = "/dev/sdc";
        type = "disk";
        content = {
          type = "gpt";
          partitions = {
            mdadm = {
              size = "100%";
              content = {
                type = "mdraid";
                name = "data";
              };
            };
          };
        };
      };
      sdd = {
        device = "/dev/sdd";
        type = "disk";
        content = {
          type = "gpt";
          partitions = {
            mdadm = {
              size = "100%";
              content = {
                type = "mdraid";
                name = "data";
              };
            };
          };
        };
      };
    };
    mdadm = {
      root = {
        type = "mdadm";
        level = 1;
        content = {
          type = "gpt";
          partitions.primary = {
            size = "100%";
            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/";
            };
          };
        };
      };
      data = {
        type = "mdadm";
        level = 10;
        content = {
          type = "gpt";
          partitions.primary = {
            size = "100%";
            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/nix/var/data";
            };
          };
        };
      };
    };
  };

  custom = {
    services.openssh.enable = true;
    services.gitlab-runner = {
      enable = true;
      runnerRegistrationConfigFile = config.sops.secrets.runnerRegistrationConfig.path;
    };
  };

}
