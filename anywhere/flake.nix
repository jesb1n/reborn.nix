{
  description = "OCI NixOS management";

  nixConfig = {
    # Flake-level settings must be literal values; Nix rejects imported thunks
    # before evaluating outputs. Keep these synchronized with lib/binary-caches.nix.
    extra-substituters = [
      "https://nixos-raspberrypi.cachix.org"
      "https://nix-community.cachix.org"
    ];
    extra-trusted-public-keys = [
      "nixos-raspberrypi.cachix.org-1:4iMO9LXa8BqhU+Rpg6LQKiGa2lsNh/j2oiYLNOQ5sPI="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    ];
  };

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    # Keep macOS-only builds independent from the Linux rolling channel so a
    # Linux upgrade cannot also change nix-darwin's package set.
    nixpkgs-latest.url = "github:NixOS/nixpkgs/nixos-unstable";
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
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs-latest";

    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs-unstable";

    mac-app-util.url = "github:hraban/mac-app-util";
    mac-app-util.inputs.nixpkgs.follows = "nixpkgs-unstable";
  };

  outputs = inputs@{ self, nixpkgs, nixpkgs-unstable, nixos-anywhere, nixos-raspberrypi, deploy-rs, disko, sops-nix, hermes-agent, nix-darwin, home-manager, mac-app-util, ... }:
    let
      fleet = import ./lib/fleet.nix;

      linuxSystems = [
        "aarch64-linux"
        "x86_64-linux"
      ];

      managementSystems = [
        "aarch64-darwin"
        "x86_64-linux"
      ];

      forAllManagementSystems = nixpkgs.lib.genAttrs managementSystems;
      forAllLinuxSystems = nixpkgs.lib.genAttrs linuxSystems;

      hostsForSystem = system:
        nixpkgs.lib.filterAttrs (_: host: host.system == system) fleet;

      activationFor = host:
        deploy-rs.lib.${fleet.${host}.system}.activate.nixos self.nixosConfigurations.${host};

      mkDeployNode = ci: host: metadata: {
        hostname = host;
        sshUser = "duck";
        remoteBuild = if ci then false else metadata.remoteBuild;
        fastConnection = metadata.fastConnection;
        activationTimeout = metadata.activationTimeout;
        confirmTimeout = metadata.confirmTimeout;

        profiles.system = {
          user = "root";
          path = activationFor host;
        };
      };

      deployNodes = nixpkgs.lib.mapAttrs (mkDeployNode false) fleet;
      ciDeployNodes = nixpkgs.lib.mapAttrs (mkDeployNode true) fleet;

      releasePackages = system:
        (nixpkgs.lib.concatMapAttrs
          (host: _: {
            "${host}-toplevel" = self.nixosConfigurations.${host}.config.system.build.toplevel;
            "${host}-activation" = activationFor host;
          })
          (hostsForSystem system))
        // {
          # The deployment runner realizes this small, pinned executable before
          # production credentials are loaded. It must not enter the broad
          # operator devShell during an activation.
          deploy-rs = deploy-rs.packages.${system}.default;
        };
    in {
      inherit fleet;

      devShells = forAllManagementSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in {
          default = pkgs.mkShell {
            packages = [
              pkgs.age
              deploy-rs.packages.${system}.default
              disko.packages.${system}.default
              pkgs.fluxcd
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

      nixosConfigurations.nuc7i3 = nixpkgs-unstable.lib.nixosSystem {
        system = "x86_64-linux";

        modules = [
          disko.nixosModules.disko
          sops-nix.nixosModules.sops
          ./hosts/nuc7i3/configuration.nix
        ];
      };

      nixosConfigurations.travelmate = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";

        modules = [
          disko.nixosModules.disko
          ./hosts/travelmate/disko-config.nix
          ./hosts/travelmate/hardware-configuration.nix
          ./hosts/travelmate/configuration.nix
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

      packages = forAllLinuxSystems (system:
        (releasePackages system) // {
          # CI invokes the pinned deploy-rs binary directly so it does not
          # materialize the operator devShell's unrelated tool closure.
          deploy-rs = deploy-rs.packages.${system}.default;
        });

      deploy.nodes = deployNodes;

      # CI imports native release closures before using this topology. Every
      # node is therefore a local no-op realization followed by an SSH copy.
      ciDeploy.nodes = ciDeployNodes;

      checks = builtins.mapAttrs
        (system: deployLib:
          let
            normalDeployChecks = deployLib.deployChecks self.deploy;
            ciDeployChecks = deployLib.deployChecks self.ciDeploy;
          in
          normalDeployChecks
          // nixpkgs.lib.mapAttrs'
            (name: value: nixpkgs.lib.nameValuePair "ci-${name}" value)
            ciDeployChecks
          // nixpkgs.lib.optionalAttrs (system == "x86_64-linux") {
            fleet-invariants = import ./tests/fleet-invariants.nix {
              pkgs = nixpkgs.legacyPackages.${system};
              inherit (nixpkgs) lib;
              inherit fleet;
              inherit (self) nixosConfigurations deploy ciDeploy;
            };

            ssh-access = import ./tests/ssh-access.nix {
              pkgs = nixpkgs-unstable.legacyPackages.${system};
            };
          })
        deploy-rs.lib;
    };
}
