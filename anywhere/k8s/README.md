# anywhere/k8s/

Application manifests for the s145-rooted k3s cluster.

Applications are **Flux-managed**: Flux Operator syncs `main` into the cluster,
`anywhere/clusters/s145/*.yaml` registers one `Kustomization` per app pointing
at a directory below, and Flux applies and prunes those resources on its own
interval.

Cluster infrastructure that isn't Flux-managed (Traefik chart override via
HelmChartConfig, the Cloudflare ACME secret) is wired in via NixOS in
[`../hosts/s145/`](../hosts/s145/) — keep that in mind when troubleshooting
ingress issues.

## Layout

```
k8s/
├── _infra/                Cross-cutting middleware/policy (Flux-managed, Kustomization `infra`)
├── vaultwarden/           Flux-managed Vaultwarden deployment, storage, service, and route
├── immich/                Flux-managed Immich stack (HelmRelease + Postgres + Valkey + route)
├── immich-public-proxy/   Flux-managed Immich share frontend (depends on `immich`, routed via cloudflared, not Traefik)
├── garage/                Flux-managed Garage S3, three-zone layout (garage-arm/-micro/-onprem HelmReleases)
├── litellm/               Flux-managed LiteLLM proxy (ChatGPT Plus OAuth + Gemini, pinned to oracle-eu-arm1, NodePort only)
├── cloudflared/           Flux-managed Cloudflare Tunnel DaemonSet
└── monitoring/            Flux-managed kube-prometheus-stack (pinned to oracle-in-arm1)
```

Every application directory is registered in
[`../clusters/s145/`](../clusters/s145/). `_infra` has no local
`kustomization.yaml`, but `clusters/s145/infra.yaml` points directly at the
directory and Kustomize treats its manifests as resources.

Flux dependency graph (`spec.dependsOn` in `clusters/s145/*.yaml`):

```
infra
 ├── cloudflared
 ├── garage
 ├── immich
 │    └── immich-public-proxy
 ├── litellm
 ├── monitoring
 └── vaultwarden
```

Conventions:

- Stateful app workloads (Immich, Vaultwarden, …) **pin `nodeSelector: kubernetes.io/hostname: s145`** so their PVCs (`local-path`, or the static `hostPath`-backed PVs under Immich) land on the 1 TB HDD, not on disposable Oracle agents.
- **Exception:** Prometheus, Grafana, Alertmanager, the Prometheus Operator, and kube-state-metrics pin to `oracle-in-arm1` — see [`monitoring/`](monitoring/). `node-exporter` still runs as a DaemonSet on every node, including the tainted `tiny` micros.
- Hostnames default to `*.beijns.eu.org` (Vaultwarden, Immich, Garage S3, Grafana) or the equivalent Cloudflare Tunnel Published-application hostname for `immich-public-proxy`. Search/replace if you use a different zone.
- Traefik handles HTTP → HTTPS redirect globally (chart-level config in [`../hosts/s145/traefik.nix`](../hosts/s145/traefik.nix)) — do **not** add redirect middlewares per app.
- Traefik `Middleware` resources are namespaced. Public app `IngressRoute`s each define their own same-namespace `security-headers` Middleware and reference it as `- name: security-headers`; do not point app routes at `kube-system/security-headers` (the copy under `_infra/security-headers.yaml`) unless Traefik is explicitly reconfigured to allow cross-namespace middleware references.
- ACME uses the Let's Encrypt production CA through Traefik's `cloudflare` cert resolver (DNS-01 via Cloudflare). There is no cert-manager in this cluster.
- `immich-public-proxy` is reached through the shared Cloudflare Tunnel (`cloudflared/`), not through a Traefik `IngressRoute` — its Published-application routing lives in the Cloudflare dashboard, not in this repo.

## Validate and reconcile

Validate a directory locally before committing:

```bash
kubectl kustomize anywhere/k8s/immich
kubectl apply --dry-run=client -f anywhere/k8s/_infra/
```

After the change is reviewed, committed, and pushed to `main`, Flux reconciles
it automatically. An explicit reconciliation changes the live cluster:

```bash
flux reconcile kustomization immich -n flux-system --with-source
flux get kustomizations -n flux-system
```

Do not apply Flux-owned resources directly with `kubectl`; Flux will restore
the state from Git. Reconcile `infra` first when its resources changed because
all top-level applications depend on it.
