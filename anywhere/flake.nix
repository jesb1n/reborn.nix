{
  description = "OCI NixOS management";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixos-anywhere.url = "github:nix-community/nixos-anywhere";
  };

  outputs = { nixpkgs, nixos-anywhere, ... }:
    let
      localSystem = "aarch64-darwin";
      pkgs = nixpkgs.legacyPackages.${localSystem};
    in {
      devShells.${localSystem}.default = pkgs.mkShell {
        packages = [
          nixos-anywhere.packages.${localSystem}.default
        ];
      };

      nixosConfigurations.oci-nixos = nixpkgs.lib.nixosSystem {
        system = "aarch64-linux";

        modules = [
          ./hosts/oci-nixos/configuration.nix
        ];
      };
    };
}