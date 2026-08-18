# Prerequisites

This repository operates existing, personal infrastructure. It is not a turnkey free-tier template: account limits, DNS zones, hostnames, Tailnet addresses, secrets, and OCI capacity are environment-specific.

## Access

You need authorized access to:

- the OCI tenancies, compartments, and regions represented by `beijns` and `beijnseu`;
- OCI CLI SecurityToken profiles with those names in `~/.oci/config`;
- the Tailscale network containing the fleet and Garage endpoint;
- the SOPS age identity configured by `SOPS_AGE_KEY_FILE`;
- the GitHub repository and Actions secrets if using CI;
- the Cloudflare account used for DNS-01 and tunnel routes;
- the k3s kubeconfig for `s145` at `~/.kube/s145.yaml`.

## Tools

The operator workstation needs:

| Tool | Use |
| --- | --- |
| OpenTofu | OCI plans and applies |
| OCI CLI | SecurityToken session authentication |
| SOPS and age | Encrypted IaC, host, and Kubernetes data |
| Nix with flakes | NixOS/nix-darwin evaluation and builds |
| deploy-rs | Routine NixOS activation |
| kubectl | Cluster inspection and manual resources |
| Flux CLI | GitOps reconciliation and status |
| Git and SSH | Source control and host access |

Most NixOS tooling is available through `nix develop` in `anywhere/`. `direnv` sets `KUBECONFIG` and `SOPS_AGE_KEY_FILE`, but does not enter the dev shell.

Check the local tools without changing infrastructure:

```bash
tofu version
oci --version
sops --version
nix --version
kubectl version --client
flux version --client
```

## OCI SecurityToken Profiles

The provider uses `auth = "SecurityToken"`; API-key environment variables are not the supported local path. Authenticate each environment before planning:

```bash
make -C IaC ENV=beijns check-auth
make -C IaC ENV=beijnseu check-auth
```

The command opens OCI session authentication when a profile has expired. Never commit OCI session tokens or generated private keys.

## SOPS Identity

The expected operator identity file is:

```text
~/.config/sops/age/keys.txt
```

Set it explicitly when not using the repository environment:

```bash
export SOPS_AGE_KEY_FILE="$HOME/.config/sops/age/keys.txt"
```

Verify access without printing plaintext:

```bash
sops -d IaC/beijns.tfvars >/dev/null
sops -d IaC/secrets/beijns.env >/dev/null
sops -d anywhere/secrets/k3s/secrets.yaml >/dev/null
```

Do not display decrypted content in logs or create plaintext tfvars as a workaround.

## Backend Connectivity

OpenTofu state uses Garage S3 at `100.69.231.117:31900`. Before `init`, `plan`, or state commands:

- connect to Tailscale;
- confirm `s145` is reachable;
- confirm the encrypted backend environment file exists for the selected environment;
- ensure Garage is healthy if performing a recovery or migration.

A connectivity failure is not a reason to switch to local state. Changing the backend without a deliberate migration can split or lose state.

## Nix and SSH

- Enable `nix-command` and `flakes`.
- Accept the flake's configured substituters where appropriate.
- Ensure `duck@<host>` resolves through Tailscale/MagicDNS.
- Keep the configured SSH key available to the operator.
- Keep `hp348` reachable for Mac-initiated builds of x86_64 micro-node closures.

Validate access:

```bash
ssh duck@s145 hostname
ssh duck@hp348 hostname
cd anywhere && nix flake metadata --no-write-lock-file >/dev/null
```

## Kubernetes and Flux

```bash
export KUBECONFIG="$HOME/.kube/s145.yaml"
kubectl cluster-info
kubectl get nodes
flux get kustomizations -n flux-system
```

Flux decryption additionally requires the in-cluster `flux-system/sops-age` Secret. Do not recreate or rotate it casually; encrypted manifests must include the matching public recipient first.

## Before Any Change

- Read the relevant app or migration runbook.
- Check `git status` and preserve unrelated work.
- Confirm the selected OCI environment and Git branch.
- Run format/evaluation checks before state-changing commands.
- Back up state and application data before storage, Garage layout, Disko, or control-plane work.
