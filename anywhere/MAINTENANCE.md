# Maintaining the OCI NixOS hosts

This repo manages three NixOS machines:

| Host | Role | Architecture | Access |
| --- | --- | --- | --- |
| `oracle-eu-arm1` | k3s control-plane | `aarch64-linux` | `ubuntu@129.159.222.42` or `ubuntu@oracle-eu-arm1` |
| `oracle-eu-micro1` | k3s worker | `x86_64-linux` | `ubuntu@oracle-eu-micro1` |
| `oracle-eu-micro2` | k3s worker | `x86_64-linux` | `ubuntu@oracle-eu-micro2` |

The preferred management machine is `s145`, because it is AMD/x86 and can build the two micro nodes locally.

## Configuration architecture

Host configs follow a **profile-based composition** pattern (inspired by the retire.nix structure). Shared settings live in reusable profiles; each host only sets what's unique to it.

```
anywhere/
├── profiles/
│   ├── base.nix          # Users, nix GC, sudo, minimal footprint
│   ├── server.nix        # GRUB boot, serial console, SSH hardening, timezone
│   ├── tailscale.nix     # Tailscale + SOPS auth key integration
│   ├── k3s-server.nix    # k3s server role, disable traefik, flannel over tailscale0
│   └── k3s-agent.nix     # k3s agent role, tiny taint, max-pods=10, zramSwap
├── hosts/
│   ├── oracle-eu-arm1/configuration.nix       # imports: base + server + tailscale + k3s-server
│   ├── oracle-eu-micro1/configuration.nix # imports: base + server + tailscale + k3s-agent
│   └── oracle-eu-micro2/configuration.nix # imports: base + server + tailscale + k3s-agent
```

### What goes WHERE

| Change needed | Edit this file |
|--------------|----------------|
| SSH keys, user accounts, nix GC settings | `profiles/base.nix` |
| Boot loader, serial console, firewall, SSH settings | `profiles/server.nix` |
| Tailscale enable/openFirewall settings | `profiles/tailscale.nix` |
| k3s server flags, disabled components | `profiles/k3s-server.nix` |
| k3s agent flags, taints, labels, zramSwap | `profiles/k3s-agent.nix` |
| Hostname, node IP, Tailscale extra flags | `hosts/<name>/configuration.nix` |
| Disk layout | `hosts/<name>/disko-config.nix` |
| SOPS secret declarations | `hosts/<name>/sops.nix` |

### Adding a new Oracle VM

1. Create `hosts/<name>/configuration.nix` — import the relevant profiles + set host-unique values
2. Create `hosts/<name>/disko-config.nix` and `hosts/<name>/sops.nix`
3. Add the `nixosConfigurations.<name>` and `deploy.nodes.<name>` entries in `flake.nix`
4. `git add` the new files, then `nix eval --raw .#nixosConfigurations.<name>.config.networking.hostName`

## Recommendation: use `deploy-rs` for normal updates

For normal updates, use `deploy-rs` from `s145`:

- it has been tested on all three nodes;
- it gives shorter commands than `nixos-rebuild`;
- it supports deploying the two workers together;
- it confirms activation with magic rollback;
- it builds the two `x86_64-linux` workers on `s145`;
- it builds the ARM control-plane on `oracle-eu-arm1` itself.

Keep `nixos-rebuild` around as the transparent fallback when debugging.

## Daily health checks

From any machine that can SSH into the control-plane:

```bash
ssh ubuntu@129.159.222.42 'sudo k3s kubectl get nodes -o wide'
ssh ubuntu@129.159.222.42 'sudo k3s kubectl get pods -A'
```

Check each NixOS host:

```bash
ssh ubuntu@129.159.222.42 'hostname; systemctl is-system-running; systemctl --failed'
ssh ubuntu@oracle-eu-micro1 'hostname; systemctl is-system-running; systemctl --failed'
ssh ubuntu@oracle-eu-micro2 'hostname; systemctl is-system-running; systemctl --failed'
```

Check Tailscale:

```bash
ssh ubuntu@129.159.222.42 'sudo tailscale status'
ssh ubuntu@oracle-eu-micro1 'sudo tailscale ip -4'
ssh ubuntu@oracle-eu-micro2 'sudo tailscale ip -4'
```

