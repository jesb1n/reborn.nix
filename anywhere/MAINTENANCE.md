# Fleet maintenance

This runbook covers routine validation, deployment, rollback, and cluster
checks for the systems defined in `anywhere/flake.nix`. Run commands from
`anywhere/` unless stated otherwise.

## Safety model

- Review `git status --short` and the relevant diff before every operation.
- Use deploy-rs for routine NixOS updates; do not use `nixos-anywhere`.
- Every host also pulls and rebuilds itself from `main` nightly
  (`profiles/auto-upgrade.nix`), so **pushing to `main` deploys the fleet**
  within about a day even without a manual deploy.
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
nix eval .#deploy.nodes.oracle-in-arm1.remoteBuild    # false
nix eval .#deploy.nodes.rpi.remoteBuild               # false
nix eval .#deploy.nodes.oracle-eu-arm1.remoteBuild    # true (is the aarch64 builder)
```

From `pro-darwin`, verify the relevant distributed builder before deploying:

```bash
nix store info --store 'ssh-ng://duck@s145'            # x86_64 builder
nix store info --store 'ssh-ng://duck@oracle-eu-arm1'  # aarch64 builder
nix config show | grep '^builders ='
cat /etc/nix/machines
```

Both should report `Trusted: 1`. If offload fails with "Host key verification
failed", the system-wide `/etc/ssh/ssh_known_hosts` is missing an entry — the
nix-daemon runs as root and does not read your `~/.ssh/known_hosts`. Fix it in
`programs.ssh.knownHosts` in `hosts/pro-darwin/darwin-configuration.nix`, not by
sshing manually to accept the key.

The four micros use `remoteBuild = false` and build on `s145`; `oracle-in-arm1`
and `rpi` use `remoteBuild = false` and build on `oracle-eu-arm1`. The two
builder hosts and `nuc7i3` build on themselves.

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
2. Other agents: `nuc7i3`, `rpi`, `oracle-eu-arm1`, `oracle-in-arm1`
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

## ARM binary cache (oracle-eu-arm1)

`oracle-eu-arm1` serves a self-hosted Nix binary cache (`nix-serve`, see
`profiles/binary-cache.nix`) to the other aarch64 nodes over Tailscale at
`http://100.84.230.4:5000`. It is enabled only when
`secrets/oracle-eu-arm1/secrets.yaml` exists, because the NAR signing key
(`nix-cache-signing-key`) comes from it. The matching public key is committed
in `lib/binary-caches.nix` under the `arm` scope; `rpi` and `oracle-in-arm1`
consume it.

Check the cache from the operator machine or any tailnet host:

```bash
ssh duck@oracle-eu-arm1 \
  'systemctl status nix-serve --no-pager; journalctl -u nix-serve -n 50 --no-pager'
curl -fsS http://100.84.230.4:5000/nix-cache-info
```

Hermes Agent no longer runs on any NixOS host (removed in commit `6b6690a`);
the `hermes/*` entries still present in `secrets/oracle-eu-arm1/secrets.yaml`
are legacy and have no declarations in `hosts/oracle-eu-arm1/sops.nix`.

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
