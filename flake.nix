{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-21.05";

  outputs = { self, nixpkgs }:
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
          terraform_0_14
          sops
        ];
      };

      nixosConfigurations = {
        db1 = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = common.modules ++ [
            ./modules/postgresql.nix
            ./modules/custom-backup-job.nix
            ({
              networking.hostName = "db1";
              networking.domain = "banditlair.com";
              networking.firewall.interfaces."enp7s0".allowedTCPPorts = [ 5432 ];
              services.custom-backup-job = {
                additionalReadWritePaths = [ "/nix/var/data/postgresql" ];
                additionalPreHook = "${pkgs.postgresql_12}/bin/pg_dump -U synapse synapse > /nix/var/data/postgresql/synapse.dmp";
                startAt = "03:00";
              };
            })
          ];
        };
        backend1 = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = common.modules ++ [
            ./modules/murmur.nix
            ./modules/synapse.nix
            ./modules/custom-backup-job.nix
            ({
              networking.hostName = "backend1";
              networking.domain = "banditlair.com";
              networking.firewall.allowedTCPPorts = [ 80 443 64738 ];
              networking.firewall.allowedUDPPorts = [ 64738 ];
              services.custom-backup-job = {
                additionalReadWritePaths = [ "/nix/var/data/murmur" ];
                additionalPreHook = "cp /var/lib/murmur/murmur.sqlite /nix/var/data/murmur/murmur.sqlite";
                startAt = "03:30";
              };
            })
          ];
        };
      };

    };
}
