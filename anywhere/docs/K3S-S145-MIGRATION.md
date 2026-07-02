# K3s cluster migration to s145 (control-plane)

One-time runbook capturing the migration from the `oracle-eu-arm1`-rooted
cluster to a new `s145`-rooted cluster. Use as a reference if you ever need
to redo any of these steps.

Status as of completion of this doc: **cluster is up, traefik is ready,
ACME staging is configured. Application workloads are not yet deployed.**

## New architecture

| Host             | Tailscale IP     | Role                              | Notes                                            |
| ---------------- | ---------------- | --------------------------------- | ------------------------------------------------ |
| `s145`           | `100.69.231.117` | **k3s control-plane** + workloads | Home server, 1 TB HDD at `/home/duck/sda`        |
| `oracle-eu-arm1` | `100.84.230.4`   | agent (general worker)            | Oracle A1.Flex, 4 OCPU / 24 GB, disposable       |
| `oracle-eu-micro1` | `100.96.237.114` | agent (tainted `tiny=true`)     | Oracle E2.1.Micro, 1 OCPU / 1 GB, disposable     |
| `oracle-eu-micro2` | `100.67.95.26`   | agent (tainted `tiny=true`)     | Oracle E2.1.Micro, 1 OCPU / 1 GB, disposable     |

Design intent:

- **s145 holds critical data** (1 TB XFS at `/home/duck/sda`). Loss of an
  Oracle VM degrades capacity but does not lose data.
- **Single control plane** by choice — etcd HA needs 3 servers, and the
  Oracle hosts are too disposable to be quorum members. State backups via
  scheduled SQLite dump are the resilience strategy for the CP.
- **Cluster traffic is on `tailscale0`** (`--flannel-iface=tailscale0`).
- **Traefik is the only ingress controller**, with built-in ACME (Cloudflare
  DNS-01). No cert-manager.

## What touched config

NixOS modules:

- `profiles/k3s-server.nix` — Traefik kept enabled (default ingress).
- `profiles/k3s-agent.nix` — generic agent, points `serverAddr` at s145.
- `profiles/k3s-agent-tiny.nix` — layer that adds `max-pods=10` + zramSwap
  for 1 GB micros.
- `hosts/s145/configuration.nix` — imports `k3s-server.nix`, sets
  `nodeName`/`nodeIP`.
- `hosts/s145/sops.nix` — declares `k3s-token` + `cloudflare-dns-api-token`;
  renders Traefik's CF Secret YAML straight into `/var/lib/rancher/k3s/server/manifests/`.
- `hosts/s145/traefik.nix` — `HelmChartConfig` overriding the chart with
  Cloudflare ACME resolver, persistence on `local-path`, node-pinned to
  s145, global HTTP→HTTPS redirect at the `web` entrypoint.
- `hosts/oracle-eu-arm1/configuration.nix` — switched from `k3s-server.nix`
  → `k3s-agent.nix`.
- `hosts/oracle-eu-micro1/`, `hosts/oracle-eu-micro2/configuration.nix` —
  switched from `k3s-agent.nix` → `k3s-agent-tiny.nix`.

SOPS:

- `.sops.yaml` — added `s145_host` to the `secrets/k3s/.*` recipient group.
- `secrets/k3s/secrets.yaml` — re-encrypted to include s145.
- `secrets/s145/secrets.yaml` — added `cloudflare-dns-api-token` (scoped
  CF token with `Zone:DNS:Edit` + `Zone:Zone:Read`).

App scaffolding (manual `kubectl apply`, NOT k3s auto-deploy):

- `k8s/README.md`
- `k8s/_infra/security-headers.yaml`
- `k8s/vaultwarden/{namespace,deployment,service,pvc,ingressroute}.yaml`
- `k8s/immich/{README.md,ingressroute.yaml}` — workload is via upstream Helm chart

## Migration steps executed

```bash
cd anywhere

# 1. Deploy the new control plane.
nix develop -c deploy .#s145

# 2. Verify s145 is healthy.
ssh duck@s145 'sudo k3s kubectl get nodes -o wide'
ssh duck@s145 'sudo ss -tlnp | grep 6443'
ssh duck@s145 'sudo k3s kubectl -n kube-system get pods'
ssh duck@s145 'sudo k3s kubectl -n kube-system get secret traefik-cloudflare'
ssh duck@s145 'sudo k3s kubectl -n kube-system get helmchartconfig traefik -o yaml | head -40'
ssh duck@s145 'sudo k3s kubectl -n kube-system get pvc'
ssh duck@s145 'sudo k3s kubectl -n kube-system wait --for=condition=Ready pod -l app.kubernetes.io/name=traefik --timeout=180s'
ssh duck@s145 'sudo k3s kubectl -n kube-system logs deploy/traefik | grep -iE "acme|cloudflare|entrypoint"'

# 3. Wipe stale k3s state on each Oracle host so they can join the new cluster.
for h in oracle-eu-arm1 oracle-eu-micro1 oracle-eu-micro2; do
  echo "=== wiping $h ==="
  ssh "duck@$h" '
    sudo systemctl stop k3s 2>/dev/null || true
    sudo k3s-killall.sh 2>/dev/null || true
    sudo rm -rf /var/lib/rancher/k3s /etc/rancher/k3s
  '
done

# 4. Deploy the agents.
nix develop -c deploy .#oracle-eu-arm1
ssh duck@s145 'sudo k3s kubectl get nodes'
nix develop -c deploy --targets .#oracle-eu-micro1 .#oracle-eu-micro2
ssh duck@s145 'sudo k3s kubectl get nodes -o wide'
# expect: all four Ready
```

