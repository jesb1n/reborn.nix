# s145 Secrets

This directory holds SOPS-encrypted secrets for the `s145` host.

## Setup

1. Generate an age key on the host:

   ```sh
   age-keygen -o /var/lib/sops-nix/key.txt
   ```

2. Get the public key:

   ```sh
   age-keygen -y /var/lib/sops-nix/key.txt
   ```

3. Add the public key to `../.sops.yaml` under `&s145_host`.

4. Create the secrets file:

   ```sh
   sops secrets/s145/secrets.yaml
   ```

   Required keys:
   - `wifi-ssid`: WiFi network name
   - `wifi-psk`: WiFi password
