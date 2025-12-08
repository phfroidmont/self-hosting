{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";
    disko.url = "github:nix-community/disko";
    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";
    deploy-rs.url = "github:serokell/deploy-rs";
    simple-nixos-mailserver.url = "gitlab:simple-nixos-mailserver/nixos-mailserver/nixos-25.11";
    foundryvtt.url = "github:reckenrode/nix-foundryvtt";
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      nixpkgs-unstable,
      disko,
      deploy-rs,
      sops-nix,
      simple-nixos-mailserver,
      foundryvtt,
    }:
    let
      pkgs = nixpkgs.legacyPackages.x86_64-linux;
      pkgs-unstable = nixpkgs-unstable.legacyPackages.x86_64-linux;

      defaultModuleArgs =
        { pkgs, ... }:
        {
          _module.args.pkgs-unstable = import nixpkgs-unstable {
            system = "x86_64-linux";
            config.allowUnfreePredicate = pkg: builtins.elem (pkgs.lib.getName pkg) [ "minecraft-server" ];
          };
        };
    in
    {
      devShells.x86_64-linux.default = pkgs.mkShell {
        sopsPGPKeyDirs = [
          "./keys/hosts"
          "./keys/users"
        ];

        nativeBuildInputs = [ (pkgs.callPackage sops-nix { }).sops-import-keys-hook ];

        buildInputs = with pkgs-unstable; [
          nixpkgs-fmt
          opentofu
          terraform-ls
          sops
          deploy-rs.packages."x86_64-linux".deploy-rs
        ];
      };

      nixosConfigurations = {
        hel1 = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = {
            inherit nixpkgs inputs;
          };

          modules = [
            disko.nixosModules.disko
            defaultModuleArgs
            sops-nix.nixosModules.sops
            simple-nixos-mailserver.nixosModule
            foundryvtt.nixosModules.foundryvtt
            ./profiles/hel.nix
            {
              sops.defaultSopsFile = ./secrets.enc.yml;
              networking.hostName = "hel1";
              networking.domain = "banditlair.com";
              nix.registry.nixpkgs.flake = nixpkgs;

              system.stateVersion = "24.05";
            }
          ];
        };
      };

      deploy.nodes =
        let
          createSystemProfile = configuration: {
            user = "root";
            sshUser = "root";
            path = deploy-rs.lib.x86_64-linux.activate.nixos configuration;
          };
        in
        {
          hel1 = {
            hostname = "37.27.138.62";
            profiles.system = createSystemProfile self.nixosConfigurations.hel1;
          };
        };

      checks = builtins.mapAttrs (system: deployLib: deployLib.deployChecks self.deploy) deploy-rs.lib;
    };
}
