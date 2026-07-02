# s145 Flux Cluster

Flux bootstraps this cluster from `anywhere/clusters/s145`.

## Capacitor

Capacitor is installed as a Flux-managed dashboard in the `flux-system`
namespace. It is intentionally not exposed through a public IngressRoute.

Access it with a private `kubectl` port-forward:

```bash
kubectl -n flux-system port-forward svc/capacitor 9000:9000
```

Then open:

```text
http://localhost:9000
```

Do not expose Capacitor publicly without authentication. If remote browser
access is needed later, prefer a private path such as Tailscale-only access or
an internal/private Traefik route protected by an authenticated forward-auth
provider.
