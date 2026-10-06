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

    bindAddress = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      example = "100.84.230.4";
      description = ''
        Address nix-serve binds. Set this to the host's own Tailscale IP so
        peers can reach it; loopback is unreachable from the tailnet no
        matter how the firewall is configured. Do not set 0.0.0.0 — these
        nodes have public OCI interfaces.
      '';
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
      # Upstream Perl nix-serve, deliberately NOT the nix-serve-ng rewrite.
      #
      # nix-serve-ng is unbuildable on aarch64 here, in two layers:
      #   1. It defaults to Lix, whose pkg-config file requires libcpuid —
      #      an x86/i686-only package, so configure fails outright with
      #      "Package 'libcpuid', required by 'lix', not found".
      #   2. Overriding to CppNix and disabling the `lix` cabal flag gets
      #      past that, but its C++ shim targets an older libnixstore API
      #      (initLibStore, openStore, settings, Signature->std::string) and
      #      does not compile against nix 2.35.
      # Pinning an older CppNix to satisfy (2) would mean building Nix itself
      # from source on a shared k3s node every rebuild.
      #
      # The Perl implementation shells out to nix-store rather than linking
      # against libnixstore, so it has no such version coupling, and it is
      # prebuilt for aarch64 on cache.nixos.org — it substitutes rather than
      # compiles. Same protocol, same narinfo/NAR endpoints.
      package = pkgs.nix-serve;

      inherit (cfg) port;

      # Bind the node's own Tailscale address, not 127.0.0.1: loopback is
      # unreachable from peers no matter what the firewall says. tailscale0
      # carries only tailnet traffic, so this is not exposed on the OCI
      # public interface — and it is never bound to 0.0.0.0.
      bindAddress = cfg.bindAddress;

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
    #
    # It also binds a tailscale0 address, which does not exist until tailscaled
    # has brought the interface up — without this the service fails at boot
    # with "Cannot assign requested address".
    #
    # Restart policy is intentionally left entirely to the upstream nix-serve
    # module (Restart="always", RestartSec="5s") — already correct for a cache
    # that other nodes block on, so overriding it only creates conflicts.
    systemd.services.nix-serve = {
      after = [
        "sops-install-secrets.service"
        "tailscaled.service"
      ];
      wants = [
        "sops-install-secrets.service"
        "tailscaled.service"
      ];
    };
  };
}
