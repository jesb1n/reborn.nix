# oracle-eu-arm1 host secrets

Host-specific SOPS secrets for the ARM control-plane. Encrypted with the
host age key (see `.sops.yaml`) and decrypted at activation time into
`/run/secrets/`.

Shared Tailscale credentials live in `secrets/tailscale/secrets.yaml`.
Shared k3s credentials live in `secrets/k3s/secrets.yaml`.

## `secrets.yaml`

Hermes Agent Telegram-gateway credentials. Create with:

```bash
cd ~/oracle-cloud-free-tier/anywhere
sops secrets/oracle-eu-arm1/secrets.yaml
```

Required keys:

```yaml
hermes:
  telegram-bot-token: "123456789:AA..."           # from @BotFather
  telegram-allowed-users: "12345678,87654321"     # numeric IDs from @userinfobot
  google-api-key: "AIza..."                       # Google AI Studio / Gemini API key
```

These are surfaced to the gateway via a SOPS template that produces
`/run/secrets/rendered/hermes-agent.env` (see `hosts/oracle-eu-arm1/sops.nix`).

Until this file exists, `services.hermes-agent` stays disabled — the rest of
the host config (k3s, Tailscale) deploys normally.
