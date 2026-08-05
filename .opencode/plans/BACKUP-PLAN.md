# Backup Plan: Immich + Vaultwarden to Google Drive

## Goal

Off-site incremental backups of Immich (photos + database) and Vaultwarden (SQLite + attachments) to Google Drive, managed via K8up (K8s backup operator) running in the cluster.

## Architecture

```
K8up Operator (Helm chart, k8up-system namespace)
  ├── rclone serve restic Deployment (REST API :8000 → Google Drive)
  ├── Schedule: immich-backup (daily 02:00 IST)
  │     ├── preBackup hook: pg_dump for postgres consistency
  │     ├── backs up: immich-library PV (317 GB) + immich-postgres-data PV (873 MB)
  │     └── ML cache PVC annotated k8up.io/backup: "false" (skipped)
  ├── Schedule: vaultwarden-backup (daily 03:00 IST)
  │     ├── preBackup hook: sqlite3 .backup for consistency
  │     └── backs up: vaultwarden-data PVC (~4 GB)
  └── Prune: keep 7 daily, 14 weekly, 6 monthly
```

## What we're protecting

| Service | Data | Size | PV Type | Path on s145 |
|---------|------|------|---------|-------------|
| Immich library | Photos/videos | 317 GB | hostPath | `/home/duck/sda/appdata/immich-app/library` |
| Immich postgres | Database | 873 MB | hostPath | `/home/duck/sda/appdata/immich-app/postgres` |
| Vaultwarden | SQLite + attachments | ~4 GB | local-path | `/var/lib/rancher/k3s/storage/pvc-05cb62f7-*` |

## Why K8up over Velero

Velero explicitly does **not** support `hostPath` volumes (which is what k3s local-path-provisioner creates). K8up works at the PVC layer and handles hostPath natively.

## Why rclone serve restic

K8up doesn't support rclone as a restic backend natively. It only supports: S3, GCS, Azure, Swift, B2, REST, Local. Workaround: run `rclone serve restic` as a Deployment, which exposes a REST API that translates restic operations to Google Drive. K8up connects via its `rest` backend.

## Pre-requisites (manual, one-time)

1. **Google Drive OAuth token** — run `rclone config` on pro-darwin
2. **Restic repo password** — `openssl rand -base64 48`
3. **Google Drive storage** — need paid plan (317 GB > 15 GB free tier)

---

## Files to create (11 new)

### 1. `anywhere/clusters/s145/k8up.yaml` — Flux Kustomization

```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: k8up
  namespace: flux-system
spec:
  interval: 3m
  retryInterval: 1m
  timeout: 5m
  dependsOn:
    - name: infra
  sourceRef:
    kind: GitRepository
    name: flux-system
  decryption:
    provider: sops
    secretRef:
      name: sops-age
  path: ./anywhere/k8s/k8up
  prune: true
  wait: true
```

### 2. `anywhere/k8s/k8up/kustomization.yaml`

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - namespace.yaml
  - helmrepository.yaml
  - helmrelease.yaml
  - rclone-secret.yaml
  - rclone-deployment.yaml
  - rclone-service.yaml
  - backup-secret.yaml
```

### 3. `anywhere/k8s/k8up/namespace.yaml`

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: k8up-system
```

### 4. `anywhere/k8s/k8up/helmrepository.yaml`

```yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: HelmRepository
metadata:
  name: k8up-io
  namespace: flux-system
spec:
  interval: 24h
  url: https://k8up-io.github.io/k8up
```

### 5. `anywhere/k8s/k8up/helmrelease.yaml`

```yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: k8up
  namespace: k8up-system
spec:
  interval: 1h
  chart:
    spec:
      chart: k8up
      sourceRef:
        kind: HelmRepository
        name: k8up-io
        namespace: flux-system
      interval: 1h
      version: "4.10.0"
  install:
    crds: CreateReplace
  upgrade:
    crds: CreateReplace
  values:
    replicaCount: 1
    k8up:
      enableLeaderElection: true
      skipWithoutAnnotation: false
      timezone: "Asia/Kolkata"
    resources:
      requests:
        cpu: 20m
        memory: 128Mi
      limits:
        memory: 256Mi
```

### 6. `anywhere/k8s/k8up/rclone-deployment.yaml`

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: rclone-serve
  namespace: k8up-system
  labels:
    app: rclone-serve
