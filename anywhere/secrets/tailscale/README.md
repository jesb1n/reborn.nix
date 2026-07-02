# tailscale secrets

Shared Tailscale pre-auth key for all NixOS hosts.

Expected encrypted file:

```text
secrets/tailscale/secrets.yaml
```

Expected plaintext shape while editing with `sops`:

```yaml
tailscale-auth-key: "tskey-auth-xxxxx"
```
