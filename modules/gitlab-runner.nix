{ config, lib, pkgs, ... }:
{
  sops.secrets = {
    runnerRegistrationConfig = {
      owner = config.users.users.gitlab-runner.name;
      key = "gitlab/runner_registration_config";
    };
  };

  users.groups.gitlab-runner = { };
  users.users.gitlab-runner = {
    isSystemUser = true;
    group = config.users.groups.gitlab-runner.name;
  };

  containers.gitlab-runner = {
    autoStart = true;

    privateNetwork = true;
    hostAddress = "192.168.100.1";
    localAddress = "192.168.100.2";

    bindMounts = {
      "${config.sops.secrets.runnerRegistrationConfig.path}" = {
        hostPath = config.sops.secrets.runnerRegistrationConfig.path;
      };
    };

    config =
      let
        hostConfig = config;
      in
      args@{ config, ... }: {

        nix = {
          package = pkgs.nixUnstable;
          extraOptions = ''
            experimental-features = nix-command flakes
          '';
        };

        environment.systemPackages = with pkgs; [
          git
          htop
          nload
        ];

        users.groups.gitlab-runner = { };
        users.users.gitlab-runner = {
          isSystemUser = true;
          group = config.users.groups.gitlab-runner.name;
        };

        services = {
          openssh.enable = true;
          gitlab-runner = {
            enable = true;
            services = {
              shell = {
                registrationConfigFile = hostConfig.sops.secrets.runnerRegistrationConfig.path;
                executor = "shell";
                tagList = [ "nix" ];
              };
            };
          };
        };

        systemd.services.gitlab-runner.serviceConfig = {
          DynamicUser = lib.mkForce false;
          User = config.users.users.gitlab-runner.name;
          Group = config.users.groups.gitlab-runner.name;
        };

        system.stateVersion = "22.05";
      };
  };
}
