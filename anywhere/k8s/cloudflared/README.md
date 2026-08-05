# Cloudflare Tunnel (cloudflared)

Cluster-wide, remotely-managed Cloudflare Tunnel connector. One Deployment;
many Published application routes in the Cloudflare dashboard.

## What This Creates

- `Namespace`: `cloudflared`
- `Secret`: `tunnel-token` (SOPS) — tunnel token from the Cloudflare dashboard
- `Deployment`: `cloudflared` (2 replicas)

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
kubectl -n cloudflared rollout status deploy/cloudflared
kubectl -n cloudflared logs -l pod=cloudflared --tail=50
```

Reference: [Cloudflare Kubernetes tunnel guide](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/deployment-guides/kubernetes/)
