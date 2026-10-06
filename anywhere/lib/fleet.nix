{
  oracle-eu-micro2 = {
    system = "x86_64-linux";
    role = "agent";
    class = "micro";
    wave = "x86-canary";
    order = 10;
    activationTimeout = 600;
    confirmTimeout = 60;
    remoteBuild = false;
    fastConnection = true;
  };

  oracle-eu-arm1 = {
    system = "aarch64-linux";
    role = "agent";
    class = "arm";
    wave = "arm-canary";
    order = 20;
    activationTimeout = 600;
    confirmTimeout = 60;
    # This host IS the aarch64-linux distributed builder (registered in
    # hosts/pro-darwin/darwin-configuration.nix). Keep `true`: building on the
    # target is building on the builder. Setting `false` would make Nix offload
    # here, fetch the outputs back to the Mac, then have deploy-rs copy the same
    # closure back again — a pointless WAN round-trip.
    # Invariant: a host that is itself a registered builder keeps remoteBuild = true.
    remoteBuild = true;
    fastConnection = false;
  };

  oracle-eu-micro1 = {
    system = "x86_64-linux";
    role = "agent";
    class = "micro";
    wave = "workers";
    order = 30;
    activationTimeout = 600;
    confirmTimeout = 60;
    remoteBuild = false;
    fastConnection = true;
  };

  oracle-in-micro1 = {
    system = "x86_64-linux";
    role = "agent";
    class = "micro";
    wave = "workers";
    order = 40;
    activationTimeout = 600;
    confirmTimeout = 60;
    remoteBuild = false;
    fastConnection = true;
  };

  oracle-in-micro2 = {
    system = "x86_64-linux";
    role = "agent";
    class = "micro";
    wave = "workers";
    order = 50;
    activationTimeout = 600;
    confirmTimeout = 60;
    remoteBuild = false;
    fastConnection = true;
  };

  oracle-in-arm1 = {
    system = "aarch64-linux";
    role = "agent";
    class = "arm";
    wave = "workers";
    order = 60;
    activationTimeout = 600;
    confirmTimeout = 60;
    # Offloaded to the oracle-eu-arm1 aarch64 builder rather than built on this
    # small A1.Flex. fastConnection = false matters now that this is `false`:
    # it adds --substitute-on-destination, so the Mumbai host pulls common paths
    # from cache.nixos.org instead of dragging the whole closure EU -> IN.
    remoteBuild = false;
    fastConnection = false;
  };

  rpi = {
    system = "aarch64-linux";
    role = "agent";
    class = "rpi";
    wave = "workers";
    order = 70;
    # Covers activation only (switch-to-configuration), not the build — keep 900
    # even though the build now happens on oracle-eu-arm1. With remoteBuild =
    # false the Pi may also substitute paths before activation starts.
    activationTimeout = 900;
    confirmTimeout = 60;
    # Slowest CPU in the fleet, SD-card store, and reports under-voltage
    # throttling — build on oracle-eu-arm1 instead. fastConnection = false is
    # important here: the Pi is Wi-Fi-only, so let it substitute what it can
    # rather than receiving the full closure over wlan0.
    remoteBuild = false;
    fastConnection = false;
  };

  nuc7i3 = {
    system = "x86_64-linux";
    role = "agent";
    class = "on-prem";
    wave = "workers";
    order = 80;
    activationTimeout = 600;
    confirmTimeout = 60;
    remoteBuild = true;
    fastConnection = true;
  };

  s145 = {
    system = "x86_64-linux";
    role = "server";
    class = "on-prem";
    wave = "control-plane";
    order = 100;
    activationTimeout = 600;
    confirmTimeout = 60;
    remoteBuild = true;
    fastConnection = false;
  };
}
