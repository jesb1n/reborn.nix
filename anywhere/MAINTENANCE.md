# Fleet maintenance

This runbook covers routine validation, deployment, rollback, and cluster
checks for the systems defined in `anywhere/flake.nix`. Run commands from
`anywhere/` unless stated otherwise.

## Safety model

- Review `git status --short` and the relevant diff before every operation.
- Use deploy-rs for routine NixOS updates; do not use `nixos-anywhere`.
- Deploy workers first and `s145` last for fleet-wide changes.
- Keep at least one known-good generation until the cluster is stable.
- Never write decrypted SOPS data to the repository.

## Daily health checks

```bash
ssh duck@s145 'sudo k3s kubectl get nodes -o wide'
ssh duck@s145 'sudo k3s kubectl get pods -A'
ssh duck@s145 'systemctl is-system-running; systemctl --failed'
```

Check a worker when investigating a node-specific problem:

```bash
ssh duck@oracle-in-micro1 \
  'hostname; systemctl is-system-running; systemctl --failed; sudo tailscale ip -4'
```

Hosts are intentionally minimal. Use `nix shell nixpkgs#<package>` for a
temporary diagnostic tool instead of adding it permanently.

## Validate Nix changes

Evaluate or build the affected host before broad validation:

```bash
nix eval --raw .#nixosConfigurations.oracle-eu-micro1.config.networking.hostName
nix build -L .#nixosConfigurations.oracle-eu-micro1.config.system.build.toplevel
nix flake check
```

New Nix files must be staged because flakes ignore untracked files.

Confirm deploy-rs placement when changing build topology:

```bash
nix eval .#deploy.nodes.oracle-eu-micro1.remoteBuild  # false
nix eval .#deploy.nodes.oracle-in-micro2.remoteBuild  # false
nix eval .#deploy.nodes.oracle-eu-arm1.remoteBuild    # true
```

From `pro-darwin`, verify the distributed builder before deploying a micro:

```bash
nix store info --store 'ssh-ng://duck@hp348'
nix config show | grep '^builders ='
```

The four micros use `remoteBuild = false`; the Mac evaluates the flake and
`hp348` builds their `x86_64-linux` closures. Other deploy-rs nodes build on
themselves.

## Deploy NixOS

One host:

```bash
nix develop -c deploy .#oracle-eu-micro2
```

All four micro workers:

```bash
nix develop -c deploy --targets \
  .#oracle-eu-micro1 .#oracle-eu-micro2 \
  .#oracle-in-micro1 .#oracle-in-micro2
```

A safe order for input or shared-profile updates is:

1. Tiny workers: `oracle-eu-micro2`, `oracle-eu-micro1`,
   `oracle-in-micro2`, `oracle-in-micro1`
2. Other agents: `hp348`, `rpi`, `oracle-eu-arm1`, `oracle-in-arm1`
3. Control plane: `s145`

After each batch, verify the target generation and cluster health:

```bash
ssh duck@oracle-eu-micro2 \
  'readlink -f /run/current-system; systemctl is-system-running; systemctl --failed'
ssh duck@s145 'sudo k3s kubectl get nodes -o wide'
ssh duck@s145 'sudo k3s kubectl get pods -A'
```

Deploy-rs success ends with activation and deployment confirmation. Treat an
activation timeout, failed magic rollback check, or unreachable target as a
failed deployment even if the build completed.

## Roll back

```bash
ssh duck@oracle-eu-micro2 'sudo nixos-rebuild list-generations | tail'
ssh duck@oracle-eu-micro2 'sudo nixos-rebuild switch --rollback'
```

Re-run the host and cluster checks after rollback. If a host cannot boot, use
its physical or cloud console; avoid changing another host until the first is
recovered.

## nixos-rebuild fallback

Use this only when debugging deploy-rs or when explicit build and target hosts
are useful:

```bash
nix run nixpkgs#nixos-rebuild -- \
  switch \
  --flake .#oracle-eu-arm1 \
  --target-host duck@oracle-eu-arm1 \
  --build-host duck@oracle-eu-arm1 \
  --elevate=sudo \
  --no-reexec \
  --use-substitutes
```

The supported privilege flag is `--elevate=sudo`, not `--use-remote-sudo`.

## pro-darwin

`pro-darwin` is not a deploy-rs node. Build before switching:

```bash
sudo darwin-rebuild build --flake .#pro-darwin
sudo darwin-rebuild switch --flake .#pro-darwin
```

Preserve the host invariants documented in `hosts/pro-darwin/AGENTS.md`.

## Hermes Agent

`oracle-eu-arm1` runs Hermes Agent with OpenAI Codex as the default model,
Google Gemini as an alternative provider, and Telegram as its messaging
gateway. The service is enabled only when
`secrets/oracle-eu-arm1/secrets.yaml` exists. That encrypted file supplies:

