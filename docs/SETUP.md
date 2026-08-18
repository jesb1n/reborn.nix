# Setup

This guide prepares an authorized operator to work with the existing repository. Creating new OCI accounts, Tailnets, DNS zones, or replacement secrets is outside the normal setup path.

## 1. Clone and Enter the Repository

```bash
git clone git@github.com:jesb1n/reborn.nix.git
cd reborn.nix
```

Do not copy decrypted files or age private keys into the checkout.

## 2. Configure the Operator Age Identity

```bash
install -d -m 700 "$HOME/.config/sops/age"
export SOPS_AGE_KEY_FILE="$HOME/.config/sops/age/keys.txt"
```

Provision the authorized identity through a secure out-of-band channel, then verify it without emitting plaintext:

```bash
sops -d IaC/beijns.tfvars >/dev/null
sops -d IaC/secrets/beijns.env >/dev/null
```

## 3. Configure OCI CLI Sessions

Create OCI CLI profiles named `beijns` and `beijnseu` using the authorized tenancy identities. The OpenTofu provider consumes OCI SecurityToken sessions, not an inline PEM variable.

```bash
make -C IaC ENV=beijns check-auth
make -C IaC ENV=beijnseu check-auth
```

Re-run `check-auth` whenever OCI reports an expired or invalid session.

## 4. Initialize an OpenTofu Environment

Connect to Tailscale first because the Garage backend is private.

```bash
make -C IaC ENV=beijns init
make -C IaC fmt
tofu -chdir=IaC validate
make -C IaC ENV=beijns plan
```

`init` decrypts the selected tfvars and backend credentials only for the command, sets the state key to `<environment>.tfstate`, and selects the matching OCI profile. Repeat with `ENV=beijnseu` for Europe.

Review plans for replacements, public IP changes, boot-volume changes, and unexpected cross-environment resources. Apply only after review:

```bash
make -C IaC ENV=beijns deploy
```

## 5. Prepare the Nix Workspace

```bash
cd anywhere
direnv allow                 # optional: exports KUBECONFIG and SOPS_AGE_KEY_FILE
nix develop                  # supplies deploy-rs, SOPS, age, Disko, and install tools
nix flake check
```

New Nix files must be staged before flake evaluation because flakes ignore untracked files.

Evaluate one host before activation:

```bash
nix eval --raw .#nixosConfigurations.s145.config.networking.hostName
nix build -L .#nixosConfigurations.s145.config.system.build.toplevel
```

## 6. Routine NixOS Deployment

Use deploy-rs from `anywhere/`:

```bash
nix develop -c deploy .#oracle-eu-arm1
nix develop -c deploy .#s145
```

For shared input updates, deploy workers first and `s145` last. The four micro targets build through the configured `hp348` builder when deployed from the Apple Silicon workstation; other nodes use remote builds.

Do not use `nixos-anywhere` for routine updates. It runs Disko and can erase the target disk. Follow a host-specific reinstall runbook only when a destructive reinstall is intended.

## 7. Configure Cluster Access

Place the authorized kubeconfig at `~/.kube/s145.yaml` with restrictive permissions:

```bash
chmod 600 "$HOME/.kube/s145.yaml"
export KUBECONFIG="$HOME/.kube/s145.yaml"
kubectl get nodes -o wide
flux get kustomizations -n flux-system
```

The repository's `anywhere/.envrc` exports this path automatically after `direnv allow`.

## 8. GitOps Changes

1. Edit resources in `anywhere/k8s/<app>/`.
2. Validate with `kubectl kustomize anywhere/k8s/<app>` when a kustomization exists, or use client-side dry-run for plain manifests.
3. Commit and push the change to the branch watched by Flux.
4. Observe reconciliation or explicitly reconcile the app.

```bash
flux reconcile kustomization immich -n flux-system --with-source
flux get kustomizations -n flux-system
```

Flux reconciliation changes the live cluster. Do not reconcile unreviewed source changes.

## Troubleshooting

### OCI authentication fails

Run `make -C IaC ENV=<environment> check-auth` and complete browser authentication. Confirm the OCI profile name matches the encrypted environment.

### Backend initialization fails

Confirm Tailscale connectivity and reachability of `100.69.231.117:31900`. Verify the selected encrypted backend environment file decrypts. Do not replace the backend with local state.

### SOPS reports no matching key

Confirm `SOPS_AGE_KEY_FILE`, file permissions, and that the encrypted file contains the operator's public recipient. Never copy a host private key into the repository.

### A micro-node build fails locally

Confirm `hp348` is online, reachable over SSH, and still configured as the x86_64 distributed builder for `pro-darwin`.

### A k3s agent does not join

Check Tailscale first, then `systemctl status k3s` on the agent. The server address is `https://100.69.231.117:6443`. Reapply the `tiny=true:NoSchedule` taint after rebuilding a micro node.