## Pending work (pick up here)

### 1. Apply the `tiny` taint on micros

The taint isn't declared in Nix (kubelet flag is, but node taints are
applied via kubectl per MAINTENANCE.md convention). Re-apply after every
cluster rebuild:

```bash
ssh duck@s145 'sudo k3s kubectl taint node oracle-eu-micro1 tiny=true:NoSchedule --overwrite'
ssh duck@s145 'sudo k3s kubectl taint node oracle-eu-micro2 tiny=true:NoSchedule --overwrite'
ssh duck@s145 'sudo k3s kubectl get nodes -o custom-columns=NAME:.metadata.name,TAINTS:.spec.taints'
```

### 2. Apply cluster-wide middleware + app manifests

```bash
ssh duck@s145 'sudo k3s kubectl apply -f -' < anywhere/k8s/_infra/security-headers.yaml

for f in anywhere/k8s/vaultwarden/*.yaml; do
  echo "=== applying $f ==="
  ssh duck@s145 'sudo k3s kubectl apply -f -' < "$f"
done

ssh duck@s145 'sudo k3s kubectl -n vaultwarden get pods,pvc,ingressroute'
```

### 3. DNS records in Cloudflare

For each app, point an A/AAAA record at whichever public IP terminates
traffic. Suggested:

```
v1.beijns.eu.org   A   <s145 public IP>
i1.beijns.eu.org   A   <s145 public IP>
```

DNS-01 ACME does not need inbound :80/:443, only outbound to Cloudflare's
API + a DNS resolver.

### 4. Verify staging certificate issuance

Hit `https://v1.beijns.eu.org` — browsers will warn because the cert is from
Let's Encrypt **Staging**. That warning is the success signal. Tail traefik
logs while you do this:

```bash
ssh duck@s145 'sudo k3s kubectl -n kube-system logs -f deploy/traefik | grep -iE "vault|acme|certificate"'
```

### 5. Promote ACME to production CA

Once staging is confirmed working:

1. In `hosts/s145/traefik.nix`, remove the `caserver` argument (or change
   to `https://acme-v02.api.letsencrypt.org/directory`).
2. `nix develop -c deploy .#s145`
3. Force fresh issuance:
   ```bash
   ssh duck@s145 'sudo k3s kubectl -n kube-system exec deploy/traefik -- rm /data/acme.json'
   ssh duck@s145 'sudo k3s kubectl -n kube-system rollout restart deploy/traefik'
   ```

### 6. Immich

Follow `k8s/immich/README.md`. Immich is managed through Flux using the
upstream Helm chart plus repo-owned Kubernetes manifests for Postgres, Valkey,
PVCs, SOPS credentials, and Traefik routing.

Keep Traefik middleware namespace-local: the Immich `IngressRoute` must
reference `security-headers` in the `immich` namespace, not
`kube-system/security-headers`.

## Standing concerns (not done, worth doing soon)

1. **Backups.** s145's HDD is one disk, no RAID. Vaultwarden + Immich +
   k3s SQLite state all live there. Schedule Restic/Borg → off-host.
2. **k3s state snapshot.** No automatic snapshot of `/var/lib/rancher/k3s/server/db/state.db`.
   Weekly systemd-timer dumping to `/home/duck/sda/backups/k3s/` is enough.
3. **`nofail` mount risk.** If the HDD fails to mount, the empty mountpoint
   stub at `/home/duck/sda` is root-owned `0755`. Kubelet (root) *can*
   write into it, which would put PVC data on root FS instead of failing
   loudly. Either chmod 0000 the stub or add `RequiresMountsFor=/home/duck/sda`
   to the k3s unit.
4. **CI workflow** (`docs/CICD.md`) was not re-verified after the
   `.sops.yaml` recipient change. Run a CI deploy to confirm it still
   decrypts `secrets/k3s/secrets.yaml`.

## Rollback (in case anything goes wrong)

This migration deleted state on all four hosts. There is no "rollback to
the previous cluster" — that cluster is gone. The recovery path is:

1. Re-run the migration steps above (idempotent on s145, destructive on
   agents).
2. Re-apply application manifests from `anywhere/k8s/` and any out-of-band
   workloads.

If s145 itself is the problem and you want to put the CP back on arm1:
revert the `imports` lines in `hosts/oracle-eu-arm1/configuration.nix`
(swap `k3s-agent.nix` → `k3s-server.nix`), revert the `serverAddr` in
`profiles/k3s-agent.nix`, redeploy.