- `hermes/telegram-bot-token`
- `hermes/telegram-allowed-users`
- `hermes/google-api-key`

After the first deployment, bootstrap ChatGPT OAuth interactively on the host:

```bash
ssh duck@oracle-eu-arm1
hermes auth add codex-oauth
sudo systemctl restart hermes-agent
```

The command starts a device-code flow. Open only the URL it prints, authenticate
with the intended ChatGPT account, and never paste the resulting credentials
into Git or chat. Hermes stores its persistent state under
`/var/lib/hermes/.hermes/`.

Check the gateway and provider configuration with:

```bash
ssh duck@oracle-eu-arm1 \
  'systemctl status hermes-agent --no-pager; journalctl -u hermes-agent -n 50 --no-pager'
ssh duck@oracle-eu-arm1 'hermes doctor'
```

Security boundaries:

- Keep `TELEGRAM_ALLOWED_USERS` restricted to explicitly approved numeric user
  IDs; never enable `TELEGRAM_ALLOW_ALL_USERS`.
- The hardened systemd unit limits filesystem access, but Hermes can execute
  shell commands as the `hermes` user. Treat every approved Telegram user as
  having shell access to that account.
- Rotate the bot token, Google API key, or OAuth grant immediately if exposed,
  then restart `hermes-agent` and verify it with `hermes doctor`.

## SOPS operations

```bash
export SOPS_AGE_KEY_FILE="$HOME/.config/sops/age/keys.txt"
sops secrets/k3s/secrets.yaml
sops -d secrets/k3s/secrets.yaml >/dev/null
sops updatekeys secrets/k3s/secrets.yaml
```

Re-key every affected shared or host file after changing `.sops.yaml`. Only
public `age1...` recipients and encrypted SOPS files belong in Git. Never copy
a host private key into another host's directory.

## Kubernetes and Flux

Flux-owned resources are registered in `clusters/s145/`. Validate an app
locally, then commit and push through the normal Git workflow before requesting
a reconciliation:

```bash
kubectl kustomize k8s/immich
flux get kustomizations -n flux-system
flux reconcile kustomization immich -n flux-system --with-source
```

Reconciliation changes the live cluster. Do not use `kubectl apply` as a
shortcut for a Flux-owned app, because Flux will restore the Git state.

For a manual-only directory, follow its README and inspect a client-side dry
run before applying:

```bash
kubectl apply --dry-run=client -f k8s/<manual-app>/
```

Check Flux and workloads after any cluster change:

```bash
flux get kustomizations -n flux-system
kubectl get pods -A
kubectl get events -A --sort-by=.lastTimestamp
```

## Tiny workers

The four 1 GB micro nodes use zram and `max-pods=10`. Their
`tiny=true:NoSchedule` taint is intentionally maintained out of band. Verify or
restore it after registration or cluster reconstruction:

```bash
kubectl get nodes -o custom-columns=NAME:.metadata.name,TAINTS:.spec.taints
kubectl taint node oracle-eu-micro1 tiny=true:NoSchedule --overwrite
kubectl taint node oracle-eu-micro2 tiny=true:NoSchedule --overwrite
kubectl taint node oracle-in-micro1 tiny=true:NoSchedule --overwrite
kubectl taint node oracle-in-micro2 tiny=true:NoSchedule --overwrite
```

Only workloads designed for these nodes should tolerate that taint.

## Updating inputs

```bash
nix flake metadata
nix flake update
# or one input:
nix flake update nixpkgs
```

Build and deploy one worker before continuing through the safe order. Input
updates can change every host closure, so do not activate the whole fleet in a
single unverified step.

## Storage and garbage collection

Automatic weekly garbage collection retains recent generations. Inspect disk
usage before manual cleanup:

```bash
ssh duck@oracle-eu-micro1 'df -h / /nix; sudo nix path-info -Sh /run/current-system'
ssh duck@oracle-eu-micro1 \
  'sudo nix-collect-garbage --delete-older-than 7d; sudo nix store optimise'
```

Avoid `nix-collect-garbage -d` immediately after a risky deployment because it
can remove rollback generations.

## OpenTofu boundary

Use OpenTofu for OCI compute, network, and security-list changes; use Nix for
host services and Kubernetes node configuration. From the repository root:

```bash
make -C IaC fmt
tofu -chdir=IaC validate
make -C IaC ENV=beijns check-auth
make -C IaC ENV=beijns init
make -C IaC ENV=beijns plan
```

An apply is state-changing and is intentionally not part of this routine check.

## Reinstallation

`nixos-anywhere` with Disko can reformat the target disk. Use it only for an
explicit installation or recovery operation with a reviewed host-specific
runbook and backups. For 1 GB Oracle micro nodes, follow
[ORACLE-IN-MICRO-NIXOS.md](./docs/ORACLE-IN-MICRO-NIXOS.md); do not infer a
reinstall command from routine deployment examples.
