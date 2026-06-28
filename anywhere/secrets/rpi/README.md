# rpi secrets

Expected encrypted file:

```text
secrets/rpi/secrets.yaml
```

Expected plaintext shape while editing with `sops`:

```yaml
wifi-ssid: "your-wifi-ssid"
wifi-psk: "your-wifi-password"
```

Shared Tailscale credentials live in `secrets/tailscale/secrets.yaml`.
