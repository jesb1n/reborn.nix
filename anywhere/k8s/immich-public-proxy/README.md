# Immich Public Proxy

Public share frontend for Immich. Exposed via the cluster Cloudflare Tunnel
(`anywhere/k8s/cloudflared/`), not Traefik.

## What This Creates

- `Deployment` + `Service`: Immich Public Proxy (`immich-public-proxy:3000`) in
  namespace `immich`

`IMMICH_URL` points at the in-cluster Immich Service
(`http://immich-server.immich.svc.cluster.local:2283`).

## Cloudflare route (dashboard)

In the shared tunnel (**Networking → Tunnels**), add a Published application:

- Hostname: `i1-proxy.beijns.eu.org`
- Service: `http://immich-public-proxy.immich.svc.cluster.local:3000`

Also set Cloudflare Cache Rules:

- **Cache** `i1-proxy.beijns.eu.org/share/photo/*/thumbnail*` (gallery stampedes)
- **Bypass** `i1-proxy.beijns.eu.org/share/video/*` (video playback)

## Immich setting

**Server Settings → External domain** → `https://i1-proxy.beijns.eu.org`

## Concurrency note

IPP has **no** setting to limit parallel **gallery thumbnail** fetches. The only
concurrency knob is `ipp.downloadFromImmichConcurrencyLimit` (default 20), and
that applies solely to “download all” zip staging — not `/share/photo/.../thumbnail`.
Large albums can still stampede Immich; prefer Cloudflare thumbnail caching and
adequate Immich server CPU (see `anywhere/k8s/immich/values.yaml`).

## Apply (Flux)

```bash
flux reconcile kustomization immich-public-proxy -n flux-system --with-source
kubectl -n immich rollout status deploy/immich-public-proxy
curl -fsS https://i1-proxy.beijns.eu.org/share/healthcheck
```
