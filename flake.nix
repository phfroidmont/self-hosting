{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-21.05";

  outputs = { self, nixpkgs }:
    let
      pkgs = nixpkgs.legacyPackages.x86_64-linux;

      common = {
        modules = [
          ./hardware/hcloud.nix
          ./modules/openssh.nix
        ];
      };
    in
    {
      devShell.x86_64-linux = pkgs.mkShell {
        buildInputs = with pkgs; [
          nixpkgs-fmt
          terraform_0_14
          sops
        ];
      };

      nixosConfigurations = {
        db1 = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = common.modules ++ [
            ./modules/postgresql.nix
            ({
              environment.systemPackages = with pkgs; [
                htop
              ];
              networking.hostName = "db1";
              networking.domain = "banditlair.com";
              networking.firewall.interfaces."enp7s0".allowedTCPPorts = [ 5432 ];
            })
          ];
        };
        backend1 = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = common.modules ++ [
            ./modules/murmur.nix
            ./modules/synapse.nix
            ({
              networking.hostName = "backend1";
              networking.domain = "banditlair.com";
              networking.firewall.allowedTCPPorts = [ 80 443 64738 ];
              networking.firewall.allowedUDPPorts = [ 64738 ];
            })
          ];
        };
      };

    };
}
