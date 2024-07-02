{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-24.05";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";
    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";
    deploy-rs.url = "github:serokell/deploy-rs";
    simple-nixos-mailserver.url =
      "gitlab:simple-nixos-mailserver/nixos-mailserver/nixos-24.05";
    foundryvtt.url = "github:reckenrode/nix-foundryvtt";
  };

  outputs = inputs@{ self, nixpkgs, nixpkgs-unstable, deploy-rs, sops-nix
    , simple-nixos-mailserver, foundryvtt }:
    let
      pkgs = nixpkgs.legacyPackages.x86_64-linux;
      pkgs-unstable = nixpkgs-unstable.legacyPackages.x86_64-linux;
      defaultModuleArgs = { pkgs, ... }: {
        _module.args.pkgs-unstable = import nixpkgs-unstable {
          inherit (pkgs.stdenv.targetPlatform) system;
          config.allowUnfreePredicate = pkg:
            builtins.elem (pkgs.lib.getName pkg) [ "minecraft-server" ];
        };
      };
    in {
      devShells.x86_64-linux.default = pkgs.mkShell {
        sopsPGPKeyDirs = [ "./keys/hosts" "./keys/users" ];

        nativeBuildInputs =
          [ (pkgs.callPackage sops-nix { }).sops-import-keys-hook ];

        buildInputs = with pkgs-unstable; [
          nixpkgs-fmt
          opentofu
          terraform-ls
          sops
          deploy-rs.packages."x86_64-linux".deploy-rs
        ];
      };

      nixosConfigurations = {
        db1 = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = { inherit nixpkgs; };
          modules = [
            sops-nix.nixosModules.sops
            ./profiles/db.nix
            ({
              sops.defaultSopsFile = ./secrets.enc.yml;
              networking.hostName = "db1";
              networking.domain = "banditlair.com";
              nix.registry.nixpkgs.flake = nixpkgs;

              system.stateVersion = "21.05";
            })
          ];
        };
        backend1 = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = { inherit nixpkgs; };
          modules = [
            sops-nix.nixosModules.sops
            ./profiles/backend.nix
            ({
              sops.defaultSopsFile = ./secrets.enc.yml;
              networking.hostName = "backend1";
              networking.domain = "banditlair.com";
              nix.registry.nixpkgs.flake = nixpkgs;

              system.stateVersion = "21.05";
            })
          ];
        };
        storage1 = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = { inherit nixpkgs inputs; };
          modules = [
            defaultModuleArgs
            sops-nix.nixosModules.sops
            simple-nixos-mailserver.nixosModule
            foundryvtt.nixosModules.foundryvtt
            ./profiles/storage.nix
            ({
              sops.defaultSopsFile = ./secrets.enc.yml;
              networking.hostName = "storage1";
              networking.domain = "banditlair.com";
              nix.registry.nixpkgs.flake = nixpkgs;

              system.stateVersion = "21.05";
            })
          ];
        };
      };

      deploy.nodes = let
        createSystemProfile = configuration: {
          user = "root";
          sshUser = "root";
          path = deploy-rs.lib.x86_64-linux.activate.nixos configuration;
        };
      in {
        db1 = {
          hostname = "db1.banditlair.com";
          profiles.system = createSystemProfile self.nixosConfigurations.db1;
        };
        backend1 = {
          hostname = "backend1.banditlair.com";
          profiles.system =
            createSystemProfile self.nixosConfigurations.backend1;
        };
        storage1 = {
          hostname = "78.46.96.243";
          profiles.system =
            createSystemProfile self.nixosConfigurations.storage1;
        };
      };

      checks = builtins.mapAttrs
        (system: deployLib: deployLib.deployChecks self.deploy) deploy-rs.lib;
    };
}
