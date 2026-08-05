# Kubernetes MCP Viewer — Implementation Plan

Read-only Kubernetes MCP server for AI tooling (OpenCode, Claude Code, Cursor, VS Code Copilot, etc.).

Give AI agents rich, safe context on the `s145` k3s cluster without any cluster-side footprint and without exposing Secrets.

**Status:** planned, not executed. This is the source-of-truth to hand back to any agent to execute.

## Goal

Enable any MCP-capable AI tool running on `pro-darwin` (or any other laptop that later gains the same setup) to query the k3s cluster with a dedicated, least-privilege identity — so the model can reason about the cluster state (nodes, pods, workloads, events, CRs, Helm releases) without cluster-admin credentials and without ever seeing Secret material.

## Non-goals

- No in-cluster AI operator (k8sgpt / HolmesGPT / kagent). Separate future project.
- No HTTP-mode / cluster-hosted MCP endpoint. Solo single-user local stdio is right for this homelab.
- No secret access at any layer.
- No write access at any layer.

---

## Locked-in decisions

| Decision | Choice | Rationale |
|---|---|---|
| MCP implementation | [`containers/kubernetes-mcp-server`](https://github.com/containers/kubernetes-mcp-server) | Under Red Hat's `containers` org (Podman/Buildah umbrella). 1.8k stars, Apache-2.0, actively maintained. Native Go client — no `kubectl`/`helm` shell-outs → low latency, no Node/Python runtime required. Ships single binary + npm + PyPI + OCI + Helm chart. Has `--read-only`, `--disable-destructive`, `--toolsets`, TOML `denied_resources`, OIDC (HTTP mode). |
| Authentication | Long-lived `kubernetes.io/service-account-token` Secret | Never expires; zero rotation burden for a solo homelab. Legacy but supported. TokenRequest (24h max) would need a launchd rotator — not worth the complexity here. |
| Install method on `pro-darwin` | Nix derivation using `fetchurl` on upstream `darwin-arm64` release binary | Reproducible, offline after fetch, no Node runtime pollution. Matches the `gke-gcloud-auth-plugin` precedent in `darwin-configuration.nix`. Not in nixpkgs (checked). |
| OpenCode config scope | Repo-scoped `oracle-cloud-free-tier/opencode.json` | Loads MCP only when opencode runs in this workspace. Avoids context bloat and unnecessary connections in unrelated projects. |
| RBAC breadth | Custom `ClusterRole` — `get/list/watch` on all resources **except `secrets`** | Built-in `view` omits `nodes`, `persistentvolumes`, `storageclasses`, `customresourcedefinitions`, RBAC, metrics — all things we need for AI diagnostic quality. Excluding `secrets` gives defense in depth alongside client-side `denied_resources`. |

---

## Architecture summary

```
┌─────────────── pro-darwin (MacBook) ───────────────┐
│                                                    │
│   OpenCode (this repo workspace)                   │
│      └── reads oracle-cloud-free-tier/opencode.json│
│           └── spawns kubernetes-mcp-server (stdio) │
│                └── --kubeconfig ~/.kube/mcp-viewer.kubeconfig
│                     └── --read-only                │
│                     └── --disable-multi-cluster    │
│                     └── --toolsets core,config,helm│
└──────────────────────┬─────────────────────────────┘
                       │ HTTPS over Tailscale
                       ▼
       https://100.69.231.117:6443  (s145 k3s API)
                       │
                       │ authenticated as
                       │ system:serviceaccount:mcp-system:mcp-viewer
                       ▼
   RBAC: ClusterRole/mcp-viewer  (get/list/watch, ex-Secrets)
```

Zero pods, zero PVCs, zero node load. Only API traffic when the AI actively queries.

---

## Deliverables

### A. Flux-managed cluster manifests

New Flux `Kustomization` following the existing per-app pattern:

**`anywhere/clusters/s145/mcp-viewer.yaml`** (new)
```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: mcp-viewer
  namespace: flux-system
spec:
  interval: 10m
  path: ./anywhere/k8s/mcp-viewer
  prune: true
  dependsOn:
    - name: infra
  sourceRef:
    kind: GitRepository
    name: flux-system
```

**`anywhere/k8s/mcp-viewer/`** (new directory)

Files:

- `kustomization.yaml` — bundles the resources below
- `namespace.yaml` — `mcp-system` Namespace
- `serviceaccount.yaml` — `mcp-viewer` ServiceAccount in `mcp-system`
- `clusterrole.yaml` — `mcp-viewer` ClusterRole (rules detailed below)
- `clusterrolebinding.yaml` — binds ClusterRole → SA
- `token-secret.yaml` — `type: kubernetes.io/service-account-token` with `annotations.kubernetes.io/service-account.name: mcp-viewer`. Kubernetes auto-populates `.data.token`.

**ClusterRole rule outline** (final resource list to be confirmed against `kubectl api-resources` at execution time):

- Rule 1 — core `""` group, `["get","list","watch"]` on:
  `pods, services, configmaps, endpoints, events, limitranges, namespaces, nodes, persistentvolumeclaims, persistentvolumes, replicationcontrollers, resourcequotas, serviceaccounts, pods/log, pods/status, nodes/stats, nodes/proxy`
  **Secrets omitted deliberately** (RBAC is deny-by-default).
- Rule 2 — `["*"]` in these groups: `apps, batch, networking.k8s.io, storage.k8s.io, rbac.authorization.k8s.io, policy, autoscaling, apiextensions.k8s.io, admissionregistration.k8s.io, coordination.k8s.io, discovery.k8s.io, metrics.k8s.io, node.k8s.io, scheduling.k8s.io, flowcontrol.apiserver.k8s.io`
- Rule 3 — Flux / Traefik / cert-manager / k3s CRDs: `["*"]` in `traefik.io, helm.cattle.io, kustomize.toolkit.fluxcd.io, source.toolkit.fluxcd.io, helm.toolkit.fluxcd.io, notification.toolkit.fluxcd.io, image.toolkit.fluxcd.io, cert-manager.io, k3s.cattle.io`
- Rule 4 — `nonResourceURLs`: `/healthz, /version, /api, /api/*, /apis, /apis/*, /metrics`

If new CRD groups are added to the cluster later (e.g., prometheus-operator), append their group to Rule 3 and Flux will reconcile.

### B. Local token extraction + kubeconfig (off-git, one-shot)

Run once on `pro-darwin` after Flux reconciles the manifests:

```bash
# 1. Extract the auto-populated token
TOKEN=$(kubectl -n mcp-system get secret mcp-viewer-token \
  -o jsonpath='{.data.token}' | base64 -d)

# 2. Extract the cluster CA (embed it for portability)
CA=$(kubectl config view --raw --minify \
  -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')

# 3. Build the kubeconfig
umask 077
cat > ~/.kube/mcp-viewer.kubeconfig <<EOF
apiVersion: v1
kind: Config
clusters:
- name: s145
  cluster:
    server: https://100.69.231.117:6443
    certificate-authority-data: ${CA}
users:
- name: mcp-viewer
  user:
    token: ${TOKEN}
contexts:
- name: mcp-viewer@s145
  context:
    cluster: s145
    user: mcp-viewer
    namespace: default
current-context: mcp-viewer@s145
EOF
chmod 600 ~/.kube/mcp-viewer.kubeconfig
```

**Verify:**
```bash
kubectl --kubeconfig ~/.kube/mcp-viewer.kubeconfig auth can-i list pods -A            # → yes
kubectl --kubeconfig ~/.kube/mcp-viewer.kubeconfig auth can-i get secrets -A          # → no
kubectl --kubeconfig ~/.kube/mcp-viewer.kubeconfig auth can-i create pods -A          # → no
kubectl --kubeconfig ~/.kube/mcp-viewer.kubeconfig get nodes,pods -A                  # → returns data
```

### C. Nix derivation on `pro-darwin`

**`anywhere/hosts/pro-darwin/pkgs/kubernetes-mcp-server.nix`** (new)
```nix
{ lib, stdenvNoCC, fetchurl }:

stdenvNoCC.mkDerivation rec {
  pname = "kubernetes-mcp-server";
  version = "<PIN LATEST RELEASE>";  # e.g. 0.x.y

  src = fetchurl {
    url = "https://github.com/containers/kubernetes-mcp-server/releases/download/v${version}/kubernetes-mcp-server-darwin-arm64";
    hash = "sha256-<PIN>";
  };

  dontUnpack = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 $src $out/bin/kubernetes-mcp-server
    runHook postInstall
  '';

  meta = with lib; {
    description = "MCP server for Kubernetes and OpenShift (native Go client)";
    homepage = "https://github.com/containers/kubernetes-mcp-server";
    license = licenses.asl20;
    platforms = [ "aarch64-darwin" ];
    mainProgram = "kubernetes-mcp-server";
  };
}
```

**Edit `anywhere/hosts/pro-darwin/home.nix`** — add to `home.packages`:
```nix
(callPackage ./pkgs/kubernetes-mcp-server.nix { })
```

Version/hash pinning: fetch the latest release tag at execution time; use `nix-prefetch-url --type sha256 <url>` or supply an obviously-wrong hash and let Nix report the correct one.

Gatekeeper note: `fetchurl` does not apply the `com.apple.quarantine` xattr, so the binary should run without a prompt. If it ever does, `xattr -d com.apple.quarantine $(which kubernetes-mcp-server)`.

### D. OpenCode MCP registration (repo-scoped)

**`oracle-cloud-free-tier/opencode.json`** (new — at repo root, one level above `anywhere/`)
```json
{
  "$schema": "https://opencode.ai/config.json",
  "mcp": {
    "kubernetes": {
      "type": "local",
      "command": [
        "kubernetes-mcp-server",
        "--kubeconfig", "/Users/jesbin/.kube/mcp-viewer.kubeconfig",
        "--read-only",
        "--disable-multi-cluster",
        "--toolsets", "core,config,helm"
      ],
      "enabled": true
    }
  }
}
```

Flags:
- `--read-only` — client-side refusal of writes (defense in depth over RBAC).
- `--disable-multi-cluster` — kubeconfig has one context; drops the `context` argument from every tool signature → less token spend per turn.
- `--toolsets core,config,helm` — skips `kcp`, `kiali`, `kubevirt`, `tekton`, `netobserv` (none present in this cluster).

### E. Documentation updates

- `anywhere/hosts/pro-darwin/AGENTS.md` — new "Kubernetes MCP" section (install path, kubeconfig location, what happens if the token is ever revoked).
- Root `AGENTS.md` — add subsection under a new "AI / MCP access" heading: describe the `mcp-system` namespace being Flux-managed via `anywhere/k8s/mcp-viewer/` and note the repo-scoped `opencode.json` at repo root.

---

## Execution order

Once approved to build:

1. **Recon** — `kubectl api-resources -o wide` to confirm active CRD groups; adjust Rule 3 of the ClusterRole if anything is missing.
2. **Author manifests** under `anywhere/k8s/mcp-viewer/` + `anywhere/clusters/s145/mcp-viewer.yaml`.
3. `git add` the new files (Flux requires tracked files; no local eval needed for k8s YAML).
4. Push (after user confirmation per repo rules) → `flux reconcile source git flux-system && flux reconcile kustomization mcp-viewer -n flux-system --with-source`.
5. Verify RBAC objects exist and `auth can-i` matrix matches expectations.
6. Extract token, build `~/.kube/mcp-viewer.kubeconfig` (Section B).
7. Fetch latest MCP release version + sha256; write `pkgs/kubernetes-mcp-server.nix`; edit `home.nix`; `git add` before `nix flake check`.
8. `nix flake check` → `sudo darwin-rebuild build --flake .#pro-darwin` (dry) → `sudo darwin-rebuild switch --flake .#pro-darwin`.
9. Sanity: `which kubernetes-mcp-server && kubernetes-mcp-server --help`.
10. Write `oracle-cloud-free-tier/opencode.json`.
11. Restart OpenCode session in this repo; test: *"use the kubernetes tool to list nodes and any non-ready pods."*
12. Update `AGENTS.md` files (Section E).
13. Pause for explicit user confirmation before commit / push.

---

## Safety properties

- **No secret access at any layer** — RBAC omits `secrets`; MCP has no path to `resources_get(kind=Secret)` returning data (would get 403).
- **No writes at any layer** — RBAC only allows `get/list/watch`; `--read-only` also refuses at MCP layer. Attempted writes: clean 403 / client-side rejection.
- **No `exec` / `attach`** — `pods/exec` requires `create` verb, which the ClusterRole does not grant.
- **Zero cluster resource footprint** — no pods, no PVCs, no node load beyond incidental API calls.
- **Tailscale-scoped** — API server only reachable over the tailnet; MCP fails closed if Tailscale is down.
- **RBAC lives in Git** — auditable diff for any permission change. No imperative `kubectl` for the ongoing setup.

---

## Risks / caveats

- **Long-lived token on disk** at `~/.kube/mcp-viewer.kubeconfig`. Mitigated by `chmod 600` + macOS FileVault. To revoke: delete the Secret in-cluster (`kubectl -n mcp-system delete secret mcp-viewer-token`) — the token immediately stops working. Recreate via Flux to rotate.
- **CRD group drift** — new CRD groups added to the cluster later will be invisible to the AI until their group is added to the ClusterRole. Note this in AGENTS.md.
- **Nix binary unsigned by upstream** — `fetchurl` sidesteps macOS quarantine, but if Gatekeeper ever intervenes: `xattr -d com.apple.quarantine`.
- **Repo-scoped config** — MCP only loads inside `oracle-cloud-free-tier/`. To use in another workspace, either duplicate `opencode.json` there or promote to `~/.config/opencode/opencode.json`.
- **Not multi-tenant** — one identity, one kubeconfig. If a second user ever wants AI access, create a separate SA + kubeconfig; do not share this one.

---

## Related upstream references

- `containers/kubernetes-mcp-server` — https://github.com/containers/kubernetes-mcp-server
- Upstream "getting started (Kubernetes)" guide (RBAC + kubeconfig pattern) — https://github.com/containers/kubernetes-mcp-server/blob/main/docs/getting-started-kubernetes.md
- OpenCode MCP docs — https://opencode.ai/docs/mcp-servers/

## Related in-repo docs

- [`anywhere/MAINTENANCE.md`](../MAINTENANCE.md) — NixOS host operations runbook
- [`docs/ARCHITECTURE.md`](../../docs/ARCHITECTURE.md) — full infrastructure diagram
- [root `AGENTS.md`](../../AGENTS.md) — repo-wide agent rules
- [`anywhere/hosts/pro-darwin/AGENTS.md`](../hosts/pro-darwin/AGENTS.md) — Mac host rules
