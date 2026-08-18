# Immich

Flux-managed Immich deployment for the `s145` k3s cluster. Registered as the
`immich` Kustomization in
[`../../clusters/s145/immich.yaml`](../../clusters/s145/immich.yaml)
(`dependsOn: infra`, SOPS decryption, `prune: true`).
[`immich-public-proxy`](../immich-public-proxy/) depends on this Kustomization.

## What This Creates

- `Namespace`: `immich`
- `Secret`: `immich-secret`, SOPS-encrypted database credentials
- `HelmRelease`: upstream `immich` chart (`immich-charts` OCI repo, `0.13.1`)
- `Deployment` + `Service`: Postgres (`ghcr.io/immich-app/postgres:14-vectorchord0.4.3-pgvectors0.2.0`), pinned to `s145`
- Helm-managed `Deployment` + `Service`: Valkey for Redis-compatible queues
- Helm-managed server (`ghcr.io/immich-app/immich-server:v3.0.3`) and
  machine-learning (`ghcr.io/immich-app/immich-machine-learning:v3.0.3`)
  Deployments, both pinned to `s145` via `defaultPodOptions.nodeSelector`
- `PersistentVolume` + `PersistentVolumeClaim`: `immich-library` (500Gi) and
  `immich-postgres-data` (50Gi), both static `hostPath` PVs under
  `/home/duck/sda/appdata/immich-app/` on `s145`
- `PersistentVolumeClaim`: `immich-machine-learning-cache` (10Gi, `local-path`)
- `Service`: `immich-server-nodeport` (NodePort `32283` → `2283`)
- `Middleware`: `security-headers` in the `immich` namespace
- `IngressRoute`: public HTTPS route at `i1.beijns.eu.org` → `immich-server:2283`

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

The `immich-library` and `immich-postgres-data` PVCs are bound to static,
pre-provisioned PVs (`pv.yaml`) rather than a dynamic StorageClass, and are
managed outside the Helm chart so uninstalling `HelmRelease/immich` does not
delete photo or database data. Keep `pv.yaml` and `pvc.yaml` in the Flux path;
removing them while `prune: true` is enabled can still delete those PVC/PV
objects — the `Retain` reclaim policy on the PVs protects the underlying
`hostPath` data, but not the Kubernetes objects themselves.
