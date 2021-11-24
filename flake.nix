{
  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  inputs.deploy-rs.url = "github:serokell/deploy-rs";

  outputs = { self, nixpkgs, deploy-rs }:
    let
      pkgs = nixpkgs.legacyPackages.x86_64-linux;

      common = {
        modules = [
          ./hardware/hcloud.nix
          ./modules/openssh.nix
          ./environment.nix
        ];
      };
    in
    {
      devShell.x86_64-linux = pkgs.mkShell {
        buildInputs = with pkgs; [
          nixpkgs-fmt
          terraform
          terraform-ls
          sops
          deploy-rs.packages."x86_64-linux".deploy-rs
        ];
      };

      nixosConfigurations = {
        db1 = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = common.modules ++ [
            ./modules/postgresql.nix
            ./modules/custom-backup-job.nix
            ./modules/custom-backup-job.nix
            (
              {
                networking.hostName = "db1";
                networking.domain = "banditlair.com";
                networking.firewall.interfaces."enp7s0".allowedTCPPorts = [ 5432 ];
                services.custom-backup-job = {
                  additionalReadWritePaths = [ "/nix/var/data/postgresql" ];
                  additionalPreHook = ''
                    ${pkgs.postgresql_12}/bin/pg_dump -U synapse synapse > /nix/var/data/postgresql/synapse.dmp
                    ${pkgs.postgresql_12}/bin/pg_dump -U nextcloud nextcloud > /nix/var/data/postgresql/nextcloud.dmp
                  '';
                  startAt = "03:00";
                };
                system.stateVersion = "21.05";
              }
            )
          ];
        };
        backend1 = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = common.modules ++ [
            ./modules/nginx.nix
            ./modules/murmur.nix
            ./modules/synapse.nix
            ./modules/nextcloud.nix
            ./modules/custom-backup-job.nix
            (
              {
                networking.hostName = "backend1";
                networking.domain = "banditlair.com";
                networking.localCommands = "ip addr add 95.216.177.3/32 dev enp1s0";
                networking.firewall.allowedTCPPorts = [ 80 443 64738 ];
                networking.firewall.allowedUDPPorts = [ 64738 ];
                services.custom-backup-job = {
                  additionalPaths = [ "/var/lib/nextcloud/config" ];
                  additionalReadWritePaths = [ "/nix/var/data/murmur" ];
                  additionalPreHook = "cp /var/lib/murmur/murmur.sqlite /nix/var/data/murmur/murmur.sqlite";
                  startAt = "03:30";
                };
                system.stateVersion = "21.05";
              }
            )
          ];
        };
      };

      deploy.nodes = {
        db1 = {
          hostname = "db1.banditlair.com";
          profiles.system = {
            user = "root";
            sshUser = "root";
            path = deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations.db1;
          };
        };
        backend1 = {
          hostname = "backend1.banditlair.com";
          profiles.system = {
            user = "root";
            sshUser = "root";
            path = deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations.backend1;
          };
        };
      };

      checks = builtins.mapAttrs (system: deployLib: deployLib.deployChecks self.deploy) deploy-rs.lib;
    };
}
