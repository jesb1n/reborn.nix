# Cloudflare Tunnel (cloudflared)

Cluster-wide, remotely-managed Cloudflare Tunnel connector. DaemonSet (one
pod per node); many Published application routes in the Cloudflare dashboard.

## What This Creates

- `Namespace`: `cloudflared`
- `Secret`: `tunnel-token` (SOPS) — tunnel token from the Cloudflare dashboard
- `DaemonSet`: `cloudflared` (`cloudflare/cloudflared:2026.7.3`, HTTP/2 to edge; tolerates `tiny=true:NoSchedule`)

### Why `--protocol http2`

Default QUIC (UDP 7844) fails from pod IPs on this cluster (`timeout: no recent
network activity` to `198.41.200.x`), while the same UDP check succeeds on the
node. Traffic path is flannel over Tailscale; force HTTP/2 so connectors use
TCP to Cloudflare. Soften `/ready` probes so dial retries are not SIGTERM'd at
10s (`failureThreshold: 1` was restarting healthy-but-still-connecting pods).

## Scheduling (taints vs tolerations)

Nodes do **not** carry tolerations. Tiny micros carry a **taint**; this
DaemonSet carries the matching **toleration** so it can still schedule there.

Live cluster (verify with `kubectl get nodes -o custom-columns=NAME:.metadata.name,TAINTS:.spec.taints`):

| Node | Taint |
|------|-------|
| `s145`, `hp348`, `oracle-eu-arm1`, `oracle-in-arm1`, `rpi` | none |
| `oracle-eu-micro1`, `oracle-eu-micro2`, `oracle-in-micro1`, `oracle-in-micro2` | `tiny=true:NoSchedule` |

DaemonSet toleration (in `daemonset.yaml`):

```yaml
tolerations:
  - key: tiny
    operator: Equal
    value: "true"
    effect: NoSchedule
```

Without that toleration, cloudflared would skip the micros. With it, every
Ready node (including 1 GB micros) runs a connector so the tunnel can survive
loss of larger nodes.

Note: the `tiny` taint is applied out-of-band after node join (not in NixOS);
see `profiles/k3s-agent-tiny.nix` and `MAINTENANCE.md`. Re-check and reapply
taints after cluster rebuilds or node re-registration, since the taint does
not survive that process.

Routing is **not** in these manifests. Add/remove hostnames under
**Networking → Tunnels → \<tunnel\> → Routes → Published application**.

Use FQDN ClusterIP URLs when the target is outside this namespace, e.g.:

```text
http://immich-public-proxy.immich.svc.cluster.local:3000
```

## One-time setup

1. Dashboard → **Networking → Tunnels** → Create tunnel.
2. Choose Docker; **copy only the token** (`eyJhIjoi...`).
3. Encrypt the token:

   ```bash
   export SOPS_AGE_KEY_FILE="$HOME/.config/sops/age/keys.txt"
   sops anywhere/k8s/cloudflared/tunnel-secret.yaml
   ```

4. For each public app, add a Published application route pointing at its
   ClusterIP Service.

## Apply (Flux)

```bash
flux reconcile kustomization cloudflared -n flux-system --with-source
kubectl -n cloudflared rollout status ds/cloudflared
kubectl -n cloudflared get pods -o wide
kubectl -n cloudflared logs -l pod=cloudflared --tail=50
```

Reference: [Cloudflare Kubernetes tunnel guide](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/deployment-guides/kubernetes/)