The hosts intentionally do not install convenience tools like `vim`, `nano`, `git`, `curl`, `wget`, `htop`, or `tmux`. If you need a temporary tool while debugging, use `nix shell` on the host:

```bash
ssh ubuntu@oracle-eu-micro1
nix shell nixpkgs#vim nixpkgs#curl
```

If a node's Tailscale IP changes, update that host's `services.k3s.nodeIP` in:

```text
hosts/<host>/configuration.nix
```

Then deploy that host again.

## Normal edit and deploy flow

From `s145`:

```bash
cd ~/oracle-cloud-free-tier/anywhere
git status --short
```

Evaluate a value before deploying:

```bash
nix eval --raw .#nixosConfigurations.oracle-eu-micro1.config.networking.hostName
nix eval --raw .#nixosConfigurations.oracle-eu-micro1.config.services.k3s.nodeIP
```

Build only, without activating:

```bash
nix build -L .#nixosConfigurations.oracle-eu-micro1.config.system.build.toplevel
nix build -L .#nixosConfigurations.oracle-eu-micro2.config.system.build.toplevel
```

Deploy with `deploy-rs`:

```bash
nix develop -c deploy .#oracle-eu-micro2
```

## deploy-rs commands

### Deploy one worker

```bash
cd ~/oracle-cloud-free-tier/anywhere

nix develop -c deploy .#oracle-eu-micro1
nix develop -c deploy .#oracle-eu-micro2
```

### Deploy both workers together

```bash
cd ~/oracle-cloud-free-tier/anywhere

nix develop -c deploy --targets .#oracle-eu-micro1 .#oracle-eu-micro2
```

This builds both worker systems on `s145`, copies them to the workers, activates them, and confirms the deploy.

### Deploy the control-plane

```bash
cd ~/oracle-cloud-free-tier/anywhere

nix develop -c deploy .#oracle-eu-arm1
```

`oracle-eu-arm1` is `aarch64-linux`, so deploy-rs is configured with `remoteBuild = true` for that node. The ARM host builds its own system.

### Deploy everything

```bash
cd ~/oracle-cloud-free-tier/anywhere

nix develop -c deploy .
```

This deploys all configured nodes:

```text
oracle-eu-arm1
oracle-eu-micro1
oracle-eu-micro2
```

Prefer workers first, then control-plane separately, unless the change is small and you are confident.

### Check deploy-rs build topology

```bash
nix eval .#deploy.nodes.oracle-eu-micro1.remoteBuild
nix eval .#deploy.nodes.oracle-eu-micro2.remoteBuild
nix eval .#deploy.nodes.oracle-eu-arm1.remoteBuild
```

Expected:

```text
false
false
true
```

### deploy-rs warnings that are usually okay

These are expected during the current workflow:

```text
warning: Git tree ... is dirty
warning: unknown flake output 'deploy'
warning: The check omitted these incompatible systems: aarch64-darwin
warning: ignoring the client-specified setting 'builders-use-substitutes'
```

The deploy is successful when you see:

```text
Activation succeeded!
Deployment confirmed.
```

## nixos-rebuild fallback commands

Use these when debugging deploy-rs or when you want the most explicit command.

### Deploy `oracle-eu-micro1`

```bash
nix run nixpkgs#nixos-rebuild -- \
  switch \
  --flake .#oracle-eu-micro1 \
  --target-host ubuntu@oracle-eu-micro1 \
  --elevate=sudo \
  --no-reexec \
  --use-substitutes
```

### Deploy `oracle-eu-micro2`

```bash
nix run nixpkgs#nixos-rebuild -- \
  switch \
  --flake .#oracle-eu-micro2 \
  --target-host ubuntu@oracle-eu-micro2 \
  --elevate=sudo \
  --no-reexec \
  --use-substitutes
```

### Deploy `oracle-eu-arm1`

```bash
nix run nixpkgs#nixos-rebuild -- \
  switch \
  --flake .#oracle-eu-arm1 \
  --target-host ubuntu@oracle-eu-arm1 \
  --build-host ubuntu@oracle-eu-arm1 \
  --elevate=sudo \
  --no-reexec \
  --use-substitutes
```

## After every deploy

Check the target:

```bash
ssh ubuntu@oracle-eu-micro1 'readlink -f /run/current-system; systemctl is-system-running; systemctl --failed'
```

Check the cluster:

```bash
ssh ubuntu@129.159.222.42 'sudo k3s kubectl get nodes -o wide'
ssh ubuntu@129.159.222.42 'sudo k3s kubectl get pods -A'
```

## Rollback

Rollback the current host to the previous generation:

```bash
ssh ubuntu@oracle-eu-micro1 'sudo nixos-rebuild switch --rollback'
```

Check generations:

```bash
ssh ubuntu@oracle-eu-micro1 'sudo nixos-rebuild list-generations | tail'
```

If the system is unreachable after a bad boot, use Oracle Cloud console recovery. This is why one-host-at-a-time deploys are safer for this cluster.

## SOPS secrets

Use the local age key on `s145`:

```bash
export SOPS_AGE_KEY_FILE="$HOME/.config/sops/age/keys.txt"
```

Edit secrets:

```bash
sops secrets/k3s/secrets.yaml
sops secrets/tailscale/secrets.yaml
sops secrets/rpi/secrets.yaml
```

Test decrypt:

```bash
sops -d secrets/k3s/secrets.yaml >/dev/null && echo k3s-ok
sops -d secrets/tailscale/secrets.yaml >/dev/null && echo tailscale-ok
sops -d secrets/rpi/secrets.yaml >/dev/null && echo rpi-ok
```

If you add a new admin key or host key, update `.sops.yaml` and rekey the affected files:

```bash
sops updatekeys secrets/k3s/secrets.yaml
sops updatekeys secrets/tailscale/secrets.yaml
sops updatekeys secrets/rpi/secrets.yaml
```

Do not commit unencrypted secrets.

## Hermes Agent (Codex + Google Gemini + Telegram on `oracle-eu-arm1`)

