# k3s cluster secret

This directory holds shared SOPS-encrypted secrets used by all k3s nodes.

Expected encrypted file:

```text
secrets/k3s/secrets.yaml
```

Expected plaintext shape while editing with `sops`:

```yaml
k3s-token: "replace-with-a-long-random-cluster-token"
```

Generate a token locally with:

```bash
openssl rand -base64 48
```

