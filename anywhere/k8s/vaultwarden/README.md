# Vaultwarden

Fresh Vaultwarden install for the k3s cluster.

## What This Creates

- `Namespace`: `vaultwarden`
- `PersistentVolumeClaim`: `vaultwarden-data`, mounted at `/data`
- `Deployment`: one Vaultwarden pod, pinned to `s145`
- `Service`: internal HTTP service for Traefik
- `Middleware`: security headers for this namespace
- `IngressRoute`: public HTTPS route at `v1.beijns.eu.org`

This uses Vaultwarden's default SQLite database, so keep `replicas: 1`.

## Apply

```bash
kubectl apply -f anywhere/k8s/vaultwarden/
kubectl -n vaultwarden rollout status deploy/vaultwarden
```

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

```bash
docker run --rm -it vaultwarden/server:1.36.0 /vaultwarden hash
kubectl -n vaultwarden create secret generic vaultwarden-secrets \
  --from-literal=admin-token='<bcrypt-hash>'
kubectl -n vaultwarden rollout restart deploy/vaultwarden
```

## Backups

Everything important lives in the `vaultwarden-data` PVC. Back it up off `s145`
regularly; losing that PVC means losing the Vaultwarden database and attachments.
