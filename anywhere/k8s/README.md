# anywhere/k8s/

Application manifests for the s145-rooted k3s cluster. Applied **manually**
(this is not in k3s's auto-deploy directory). Cluster infrastructure
(Traefik chart override, secrets) is wired in via NixOS in
[`../hosts/s145/`](../hosts/s145/) — keep that in mind.

## Layout

```
k8s/
├── _infra/        Cross-cutting middlewares & policies applied once per cluster
├── vaultwarden/   Full reference deployment (deployment + svc + pvc + route)
└── immich/        Flux-managed Immich stack (HelmRelease + db + redis + route)
```

Conventions:

- Every stateful workload **pins `nodeSelector: kubernetes.io/hostname: s145`** so PVCs (`local-path` storage class) land on the 1 TB HDD, not on disposable Oracle agents.
- Hostnames default to `*.jesb.in`. Search/replace if you use a different zone.
- Traefik handles HTTP → HTTPS redirect globally (chart-level config in [`../hosts/s145/traefik.nix`](../hosts/s145/traefik.nix)) — do **not** add redirect middlewares per app.
- Traefik `Middleware` resources are namespaced. Public app `IngressRoute`s should include a same-namespace `security-headers` Middleware and reference it as `- name: security-headers`; do not point app routes at `kube-system/security-headers`.
- ACME uses the Let's Encrypt production CA through Traefik's default ACME endpoint.

## Apply

From any machine with `kubectl` and the cluster's kubeconfig:

```bash
# Cluster-wide infrastructure (run once after first deploy)
kubectl apply -f anywhere/k8s/_infra/

# Per-app
kubectl apply -f anywhere/k8s/vaultwarden/
kubectl apply -f anywhere/k8s/immich/
```

For Flux-managed apps, prefer reconciling the cluster Kustomization after
commit/push:

```bash
flux reconcile kustomization immich -n flux-system --with-source
```

From s145 directly (no kubeconfig needed):

```bash
ssh duck@s145 'sudo k3s kubectl apply -f -' < anywhere/k8s/vaultwarden/deployment.yaml
# …or pipe a whole dir:
tar c anywhere/k8s/vaultwarden | ssh duck@s145 'sudo tar x -C /tmp && sudo k3s kubectl apply -f /tmp/anywhere/k8s/vaultwarden/'
```

## Reissue Certificates

If Traefik previously stored staging certificates, delete `acme.json` after the
NixOS deploy so it requests production certificates:

```bash
ssh duck@s145 'sudo k3s kubectl -n kube-system exec deploy/traefik -- rm /data/acme.json'
ssh duck@s145 'sudo k3s kubectl -n kube-system rollout restart deploy/traefik'
```
