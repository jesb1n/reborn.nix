{ config, lib, ... }:

let
  hostSecretsFile = ../../secrets/s145/secrets.yaml;
  hasHostSecretsFile = builtins.pathExists hostSecretsFile;
  tailscaleSecretsFile = ../../secrets/tailscale/secrets.yaml;
  hasTailscaleSecretsFile = builtins.pathExists tailscaleSecretsFile;
  clusterSecretsFile = ../../secrets/k3s/secrets.yaml;
  hasClusterSecretsFile = builtins.pathExists clusterSecretsFile;
in
{
  sops = {
    age.keyFile = "/var/lib/sops-nix/key.txt";
    age.generateKey = false;
    age.sshKeyPaths = [ ];

    defaultSopsFormat = "yaml";

    secrets = lib.mkMerge [
      (lib.mkIf hasTailscaleSecretsFile {
        "tailscale-auth-key" = {
          sopsFile = tailscaleSecretsFile;
        };
      })

      (lib.mkIf hasClusterSecretsFile {
        # Shared k3s cluster token used by the server (this host) and worker agents.
        "k3s-token" = {
          sopsFile = clusterSecretsFile;
        };
      })

      (lib.mkIf hasHostSecretsFile {
        "wifi-ssid" = {
          sopsFile = hostSecretsFile;
        };

        "wifi-psk" = {
          sopsFile = hostSecretsFile;
        };

        # Scoped Cloudflare API token (Zone:DNS:Edit + Zone:Zone:Read).
        # Consumed by Traefik's ACME DNS-01 challenge via a k8s Secret.
        "cloudflare-dns-api-token" = {
          sopsFile = hostSecretsFile;
        };
      })
    ];

    templates = lib.mkIf hasHostSecretsFile {
      "s145-network.env".content = ''
        WIFI_SSID=${config.sops.placeholder."wifi-ssid"}
        WIFI_PSK=${config.sops.placeholder."wifi-psk"}
      '';

      # Rendered straight into k3s's auto-deploy manifests dir so the
      # token never lives on disk as plain text outside /run.
      "traefik-cloudflare-secret.yaml" = {
        path = "/var/lib/rancher/k3s/server/manifests/traefik-cloudflare-secret.yaml";
        mode = "0600";
        owner = "root";
        group = "root";
        content = ''
          apiVersion: v1
          kind: Secret
          metadata:
            name: traefik-cloudflare
            namespace: kube-system
          type: Opaque
          stringData:
            CF_DNS_API_TOKEN: ${config.sops.placeholder."cloudflare-dns-api-token"}
        '';
      };
    };
  };
}
