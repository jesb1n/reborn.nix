# Immich

Flux-managed Immich deployment for the `s145` k3s cluster.

## What This Creates

- `Namespace`: `immich`
- `Secret`: `immich-secret`, SOPS-encrypted database credentials
- `HelmRelease`: upstream Immich chart
- `Deployment` + `Service`: Postgres using the Immich-recommended image
- `Deployment` + `Service`: Valkey for Redis-compatible queues
- `PersistentVolumeClaim`: `immich-library`, `immich-postgres-data`, and `immich-machine-learning-cache`
- `Middleware`: security headers in the `immich` namespace
- `IngressRoute`: public HTTPS route at `i1.beijns.eu.org`

## Routing Notes

Traefik `Middleware` resources are namespaced. The Immich `IngressRoute` must
reference the same-namespace middleware:

```yaml
middlewares:
  - name: security-headers
```

Do not reference `kube-system/security-headers` from the `immich` namespace.
Traefik will reject that unless cross-namespace middleware references are
explicitly enabled.

## Apply

After committing and pushing changes:

```bash
flux reconcile kustomization immich -n flux-system --with-source
flux get helmrelease immich -n immich
```

Flux SOPS decryption requires `Secret/flux-system/sops-age` to exist with the
cluster age key as `age.agekey`.

## Storage

The important PVCs are managed outside the Helm chart so uninstalling
`HelmRelease/immich` does not delete photo, database, or ML cache data. Keep
`pvc.yaml` in the Flux path; removing it while `prune: true` is enabled can
still delete those PVC objects.
