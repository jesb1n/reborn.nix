# profiles/binary-cache.nix — self-hosted Nix binary cache over Tailscale.
#
# Why: inputs rebased with `follows` (deploy-rs, sops-nix) never match their
# upstream Cachix hashes, and sops-install-secrets has no public cache at all.
# Every aarch64 node therefore compiles the same Go/Rust toolchain output from
# scratch — brutal on the Pi (SD card) and the 1 GB micros.
#
# With this, the first ARM host to build a path serves it to every other ARM
# host. Compile once, substitute everywhere.
#
# Transport: Tailscale only. nix-serve binds 127.0.0.1 and is reached over the
# tailnet; the port is opened solely on the `tailscale0` interface, never on
# the public OCI interface. Tailscale already provides the authenticated,
# encrypted channel, so the cache itself stays unauthenticated-but-private.
#
# Trust model: a binary cache is a code-execution channel. Clients only accept
# paths signed by a key they trust, so the PRIVATE signing key lives on the
# cache host (sops-managed, mode 0400) and only the PUBLIC key is committed to
# lib/binary-caches.nix.
#
# Generate the keypair ONCE, then encrypt the private half per host:
#   nix key generate-secret --key-name reborn-arm-1 > /tmp/cache-priv.pem
#   nix key convert-secret-to-public < /tmp/cache-priv.pem    # -> lib/binary-caches.nix
#   sops anywhere/secrets/<host>/secrets.yaml                 # add nix-cache-signing-key
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.fleet.binaryCache;
in
{
  options.fleet.binaryCache = {
    enable = lib.mkEnableOption "self-hosted Nix binary cache served over Tailscale";

    port = lib.mkOption {
      type = lib.types.port;
      default = 5000;
      description = "Port nix-serve listens on (tailnet-only).";
    };

    secretName = lib.mkOption {
      type = lib.types.str;
      default = "nix-cache-signing-key";
      description = ''
        Key in the host's sops secrets file holding the PRIVATE cache signing
        key. Must already be declared in hosts/<name>/sops.nix.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    services.nix-serve = {
      enable = true;
      # nix-serve-ng: Haskell rewrite of nix-serve. Same protocol, far lower
      # memory and much faster narinfo lookups — matters on a shared ARM node
      # that is also running k3s workloads.
      package = pkgs.nix-serve-ng;

      inherit (cfg) port;

      # Bind loopback: Tailscale reaches it via the tailnet address, and
      # nothing is exposed on the OCI public interface even if the firewall
      # were misconfigured.
      bindAddress = "127.0.0.1";

      secretKeyFile = config.sops.secrets.${cfg.secretName}.path;
    };

    # Serve to the tailnet only. profiles/server.nix already marks tailscale0
    # a trusted interface; this is the explicit, narrow grant.
    networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ cfg.port ];

    # nix-serve streams NARs straight out of the local store, so the cache is
    # only as useful as what this host has built. Keep GC from evicting paths
    # other nodes are about to ask for: base.nix deletes >7d, which is fine for
    # a leaf node but too aggressive for a cache.
    nix.gc.options = lib.mkForce "--delete-older-than 30d";

    # Keep build inputs so a rebuild of a slightly-changed derivation reuses
    # local dependencies instead of re-fetching or recompiling them.
    nix.settings.keep-outputs = true;
    nix.settings.keep-derivations = true;

    # nix-serve reads the signing key at startup; without this ordering it can
    # race sops-nix on boot and come up unable to sign.
    systemd.services.nix-serve = {
      after = [ "sops-install-secrets.service" ];
      wants = [ "sops-install-secrets.service" ];
      serviceConfig.Restart = "on-failure";
      serviceConfig.RestartSec = "10s";
    };
  };
}
