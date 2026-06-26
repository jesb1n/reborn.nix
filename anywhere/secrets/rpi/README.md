# rpi secrets

Expected encrypted file:

```text
secrets/rpi/secrets.yaml
```

Expected plaintext shape while editing with `sops`:

```yaml
tailscale-auth-key: "tskey-auth-xxxxx"
wifi-ssid: "your-wifi-ssid"
wifi-psk: "your-wifi-password"
```
