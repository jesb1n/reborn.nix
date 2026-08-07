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
| `sitecustomize.py` | runtime monkeypatch for the ChatGPT SSE output bug (mounted via `litellm-patch` ConfigMap, `PYTHONPATH=/patch`) |
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

### Endpoint behavior

All endpoints are reliable, both models:

- `/v1/responses` → OK (streamed and non-stream).
- `/v1/chat/completions` → OK with `stream: true` **and** `stream: false`.

Upstream LiteLLM shipped the ChatGPT SSE output bug (`ChatgptException - Unknown
items in responses API response: []`, BerriAI/litellm #26309 / #25429 /
#29396): the Codex backend streams content via `response.output_item.done` /
`output_text.done` events but sends a terminal `response.completed` carrying
`output: []`, and LiteLLM's *streaming* iterator only reads
`response.completed.output`. This breaks any `/v1/chat/completions` call
(`stream: false` in particular), since the ChatGPT provider forces `stream=true`
upstream. The fix (upstream PR #31332) is **not in any stable tag**, including
v1.95.0.

We apply it ourselves as a runtime monkeypatch (`sitecustomize.py`, mounted via
the `litellm-patch` ConfigMap, `PYTHONPATH=/patch`): it accumulates
`output_item.done`/`output_text.done` items while streaming and backfills
`response.completed.output` when it arrives empty — only for the `chatgpt`
provider, leaving the standard OpenAI path untouched. Verify it is active with:

```bash
kubectl -n litellm exec deploy/litellm -- python3 -c \
  "import importlib; s=importlib.import_module('litellm.responses.streaming_iterator'); print(getattr(s,'_litellm_chatgpt_backfill_installed',False))"
```

If a future LiteLLM release merges #31332, delete `sitecustomize.py` (and its
kustomization entry + deployment mounts).

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