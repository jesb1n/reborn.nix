# Canonical binary-cache trust policy for the NixOS fleet.
#
# Keep cache signing keys in source control.  They are public trust policy, not
# credentials.  Consumers should use the rendered `flakeNixConfig` for the
# flake-level settings and `byScope.fleet` / `byScope.rpi` for NixOS modules.
#
# The order of this list is intentional:
#   * cache.nixos.org remains the first persistent fleet substituter;
#   * the Raspberry Pi cache remains the first flake extra substituter, matching
#     the historical flake configuration;
#   * nix-community remains the second persistent fleet substituter.
let
  caches = [
    {
      name = "cache.nixos.org";
      url = "https://cache.nixos.org";
      publicKey = "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=";
      scope = "fleet";
      baseline = true;
      keyMonitor = "manual";
    }
    {
      name = "nixos-raspberrypi.cachix.org";
      url = "https://nixos-raspberrypi.cachix.org";
      publicKey = "nixos-raspberrypi.cachix.org-1:4iMO9LXa8BqhU+Rpg6LQKiGa2lsNh/j2oiYLNOQ5sPI=";
      scope = "rpi";
      baseline = false;
      keyMonitor = "manual";
    }
    {
      name = "nix-community.cachix.org";
      url = "https://nix-community.cachix.org";
      publicKey = "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs=";
      scope = "fleet";
      baseline = false;
      keyMonitor = "manual";
    }
    # Self-hosted ARM caches on the two Oracle A1.Flex nodes, reachable only
    # over Tailscale. These exist because `follows`-rebased inputs (deploy-rs,
    # sops-nix) miss upstream Cachix, and sops-install-secrets has no public
    # cache at all — without these every aarch64 node recompiles the same Go
    # and Rust output. Plain http:// is correct here: the tailnet already
    # provides authenticated transport encryption, and NAR signatures (not TLS)
    # are what establish trust in cache contents.
    {
      name = "oracle-eu-arm1";
      url = "http://oracle-eu-arm1:5000";
      publicKey = "oracle-eu-arm1:PLACEHOLDER_REPLACE_WITH_GENERATED_PUBLIC_KEY=";
      scope = "arm";
      baseline = false;
      keyMonitor = "manual";
    }
    {
      name = "oracle-in-arm1";
      url = "http://oracle-in-arm1:5000";
      publicKey = "oracle-in-arm1:PLACEHOLDER_REPLACE_WITH_GENERATED_PUBLIC_KEY=";
      scope = "arm";
      baseline = false;
      keyMonitor = "manual";
    }
  ];

  unique = values:
    let
      loop = seen: remaining:
        if remaining == [ ] then
          true
        else
          let
            value = builtins.head remaining;
            rest = builtins.tail remaining;
          in
          if builtins.elem value seen then false else loop (seen ++ [ value ]) rest;
    in
    loop [ ] values;

  cachesForScope = scope:
    builtins.filter (cache: cache.scope == scope) caches;

  baselineCaches = builtins.filter (cache: cache.baseline) caches;
  fleetCaches = cachesForScope "fleet";
  rpiCaches = cachesForScope "rpi";
  armCaches = cachesForScope "arm";

  # Flake-level extras intentionally include every non-baseline *public* cache.
  # This lets the Raspberry Pi input use its cache during evaluation while
  # keeping cache.nixos.org explicit as the baseline supplied by Nix itself.
  # The self-hosted `arm` caches are deliberately EXCLUDED: flake nixConfig is
  # consulted during evaluation on the operator's Mac, which may be off-tailnet,
  # and an unreachable substituter there costs a timeout on every eval. They are
  # applied as host-level nix.settings instead.
  flakeExtraCaches = builtins.filter (cache: !cache.baseline && cache.scope != "arm") caches;

  urls = caches': builtins.map (cache: cache.url) caches';
  publicKeys = caches': builtins.map (cache: cache.publicKey) caches';

  renderScope = scopeCaches: {
    caches = scopeCaches;
    substituters = urls scopeCaches;
    trustedPublicKeys = publicKeys scopeCaches;
    # This spelling is convenient when assigning directly to nix.settings.
    trusted-public-keys = publicKeys scopeCaches;
  };

  fleet = renderScope fleetCaches;
  rpi = renderScope rpiCaches;
  arm = renderScope armCaches;
  flakeExtras = renderScope flakeExtraCaches;

  fleetNixSettings = {
    substituters = fleet.substituters;
    trusted-public-keys = fleet.trustedPublicKeys;
  };
  rpiNixSettings = {
    substituters = rpi.substituters;
    trusted-public-keys = rpi.trustedPublicKeys;
  };
  armNixSettings = {
    substituters = arm.substituters;
    trusted-public-keys = arm.trustedPublicKeys;
  };
  flakeNixConfig = {
    extra-substituters = flakeExtras.substituters;
    extra-trusted-public-keys = flakeExtras.trustedPublicKeys;
  };

  # Nix cache public keys have the form `<cache-name>-<key-id>:<base64>`.
  validPublicKey = key:
    builtins.match "^[^:]+:[A-Za-z0-9+/=]+$" key != null;

  keyIdentity = key:
    let match = builtins.match "^([^:]+):[^:]+$" key;
    in if match == null then null else builtins.elemAt match 0;

  identityMatchesName = cache:
    let
      identity = keyIdentity cache.publicKey;
      nameLength = builtins.stringLength cache.name;
    in
    if identity == null || builtins.stringLength identity < nameLength then
      false
    else
      let suffix = builtins.substring nameLength (builtins.stringLength identity) identity;
      in
      builtins.substring 0 nameLength identity == cache.name
      && (suffix == "" || builtins.match "^-[A-Za-z0-9._-]+$" suffix != null);

  validUrl = cache:
    let
      https = builtins.match "^https://([^/]+)/?$" cache.url;
      # Self-hosted caches are addressed by Tailscale MagicDNS name and port
      # over plain HTTP — see the `arm` scope note above.
      http = builtins.match "^http://([^/:]+)(:[0-9]+)?/?$" cache.url;
    in
    if cache.scope == "arm" then
      http != null && builtins.elemAt http 0 == cache.name
    else
      https != null && builtins.elemAt https 0 == cache.name;

  scopeNames = [ "fleet" "rpi" "arm" ];
  names = builtins.map (cache: cache.name) caches;
  cacheUrls = builtins.map (cache: cache.url) caches;
  cacheKeys = builtins.map (cache: cache.publicKey) caches;

  checks = {
    scopes-are-approved = builtins.all (cache: builtins.elem cache.scope scopeNames) caches;
    urls-are-https = builtins.all (cache: validUrl cache) caches;
    names-are-unique = unique names;
    urls-are-unique = unique cacheUrls;
    keys-are-unique = unique cacheKeys;
    keys-have-valid-format = builtins.all (cache: validPublicKey cache.publicKey) caches;
    keys-match-cache-identities = builtins.all identityMatchesName caches;
    key-monitor-modes-approved = builtins.all
      (cache: builtins.elem cache.keyMonitor [ "manual" "nix-cache-info" ]) caches;
    one-key-per-fleet-substituter =
      builtins.length fleet.substituters == builtins.length fleet.trustedPublicKeys;
    one-key-per-rpi-substituter =
      builtins.length rpi.substituters == builtins.length rpi.trustedPublicKeys;
    one-key-per-arm-substituter =
      builtins.length arm.substituters == builtins.length arm.trustedPublicKeys;
    one-key-per-flake-substituter =
      builtins.length flakeExtras.substituters == builtins.length flakeExtras.trustedPublicKeys;
    exactly-one-baseline = builtins.length baselineCaches == 1;
    rendered-fleet-settings-match-inventory =
      fleetNixSettings.substituters == fleet.substituters
      && fleetNixSettings.trusted-public-keys == fleet.trustedPublicKeys;
    rendered-rpi-settings-match-inventory =
      rpiNixSettings.substituters == rpi.substituters
      && rpiNixSettings.trusted-public-keys == rpi.trustedPublicKeys;
    rendered-flake-settings-match-inventory =
      flakeNixConfig.extra-substituters == flakeExtras.substituters
      && flakeNixConfig.extra-trusted-public-keys == flakeExtras.trustedPublicKeys;
    flake-literals-match-inventory =
      let flakeLiteralConfig = (import ../flake.nix).nixConfig;
      in flakeLiteralConfig == flakeNixConfig;
  };

  valid = builtins.all (result: result) (builtins.attrValues checks);
in
{
  inherit caches baselineCaches fleetCaches rpiCaches armCaches flakeExtraCaches checks valid;

  # Rendered settings for NixOS modules.  The aliases at the top level make
  # this file easy to consume from small modules without knowing its internals.
  inherit fleet rpi arm flakeExtras;
  # Short aliases for consumers that model caches by target surface.
  flake = flakeExtras;
  host = {
    inherit fleet rpi arm;
  };
  byScope = {
    inherit fleet rpi arm;
  };
  nixSettings = fleetNixSettings;
  inherit rpiNixSettings armNixSettings;
  substituters = fleet.substituters;
  trustedPublicKeys = fleet.trustedPublicKeys;
  rpiSubstituters = rpi.substituters;
  rpiTrustedPublicKeys = rpi.trustedPublicKeys;
  armSubstituters = arm.substituters;
  armTrustedPublicKeys = arm.trustedPublicKeys;

  # `nixConfig` deliberately contains only non-baseline caches.  Nix already
  # knows cache.nixos.org, while these entries are needed during flake input
  # evaluation (including nixos-raspberrypi).
  inherit flakeNixConfig;
}
