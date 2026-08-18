# Vaultwarden

Vaultwarden deployment for the k3s cluster. Flux owns this directory through
[`../../clusters/s145/vaultwarden.yaml`](../../clusters/s145/vaultwarden.yaml)
and reconciles it after changes reach `main`.

## What This Creates

- `Namespace`: `vaultwarden`
- `PersistentVolumeClaim`: `vaultwarden-data`, mounted at `/data`
- `Deployment`: one Vaultwarden pod (`vaultwarden/server:1.37.1`), pinned to `s145`
- `Service`: internal HTTP service for Traefik
- `Middleware`: `security-headers`, same-namespace
- `IngressRoute`: public HTTPS route at `v1.beijns.eu.org`, referencing that same-namespace Middleware

This uses Vaultwarden's default SQLite database, so keep `replicas: 1`.

## Validate and reconcile

```bash
kubectl apply --dry-run=client -f anywhere/k8s/vaultwarden/
flux reconcile kustomization vaultwarden -n flux-system --with-source
kubectl -n vaultwarden rollout status deploy/vaultwarden
```

Reconciliation changes the live cluster. Commit and push reviewed changes
before requesting it; do not apply this Flux-owned directory directly.

Open:

```text
https://v1.beijns.eu.org
```

If you still need to create the first account, temporarily open signups:

```bash
kubectl -n vaultwarden set env deploy/vaultwarden SIGNUPS_ALLOWED=true
```

After creating the account, close signups again:

```bash
kubectl -n vaultwarden set env deploy/vaultwarden SIGNUPS_ALLOWED=false
```

## Optional Admin Token

The Deployment looks for an optional secret named `vaultwarden-secrets` with key
`admin-token`. If you want the `/admin` panel, create that before or after apply:

Generate the hash, then enter it through a silent prompt so it does not appear
in shell history or the process arguments:

```bash
docker run --rm -it vaultwarden/server:1.37.1 /vaultwarden hash
read -rsp 'Vaultwarden admin hash: ' ADMIN_TOKEN; echo
printf '%s' "$ADMIN_TOKEN" | kubectl -n vaultwarden create secret generic vaultwarden-secrets \
  --from-file=admin-token=/dev/stdin
unset ADMIN_TOKEN
kubectl -n vaultwarden rollout restart deploy/vaultwarden
```

The Secret is intentionally outside the Flux-managed directory. Back up the
admin hash in a password manager; never commit it or place it in command-line
arguments.

## Backups

Everything important lives in the `vaultwarden-data` PVC. Back it up off `s145`
regularly; losing that PVC means losing the Vaultwarden database and attachments.
