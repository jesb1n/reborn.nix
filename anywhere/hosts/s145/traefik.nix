# hosts/s145/traefik.nix — Traefik ingress with Cloudflare DNS-01 ACME.
#
# Approach: extend the default Traefik HelmChart that ships with k3s by
# dropping a HelmChartConfig and a backing Secret into k3s's auto-deploy
# manifests dir (/var/lib/rancher/k3s/server/manifests/). No cert-manager.
#
# Files this module manages in that directory:
#   * traefik-config.yaml          — static chart overrides (this module)
#   * traefik-cloudflare-secret.yaml — rendered by sops-nix (hosts/s145/sops.nix)
#
# Currently pinned to Let's Encrypt **staging** to avoid burning prod quota
# during first-deploy. Flip the `caserver` arg below to production once you
# see a successful staging issuance:
#   https://acme-v02.api.letsencrypt.org/directory
#
# Cloudflare token must be a *scoped* token with at least:
#   Zone:DNS:Edit + Zone:Zone:Read for the relevant zones.
{ lib, pkgs, ... }:

let
  clusterSecretsFile = ../../secrets/k3s/secrets.yaml;
  hasClusterSecretsFile = builtins.pathExists clusterSecretsFile;
  hostSecretsFile = ../../secrets/s145/secrets.yaml;
  hasHostSecretsFile = builtins.pathExists hostSecretsFile;

  # Static (non-secret) HelmChartConfig. Lives in the Nix store so changes
  # flow through normal NixOS rebuilds.
  traefikChartConfig = pkgs.writeText "traefik-config.yaml" ''
    apiVersion: helm.cattle.io/v1
    kind: HelmChartConfig
    metadata:
      name: traefik
      namespace: kube-system
    spec:
      valuesContent: |-
        # ACME state lives in /data on local-path PVC; cannot be shared.
        deployment:
          replicas: 1
        # Pin Traefik to s145 so the PVC (and acme.json) survives there.
        nodeSelector:
          kubernetes.io/hostname: s145
        persistence:
          enabled: true
          name: data
          size: 128Mi
          storageClass: local-path
          accessMode: ReadWriteOnce
          path: /data
        env:
          - name: CF_DNS_API_TOKEN
            valueFrom:
              secretKeyRef:
                name: traefik-cloudflare
                key: CF_DNS_API_TOKEN
        additionalArguments:
          # Global HTTP → HTTPS redirect at the `web` entrypoint, so app
          # IngressRoutes don't need to repeat the redirect boilerplate.
          - "--entryPoints.web.http.redirections.entryPoint.to=websecure"
          - "--entryPoints.web.http.redirections.entryPoint.scheme=https"
          - "--entryPoints.web.http.redirections.entryPoint.permanent=true"
          - "--certificatesresolvers.cloudflare.acme.email=acme@jesb.in"
          - "--certificatesresolvers.cloudflare.acme.storage=/data/acme.json"
          - "--certificatesresolvers.cloudflare.acme.dnschallenge=true"
          - "--certificatesresolvers.cloudflare.acme.dnschallenge.provider=cloudflare"
          - "--certificatesresolvers.cloudflare.acme.dnschallenge.resolvers=1.1.1.1:53,8.8.8.8:53"
          # Staging CA — flip to production once staging issuance succeeds.
          - "--certificatesresolvers.cloudflare.acme.caserver=https://acme-staging-v02.api.letsencrypt.org/directory"
  '';
in
{
  # Wire the manifest into k3s only when all the inputs it needs exist;
  # otherwise the cluster won't be enabled in the first place.
  config = lib.mkIf (hasClusterSecretsFile && hasHostSecretsFile) {
    systemd.tmpfiles.rules = [
      "d /var/lib/rancher/k3s/server/manifests 0755 root root -"
      "L+ /var/lib/rancher/k3s/server/manifests/traefik-config.yaml - - - - ${traefikChartConfig}"
    ];
  };
}