spec:
  replicas: 1
  strategy:
    type: Recreate
  selector:
    matchLabels:
      app: rclone-serve
  template:
    metadata:
      labels:
        app: rclone-serve
    spec:
      nodeSelector:
        kubernetes.io/hostname: s145
      containers:
        - name: rclone
          image: rclone/rclone:1.69.2
          env:
            - name: RCLONE_CONFIG
              value: /config/rclone
          command:
            - rclone
            - serve
            - restic
            - --addr
            - ":8000"
            - --verbose
            - --server-read-timeout
            - "24h"
            - --server-write-timeout
            - "24h"
            - gdrive:k8up-backups
          ports:
            - containerPort: 8000
              name: rest
          readinessProbe:
            tcpSocket:
              port: rest
            initialDelaySeconds: 5
            periodSeconds: 10
          livenessProbe:
            tcpSocket:
              port: rest
            initialDelaySeconds: 10
            periodSeconds: 30
          resources:
            requests:
              cpu: 50m
              memory: 64Mi
            limits:
              memory: 128Mi
          volumeMounts:
            - name: rclone-config
              mountPath: /config/rclone
              readOnly: true
      volumes:
        - name: rclone-config
          secret:
            secretName: rclone-config
```

### 7. `anywhere/k8s/k8up/rclone-service.yaml`

```yaml
apiVersion: v1
kind: Service
metadata:
  name: rclone-serve
  namespace: k8up-system
spec:
  selector:
    app: rclone-serve
  ports:
    - name: rest
      port: 8000
      targetPort: rest
```

### 8. `anywhere/k8s/k8up/rclone-secret.yaml` (SOPS-encrypted)

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: rclone-config
  namespace: k8up-system
type: Opaque
stringData:
  rclone.conf: |
    [gdrive]
    type = drive
    scope = drive
    token = <REPLACE_AFTER_RCLONE_CONFIG>
```

### 9. `anywhere/k8s/k8up/backup-secret.yaml` (SOPS-encrypted)

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: backup-repo
  namespace: k8up-system
type: Opaque
stringData:
  password: <REPLACE_WITH_GENERATED_PASSWORD>
```

### 10. `anywhere/k8s/immich/k8up-schedule.yaml` (SOPS-encrypted)

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: backup-repo
  namespace: immich
type: Opaque
stringData:
  password: <SAME_PASSWORD_AS_ABOVE>
---
apiVersion: k8up.io/v1
kind: Schedule
metadata:
  name: immich-backup
  namespace: immich
spec:
  backend:
    repoPasswordSecretRef:
      name: backup-repo
      key: password
    rest:
      url: "http://rclone-serve.k8up-system:8000/immich/"
  backup:
    schedule: "0 2 * * *"
    failedJobsHistoryLimit: 3
    successfulJobsHistoryLimit: 3
    activeDeadlineSeconds: 259200
  check:
    schedule: "0 4 * * 0"
  prune:
    schedule: "0 5 * * 0"
    retention:
      keepLast: 3
      keepDaily: 14
      keepWeekly: 8
      keepMonthly: 6
```

### 11. `anywhere/k8s/vaultwarden/k8up-schedule.yaml` (SOPS-encrypted)

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: backup-repo
  namespace: vaultwarden
type: Opaque
stringData:
  password: <SAME_PASSWORD_AS_ABOVE>
---
apiVersion: k8up.io/v1
kind: Schedule
metadata:
  name: vaultwarden-backup
  namespace: vaultwarden
spec:
  backend:
    repoPasswordSecretRef:
      name: backup-repo
      key: password
    rest:
      url: "http://rclone-serve.k8up-system:8000/vaultwarden/"
  backup:
    schedule: "0 3 * * *"
    failedJobsHistoryLimit: 3
    successfulJobsHistoryLimit: 3
    activeDeadlineSeconds: 3600
  check:
    schedule: "0 4 * * 0"
  prune:
    schedule: "0 5 * * 0"
    retention:
      keepLast: 5
      keepDaily: 14
      keepWeekly: 8
      keepMonthly: 6
```

---

## Files to modify (8 existing)

### 1. `anywhere/clusters/s145/immich.yaml` — add dependsOn

```yaml
spec:
  dependsOn:
    - name: infra
    - name: k8up        # <-- ADD
```

### 2. `anywhere/clusters/s145/vaultwarden.yaml` — add dependsOn + SOPS

```yaml
spec:
  dependsOn:
    - name: infra
    - name: k8up        # <-- ADD
  decryption:             # <-- ADD
    provider: sops        # <-- ADD
    secretRef:            # <-- ADD
      name: sops-age      # <-- ADD
```

### 3. `anywhere/k8s/immich/kustomization.yaml` — add schedule

Add to resources list:
```yaml
  - k8up-schedule.yaml   # <-- ADD
