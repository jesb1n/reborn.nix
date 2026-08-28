# OmniRoute

Private, Flux-managed OmniRoute gateway running alongside LiteLLM. The stable
`3.8.49-web` image includes Chromium for supported web-cookie providers and is
pinned to `nuc7i3` because SQLite and Redis use node-local `local-path` volumes.

## Access

Tailnet only; no public ingress or DNS is configured.

- Dashboard: `http://100.119.33.56:32128`
- OpenAI-compatible API: `http://100.119.33.56:32129`
- Live WebSocket: `ws://100.119.33.56:32132/live-ws`

Redis remains cluster-internal. `externalTrafficPolicy: Local` ensures these
NodePorts answer only on the node hosting OmniRoute.

## Credentials

`secret.yaml` contains SOPS-encrypted storage, JWT, API-key encryption,
WebSocket bridge, and initial-admin credentials. Retrieve the generated initial
password without printing other secrets, sign in, and change it immediately:

```bash
SOPS_AGE_KEY_FILE="$HOME/.config/sops/age/keys.txt" \
  sops decrypt --extract '["stringData"]["INITIAL_PASSWORD"]' \
  anywhere/k8s/omniroute/secret.yaml
```

Add provider API keys, OAuth credentials, and browser cookies through the
OmniRoute dashboard; they are encrypted in the SQLite database on
`omniroute-data`.

Web cookies expire and often lack tool-calling support. Prefer official API or
OAuth providers for agent workloads. ChatGPT Web Codex is deferred because its
CDP browser sidecar is not part of the pinned stable release.

## Operations

Back up `/app/data` before upgrades. The default `local-path` StorageClass uses
node-local volumes with reclaim policy `Delete`; deleting a PVC is destructive,
and moving to another node requires an explicit data copy. Preserve both the
PVC data and the SOPS-encrypted Secret or credentials and sessions cannot be
recovered.

The container keeps all Linux capabilities dropped. Playwright disables the
Chromium sandbox by default, and OmniRoute's pooled browser path also supplies
`--no-sandbox`; verify one web-cookie provider after deployment. The 4 GiB
memory limit leaves headroom beyond the 2 GiB Node heap for Chromium and native
modules; monitor real use before increasing browser concurrency.

Validate without changing the cluster:

```bash
kubectl kustomize anywhere/k8s/omniroute
kubectl apply --dry-run=client -k anywhere/k8s/omniroute
```

Flux deployment is intentionally separate and requires explicit approval.
