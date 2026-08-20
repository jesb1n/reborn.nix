{
  pkgs,
  lib,
  fleet,
  nixosConfigurations,
  deploy,
  ciDeploy,
}:

let
  binaryCaches = import ../lib/binary-caches.nix;
  fleetHosts = builtins.attrNames fleet;
  configurationHosts = builtins.attrNames nixosConfigurations;
  deployHosts = builtins.attrNames deploy.nodes;
  ciDeployHosts = builtins.attrNames ciDeploy.nodes;

  check = host: description: assertion: {
    inherit assertion;
    message = "${host}: ${description}";
  };

  hostChecks = lib.concatMap (host:
    let
      metadata = fleet.${host};
      config = nixosConfigurations.${host}.config;
      deployNode = deploy.nodes.${host};
      ciDeployNode = ciDeploy.nodes.${host};
      operatorKeys = config.users.users.duck.openssh.authorizedKeys.keys;
    in
    [
      (check host "networking.hostName must match fleet identity"
        (config.networking.hostName == host))
      (check host "native platform must match fleet metadata"
        (config.nixpkgs.hostPlatform.system == metadata.system))

      (check host "OpenSSH must be enabled" config.services.openssh.enable)
      (check host "SSH password authentication must be disabled"
        (config.services.openssh.settings.PasswordAuthentication == false))
      (check host "SSH keyboard-interactive authentication must be disabled"
        (config.services.openssh.settings.KbdInteractiveAuthentication == false))
      (check host "SSH root login must be disabled"
        (config.services.openssh.settings.PermitRootLogin == "no"))

      (check host "users must be immutable" (config.users.mutableUsers == false))
      (check host "duck must be a normal user" config.users.users.duck.isNormalUser)
      (check host "duck must remain in wheel"
        (lib.elem "wheel" config.users.users.duck.extraGroups))
      # A dedicated CI key is a bootstrap prerequisite, not repository policy yet.
      # Until it is provisioned, keep proving that normal operator access exists.
      (check host "duck must retain at least one ordinary SSH operator key"
        (lib.any (key: builtins.match "^ssh-[^ ]+ [A-Za-z0-9+/=]+( .*)?$" key != null) operatorKeys))
      (check host "duck must remain password-locked"
        (config.users.users.duck.hashedPassword == "!"))
      (check host "root must remain password-locked"
        (config.users.users.root.hashedPassword == "!"))
      (check host "wheel must retain passwordless sudo"
        (config.security.sudo.wheelNeedsPassword == false))

      (check host "Tailscale must be enabled" config.services.tailscale.enable)
      (check host "Tailscale firewall integration must be enabled"
        config.services.tailscale.openFirewall)
      (check host "tailscale0 must remain a trusted firewall interface"
        (lib.elem "tailscale0" config.networking.firewall.trustedInterfaces))
      (check host "duck must remain a trusted Nix user"
        (lib.elem "duck" config.nix.settings.trusted-users))

      (check host "fleet cache substituters must include reviewed policy"
        (let
          expected = binaryCaches.nixSettings.substituters
            ++ lib.optionals (host == "rpi") binaryCaches.rpiNixSettings.substituters;
        in lib.all (value: lib.elem value config.nix.settings.substituters) expected))
      (check host "fleet cache keys must include reviewed policy"
        (let
          expected = binaryCaches.nixSettings.trusted-public-keys
            ++ lib.optionals (host == "rpi") binaryCaches.rpiNixSettings.trusted-public-keys;
        in lib.all (value: lib.elem value config.nix.settings.trusted-public-keys) expected))

      (check host "deploy hostname must match fleet identity"
        (deployNode.hostname == host))
      (check host "deploy SSH user must be duck"
        (deployNode.sshUser == "duck"))
      (check host "deploy activation user must be root"
        (deployNode.profiles.system.user == "root"))
      (check host "deploy activation timeout must match fleet metadata"
        (deployNode.activationTimeout == metadata.activationTimeout))
      (check host "deploy confirmation timeout must match fleet metadata"
        (deployNode.confirmTimeout == metadata.confirmTimeout))
      (check host "interactive remoteBuild must match fleet metadata"
        (deployNode.remoteBuild == metadata.remoteBuild))
      (check host "interactive fastConnection must match fleet metadata"
        (deployNode.fastConnection == metadata.fastConnection))

      (check host "CI deploy hostname must match fleet identity"
        (ciDeployNode.hostname == host))
      (check host "CI deploy SSH user must be duck"
        (ciDeployNode.sshUser == "duck"))
      (check host "CI deploy activation user must be root"
        (ciDeployNode.profiles.system.user == "root"))
      (check host "CI deploy activation timeout must match fleet metadata"
        (ciDeployNode.activationTimeout == metadata.activationTimeout))
      (check host "CI deploy confirmation timeout must match fleet metadata"
        (ciDeployNode.confirmTimeout == metadata.confirmTimeout))
      (check host "CI deploy must never build on a fleet host"
        (ciDeployNode.remoteBuild == false))
      (check host "CI fastConnection must match fleet metadata"
        (ciDeployNode.fastConnection == metadata.fastConnection))
      (check host "interactive and CI deploys must use the same activation package"
        (toString deployNode.profiles.system.path == toString ciDeployNode.profiles.system.path))
    ]) fleetHosts;

  inventoryChecks = [
    {
      assertion = fleetHosts == configurationHosts;
      message = "nixosConfigurations must contain exactly the nine fleet hosts";
    }
    {
      assertion = fleetHosts == deployHosts;
      message = "deploy.nodes must contain exactly the nine fleet hosts";
    }
    {
      assertion = fleetHosts == ciDeployHosts;
      message = "ciDeploy.nodes must contain exactly the nine fleet hosts";
    }
    {
      assertion = builtins.length fleetHosts == 9;
      message = "fleet inventory must contain exactly nine hosts";
    }
  ];

  failures = map (item: item.message)
    (lib.filter (item: !item.assertion) (inventoryChecks ++ hostChecks));
in
assert lib.assertMsg (failures == [ ]) ''
  Fleet invariants failed:
  ${lib.concatMapStringsSep "\n" (message: "- ${message}") failures}
'';
pkgs.runCommand "fleet-invariants" { } ''
  touch "$out"
''
