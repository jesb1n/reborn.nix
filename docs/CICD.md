# CI/CD

OpenTofu remains deliberately manual. NixOS activation is a separate protected
workflow, and Flux continues to reconcile Kubernetes resources from main.

## Workflows

| Workflow | Trigger | Behavior |
| --- | --- | --- |
| .github/workflows/apply.yml | workflow_dispatch | OpenTofu init, validate, plan, and apply |
| .github/workflows/destroy.yml | workflow_dispatch | OpenTofu init and destroy |
| .github/workflows/nixos-ci.yml | pull request, main push, manual | Static/VM gates and native x86/ARM release builds |
| .github/workflows/nixos-reconcile.yml | daily schedule, manual | Rebuild exact main SHA and reconcile the selected fleet |
| .github/workflows/nix-cache-keys.yml | pull request, main push, daily schedule, manual | Validate cache trust and alert for manual key review |

OpenTofu apply/destroy and Nix reconciliation are state-changing. They require
deliberate invocation and separate credentials. The CI and cache-monitor jobs
are read-only with respect to the fleet.

## OpenTofu

The OpenTofu workflows use the existing Garage backend and repository secrets:

| Secret | Purpose |
| --- | --- |
| AWS_ACCESS_KEY_ID | Garage S3 access key |
| AWS_SECRET_ACCESS_KEY | Garage S3 secret key |

The backend is a Tailscale address, and the checked-in workflows do not provide
OCI SecurityToken, SOPS, or private-route bootstrap. The local multi-environment
Makefile remains the authoritative operator path:

~~~text
make -C IaC ENV=beijns check-auth
make -C IaC ENV=beijns init
make -C IaC ENV=beijns plan
make -C IaC ENV=beijns deploy
~~~

Do not change the backend or add long-lived cloud keys just to make Actions
initialization succeed.

## Native Nix Builds

Pull requests run the evaluated fleet invariants, deploy-rs checks, the x86 SSH
authentication VM, and all nine release outputs. They do not receive Tailscale,
SSH, SOPS, OCI, or deployment secrets and do not upload deployable artifacts.
The three intended required checks run on every pull request and main push;
there are no path filters that can leave an unrelated change stuck at Expected.

Pushes to main repeat the same gates and publish one short-lived artifact for
each native architecture:

~~~text
closure.nar.zst
manifest.json
SHA256SUMS
~~~

The x86 job uses ubuntu-24.04. The ARM job uses ubuntu-24.04-arm. Both release
jobs fail unless GitHub's runner architecture and `uname -m` match the expected
native system. The release manifest binds the complete deduplicated closure to
the source SHA, architecture, fleet metadata, archive digest, byte count,
compression ratio, and store-path count. Export streams directly through zstd;
upload compression is disabled. The release helper enforces a free-disk
watermark and an optional archive-size ceiling. Job summaries record closure
bytes, archive bytes, path count, compression ratio, and the post-export/import
disk snapshot. Measure the real runner high-water mark and upload/download
timings before enabling production.

## Protected Reconciliation

The reconciliation workflow checks out refs/heads/main once and carries the
resulting immutable SHA through validation, both native builds, artifact download,
and deployment. It runs daily at 20:30 UTC, which is 02:00 Asia/Kolkata. Manual
dispatch supports check-only/deploy plus all, x86, arm, canary, workers,
control-plane, or named-host targets. The production concurrency group never
cancels an activation.

Scheduled runs default to check-only. Set the repository variable
`NIXOS_SCHEDULED_DEPLOY_ENABLED=true` only after both native GitHub runners have
completed the archive/disk proof and the check-only, canary, and full manual
deployment gates have succeeded. Manual deploy dispatch remains available for
the staged rollout.

The deployment job is a hosted x86 runner. It checks that both immutable artifact
IDs and service-reported digests are present and distinct, then downloads by ID.
It joins Tailscale ephemerally as tag:nixos-ci and uses strict OpenSSH host-key
checking. Configure the protected fleet-production environment with:

| Secret | Purpose |
| --- | --- |
| FLEET_SSH_PRIVATE_KEY | Dedicated Ed25519 key for duck |
| NIX_DEPLOY_KNOWN_HOSTS | Reviewed pinned host keys |
| TS_OAUTH_CLIENT_ID | Restricted Tailscale OAuth client |
| TS_OAUTH_SECRET | Restricted Tailscale OAuth secret |

Bootstrap the matching public key to every host in the evaluated fleet inventory
before enabling deployment.
The reconciler verifies exact artifact contents and checksums, inspects the
legacy Nix export with `nix nario list`, and requires its exact store-path set to
match the declared root closures. It then imports both archives before contacting
a host, compares release metadata with the evaluated fleet inventory, and
confirms every declared toplevel and activation path.

Each host record also carries `activation_drv`, the exact derivation that produced
the deploy-rs activation output. The export includes that derivation and its
requisite closure. Before any host is contacted, the reconciler verifies that the
imported activation output resolves back to the manifest's deriver. During
activation it disables builders, substituters, and substitution for deploy-rs. The
preceding `nix copy` is also offline with builders and substituters disabled, and
deploy-rs is forced into fast-connection mode so the destination cannot substitute
the closure independently. An absent imported path therefore fails the release
instead of silently building on the runner or a target.

Each selected host is then checked through a fresh strict SSH session for
hostname, architecture, current generation, systemd state, failed units,
Tailscale, k3s, and passwordless sudo. Changed hosts receive only the imported
toplevel and activation paths. A generated literal deploy-rs definition sets
remoteBuild = false while retaining magic rollback and inventory timeouts.
Canaries run first, workers run next, and s145 is last. Any failed gate stops
later hosts; there is no automatic fleet-wide rollback.

The check-only mode performs all verification and health checks without copying
or activating. An unchanged full-fleet run performs zero activations but still
checks canaries and cluster readiness.

## Cache Key Monitoring

anywhere/lib/binary-caches.nix is the single reviewed cache trust inventory.
The workflow validates HTTPS URLs, unique names/URLs/keys, approved scopes, and
the baseline cache. Scheduled and manual runs also fetch each allowlisted
`nix-cache-info` endpoint with TLS verification, bounded size/time, and no
redirects, and require the standard `/nix/store` store directory.

The Nix binary-cache protocol does not portably publish cache signing keys in
`nix-cache-info`, so automatic key discovery and rotation PR creation are
disabled. The scheduled workflow emits a manual-review alert and records only
the committed public-key fingerprints and endpoint reachability. It never
changes trust policy, writes secrets, merges, or deploys.

For rotation, verify the replacement key through an independent official
channel such as the upstream project's signed announcement, repository, or
Cachix cache settings. Update only `anywhere/lib/binary-caches.nix`, run the full
Nix CI, and merge through normal human review. If no corroboration exists, keep
the old key pinned; remove or temporarily stop using the affected cache through
a separate reviewed change and allow source builds rather than accepting an
unauthenticated replacement key.

## Scope And Safety

The workflows do not include pro-darwin, OpenTofu state redesign, Flux mutation,
nixos-anywhere, automatic lock updates, commits, pushes, credential bootstrap,
GitHub settings changes, Tailscale policy changes, or live deployment during
repository implementation. Those actions require separate explicit approval.
