# monitoring — kube-prometheus-stack (Flux)

Host + Kubernetes metrics via the official
[kube-prometheus-stack](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack)
chart (`88.1.5`).

| Piece | Where |
|-------|--------|
| Manifests | this directory |
| Flux Kustomization | [`../../clusters/s145/monitoring.yaml`](../../clusters/s145/monitoring.yaml) |
| Grafana | https://g1.beijns.eu.org (`admin` / SOPS secret `grafana-admin`) |
| Pin | Prometheus, Grafana, Alertmanager, Operator, kube-state-metrics → `oracle-in-arm1` |
| DaemonSet | node-exporter on every node (incl. `tiny` micros; chart default tolerations) |

## Reconcile (after review + push to `main`)

```bash
flux reconcile kustomization monitoring -n flux-system --with-source
kubectl -n monitoring get pods -o wide
kubectl -n monitoring get pvc
# Prom/Grafana/AM only on oracle-in-arm1; node-exporter on all Ready nodes
```

DNS: create Cloudflare A/CNAME for `g1.beijns.eu.org` pointing at the same Traefik/tunnel path as other `*.beijns.eu.org` apps.

## Follow-up (not in this change)

### SMART on bare-metal (NixOS, not this chart)

Disk SMART is host-level `services.smartd` via [`profiles/smartd.nix`](../../profiles/smartd.nix). Only physical hosts — skip OCI VMs.

| Host | Status |
|------|--------|
| `s145` | Enabled (profile) |
| `hp348` | Enabled (profile) |
| `rpi` | Enabled (profile; `autodetect` skips media without SMART) |
| `oracle-*` | Skip |
| `pro-darwin` | Skip (nix-darwin) |

Prefer a shared profile (`profiles/smartd.nix`) imported only by bare-metal hosts.

### App metrics endpoints (native only)

After Prometheus is healthy, enable out-of-box `/metrics` where supported and scrape with `ServiceMonitor` / `PodMonitor` (selectors already allow all namespaces):

| App | Action |
|-----|--------|
| Immich | **Done** — `immich.metrics.enabled: true` (ServiceMonitor; Prometheus scrapes `:8081`/`:8082`) |
| Garage | **Done** — PodMonitor on admin `:3903/metrics` |
| Vaultwarden | Skip on `1.36.0` (no native metrics in this tag) |
| cloudflared | **Done** — PodMonitor on `:2000/metrics` (DaemonSet) |
| Traefik | **Done** — `metrics.prometheus` service + ServiceMonitor in `traefik.nix` (needs `deploy .#s145`) |
| immich-public-proxy | Skip — no upstream metrics |
