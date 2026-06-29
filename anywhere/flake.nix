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
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixos-anywhere.url = "github:nix-community/nixos-anywhere";
    nixos-raspberrypi.url = "github:nvmd/nixos-raspberrypi/main";

    deploy-rs.url = "github:serokell/deploy-rs";
    deploy-rs.inputs.nixpkgs.follows = "nixpkgs";

    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";

    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, nixpkgs-unstable, nixos-anywhere, nixos-raspberrypi, deploy-rs, disko, sops-nix, ... }:
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

      nixosConfigurations.oracle-eu-arm1 = nixpkgs-unstable.lib.nixosSystem {
        system = "aarch64-linux";

        modules = [
          sops-nix.nixosModules.sops
          ./hosts/oracle-eu-arm1/configuration.nix
        ];
      };

      nixosConfigurations.oracle-eu-micro1 = nixpkgs-unstable.lib.nixosSystem {
        system = "x86_64-linux";

        modules = [
          disko.nixosModules.disko
          sops-nix.nixosModules.sops
          ./hosts/oracle-eu-micro1/configuration.nix
        ];
      };

      nixosConfigurations.oracle-eu-micro2 = nixpkgs-unstable.lib.nixosSystem {
        system = "x86_64-linux";

        modules = [
          disko.nixosModules.disko
          sops-nix.nixosModules.sops
          ./hosts/oracle-eu-micro2/configuration.nix
        ];
      };

      nixosConfigurations.s145 = nixpkgs-unstable.lib.nixosSystem {
        system = "x86_64-linux";

        modules = [
          disko.nixosModules.disko
          sops-nix.nixosModules.sops
          ./hosts/s145/configuration.nix
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
        oracle-eu-arm1 = {
          hostname = "oracle-eu-arm1";
          sshUser = "duck";
          remoteBuild = true;
          activationTimeout = 600;
          confirmTimeout = 60;

          profiles.system = {
            user = "root";
            path = deploy-rs.lib.aarch64-linux.activate.nixos self.nixosConfigurations.oracle-eu-arm1;
          };
        };

        oracle-eu-micro1 = {
          hostname = "oracle-eu-micro1";
          sshUser = "duck";
          remoteBuild = true;
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
          sshUser = "duck";
          remoteBuild = true;
          fastConnection = true;
          activationTimeout = 600;
          confirmTimeout = 60;

          profiles.system = {
            user = "root";
            path = deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations.oracle-eu-micro2;
          };
        };

        rpi = {
          hostname = "192.168.1.68";
          sshUser = "duck";
          remoteBuild = true;
          activationTimeout = 900;
          confirmTimeout = 60;

          profiles.system = {
            user = "root";
            path = deploy-rs.lib.aarch64-linux.activate.nixos self.nixosConfigurations.rpi;
          };
        };

        s145 = {
          hostname = "192.168.1.66";
          sshUser = "duck";
          remoteBuild = true;
          activationTimeout = 600;
          confirmTimeout = 60;

          profiles.system = {
            user = "root";
            path = deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations.s145;
          };
        };
      };
    };
}
