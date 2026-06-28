{
  description = "OCI NixOS management";

  nixConfig = {
    extra-substituters = [
      "https://nixos-raspberrypi.cachix.org"
    ];
    extra-trusted-public-keys = [
      "nixos-raspberrypi.cachix.org-1:4iMO9LXa8BqhU+Rpg6LQKiGa2lsNh/j2oiYLNOQ5sPI="
    ];
  };

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixos-anywhere.url = "github:nix-community/nixos-anywhere";
    nixos-raspberrypi.url = "github:nvmd/nixos-raspberrypi/main";

    deploy-rs.url = "github:serokell/deploy-rs";
    deploy-rs.inputs.nixpkgs.follows = "nixpkgs";

    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";

    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, nixos-anywhere, nixos-raspberrypi, deploy-rs, disko, sops-nix, ... }:
    let
      managementSystems = [
        "aarch64-darwin"
        "x86_64-linux"
      ];

      forAllManagementSystems = nixpkgs.lib.genAttrs managementSystems;
    in {
      devShells = forAllManagementSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in {
          default = pkgs.mkShell {
            packages = [
              pkgs.age
              deploy-rs.packages.${system}.default
              disko.packages.${system}.default
              nixos-anywhere.packages.${system}.default
              pkgs.sops
              pkgs.ssh-to-age
            ];
          };
        });

      packages.x86_64-linux = {
        kexec-wifi-tailscale-image =
          nixpkgs.legacyPackages.x86_64-linux.callPackage ./packages/kexec-wifi-tailscale-image.nix { };
      };

      packages.aarch64-linux = {
        kexec-wifi-tailscale-image =
          nixpkgs.legacyPackages.aarch64-linux.callPackage ./packages/kexec-wifi-tailscale-image.nix { };
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

      nixosConfigurations.rpi = nixos-raspberrypi.lib.nixosSystem {
        modules = [
          nixos-raspberrypi.nixosModules.raspberry-pi-4.base
          disko.nixosModules.disko
          sops-nix.nixosModules.sops
          ./hosts/rpi/configuration.nix
        ];
      };

      deploy.nodes = {
        oci-nixos = {
          hostname = "oci-nixos";
          sshUser = "ubuntu";
          remoteBuild = true;
          activationTimeout = 600;
          confirmTimeout = 60;

          profiles.system = {
            user = "root";
            path = deploy-rs.lib.aarch64-linux.activate.nixos self.nixosConfigurations.oci-nixos;
          };
        };

        oracle-eu-micro1 = {
          hostname = "oracle-eu-micro1";
          sshUser = "ubuntu";
          remoteBuild = false;
          fastConnection = true;
          activationTimeout = 600;
          confirmTimeout = 60;

          profiles.system = {
            user = "root";
            path = deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations.oracle-eu-micro1;
          };
        };

        oracle-eu-micro2 = {
          hostname = "oracle-eu-micro2";
          sshUser = "ubuntu";
          remoteBuild = false;
          fastConnection = true;
          activationTimeout = 600;
          confirmTimeout = 60;

          profiles.system = {
            user = "root";
            path = deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations.oracle-eu-micro2;
          };
        };

        rpi = {
          hostname = "100.79.146.32";
          sshUser = "ubuntu";
          remoteBuild = true;
          activationTimeout = 900;
          confirmTimeout = 60;

          profiles.system = {
            user = "root";
            path = deploy-rs.lib.aarch64-linux.activate.nixos self.nixosConfigurations.rpi;
          };
        };
      };
    };
}
