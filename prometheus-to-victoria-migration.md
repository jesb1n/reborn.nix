# Prometheus → VictoriaMetrics + VictoriaLogs: historical proposal

> **Status: superseded and not implemented.** The cluster still uses the
> Flux-managed `kube-prometheus-stack` under `anywhere/k8s/monitoring/`; no
> `anywhere/k8s/victoria/` resources were created. This document is retained as
> design history only. Reassess chart versions, capacity, retention, and the
> current monitoring manifests before reviving any part of it.

Swap the metrics backend to VictoriaMetrics and add VictoriaLogs for logs. The old stack
stays running the whole time — no downtime, easy rollback. About 1–2 weeks total, most of
it waiting while both run side by side.

**End state:** the same Grafana and the same dashboards, your ServiceMonitors converted
automatically. Metrics kept 90 days instead of 15, plus searchable logs for the first
time.

## Phase 0 — Prep (half a day)

1. Pick and pin the chart versions:

   ```bash
   helm repo add vm https://victoriametrics.github.io/helm-charts/
   helm repo update
   helm search repo vm/victoria-metrics-k8s-stack --versions | head
   helm search repo vm/victoria-logs-collector --versions | head
   ```

   Write down the two versions. Never use `latest`.

2. Create `anywhere/k8s/victoria/` — a new Flux folder, same pattern as `monitoring/`.
   Add a HelmRepository alongside the existing one:

   ```yaml
   apiVersion: source.toolkit.fluxcd.io/v1
   kind: HelmRepository
   metadata:
     name: victoriametrics
     namespace: flux-system
   spec:
     interval: 1h
     url: https://victoriametrics.github.io/helm-charts/
   ```

3. Write a short note in the repo explaining why (metrics only kept 15 days, no logs at
   all, micro nodes can't afford a heavier stack). Five lines is enough.

## Phase 1 — Install VictoriaMetrics next to Prometheus (1 day)

Deploy `victoria-metrics-k8s-stack` with most components turned off, because
kube-prometheus-stack already runs them:

- grafana → **off** (keep the existing one)
- kube-state-metrics → **off** (existing one stays)
- node-exporter → **off** (existing one stays)
- vmsingle → **on**, pinned to `oracle-in-arm1`, retention 90 days, ~15Gi PVC
- Prometheus CRD installation → **off** (kube-prometheus-stack owns them)
- converter ownership → **leave OFF** (this is the important one)

```yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: victoria-metrics-stack
  namespace: monitoring
spec:
  interval: 1h
  chart:
    spec:
      chart: victoria-metrics-k8s-stack
      version: "<pinned version>"
      sourceRef:
        kind: HelmRepository
        name: victoriametrics
        namespace: flux-system
  values:
    grafana:
      enabled: false
    kube-state-metrics:
      enabled: false
    prometheus-node-exporter:
      enabled: false
    vmsingle:
      spec:
        retentionPeriod: 90d
        nodeSelector:
          kubernetes.io/hostname: oracle-in-arm1
        storage:
          storageClassName: local-path
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 15Gi
```

Check it works:

```bash
kubectl -n monitoring get vmsingle
kubectl -n monitoring get vmservicescrape   # should list immich, garage, cloudflared, traefik
kubectl -n monitoring get vmpodscrape
```

The operator converts ServiceMonitors → VMServiceScrapes automatically, so nothing in the
app folders changes. If a scrape is missing you'll see it here — fix it while the old
stack still works.

## Phase 2 — Add logs (1 day)

1. Deploy VictoriaLogs (`VLSingle`) in the same folder — pinned to `oracle-in-arm1`,
   retention 30 days, ~15Gi PVC.
2. Deploy the `victoria-logs-collector` chart. It runs `vlagent` as a DaemonSet on every
   node. Add a `tiny` toleration so the micro nodes are covered; each pod costs ~64Mi.
3. Add the `victoriametrics-logs-datasource` plugin to Grafana and a VictoriaLogs
   datasource pointing at the `VLSingle` service.

Check: open Grafana → Explore → VictoriaLogs → container logs should be streaming from
every node.

Note: this covers container logs. Host logs (journald: kernel, sshd, k3s itself) aren't
included — vlagent can't read journald yet. Add that later from just `s145` and the two
ARM hosts if you need it.

## Phase 3 — Compare, then switch (about a week)

1. Add VictoriaMetrics as a second Grafana datasource (not the default yet).
2. Open the same dashboards against both datasources for a few days. Numbers should
   match. Empty panels mean a scrape that didn't convert — investigate here, where the
   old stack still has the data.
3. When you're satisfied: make VictoriaMetrics the default datasource. Keep Prometheus
   running.
4. Drop Prometheus retention to 2 days — a rollback window with data, without keeping
   15 days.

## Phase 4 — Remove Prometheus (half a day, order matters)

1. **FIRST:** turn kube-state-metrics and node-exporter back **on** in the VM chart
   (they've been off the whole time). Wait until they're healthy.
2. Remove the kube-prometheus-stack HelmRelease.
3. Keep the Prometheus CRDs (ServiceMonitor, PodMonitor, …) installed — the VM operator
   still reads them to do the conversion. Hand ownership to the VM chart, or just leave
   them; do not delete them.
4. Final check: `kubectl -n monitoring get pods` — all healthy, dashboards populated,
   alerts still firing.

## Rollback

Anything look wrong during Phase 3 or 4? Set Prometheus back as the default datasource.
The old stack isn't deleted until the last step, and even then its data lives for the
2-day retention window.

## Rules to not break

- **Never** enable converter ownership — it deletes your new scrapes the moment the old
  stack is removed.
- **Never** run two node-exporter DaemonSets — the 1GB micro nodes can't take it.
- **Never** delete the Prometheus CRDs — conversion silently stops.
- Pin versions, and read the chart's `values.yaml` at your pinned version before applying.
  Value names have moved between releases.
