# Garage three-zone migration

This runbook documents the safe path from the current four-node `garage` StatefulSet to the new three-zone layout split across `garage-arm`, `garage-micro`, and `garage-onprem`.

## What is already declarative

The steady-state Kubernetes resources live in `anywhere/k8s/garage/` and are intended to be committed so Flux can reconcile them:

- `garage-arm-helm.yaml`, `garage-micro-helm.yaml`, `garage-onprem-helm.yaml`
- `values-base.yaml` plus the three class-specific override files
- shared S3 service, NodePort, PodMonitor, PDB, and Traefik route definitions
- `garage-cluster-config.yaml` with shared Garage discovery and domain settings

## What is still manual

Garage node layout is not declarative in this repo. After Flux creates the new pods, the one-time Garage CLI migration still has to be done manually:

- inspect live node IDs
- assign new nodes to `in`, `eu`, and `onprem`
- stage removal of the old `dc1` identities
- review the proposed layout version
- apply the layout once
- wait for resync completion before any cleanup

## Important warning before commit/push

Do not let Flux prune the current single `garage` HelmRelease until the new releases have joined and the manual layout migration has completed.

The current refactor proves the target steady state, but pushing it as-is to the Flux-watched branch would remove the old single release too early. The next step is to add an overlap-safe transition so old and new resources can coexist during the migration window.

## Coexistence plan

The overlap step should work like this:

- keep the current single `garage` HelmRelease active while the three new releases are introduced
- allow the old four Garage identities and the new eight identities to exist at the same time
- keep client traffic stable through the existing S3 Service and NodePort until the new identities are healthy
- avoid Helm resource collisions by using distinct release names and fullname overrides for the new StatefulSets
- keep shared discovery at `service_name = "garage"` so all nodes join one Garage cluster
- delay retirement of the old release until after layout migration and resync verification

This means the old release cannot be removed from the Flux path until after the manual layout migration is complete.

## Safe execution order

### 1. Add the overlap-safe transition

Before pushing, add or verify:

- keep the old `garage` HelmRelease in Git during the migration window using its own values file
- let the public ClusterIP service, NodePort, and PodMonitor match both old and new pods through the shared `app.kubernetes.io/name=garage` label
- keep the new steady-state cluster label `garage.cluster=primary` on the new releases only, so cleanup can later switch traffic away from the old pods cleanly
- avoid ServiceAccount collisions by letting each new Helm release create its own default release-scoped ServiceAccount instead of forcing a shared `garage` name
- an explicit final step that removes the old release only after successful resync and verification

### 2. Commit and push Git changes

Once the coexistence step is in place:

```bash
git status
git add anywhere/k8s/garage anywhere/.envrc
git commit
git push
```

Flux only reconciles committed and pushed repo content.

### 3. Reconcile Garage in Flux

```bash
flux reconcile kustomization garage -n flux-system --with-source
kubectl get pods -n garage -o wide
kubectl get garagenodes.deuxfleurs.fr -n garage
```

Expected goal at this stage: the old four identities still exist, and the new eight identities come up healthy.

### 4. Capture fresh pre-migration evidence

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

Also take an external backup of the OpenTofu state before changing the layout.

### 5. Map live node IDs to hosts

Use `garage status` and `kubectl get pods -n garage -o wide` together to build a live node map:

- `oracle-in-arm1` -> new arm node ID
- `oracle-in-micro1` -> new micro node ID
- `oracle-in-micro2` -> new micro node ID
- `oracle-eu-arm1` -> new arm node ID
- `oracle-eu-micro1` -> new micro node ID
- `oracle-eu-micro2` -> new micro node ID
- `s145` -> new on-prem node ID
- `hp348` -> new on-prem node ID

Do not reuse historical IDs from notes.

### 6. Stage the new three-zone layout

Use live IDs only:

```bash
# India
garage layout assign -z in -c 50GB -t oracle-in-arm1 <in-arm-id>
garage layout assign -z in -c 30GB -t oracle-in-micro1 <in-micro1-id>
garage layout assign -z in -c 30GB -t oracle-in-micro2 <in-micro2-id>

# Europe
garage layout assign -z eu -c 50GB -t oracle-eu-arm1 <eu-arm-id>
garage layout assign -z eu -c 30GB -t oracle-eu-micro1 <eu-micro1-id>
garage layout assign -z eu -c 30GB -t oracle-eu-micro2 <eu-micro2-id>

# On-prem
garage layout assign -z onprem -c 50GB -t s145 <s145-id>
garage layout assign -z onprem -c 50GB -t hp348 <hp348-id>
```

Then stage removal of the four old `dc1` identities using the exact CLI syntax returned by the live container's `garage layout remove --help`.

Review before apply:

```bash
garage layout show
```

Apply once:

```bash
garage layout apply --version <reviewed-version>
```

### 7. Wait for migration completion

Do not retire the old nodes yet.

Repeat until stable:

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

### 8. Verify S3 and OpenTofu

```bash
terraform -chdir=IaC state list
# or
opentofu -chdir=IaC state list
```

Also verify Traefik routing for:

- `s3.beijns.eu.org`
- `*.s3.beijns.eu.org`
- `*.s3-web.beijns.eu.org`

### 9. Cut over traffic if needed

Once the new cluster is healthy and synced, finalize selector/cutover behavior so client-facing services point only at the intended steady-state pods.

### 10. Cleanup is a separate step

Only after successful resync and verification:

- retire the old single `garage` release
- keep PVC deletion separate and explicit
- do not remove old PVCs until rollback is no longer needed

## Rollback checkpoints

- Before `layout apply`: revert staged layout changes
- After `layout apply` but during resync: keep old nodes online and stabilize
- Before PVC deletion: old data is still your rollback window
- After PVC deletion: rollback options are greatly reduced
