{
  description = "OCI NixOS management";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixos-anywhere.url = "github:nix-community/nixos-anywhere";

    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { nixpkgs, nixos-anywhere, sops-nix, ... }:
    let
      localSystem = "aarch64-darwin";
      pkgs = nixpkgs.legacyPackages.${localSystem};
    in {
      devShells.${localSystem}.default = pkgs.mkShell {
        packages = [
          pkgs.age
          nixos-anywhere.packages.${localSystem}.default
          pkgs.sops
          pkgs.ssh-to-age
        ];
      };

      nixosConfigurations.oci-nixos = nixpkgs.lib.nixosSystem {
        system = "aarch64-linux";

        modules = [
          sops-nix.nixosModules.sops
          ./hosts/oci-nixos/configuration.nix
        ];
      };
    };
}
