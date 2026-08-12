# hosts/s145/wifi-watchdog.nix — self-healing WiFi connectivity watchdog.
#
# s145 is a laptop with no ethernet port — WiFi (wlp2s0) is the single
# network path. On 2026-08-12 the GPV AP glitched at 00:37, wpa_supplicant
# temp-disabled the SSID and NetworkManager never retried: ~20h outage
# while the machine itself stayed healthy. This watchdog recovers that
# stuck state automatically.
#
# Design:
#   * A systemd timer fires a check every 5 minutes (OnCalendar=*:0/5).
#   * Pass  = a default route exists AND its gateway answers one ping.
#   * Fail  = no default route, or the gateway does not answer.
#   * Recovery only triggers after 3 consecutive failures; any successful
#     check resets the counter. A transient AP flap (seconds) never fires.
#   * Recovery: bounce the radio (nmcli radio wifi off/on) and wait up to
#     60s for wlp2s0 to re-associate; escalate to a NetworkManager restart
#     if the bounce does not reconnect. NM only manages wlp2s0 — cni0,
#     flannel.1 and tailscale0 are "external" and survive the restart.
#   * An ISP-only outage (router up, WiFi up, no internet) keeps the
#     gateway pingable, so the watchdog stays quiet — bouncing the radio
#     cannot fix an ISP outage.
#   * A 30-minute cooldown after any recovery action prevents escalation
#     thrash during prolonged home-network outages; once power/ISP returns,
#     NM's own autoconnect recovers the link and the next check passes.
#   * State files live in /run (tmpfs) — no disk writes.
{
  pkgs,
  ...
}:

let
  stateDir = "/run/s145-wifi-watchdog";
  maxFailures = 3;
  cooldownSeconds = 1800;
  iface = "wlp2s0";

  watchdogScript = pkgs.writeShellScript "s145-wifi-watchdog" ''
    set -u

    STATE_DIR=${stateDir}
    COUNTER_FILE=$STATE_DIR/failures
    LAST_ACTION_FILE=$STATE_DIR/last-action
    MAX_FAILURES=${toString maxFailures}
    COOLDOWN_SECONDS=${toString cooldownSeconds}
    IFACE=${iface}

    mkdir -p "$STATE_DIR"

    pass() {
      rm -f "$COUNTER_FILE"
    }

    fail() {
      local n=0
      [[ -f "$COUNTER_FILE" ]] && n=$(<"$COUNTER_FILE")
      n=$((n + 1))
      echo "$n" > "$COUNTER_FILE"
      echo "connectivity check failed ($n/$MAX_FAILURES)"

      if (( n < MAX_FAILURES )); then
        return 0
      fi

      # Avoid escalation thrash during a long home-network outage.
      if [[ -f "$LAST_ACTION_FILE" ]]; then
        local last now
        last=$(<"$LAST_ACTION_FILE")
        now=$(date +%s)
        if (( now - last < COOLDOWN_SECONDS )); then
          echo "recovery action suppressed by cooldown ($COOLDOWN_SECONDS s)"
          return 0
        fi
      fi
      date +%s > "$LAST_ACTION_FILE"
      rm -f "$COUNTER_FILE"

      echo "WiFi connectivity lost after $MAX_FAILURES consecutive failures, bouncing radio ($IFACE)"
      nmcli radio wifi off
      sleep 3
      nmcli radio wifi on

      # NOTE: nmcli terse output is "GENERAL.STATE:100 (connected)" — match
      # the substring, not the bare word, or recovery is never detected.
      local i state
      for i in $(seq 1 60); do
        state=$(nmcli -t -f GENERAL.STATE device show "$IFACE" 2>/dev/null | sed 's/^GENERAL.STATE://')
        [[ "$state" == *"connected"* ]] && {
          echo "WiFi recovered after radio bounce"
          return 0
        }
        sleep 1
      done

      echo "radio bounce did not recover WiFi, restarting NetworkManager"
      systemctl restart NetworkManager
    }

    GW=$(ip route show default 2>/dev/null | awk '{print $3}' | head -n1)
    if [[ -z "$GW" ]]; then
      echo "no default route"
      fail
      exit 0
    fi

    if ping -c1 -W2 "$GW" >/dev/null 2>&1; then
      pass
      exit 0
    fi

    echo "gateway $GW unreachable"
    fail
    exit 0
  '';
in
{
  systemd.timers.s145-wifi-watchdog = {
    description = "Periodic WiFi connectivity check for s145";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*:0/5";
      Persistent = false;
      AccuracySec = "10s";
    };
  };

  systemd.services.s145-wifi-watchdog = {
    description = "Self-healing WiFi connectivity check for s145";
    path = with pkgs; [
      coreutils
      gawk
      gnused
      iproute2
      iputils
      networkmanager # nmcli
      systemd # systemctl
    ];
    serviceConfig = {
      ExecStart = watchdogScript;
      Type = "oneshot";
      TimeoutSec = 180;
    };
  };
}