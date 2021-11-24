{
  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  inputs.deploy-rs.url = "github:serokell/deploy-rs";

  outputs = { self, nixpkgs, deploy-rs }:
    let
      pkgs = nixpkgs.legacyPackages.x86_64-linux;
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
          modules = [
            ./profiles/db.nix
            (
              {
                networking.hostName = "db1";
                networking.domain = "banditlair.com";

                system.stateVersion = "21.05";
              }
            )
          ];
        };
        backend1 = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            ./profiles/backend.nix
            (
              {
                networking.hostName = "backend1";
                networking.domain = "banditlair.com";

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
