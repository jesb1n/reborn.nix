# litellm — LiteLLM Proxy (ChatGPT Plus OAuth)

Private AI gateway exposing the user's **ChatGPT Plus** subscription as an
OpenAI-compatible API. Authenticates to ChatGPT's Codex backend via OAuth
**device flow** (no OpenAI API billing). Flux-managed.

## Layout

| File | Purpose |
|------|---------|
| `namespace.yaml` | `litellm` namespace |
| `secret.yaml` | SOPS-encrypted Secret: `LITELLM_MASTER_KEY`, `LITELLM_SALT_KEY` (recipients: `pro_darwin`, `mark`, `s145_cluster`) |
| `config.yaml` | proxy config → ConfigMap via `configMapGenerator` (no secrets) |
| `deployment.yaml` | pinned `ghcr.io/berriai/litellm:v1.95.0`, 1 replica, `nodeSelector: oracle-eu-arm1`, `/health/*` probes |
| `service.yaml` | NodePort `31400` → `4000`, `externalTrafficPolicy: Local` (no public ingress) |
| `pvc.yaml` | `local-path` `1Gi` on the pinned node (holds `auth.json` + SQLite) |
| `login-job.yaml` | **NOT in kustomization** — one-time/on-demand device login, manual `kubectl` |
| `kustomization.yaml` | resources + `configMapGenerator` |

`clusters/s145/litellm.yaml` is the Flux `Kustomization` (SOPS decrypt via
`sops-age`, `dependsOn: infra`, `prune`).

## Models

- `chatgpt-sol`  → `chatgpt/gpt-5.6-sol` (responses)
- `chatgpt-codex` → `chatgpt/gpt-5.4` (responses)

Both `mode: responses`. `chatgpt_auth_file_path` points at the PVC-mounted
auth file to disable interactive login and avoid the device-code restart loop.

> Note: `gpt-5.3-codex` is **deprecated** on the Codex-with-ChatGPT backend and
> returns 400 (`not supported when using Codex with a ChatGPT account`).
> `chatgpt-codex` now routes to `gpt-5.4` instead.

### Endpoint behavior (upstream limitation)

- `/v1/responses` → reliable, both models.
- `/v1/chat/completions` with `stream: true` → reliable, both models.
- `/v1/chat/completions` with `stream: false` → **breaks upstream**:
  `ChatgptException - Unknown items in responses API response: []`. This is the
  open ChatGPT-provider SSE bug (BerriAI/litellm #26309 / #25429 /
  #26394); the `output_item.done` accumulator fix (PR #31332) is **not yet in any
  stable tag**, including v1.95.0. Prefer `stream: true` (or `/v1/responses`).

## First-time / renewed ChatGPT login

The login Job is deliberately **excluded from the Flux kustomization** so Flux
(`prune: true`) never manages or deletes it. Run it manually whenever you
need to (re)authenticate the ChatGPT Plus account:

```bash
kubectl -n litellm apply -f anywhere/k8s/litellm/login-job.yaml
kubectl -n litellm logs -f job/litellm-login   # prints device code + verification URL
# sign in with the ChatGPT Plus account in the browser, enter the code
kubectl -n litellm delete job litellm-login    # token persists on the PVC
kubectl -n litellm rollout restart deploy/litellm
```

The token file is written into the shared `litellm-token` PVC
(`/data/chatgpt/auth.json`). A pod restart/redeploy does **not** require a new
login until the upstream session expires or is revoked. The Job pins the same
`oracle-eu-arm1` node as the deployment.

## Access

Private only. No IngressRoute, no public DNS. Reach over the Tailnet at:

```
http://100.84.230.4:31400   # oracle-eu-arm1
http://<tailnet-ip>:31400   # if re-pinned
```

`tailscale0` is a trusted firewall interface (`profiles/server.nix`), so the
NodePort is reachable over WireGuard without further firewall changes. All API
calls require a bearer key (currently the master key from the SOPS secret).

## Apply / sync

```bash
# from anywhere/
git push && flux reconcile kustomization litellm -n flux-system --with-source
```

## Update notes

- Pin `image.tag` (do **not** use `:latest`); the official images are
  `ghcr.io/berriai/litellm` (multi-arch, incl. arm64) / `litellm-database`.
- This uses SQLite (master-key auth) — no Postgres, no Kafka, and thus no
  virtual keys / spend logs. 1 replica (single writable ChatGPT token → no
  refresh races). Deviations from the official production docs are deliberate.

## Rollback / revoke

- Edit `image.tag` in git → `flux reconcile`. Or `kubectl -n litellm rollout undo deploy/litellm`.
- Cut all clients: rotate the master key (re-`sops -e`) or `kubectl delete secret litellm-secret`.
- Force full re-login: `kubectl -n litellm delete pvc litellm-token`.