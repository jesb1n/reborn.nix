{
  description = "OCI NixOS management";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixos-anywhere.url = "github:nix-community/nixos-anywhere";

    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";

    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { nixpkgs, nixos-anywhere, disko, sops-nix, ... }:
    let
      localSystem = "aarch64-darwin";
      pkgs = nixpkgs.legacyPackages.${localSystem};
    in {
      devShells.${localSystem}.default = pkgs.mkShell {
        packages = [
          pkgs.age
          disko.packages.${localSystem}.default
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

      nixosConfigurations.oracle-eu-micro1 = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";

        modules = [
          disko.nixosModules.disko
          sops-nix.nixosModules.sops
          ./hosts/oracle-eu-micro1/configuration.nix
        ];
      };

      nixosConfigurations.oracle-eu-micro2 = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";

        modules = [
          disko.nixosModules.disko
          sops-nix.nixosModules.sops
          ./hosts/oracle-eu-micro2/configuration.nix
        ];
      };
    };
}
