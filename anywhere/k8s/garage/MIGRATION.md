# Garage three-zone migration — COMPLETED

> **Status: done.** The single-release `garage` HelmRelease, its
> `garage-helm.yaml` manifest, and `values-old.yaml` were retired in commit
> `dcd482c` ("Retire legacy Garage workload"). `anywhere/k8s/garage/` now only
> declares the steady-state three-zone layout
> (`garage-arm`, `garage-micro`, `garage-onprem` HelmReleases plus
> `values-base.yaml` and the three class-specific override files). There is no
> pending overlap window and no old release left to prune.
>
> This file is kept for historical context and because the manual
> `garage layout` CLI steps below are the reference procedure the next time
> node layout needs to change (e.g. adding/removing a zone or a node). It no
> longer describes the *current* state of the cluster — read
> [`README.md`](../README.md) and the checked-in manifests in this directory
> for that.

This runbook originally documented the safe path from the legacy four-node
`garage` StatefulSet-based HelmRelease to the three-zone layout split across
`garage-arm`, `garage-micro`, and `garage-onprem`. That migration is complete;
the sections below are retained as a template for future layout changes.

## What is declarative today

The steady-state Kubernetes resources live in `anywhere/k8s/garage/` and are
committed so Flux can reconcile them:

- `garage-arm-helm.yaml`, `garage-micro-helm.yaml`, `garage-onprem-helm.yaml`
- `values-base.yaml` plus the three class-specific override files
- shared S3 `Service`, `NodePort`, `PodMonitor`, `PodDisruptionBudget`, and Traefik `IngressRoute` definitions
- `garage-cluster-config.yaml` with shared Garage discovery and domain settings

## What is still manual

Garage node layout (which physical node holds which Garage identity, and in
which zone) is **not** declarative in this repo — it lives in Garage's own
metadata, set via the `garage layout` CLI. Any future layout change (adding a
node, retiring a node, rebalancing zones) still requires the manual Garage CLI
steps below:

- inspect live node IDs
- assign nodes to their zone (`in`, `eu`, `onprem`, or whatever the target layout is)
- stage removal of any identities being retired
- review the proposed layout version
- apply the layout once
- wait for resync completion before any cleanup

## Reference procedure for a future layout change

The steps below are the general pattern used for the original migration and
apply to any future rebalance. Replace zone/node names and IDs as needed for
the change you are making.

### 1. Land the Kustomize/Helm changes first

Add or update the HelmRelease(s) and values files for the target layout in
`anywhere/k8s/garage/` and commit/push:

```bash
git status
git add anywhere/k8s/garage
git commit
git push
```

Flux only reconciles committed and pushed repo content.

### 2. Reconcile Garage in Flux

```bash
flux reconcile kustomization garage -n flux-system --with-source
kubectl get pods -n garage -o wide
kubectl get garagenodes.deuxfleurs.fr -n garage
```

Confirm the new/changed pods come up healthy before touching layout.

### 3. Capture fresh pre-migration evidence

Right before touching layout:

```bash
garage status
garage layout show
garage layout history
garage stats --all-nodes
garage bucket info tofu-backend
kubectl get pods -n garage -o wide
kubectl get pvc -n garage
```

Also take an external backup of the OpenTofu state before changing the layout,
since Garage backs the Terraform/OpenTofu S3 state bucket (`tofu-backend`).

### 4. Map live node IDs to hosts

Use `garage status` and `kubectl get pods -n garage -o wide` together to build
a live node map. Do not reuse historical IDs from old notes — Garage assigns a
fresh node ID whenever a node's Garage identity is recreated.

### 5. Stage the layout change

Use live IDs only, e.g.:

```bash
garage layout assign -z <zone> -c <capacity> -t <hostname> <node-id>
```

Then stage removal of any identities being retired using the exact CLI syntax
returned by the live container's `garage layout remove --help`.

Review before applying:

```bash
garage layout show
```

Apply once:

```bash
garage layout apply --version <reviewed-version>
```

### 6. Wait for migration completion

Do not retire any old nodes/PVCs yet. Repeat until stable:

```bash
garage layout history
garage stats --all-nodes
garage bucket info tofu-backend
```

Success criteria:

- all nodes healthy
- resync queue is zero on all nodes
- block resync errors are zero
- `tofu-backend` bucket metadata is unchanged
- S3 API still works with the existing endpoint and credentials

### 7. Verify S3 and OpenTofu

```bash
tofu -chdir=IaC state list
```

Also verify Traefik routing for:

- `s3.beijns.eu.org`
- `*.s3.beijns.eu.org`
- `*.s3-web.beijns.eu.org`

### 8. Cleanup is a separate step

Only after successful resync and verification:

- retire any old HelmRelease(s)/manifests no longer needed
- keep PVC deletion separate and explicit
- do not remove old PVCs until rollback is no longer needed

## Rollback checkpoints

- Before `layout apply`: revert staged layout changes
- After `layout apply` but during resync: keep old nodes online and stabilize
- Before PVC deletion: old data is still your rollback window
- After PVC deletion: rollback options are greatly reduced
