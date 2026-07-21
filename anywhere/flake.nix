{
  description = "OCI NixOS management";

  nixConfig = {
    extra-substituters = [
      "https://nixos-raspberrypi.cachix.org"
      "https://nix-community.cachix.org"
    ];
    extra-trusted-public-keys = [
      "nixos-raspberrypi.cachix.org-1:4iMO9LXa8BqhU+Rpg6LQKiGa2lsNh/j2oiYLNOQ5sPI="
      "nix-community.cachix.org-1:b9F6KGrNS7LDfJs+c9UF4/tEaS7KE0mTChZdG4h6IVk="
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

    # Upstream Hermes Agent — provides services.hermes-agent NixOS module.
    # Pinned to nixpkgs-unstable because hermes-agent's own flake tracks unstable
    # (uv2nix + recent Python/Node, won't build cleanly against 26.05).
    hermes-agent.url = "github:NousResearch/hermes-agent";
    hermes-agent.inputs.nixpkgs.follows = "nixpkgs-unstable";

    nix-darwin.url = "github:LnL7/nix-darwin";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs-unstable";

    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs-unstable";

    mac-app-util.url = "github:hraban/mac-app-util";
    mac-app-util.inputs.nixpkgs.follows = "nixpkgs-unstable";
  };

  outputs = inputs@{ self, nixpkgs, nixpkgs-unstable, nixos-anywhere, nixos-raspberrypi, deploy-rs, disko, sops-nix, hermes-agent, nix-darwin, home-manager, mac-app-util, ... }:
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
          hermes-agent.nixosModules.default
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

      nixosConfigurations.oracle-in-arm1 = nixpkgs-unstable.lib.nixosSystem {
        system = "aarch64-linux";

        modules = [
          disko.nixosModules.disko
          sops-nix.nixosModules.sops
          ./hosts/oracle-in-arm1/configuration.nix
        ];
      };

      nixosConfigurations.oracle-in-micro1 = nixpkgs-unstable.lib.nixosSystem {
        system = "x86_64-linux";

        modules = [
          disko.nixosModules.disko
          sops-nix.nixosModules.sops
          ./hosts/oracle-in-micro1/configuration.nix
        ];
      };

      nixosConfigurations.oracle-in-micro2 = nixpkgs-unstable.lib.nixosSystem {
        system = "x86_64-linux";

        modules = [
          disko.nixosModules.disko
          sops-nix.nixosModules.sops
          ./hosts/oracle-in-micro2/configuration.nix
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

      nixosConfigurations.hp348 = nixpkgs-unstable.lib.nixosSystem {
        system = "x86_64-linux";

        modules = [
          disko.nixosModules.disko
          sops-nix.nixosModules.sops
          ./hosts/hp348/configuration.nix
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

      darwinConfigurations.pro-darwin = nix-darwin.lib.darwinSystem {
        system = "aarch64-darwin";
        modules = [
          ./hosts/pro-darwin/darwin-configuration.nix
          home-manager.darwinModules.home-manager
          mac-app-util.darwinModules.default
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.sharedModules = [ mac-app-util.homeManagerModules.default ];
            home-manager.users.jesbin = import ./hosts/pro-darwin/home.nix;
          }
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

        oracle-in-arm1 = {
          hostname = "oracle-in-arm1";
          sshUser = "duck";
          remoteBuild = true;
          activationTimeout = 600;
          confirmTimeout = 60;

          profiles.system = {
            user = "root";
            path = deploy-rs.lib.aarch64-linux.activate.nixos self.nixosConfigurations.oracle-in-arm1;
          };
        };

        oracle-in-micro1 = {
          hostname = "129.154.240.246";
          sshUser = "ubuntu";
          remoteBuild = false;
          fastConnection = true;
          activationTimeout = 600;
          confirmTimeout = 60;

          profiles.system = {
            user = "root";
            path = deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations.oracle-in-micro1;
          };
        };

        oracle-in-micro2 = {
          hostname = "oracle-in-micro2";
          sshUser = "duck";
          remoteBuild = true;
          fastConnection = true;
          activationTimeout = 600;
          confirmTimeout = 60;

          profiles.system = {
            user = "root";
            path = deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations.oracle-in-micro2;
          };
        };

        rpi = {
          hostname = "rpi";
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
          hostname = "s145";
          sshUser = "duck";
          remoteBuild = true;
          activationTimeout = 600;
          confirmTimeout = 60;

          profiles.system = {
            user = "root";
            path = deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations.s145;
          };
        };

        hp348 = {
          hostname = "hp348";
          sshUser = "duck";
          remoteBuild = true;
          fastConnection = true;
          activationTimeout = 600;
          confirmTimeout = 60;

          profiles.system = {
            user = "root";
            path = deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations.hp348;
          };
        };
      };
    };
}