```

### 4. `anywhere/k8s/immich/postgres.yaml` — add backup annotations

Add to `spec.template.metadata` (pod template):
```yaml
  template:
    metadata:
      labels:
        app.kubernetes.io/name: immich-postgres
      annotations:                            # <-- ADD
        k8up.io/backupcommand: >-             # <-- ADD
          sh -c 'PGDATABASE="$POSTGRES_DB" PGUSER="$POSTGRES_USER"
          PGPASSWORD="$POSTGRES_PASSWORD" pg_dump --clean'   # <-- ADD
        k8up.io/file-extension: .sql          # <-- ADD
```

### 5. `anywhere/k8s/immich/pvc.yaml` — skip ML cache

Add annotation to `immich-machine-learning-cache` PVC:
```yaml
  metadata:
    name: immich-machine-learning-cache
    namespace: immich
    annotations:                              # <-- ADD
      k8up.io/backup: "false"                # <-- ADD
```

### 6. `anywhere/k8s/vaultwarden/deployment.yaml` — add backup annotations

Add to `spec.template.metadata` (pod template):
```yaml
  template:
    metadata:
      labels:
        app: vaultwarden
      annotations:                            # <-- ADD
        k8up.io/backupcommand: >-             # <-- ADD
          sh -c 'sqlite3 /data/db.sqlite3 ".backup /dev/stdout"'  # <-- ADD
        k8up.io/file-extension: .sqlite3      # <-- ADD
```

### 7. `anywhere/k8s/vaultwarden/kustomization.yaml` — create new

Currently doesn't exist. Create:
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - namespace.yaml
  - deployment.yaml
  - service.yaml
  - pvc.yaml
  - ingressroute.yaml
  - security-headers.yaml
  - k8up-schedule.yaml
```

### 8. `anywhere/.sops.yaml` — add k8up creation rules

Append after existing `k8s/garage/garage-secret.yaml` rule:
```yaml
  - path_regex: k8s/k8up/.*
    encrypted_regex: "^(data|stringData)$"
    key_groups:
      - age:
          - *pro_darwin
          - *mark
          - *s145_cluster

  - path_regex: k8s/immich/k8up-schedule.yaml
    encrypted_regex: "^(data|stringData)$"
    key_groups:
      - age:
          - *pro_darwin
          - *mark
          - *s145_cluster

  - path_regex: k8s/vaultwarden/k8up-schedule.yaml
    encrypted_regex: "^(data|stringData)$"
    key_groups:
      - age:
          - *pro_darwin
          - *mark
          - *s145_cluster
```

---

## Deployment order

1. Add SOPS creation rules to `.sops.yaml`
2. Run `rclone config` on pro-darwin → get OAuth token
3. Generate restic repo password
4. Create `rclone-secret.yaml` and `backup-secret.yaml` (SOPS-encrypted)
5. Create all K8up manifests
6. Create backup Schedule CRs + per-namespace `backup-repo` secrets
7. Modify existing files (annotations, dependsOn, kustomization)
8. Create vaultwarden `kustomization.yaml`
9. `git add` all files
10. Commit and push → Flux reconciles
11. Verify: `kubectl -n k8up-system get pods`, check rclone + operator running
12. Trigger manual backup test
13. Monitor first full backup (317 GB, expected 1-2 days)

## Verification commands

```bash
# Check K8up operator
kubectl -n k8up-system get pods

# Check rclone serve
kubectl -n k8up-system get pods -l app=rclone-serve
kubectl -n k8up-system logs -l app=rclone-serve

# Check schedules
kubectl -n immich get schedules
kubectl -n vaultwarden get schedules

# Trigger manual backup
kubectl -n immich create -f - <<'EOF'
apiVersion: k8up.io/v1
kind: Backup
metadata:
  name: immich-manual-test
  namespace: immich
spec:
  backend:
    repoPasswordSecretRef:
      name: backup-repo
      key: password
    rest:
      url: "http://rclone-serve.k8up-system:8000/immich/"
  failedJobsHistoryLimit: 1
EOF

# Check backup status
kubectl -n immich get backups -w

# Verify Google Drive contents (from pro-darwin)
rclone ls gdrive:k8up-backups/
```

## Key considerations

- **Google Drive storage**: 317 GB library needs a paid Google One plan
- **Upload rate limit**: 750 GB/day Google Drive limit (not a concern for incremental backups)
- **First backup**: 317 GB at 10 Mbps ≈ 3 days; set `activeDeadlineSeconds: 259200` (3 days)
- **Subsequent backups**: incremental (only changed blocks via restic dedup), minutes to hours
- **restic repo password**: store outside cluster (password manager + printed copy)
- **No NixOS changes needed**: everything runs inside K8s
- **rclone token refresh**: automatic; re-authorize if Google Cloud app stays in "testing" mode
