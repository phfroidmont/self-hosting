{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-21.05";

  outputs = { self, nixpkgs }:
    let
      pkgs = nixpkgs.legacyPackages.x86_64-linux;

      inputs = with pkgs; [
        terraform_0_14
        sops
      ];
    in {
      devShell.x86_64-linux = pkgs.mkShell {
        buildInputs = inputs;
      };

      nixosConfigurations.db1 = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [ { imports = [ ./db1.nix ]; } ];
      };

      nixosConfigurations.backend1 = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [ { imports = [ ./backend1.nix ]; } ];
      };
    };
}
