# profiles/pihole.nix — Pi-hole FTL + dashboard, with DNS-over-TLS upstream.
#
# Shape:
#
#   client ──53/udp,tcp──▶ pihole-FTL ──127.0.0.1#5353──▶ stubby ──853/TLS──▶ Cloudflare
#            (tailnet +                (filtering,                (DoT, cert-pinned
#             home LAN)                 dnsmasq fork)              by tls_auth_name)
#
# Only stubby ever talks to the internet for resolution, and only over TLS —
# nothing leaves the host as cleartext DNS.
#
# Reachability is interface-scoped, not host-wide: port 53 is opened on the
# tailnet interface and on the LAN interface named by `fleet.pihole.lanInterface`,
# never on a default-route interface. FTL itself listens on the wildcard
# (`listeningMode = "ALL"`) because `LOCAL` rejects tailnet peers — a /32
# tailscale0 address means 100.64.0.0/10 is not a "local subnet" from dnsmasq's
# point of view. The firewall, not the daemon, is the boundary here.
#
# Config is immutable: `misc.readOnly = true` (the nixpkgs module default) means
# the UI and `pihole` CLI cannot write settings back. Everything is a NixOS
# option. The one exception is the admin password, which cannot live in
# pihole.toml because that file is a world-readable /nix/store path — it is
# injected at runtime from a sops secret via FTL's `FTLCONF_*` environment
# override instead.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.fleet.pihole;
in
{
  options.fleet.pihole = {
    enable = lib.mkEnableOption "Pi-hole FTL with a DNS-over-TLS upstream";

    tailscaleIP = lib.mkOption {
      type = lib.types.str;
      example = "100.118.166.120";
      description = ''
        The host's own Tailscale address. The dashboard binds this address
        only, so the UI is unreachable from the LAN and from any public
        interface even if the firewall were misconfigured.
      '';
    };

    lanInterface = lib.mkOption {
      type = lib.types.str;
      example = "wlan0";
      description = ''
        LAN interface on which to accept DNS queries, in addition to
        `tailscale0`. Queries are accepted on this interface only; no other
        interface gets port 53.
      '';
    };

    webPort = lib.mkOption {
      type = lib.types.port;
      default = 8081;
      description = "Dashboard port, bound to `tailscaleIP` only.";
    };

    allowedWebCIDRs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "100.64.0.0/10"
        "fd7a:115c:a1e0::/48"
      ];
      description = ''
        Source ranges allowed to reach the dashboard, enforced by FTL's own
        ACL as defence in depth behind the bind address. Defaults to the
        CGNAT and ULA ranges Tailscale allocates from.
      '';
    };

    upstreamPort = lib.mkOption {
      type = lib.types.port;
      default = 5353;
      description = "Loopback port stubby listens on for FTL's forwarded queries.";
    };

    passwordSecretName = lib.mkOption {
      type = lib.types.str;
      default = "pihole-web-password";
      description = ''
        Key in the host's sops secrets file holding the dashboard password in
        cleartext. Must already be declared in `hosts/<name>/sops.nix`.
        FTL hashes it at startup; the plaintext never reaches the Nix store.
      '';
    };

    lists = lib.mkOption {
      type = lib.types.listOf lib.types.attrs;
      default = [
        {
          url = "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts";
          description = "Steven Black's unified hosts (adware + malware)";
        }
      ];
      description = ''
        Adlists loaded into gravity on startup via the local API. Requires the
        webserver to be enabled, which it always is here.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # ---------------------------------------------------------------- stubby
    # DoT forwarder. Binds loopback only — it is an implementation detail of
    # the resolver on this host, never a network service.
    services.stubby = {
      enable = true;
      settings = {
        resolution_type = "GETDNS_RESOLUTION_STUB";
        dns_transport_list = [ "GETDNS_TRANSPORT_TLS" ];
        # REQUIRED, not opportunistic: a downgrade to cleartext is a failure,
        # not a fallback. Pairs with tls_auth_name below to pin the identity.
        tls_authentication = "GETDNS_AUTHENTICATION_REQUIRED";
        tls_query_padding_blocksize = 128;
        edns_client_subnet_private = 1;
        round_robin_upstreams = 1;
        idle_timeout = 10000;
        listen_addresses = [ "127.0.0.1@${toString cfg.upstreamPort}" ];
        upstream_recursive_servers = [
          {
            address_data = "1.1.1.1";
            tls_auth_name = "cloudflare-dns.com";
          }
          {
            address_data = "1.0.0.1";
            tls_auth_name = "cloudflare-dns.com";
          }
          {
            address_data = "2606:4700:4700::1111";
            tls_auth_name = "cloudflare-dns.com";
          }
          {
            address_data = "2606:4700:4700::1001";
            tls_auth_name = "cloudflare-dns.com";
          }
        ];
      };
    };

    # ------------------------------------------------------------ pihole-FTL
    services.pihole-ftl = {
      enable = true;
      inherit (cfg) lists;

      # Trim the query database rather than letting it grow without bound on
      # an SD card.
      queryLogDeleter.enable = true;
      queryLogDeleter.age = 30;

      # Firewall rules are written explicitly below, scoped per interface.
      # These open the port on *every* interface, which is not wanted here.
      openFirewallDNS = false;
      openFirewallDHCP = false;
      openFirewallWebserver = false;

      settings = {
        dns = {
          # Forward only to stubby. No plaintext upstream anywhere.
          upstreams = [ "127.0.0.1#${toString cfg.upstreamPort}" ];

          # See the header comment: LOCAL would drop tailnet queries because
          # tailscale0 carries a /32. The firewall provides the boundary.
          listeningMode = "ALL";

          # DNSSEC validation happens at Cloudflare's resolver and the channel
          # to it is authenticated TLS, so re-validating here only costs the
          # Pi CPU and extra round trips.
          dnssec = false;

          domainNeeded = true;
          expandHosts = true;
          # Do not forward reverse lookups for RFC1918 space upstream.
          bogusPriv = true;
        };

        dhcp.active = false;

        webserver = {
          # Last match wins and a non-empty ACL denies by default, so this is
          # an allowlist.
          acl = lib.concatMapStringsSep "," (c: "+${c}") cfg.allowedWebCIDRs;

          api = {
            # The `pihole` CLI needs an ephemeral local password to drive the
            # API that loads `lists` at startup.
            cli_pw = true;
            # Third-party app passwords must not be able to rewrite config —
            # config is owned by Nix.
            app_sudo = false;
          };
        };

        # Config stays immutable (module default, restated for visibility):
        # neither the dashboard nor the CLI may write settings back.
        misc.readOnly = true;
      };
    };

    services.pihole-web = {
      enable = true;
      hostName = "pi.hole";
      # Bind the tailnet address explicitly. `o` = optional: tailscale0 does
      # not exist yet on a cold boot, and an unbindable port must not take the
      # whole resolver down with it — DNS matters more than the dashboard.
      ports = [ "${cfg.tailscaleIP}:${toString cfg.webPort}o" ];
    };

    # ------------------------------------------------------------- password
    # pihole.toml is a /nix/store path (world-readable), so `webserver.api.pwhash`
    # cannot hold a secret. FTL reads `FTLCONF_<key>` environment overrides at
    # startup and hashes `webserver.api.password` itself, so the secret arrives
    # via an EnvironmentFile sops renders at activation time, mode 0400.
    sops.templates."pihole-web.env".content = ''
      FTLCONF_webserver_api_password=${config.sops.placeholder.${cfg.passwordSecretName}}
    '';

    systemd.services.pihole-ftl = {
      # tailscale0 must exist before the dashboard tries to bind it, and the
      # password file must exist before FTL reads its environment. Ordering
      # only — the upstream module's restart policy is left untouched.
      after = [
        "sops-install-secrets.service"
        "tailscaled.service"
        "stubby.service"
      ];
      wants = [
        "sops-install-secrets.service"
        "tailscaled.service"
        "stubby.service"
      ];
      serviceConfig.EnvironmentFile = [ config.sops.templates."pihole-web.env".path ];
    };

    # -------------------------------------------------------------- firewall
    # Port 53 on the tailnet and the named LAN interface only. An open resolver
    # on a public interface is a DNS amplification reflector; nothing here binds
    # one.
    networking.firewall.interfaces = {
      tailscale0 = {
        allowedUDPPorts = [ 53 ];
        allowedTCPPorts = [
          53
          cfg.webPort
        ];
      };

      ${cfg.lanInterface} = {
        allowedUDPPorts = [ 53 ];
        allowedTCPPorts = [ 53 ];
      };
    };

    # Resolve through the local Pi-hole rather than whatever DHCP handed out,
    # so the host's own queries are filtered and encrypted like every client's.
    #
    # 1.1.1.1 is a deliberate fallback, not a second opinion: glibc only tries
    # it after 127.0.0.1 fails to answer, i.e. when pihole-ftl is down. Without
    # it a failed FTL start leaves the Pi with no resolver at all — nightly
    # `nixos-upgrade` could not reach GitHub to pull the fix that repairs it.
    # Trade-off: while FTL is down the host's own queries are unfiltered and
    # cleartext (they bypass stubby/DoT). Clients are unaffected either way —
    # they query FTL directly and simply get no answer if it is down.
    networking.nameservers = [ "127.0.0.1" "1.1.1.1" ];
    networking.networkmanager.dns = "none";

    environment.systemPackages = [ pkgs.dig ];
  };
}
