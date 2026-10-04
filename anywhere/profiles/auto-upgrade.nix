# profiles/auto-upgrade.nix — pull-based self-deploy from the git remote.
#
# Each host runs `nixos-rebuild switch --flake <repo>#<hostname>` on a timer,
# building with its OWN CPU instead of waiting for a push from the operator's
# Mac. This is the pull counterpart to deploy-rs: deploy-rs stays the tool for
# deliberate, supervised rollouts; this profile closes drift automatically.
#
# NOTHING HERE TOUCHES DISKS. `nixos-rebuild switch` only builds a new system
# closure and flips the /nix/var/nix/profiles/system symlink. disko and
# nixos-anywhere are never invoked, so partitions and data are untouched.
#
# Reboots: allowed, but only when the new generation actually requires one
# (kernel/initrd/systemd change) AND the clock is inside `rebootWindow`.
# Outside that window the generation still activates; only the reboot defers.
#
# Switching to a self-hosted git mirror later is a one-line change — set
# `fleet.autoUpgrade.flakeRef` (e.g. "git+https://git.jesb.in/jesbin/reborn.nix?dir=anywhere")
# in base.nix. Nothing else in this profile assumes GitHub.
#
# Rollback is the normal NixOS mechanism: pick the previous generation from the
# bootloader, or `nixos-rebuild switch --rollback`.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.fleet.autoUpgrade;
in
{
  options.fleet.autoUpgrade = {
    enable = lib.mkEnableOption "pull-based auto-upgrade from the fleet git remote";

    flakeRef = lib.mkOption {
      type = lib.types.str;
      default = "github:jesb1n/reborn.nix?dir=anywhere";
      description = ''
        Flake reference to build from. The host's own `networking.hostName` is
        appended as the attribute, so each node self-selects its configuration.
      '';
    };

    dates = lib.mkOption {
      type = lib.types.str;
      default = "04:30";
      description = "systemd OnCalendar expression for the upgrade timer.";
    };

    randomizedDelaySec = lib.mkOption {
      type = lib.types.str;
      default = "45min";
      description = ''
        Jitter before firing. Keeps nine nodes from hammering GitHub and the
        binary caches at the same instant.
      '';
    };

    rebootWindow = lib.mkOption {
      type = lib.types.nullOr (
        lib.types.submodule {
          options = {
            lower = lib.mkOption {
              type = lib.types.str;
              description = "Earliest wall-clock time an unattended reboot may start.";
            };
            upper = lib.mkOption {
              type = lib.types.str;
              description = "Latest wall-clock time an unattended reboot may start.";
            };
          };
        }
      );
      default = {
        lower = "04:00";
        upper = "06:00";
      };
      description = ''
        Window in which an unattended reboot is permitted. Outside it the new
        generation is still built and activated — only the reboot is deferred
        to a later run. Set to null to permit a reboot at any hour.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    system.autoUpgrade = {
      enable = true;

      # `nixos-rebuild switch`, NOT boot — we want the new generation live
      # immediately so k3s picks up rotated secrets without a reboot.
      operation = "switch";

      flake = "${cfg.flakeRef}#${config.networking.hostName}";

      # nixos-rebuild already passes --refresh for flake upgrades; only the
      # negative-TTL override is needed so a cache miss on one run doesn't
      # suppress a genuine update on the next.
      flags = [
        "--option"
        "narinfo-cache-negative-ttl"
        "0"
      ];

      inherit (cfg) dates randomizedDelaySec;

      # Reboot when the new generation needs it (kernel, initrd, or systemd
      # change) — but only inside rebootWindow. Outside the window the
      # generation is still activated and the reboot waits for the next run,
      # so a midday upgrade never yanks k3s workloads out from under you.
      allowReboot = true;
      inherit (cfg) rebootWindow;
    };

    # nixos-rebuild shells out to git for flake fetching, and the minimal
    # profile in base.nix ships no default packages.
    environment.systemPackages = [ pkgs.git ];

    systemd.services.nixos-upgrade = {
      # Don't fight the weekly GC/optimise timers from base.nix for the nix
      # daemon lock, and don't start before the network is actually usable.
      after = [
        "network-online.target"
        "nix-gc.service"
        "nix-optimise.service"
      ];
      wants = [ "network-online.target" ];

      serviceConfig = {
        # A micro node building a full closure can legitimately take a while;
        # but it must not wedge forever holding the nix lock.
        TimeoutStartSec = "3h";

        # Build failures are expected transients (GitHub blip, cache miss on a
        # slow node). Retry rather than waiting a full day for the next timer.
        Restart = "on-failure";
        RestartSec = "30min";
      };

      # Keep retries bounded so a genuinely broken commit doesn't loop all day.
      startLimitBurst = 3;
      startLimitIntervalSec = 7200;
    };
  };
}
