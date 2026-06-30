# anywhere/k8s/immich/

Immich is large (server + microservices + postgres + redis + ML), so the
workload itself is deployed via the **upstream Helm chart**, not vanilla
manifests in this folder. Only the route lives here so that DNS hostnames
and TLS settings are version-controlled alongside Vaultwarden.

## Install the chart

```bash
helm repo add immich https://immich-app.github.io/immich-charts
helm repo update

# Pin chart version explicitly; never use `latest`.
helm upgrade --install immich immich/immich \
  --namespace immich --create-namespace \
  --version 0.9.4 \
  --values values.yaml
```

A starter `values.yaml` should at minimum:

- Pin every stateful component (server, postgres, redis) to s145 via
  `nodeSelector: { kubernetes.io/hostname: s145 }`.
- Use `storageClass: local-path` for all PVCs (Postgres data, library, uploads).
- **Disable the chart's bundled ingress** (`ingress.enabled: false`) — we use
  the IngressRoute in this folder instead.
- Mount the photo library onto the HDD via a `hostPath` PV: source
  `/home/duck/sda/immich/library` on s145.

## Apply the route

```bash
kubectl apply -f ingressroute.yaml
```

The route assumes the Helm chart exposes a Service named `immich-server` on
port 2283 in the `immich` namespace (the upstream chart's default). Adjust
if you rename things.
