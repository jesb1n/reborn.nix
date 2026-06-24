{
  description = "OCI NixOS management";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixos-anywhere.url = "github:nix-community/nixos-anywhere";
  };

  outputs = { nixpkgs, nixos-anywhere, ... }:
    let
      system = "aarch64-darwin";
      pkgs = nixpkgs.legacyPackages.${system};
    in {
      devShells.${system}.default = pkgs.mkShell {
        packages = [
          nixos-anywhere.packages.${system}.default
        ];
      };
    };
}