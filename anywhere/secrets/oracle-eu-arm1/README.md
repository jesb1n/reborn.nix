# oracle-eu-arm1 host secrets

Host-specific SOPS secrets for this ARM k3s agent and aarch64 binary cache.
Encrypted with the host age key (see `.sops.yaml`) and decrypted at
activation time into `/run/secrets/`.

Shared Tailscale credentials live in `secrets/tailscale/secrets.yaml`.
Shared k3s credentials live in `secrets/k3s/secrets.yaml`.

## `secrets.yaml`

Expected plaintext shape while editing with `sops`:

```yaml
nix-cache-signing-key: "reborn-arm-1:<base64 private key>"
```

`nix-cache-signing-key` is the private NAR signing key for the self-hosted
binary cache (`profiles/binary-cache.nix`). Only the public half is committed,
in `lib/binary-caches.nix`. Generate a new pair with:

```bash
nix key generate-secret --key-name <name> > cache-priv.pem
nix key convert-secret-to-public < cache-priv.pem   # -> lib/binary-caches.nix
sops secrets/oracle-eu-arm1/secrets.yaml             # paste the private half
```

While this file is absent, `fleet.binaryCache` stays disabled and the rest of
the host (k3s, Tailscale) deploys normally.

The file may still contain legacy `hermes/*` keys from the removed Hermes
Agent gateway (commit `6b6690a`). Nothing declares them in
`hosts/oracle-eu-arm1/sops.nix`; they can be deleted on the next edit.
