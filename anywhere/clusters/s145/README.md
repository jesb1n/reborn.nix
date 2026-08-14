# s145 Flux registrations

Flux Operator syncs `refs/heads/main` from this repository and reads this
directory as its cluster path. Each YAML file registers a Flux
`Kustomization` whose resources live under `anywhere/k8s/`.

## Registered resources

| Kustomization | Source path | Dependency | SOPS decryption |
| --- | --- | --- | --- |
| `infra` | `anywhere/k8s/_infra` | none | no |
| `cloudflared` | `anywhere/k8s/cloudflared` | `infra` | yes |
| `garage` | `anywhere/k8s/garage` | `infra` | yes |
| `immich` | `anywhere/k8s/immich` | `infra` | yes |
| `immich-public-proxy` | `anywhere/k8s/immich-public-proxy` | `immich` | no |
| `litellm` | `anywhere/k8s/litellm` | `infra` | yes |
| `monitoring` | `anywhere/k8s/monitoring` | `infra` | yes |
| `vaultwarden` | `anywhere/k8s/vaultwarden` | `infra` | no |

The `FluxInstance` in `anywhere/operator/flux-instance.yaml` defines the Git
source, branch, interval, and this cluster path. Adding a directory below
`anywhere/k8s/` does not deploy it until a registration exists here.

## Validate

Inspect a registration and render its application before committing:

```bash
kubectl apply --dry-run=client -f anywhere/clusters/s145/immich.yaml
kubectl kustomize anywhere/k8s/immich
```

Encrypted manifests must include the public recipient corresponding to
`Secret/flux-system/sops-age`. Never commit that Secret or its private age key.

## Reconcile

Flux observes changes on `main`. To inspect status:

```bash
flux get sources git -n flux-system
flux get kustomizations -n flux-system
```

After a reviewed change is committed and pushed, an operator may request an
immediate reconciliation:

```bash
flux reconcile kustomization immich -n flux-system --with-source
```

Reconciliation changes the live cluster. Do not use direct `kubectl apply` for
resources owned by these Kustomizations; Flux will restore the Git state.
