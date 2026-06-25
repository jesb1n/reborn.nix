# oci-nixos secrets

This directory holds SOPS-encrypted secrets for the OCI NixOS host.

Do not commit plaintext secrets.

Expected encrypted file:

```text
secrets/oci-nixos/secrets.yaml
```

Expected plaintext shape while editing with `sops`:

```yaml
tailscale-auth-key: "tskey-auth-xxxxx"
```