The control-plane also runs the [Hermes Agent](https://github.com/NousResearch/hermes-agent) gateway. Its default model remains OpenAI Codex through ChatGPT OAuth, with Google Gemini available through Google's OpenAI-compatible endpoint. Inbound chat lives on Telegram.

### Secrets (one-time, on `s145`)

Get a bot token from `@BotFather` and your numeric Telegram user ID from `@userinfobot`, then encrypt them:

```bash
cd ~/oracle-cloud-free-tier/anywhere
sops secrets/oracle-eu-arm1/secrets.yaml
```

The file must contain (plain values; SOPS encrypts on save):

```yaml
hermes:
  telegram-bot-token: "123456789:AA..."
  telegram-allowed-users: "12345678,87654321"   # comma-separated user IDs
  google-api-key: "AIza..."                      # Google AI Studio / Gemini API key
```

Verify decrypt:

```bash
sops -d secrets/oracle-eu-arm1/secrets.yaml >/dev/null && echo arm1-ok
```

### Deploy

```bash
cd ~/oracle-cloud-free-tier/anywhere
nix develop -c deploy .#oracle-eu-arm1
```

The first build pulls the full hermes-agent flake (Python venv via uv2nix + Node workspace) and runs on the ARM host itself (`remoteBuild = true`). Expect a long first deploy; later deploys hit the local store.

### Bootstrap ChatGPT OAuth (one-time, after deploy)

Codex credentials are minted via device-code OAuth against your ChatGPT account. From any shell on `oracle-eu-arm1`:

```bash
ssh ubuntu@oracle-eu-arm1
hermes auth add codex-oauth
# Open the printed URL in a browser, sign in with ChatGPT, paste the code.
sudo systemctl restart hermes-agent
```

`auth.json` lands at `/var/lib/hermes/.hermes/auth.json` and the module preserves it across redeploys. Hermes refreshes the token automatically; only re-run if `hermes doctor` reports a revoked grant.

### Pick a model

```bash
hermes model
# → choose "OpenAI Codex" for the default Codex model
# or choose "Google Gemini" → pick gemini-3.5-flash
```

### Health checks

```bash
ssh ubuntu@oracle-eu-arm1 'systemctl status hermes-agent --no-pager; journalctl -u hermes-agent -n 50 --no-pager'
ssh ubuntu@oracle-eu-arm1 'hermes doctor'
```

### Security notes

- The `TELEGRAM_ALLOWED_USERS` allowlist is the only gate. Anyone who finds your bot and isn't on the list is silently ignored. Never set `TELEGRAM_ALLOW_ALL_USERS=true`.
- The systemd unit is hardened (`NoNewPrivileges`, `ProtectSystem=strict`, `ReadWritePaths` restricted to `/var/lib/hermes/`), but the agent still runs shell commands as the `hermes` user. Treat any approved Telegram user as having shell access to that account.
- `hermes auth add codex-oauth` uses OAuth scopes documented for the official Codex CLI. Re-using those tokens from a non-Codex client is in the OpenAI ToS grey zone — there is some risk of account-level enforcement if usage patterns look anomalous.

## Updating Nix inputs

Inspect current inputs:

```bash
nix flake metadata
```

Update all inputs:

```bash
nix flake update
```

Or update only one input:

```bash
nix flake lock --update-input nixpkgs
```

Then build and deploy one host first. Do not update all machines at once.

Suggested order:

1. `oracle-eu-micro2`
2. `oracle-eu-micro1`
3. `oracle-eu-arm1`

Keep the control-plane last unless the change is specifically for it.

## Garbage collection and storage cleanup

Each host is configured to run conservative automatic Nix cleanup:

```nix
nix.gc = {
  automatic = true;
  dates = "weekly";
  options = "--delete-older-than 7d";
  randomizedDelaySec = "45min";
};

nix.optimise = {
  automatic = true;
  dates = [ "weekly" ];
  randomizedDelaySec = "45min";
};
```

The bootloader is also limited to the latest 3 generations:

```nix
boot.loader.grub.configurationLimit = 3;
```

This keeps enough rollback history for normal mistakes, while preventing the tiny disks from accumulating months of old systems.

Check disk usage:

```bash
ssh ubuntu@oracle-eu-micro1 'df -h / /nix; sudo nix path-info -Sh /run/current-system'
ssh ubuntu@oracle-eu-micro2 'df -h / /nix; sudo nix path-info -Sh /run/current-system'
ssh ubuntu@oracle-eu-arm1 'df -h / /nix; sudo nix path-info -Sh /run/current-system'
```

Run cleanup manually on one host:

```bash
ssh ubuntu@oracle-eu-micro1 'sudo nix-collect-garbage --delete-older-than 7d; sudo nix store optimise'
```

More aggressive cleanup, only when you are sure you do not need rollback generations:

```bash
ssh ubuntu@oracle-eu-micro1 'sudo nix-collect-garbage -d; sudo nix store optimise'
```

Avoid running aggressive cleanup immediately after a risky deploy. Keep at least one known-good generation until the cluster has been stable for a while.

## `nixos-anywhere` is for reinstalling

Use `nixos-anywhere` only when installing/reinstalling a machine.

Important: the normal `nixos-anywhere` flow with `disko` reformats the target disk. It is not the day-to-day update command.

For normal maintenance, use `nixos-rebuild switch`.

If you ever need to reinstall a micro node:

```bash
cd ~/oracle-cloud-free-tier/anywhere

nix run github:nix-community/nixos-anywhere -- \
  --debug \
  --flake .#oracle-eu-micro2 \
  --target-host ubuntu@89.168.126.35 \
  --copy-host-keys \
  --extra-files /tmp/oracle-eu-micro2-extra \
  --build-on local \
  --no-disko-deps \
  --kexec-extra-flags "--kexec-syscall"
```

Only run this when you are prepared to destroy and recreate that machine's OS disk.

## Terraform / OCI network changes

From the repo root:

```bash
tofu fmt -check
tofu plan -out=tfplan
tofu apply tfplan
```

Use Terraform/OpenTofu for OCI infrastructure changes such as security list rules, instance creation, public IPs, and networking.

Use Nix for OS/service changes such as Tailscale, k3s, users, SSH keys, packages, and systemd services.

For the planned public HTTP/HTTPS path using OCI Network Load Balancer and Kubernetes Gateway API, see [GATEWAY-NLB-PLAN.md](./GATEWAY-NLB-PLAN.md).

## Tiny worker notes

The 1 vCPU / 1 GB RAM workers should stay protected from accidental heavy workloads.

Check taints:

```bash
ssh ubuntu@129.159.222.42 'sudo k3s kubectl describe nodes | grep -E "Name:|Taints:"'
```

If a workload should run on the tiny nodes, give it an explicit toleration for:

```text
tiny=true:NoSchedule
```

This keeps the little machines useful without letting Kubernetes schedule random heavy pods onto them.
