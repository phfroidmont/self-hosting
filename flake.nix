{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";
    disko.url = "github:nix-community/disko";
    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";
    deploy-rs.url = "github:serokell/deploy-rs";
    simple-nixos-mailserver.url = "gitlab:simple-nixos-mailserver/nixos-mailserver/nixos-26.05";
    foundryvtt.url = "github:reckenrode/nix-foundryvtt";
  };

  outputs =
    inputs@{ self
    , nixpkgs
    , nixpkgs-unstable
    , disko
    , deploy-rs
    , sops-nix
    , simple-nixos-mailserver
    , foundryvtt
    ,
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
          jq
          yq-go
          curl
          openssh
          gnupg
          coreutils
          util-linux
          shellcheck
          shfmt
          python3
          openssl
          hcloud
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

              system.stateVersion = "25.11";
            }
          ];
        };
        relay1 = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = {
            inherit nixpkgs inputs;
          };

          modules = [
            disko.nixosModules.disko
            defaultModuleArgs
            sops-nix.nixosModules.sops
            ./profiles/relay1.nix
            {
              sops.defaultSopsFile = ./secrets.enc.yml;
              networking.hostName = "relay1";
              networking.domain = "froidmont.org";
              nix.registry.nixpkgs.flake = nixpkgs;

              system.stateVersion = "24.05";
            }
          ];
        };
        pangolin1 = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = {
            inherit nixpkgs inputs;
          };

          modules = [
            disko.nixosModules.disko
            defaultModuleArgs
            sops-nix.nixosModules.sops
            ./profiles/pangolin1.nix
            {
              networking.hostName = "pangolin1";
              networking.domain = "banditlair.com";
              nix.registry.nixpkgs.flake = nixpkgs;

              system.stateVersion = "26.05";
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
            hostname = "hel1.bl.internal";
            sshOpts = [ "-o" "HostKeyAlias=37.27.138.62" ];
            profiles.system = createSystemProfile self.nixosConfigurations.hel1;
          };
          relay1 = {
            hostname = "relay1.bl.internal";
            sshOpts = [ "-o" "HostKeyAlias=rl.banditlair.com" ];
            profiles.system = createSystemProfile self.nixosConfigurations.relay1;
          };
          pangolin1 = {
            hostname = "pangolin.banditlair.com";
            profiles.system = createSystemProfile self.nixosConfigurations.pangolin1;
          };
        };

      checks = builtins.mapAttrs
        (system: deployLib:
          deployLib.deployChecks self.deploy
          // nixpkgs.lib.optionalAttrs (system == "x86_64-linux") {
            pangolin-native = import ./packages/pangolin/test.nix { inherit pkgs; };
            telemetry-client = import ./packages/pangolin/telemetry-client-test.nix { inherit pkgs; };
            telemetry-gateway = import ./packages/pangolin/telemetry-gateway-test.nix { inherit pkgs; };
            telemetry-loki = import ./packages/pangolin/telemetry-loki-test.nix { inherit pkgs; };
            telemetry-central = import ./packages/pangolin/telemetry-central-test.nix {
              inherit pkgs;
              helConfiguration = self.nixosConfigurations.hel1;
            };
            telemetry-alerting = import ./packages/pangolin/telemetry-alerting-test.nix { inherit pkgs; };
            telemetry-dashboards = import ./packages/pangolin/telemetry-dashboards-test.nix { inherit pkgs; };
            telemetry-watchdog = import ./packages/telemetry-watchdog/test.nix { inherit pkgs; };
            telemetry-alert-secrets = pkgs.runCommand "telemetry-alert-secret-tests"
              {
                nativeBuildInputs = with pkgs; [ bash python3 sops gnupg openssl util-linux coreutils monit yq-go ];
              } ''
              export HOME="$TMPDIR/home"
              mkdir -p "$HOME"
              bash ${./tests/prepare-telemetry-alerts-test.sh} ${./.}
              touch "$out"
            '';
            telemetry-enrollment = pkgs.runCommand "telemetry-enrollment-tests"
              {
                nativeBuildInputs = with pkgs; [ bash jq yq-go sops gnupg python3 curl openssh coreutils util-linux ];
              } ''
              export HOME="$TMPDIR/home"
              mkdir -p "$HOME"
              bash ${./tests/pangolin-enroll-telemetry-test.sh} ${./.}
              touch "$out"
            '';
          })
        deploy-rs.lib;
    };
}
