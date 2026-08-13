# litellm — LiteLLM Proxy

Private, Flux-managed AI gateway exposing ChatGPT and Google Gemini models as
an OpenAI-compatible API. ChatGPT authenticates to the Codex backend through
OAuth device flow; Gemini uses a Google AI Studio API key.

## Layout

| File | Purpose |
|------|---------|
| `namespace.yaml` | `litellm` namespace |
| `secret.yaml` | SOPS-encrypted Secret: `LITELLM_MASTER_KEY`, `LITELLM_SALT_KEY`, `GEMINI_API_KEY` (recipients: `pro_darwin`, `mark`, `s145_cluster`) |
| `config.yaml` | proxy config → hash-suffixed ConfigMap via `configMapGenerator` (no secrets) |
| `deployment.yaml` | pinned `ghcr.io/berriai/litellm:v1.95.0`, 1 replica, `nodeSelector: oracle-eu-arm1`, `/health/*` probes |
| `sitecustomize.py` | runtime monkeypatch for the ChatGPT SSE output bug (mounted via `litellm-patch` ConfigMap, `PYTHONPATH=/patch`) |
| `service.yaml` | NodePort `31400` → `4000`, `externalTrafficPolicy: Local` (no public ingress) |
| `pvc.yaml` | `local-path` `1Gi` on the pinned node (holds `auth.json` + SQLite) |
| `login-job.yaml` | **NOT in kustomization** — one-time/on-demand device login, manual `kubectl` (see "First-time / renewed login") |
| `kustomization.yaml` | resources + `configMapGenerator` |

`clusters/s145/litellm.yaml` is the Flux `Kustomization` (SOPS decrypt via
`sops-age`, `dependsOn: infra`, `prune`).

## Models

| Proxy alias | Provider model | Use |
|-------------|----------------|-----|
| `chatgpt-sol` | `chatgpt/gpt-5.6-sol` | Long-context, high-capability responses |
| `chatgpt-codex` | `chatgpt/gpt-5.4` | Coding through ChatGPT OAuth |
| `gemini-flash` | `gemini/gemini-3.7-flash` | Default balance of quality, latency, and cost |
| `gemini-flash-lite` | `gemini/gemini-3.5-flash-lite` | Low-cost, high-throughput tasks |

The ChatGPT models use `mode: responses`. `chatgpt_auth_file_path` points at the
PVC-mounted auth file to disable interactive login and avoid the device-code
restart loop. `gpt-5.3-codex` is deprecated on the Codex-with-ChatGPT backend;
`chatgpt-codex` therefore routes to `gpt-5.4`.

Gemini uses LiteLLM's native `gemini/` provider and reads `GEMINI_API_KEY` from
the SOPS-encrypted Secret. The friendly proxy aliases isolate clients from
Google endpoint changes. Leave Gemini 3 `temperature` unset (the recommended
provider default is `1.0`); clients may select `reasoning_effort` per request.
The API key currently has no available `gemini-3.1-pro-preview` quota, so the
proxy deliberately exposes only the two Flash models verified on its free tier.
The runtime compatibility patch maps Copilot's nonstandard
`tool_choice: validated` to Gemini's `auto` mode. Tool definitions are preserved,
so Gemini can still select tools automatically; ChatGPT routes are unaffected.

### Gemini API access

The Google AI Pro consumer benefit supplied through Jio does **not** provide
Gemini API credits or a supported subscription-OAuth credential for LiteLLM.
Create a separate key in Google AI Studio; usage is governed by the Gemini API
free tier or by separately enabled API billing. Free-tier prompts may be used
to improve Google's products, while paid-tier data handling differs.

Edit the encrypted Secret without putting the key in shell history:

```bash
export SOPS_AGE_KEY_FILE="$HOME/.config/sops/age/keys.txt"
sops anywhere/k8s/litellm/secret.yaml
```

Add `GEMINI_API_KEY` under `stringData`, save, and let SOPS re-encrypt the file.
Never commit a plaintext key or paste it into logs, commands, or documentation.

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

### Upstream-fix removal tracker

This monkeypatch is a **stopgap only** — remove it once the upstream fix lands.

- **Tracked issue:** BerriAI/litellm #26309 / #25429 / #29396.
- **Tracked fix PR:** #31332 (accumulate `output_item.done` → backfill
  `response.completed.output`) — **not merged into any stable tag as of v1.95.0**.
- **To check before removal:** the fixed release must be newer than v1.95.0 and
  its changelog/PR #31332 must reference the empty-output recovery in
  `litellm/responses/*streaming_iterator*.py`. Test
  `/v1/chat/completions` with `stream: false` first — if it returns content
  without the patch, the fix is upstream.

**Removal checklist (all in one commit):**
1. Delete `anywhere/k8s/litellm/sitecustomize.py`.
2. Remove the `litellm-patch` entry from `kustomization.yaml`'s
   `configMapGenerator`.
3. Remove the `patch` volume, its mount, and the `PYTHONPATH=/patch` env from
   `deployment.yaml`.
4. Bump `image.tag` (e.g. to the release containing the fix).
5. Delete this "Upstream-fix tracking" section and restore the flat
   "endpoints reliable" wording.
6. Regenerate + apply, then `kubectl -n litellm delete cm litellm-patch`.

## First-time / renewed ChatGPT login

The login Job is deliberately **excluded from the Flux kustomization** so Flux
(`prune: true`) never manages or deletes it. Run it manually whenever you
need to (re)authenticate the ChatGPT Plus account — e.g. **first install**, a
session **expiry/revocation** (calls start failing with auth errors), or a
manual account **re-auth**. The full procedure and how-it-works are documented
in the Job's own header comment (`login-job.yaml`); abbreviated:

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
# Validate from the repository root without changing the cluster.
kubectl kustomize anywhere/k8s/litellm >/dev/null

# After commit and push, reconcile the Flux-managed workload.
flux reconcile kustomization litellm -n flux-system --with-source
```

Smoke-test each Gemini alias over the Tailnet after reconciliation (set the
master key interactively so it is not stored in shell history):

```bash
read -rs LITELLM_KEY; export LITELLM_KEY; echo
for model in gemini-flash gemini-flash-lite; do
  curl --fail-with-body --silent --show-error \
    http://100.84.230.4:31400/v1/chat/completions \
    -H "Authorization: Bearer $LITELLM_KEY" \
    -H 'Content-Type: application/json' \
    -d "{\"model\":\"$model\",\"messages\":[{\"role\":\"user\",\"content\":\"Reply with OK\"}]}"
  echo
done
unset LITELLM_KEY
```

## Update notes

- Pin `image.tag` (do **not** use `:latest`); the official images are
  `ghcr.io/berriai/litellm` (multi-arch, incl. arm64) / `litellm-database`.
- This uses SQLite (master-key auth) — no Postgres, no Kafka, and thus no
  virtual keys / spend logs. 1 replica (single writable ChatGPT token → no
  refresh races). Deviations from the official production docs are deliberate.
- Review Google's model lifecycle before each LiteLLM image upgrade and update
  preview provider IDs behind the existing proxy aliases when required.

## Rollback / revoke

- Edit `image.tag` in git → `flux reconcile`. Or `kubectl -n litellm rollout undo deploy/litellm`.
- Cut all clients: rotate the master key (re-`sops -e`) or `kubectl delete secret litellm-secret`.
- Force full re-login: `kubectl -n litellm delete pvc litellm-token`.