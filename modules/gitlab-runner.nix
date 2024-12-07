{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.custom.services.gitlab-runner;
in
{
  options.custom.services.gitlab-runner = {
    enable = mkEnableOption "gitlab-runner";
    runnerRegistrationConfigFile = lib.mkOption { type = lib.types.path; };
  };

  config = mkIf cfg.enable {

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
        "${cfg.runnerRegistrationConfigFile}" = {
          hostPath = cfg.runnerRegistrationConfigFile;
        };
      };

      config =
        { config, ... }:
        {

          nix = {
            package = pkgs.nixVersions.latest;
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

          programs.ssh.extraConfig = ''
            StrictHostKeyChecking=no
            UserKnownHostsFile=/dev/null
          '';

          networking.useHostResolvConf = lib.mkForce false;

          services = {
            openssh.enable = true;
            resolved.enable = true;
            gitlab-runner = {
              enable = true;
              services = {
                shell = {
                  authenticationTokenConfigFile = cfg.runnerRegistrationConfigFile;
                  executor = "shell";
                };
              };
            };
          };

          systemd.services.gitlab-runner.serviceConfig = {
            DynamicUser = lib.mkForce false;
            User = config.users.users.gitlab-runner.name;
            Group = config.users.groups.gitlab-runner.name;
          };

          system.stateVersion = "24.05";
        };
    };
  };
}
