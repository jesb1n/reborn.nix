#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ANYWHERE_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
RECONCILER="$ANYWHERE_DIR/scripts/fleet-reconcile"
SOURCE_SHA=ae136afecd040e4d3e057703a5e2abcd744da13f

TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/fleet-reconcile-tests.XXXXXX")
cleanup_tests() {
  if [[ "${FLEET_TEST_KEEP:-false}" == true ]]; then
    printf 'kept test fixtures at %s\n' "$TEST_ROOT" >&2
  else
    rm -rf -- "$TEST_ROOT"
  fi
}
trap cleanup_tests EXIT

passes=0
failures=0

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum -- "$1" | awk '{print $1}'
  else
    shasum -a 256 -- "$1" | awk '{print $1}'
  fi
}

desired_path() {
  printf '/nix/store/%s-toplevel\n' "$1"
}

activation_path() {
  printf '/nix/store/%s-activation\n' "$1"
}

write_inventory() {
  local file=$1
  jq -n '
    def host($system; $role; $class; $wave; $order; $at; $remote; $fast):
      {system:$system, role:$role, class:$class, wave:$wave, order:$order,
       activationTimeout:$at, confirmTimeout:60, remoteBuild:$remote,
       fastConnection:$fast};
    {
      "oracle-eu-micro2": host("x86_64-linux"; "agent"; "micro"; "x86-canary"; 10; 600; false; true),
      "oracle-eu-arm1": host("aarch64-linux"; "agent"; "arm"; "arm-canary"; 20; 600; true; false),
      "oracle-eu-micro1": host("x86_64-linux"; "agent"; "micro"; "workers"; 30; 600; false; true),
      "oracle-in-micro1": host("x86_64-linux"; "agent"; "micro"; "workers"; 40; 600; false; true),
      "oracle-in-micro2": host("x86_64-linux"; "agent"; "micro"; "workers"; 50; 600; false; true),
      "oracle-in-arm1": host("aarch64-linux"; "agent"; "arm"; "workers"; 60; 600; true; false),
      "rpi": host("aarch64-linux"; "agent"; "rpi"; "workers"; 70; 900; true; false),
      "hp348": host("x86_64-linux"; "agent"; "on-prem"; "workers"; 80; 600; true; true),
      "nuc7i3": host("x86_64-linux"; "agent"; "on-prem"; "workers"; 90; 600; true; true),
      "s145": host("x86_64-linux"; "server"; "on-prem"; "control-plane"; 100; 600; true; false)
    }
  ' >"$file"
}

refresh_checksums() {
  local release=$1
  {
    printf '%s  closure.nar.zst\n' "$(sha256_file "$release/closure.nar.zst")"
    printf '%s  manifest.json\n' "$(sha256_file "$release/manifest.json")"
  } >"$release/SHA256SUMS"
}

write_release() {
  local case_dir=$1 system=$2 release
  release="$case_dir/releases/$system"
  local inventory_sha archive_sha archive_bytes host_count path_count
  mkdir -p -- "$release"
  printf 'mock archive for %s\n' "$system" >"$release/closure.nar.zst"
  inventory_sha=$(jq -S -c . "$case_dir/inventory.json" | {
    if command -v sha256sum >/dev/null 2>&1; then sha256sum; else shasum -a 256; fi
  } | awk '{print $1}')
  archive_sha=$(sha256_file "$release/closure.nar.zst")
  archive_bytes=$(wc -c <"$release/closure.nar.zst" | tr -d ' ')
  host_count=$(jq --arg system "$system" '[to_entries[] | select(.value.system == $system)] | length' "$case_dir/inventory.json")
  path_count=$((host_count * 3))
  jq -S \
    --arg source_sha "$SOURCE_SHA" \
    --arg system "$system" \
    --arg inventory_sha "$inventory_sha" \
    --arg archive_sha "$archive_sha" \
    --argjson archive_bytes "$archive_bytes" \
    --argjson path_count "$path_count" '
      def record($name; $value):
        {system:$value.system, role:$value.role, class:$value.class,
         wave:$value.wave, order:$value.order,
         activation_timeout:$value.activationTimeout,
         confirm_timeout:$value.confirmTimeout,
         remote_build:$value.remoteBuild,
         fast_connection:$value.fastConnection,
         toplevel:("/nix/store/" + $name + "-toplevel"),
         activation:("/nix/store/" + $name + "-activation"),
         activation_drv:("/nix/store/" + $name + "-activation.drv")};
      {
        schema:1,
        source_sha:$source_sha,
        system:$system,
        created_by_run:"mock/1",
        inventory_sha256:$inventory_sha,
        archive:{
          file:"closure.nar.zst",
          sha256:$archive_sha,
          bytes:$archive_bytes,
          closure_bytes:4096,
          store_path_count:$path_count,
          compression_ratio:0.5
        },
        hosts:(with_entries(select(.value.system == $system) |
          .value = record(.key; .value)))
      }
    ' "$case_dir/inventory.json" >"$release/manifest.json"
  refresh_checksums "$release"
}

create_case() {
  local name=$1 case_dir
  case_dir="$TEST_ROOT/$name"
  mkdir -p -- "$case_dir/releases" "$case_dir/state" "$case_dir/live"
  write_inventory "$case_dir/inventory.json"
  write_release "$case_dir" x86_64-linux
  write_release "$case_dir" aarch64-linux
  : >"$case_dir/known_hosts"
  : >"$case_dir/ssh-key"
  chmod 600 "$case_dir/known_hosts" "$case_dir/ssh-key"
  printf '%s\n' "$case_dir"
}

install_mock() {
  local path=$1
  shift
  printf '%s\n' '#!/usr/bin/env bash' 'set -Eeuo pipefail' >"$path"
  printf '%s\n' "$@" >>"$path"
  chmod +x "$path"
}

install_mocks() {
  local case_dir=$1 mocks
  mocks="$case_dir/mocks"
  mkdir -p -- "$mocks" "$case_dir/state" "$case_dir/live"

  install_mock "$mocks/git" "$(cat <<'MOCK'
case "${1:-}" in
  rev-parse) printf "%s\n" "$MOCK_SOURCE_SHA" ;;
  status) exit 0 ;;
  *) printf "unexpected git invocation: %q\n" "$*" >&2; exit 91 ;;
esac
MOCK
)"

  install_mock "$mocks/zstd" "$(cat <<'MOCK'
[[ "${1:-}" == -dc && "${2:-}" == -- && -f "${3:-}" ]] || exit 92
printf 'mock archive for %s\n' "$(basename -- "${3%/*}")"
MOCK
)"

  install_mock "$mocks/nix-store" "$(cat <<'MOCK'
case "${1:-}" in
  --import)
    command cat >/dev/null
    printf "import\n" >>"$MOCK_STATE/nix-store.log"
    ;;
  --verify-path)
    [[ "${2:-}" == /nix/store/* ]]
    ;;
  --query)
    if [[ "${2:-}" == --deriver && "${3:-}" == /nix/store/* ]]; then
      printf '%s-activation.drv\n' "${3%-activation}"
    elif [[ "${2:-}" == --requisites && "${3:-}" == /nix/store/* ]]; then
      printf "%s\n" "$3"
    else
      exit 93
    fi
    ;;
  *)
    printf "unexpected nix-store invocation: %q\n" "$*" >&2
    exit 94
    ;;
esac
MOCK
)"

  install_mock "$mocks/nix" "$(cat <<'MOCK'
quote_args() {
  local arg
  for arg in "$@"; do printf "%q " "$arg"; done
  printf "\n"
}
case "${1:-}" in
  eval)
    command cat -- "$MOCK_INVENTORY"
    ;;
  nario)
    [[ "${2:-}" == list && "${3:-}" == --json && "${4:-}" == --no-pretty ]] || exit 96
    payload=$(command cat)
    system=${payload##*for }
    manifest="$MOCK_RELEASES/$system/manifest.json"
    [[ -f "$manifest" ]] || exit 96
    extra=''
    drop=''
    [[ ! -f "$MOCK_STATE/archive-extra-$system" ]] || extra=$(command cat -- "$MOCK_STATE/archive-extra-$system")
    [[ ! -f "$MOCK_STATE/archive-drop-$system" ]] || drop=$(command cat -- "$MOCK_STATE/archive-drop-$system")
    jq -n --slurpfile manifest "$manifest" --arg extra "$extra" --arg drop "$drop" '
      ([ $manifest[0].hosts[] | [.toplevel, .activation, .activation_drv][] ] |
       map(select(. != $drop)) + (if $extra == "" then [] else [$extra] end) | unique) as $paths |
      {version:1, paths:(reduce $paths[] as $path ({}; .[$path] = {references:[]}))}
    '
    ;;
  copy)
    { printf "copy "; quote_args "$@"; } >>"$MOCK_STATE/nix.log"
    printf "NIX_SSHOPTS=%s\n" "${NIX_SSHOPTS:-}" >>"$MOCK_STATE/nix.log"
    ;;
  *)
    printf "unexpected nix invocation: %q\n" "$*" >&2
    exit 96
    ;;
esac
MOCK
)"

  install_mock "$mocks/deploy" "$(cat <<'MOCK'
quote_args() {
  local arg
  for arg in "$@"; do printf "%q " "$arg"; done
  printf "\n"
}
{ printf "deploy "; quote_args "$@"; } >>"$MOCK_STATE/deploy.log"
printf '%s' "${NIX_CONFIG:-}" >"$MOCK_STATE/deploy-nix-config"
deploy_file=""
host=""
  while (($# > 0)); do
    case "$1" in
      --file)
        deploy_file=$2
        shift 2
        ;;
      --skip-checks)
        shift
        ;;
      --fast-connection)
        [[ "${2:-}" == true ]] || exit 95
        shift 2
        ;;
      --)
        break
        ;;
    *)
      host=$1
      shift
      ;;
  esac
done
[[ -n "$host" && -n "$deploy_file" && -f "$deploy_file/default.nix" ]] || exit 95
command cp -- "$deploy_file/default.nix" "$MOCK_STATE/deploy-$host.nix"
: >"$MOCK_STATE/activated-$host"
MOCK
)"

  install_mock "$mocks/ssh" "$(cat <<'MOCK'
target=${*: -2:1}
remote_command=${*: -1}
host=${target#*@}
printf "%s\t%s\n" "$host" "${remote_command%%$'\n'*}" >>"$MOCK_STATE/ssh.log"

if [[ "$remote_command" == *"kubectl get node "* ]]; then
  prefix="get node '"
  suffix="' -o json"
  node=${remote_command#*"$prefix"}
  node=${node%%"$suffix"*}
  [[ -n "$node" ]] || exit 97
  if [[ -f "$MOCK_STATE/activated-$node" ]]; then
    count_file="$MOCK_STATE/post-node-$node.count"
    count=0
    [[ ! -f "$count_file" ]] || count=$(command cat -- "$count_file")
    count=$((count + 1))
    printf "%s\n" "$count" >"$count_file"
    if (( count <= ${MOCK_POST_NODE_NOT_READY:-0} )); then
      jq -n --arg node "$node" '{metadata:{name:$node},status:{conditions:[{type:"Ready",status:"False"}]}}'
      exit 0
    fi
  fi
  jq -n --arg node "$node" '{metadata:{name:$node},status:{conditions:[{type:"Ready",status:"True"}]}}'
  exit 0
fi

if [[ "$remote_command" == *"kubectl get nodes -o json"* ]]; then
  hosts=$(jq -r 'keys[]' "$MOCK_INVENTORY")
  printf '{"items":['
  first=true
  while IFS= read -r node; do
    [[ "$first" == true ]] || printf ','
    first=false
    jq -n --arg node "$node" '{metadata:{name:$node},status:{conditions:[{type:"Ready",status:"True"}]}}' | tr -d '\n'
  done <<<"$hosts"
  printf ']}\n'
  exit 0
fi

if [[ "$remote_command" == *"kubectl get pods -A -o json"* ]]; then
  printf "%s\n" '{"items":[]}'
  exit 0
fi

system=$(jq -r --arg host "$host" '.[$host].system' "$MOCK_INVENTORY")
[[ "$system" != null ]] || exit 98
arch=x86_64
[[ "$system" != aarch64-linux ]] || arch=aarch64
desired="/nix/store/$host-toplevel"
manifest_file="$MOCK_RELEASES/$system/manifest.json"
if [[ -f "$manifest_file" ]]; then
  desired=$(jq -r --arg host "$host" '.hosts[$host].toplevel // empty' \
    "$manifest_file")
fi
current=$desired
[[ ! -f "$MOCK_LIVE/$host" ]] || current=$(command cat -- "$MOCK_LIVE/$host")

if [[ -f "$MOCK_STATE/activated-$host" ]]; then
  current=$desired
  count_file="$MOCK_STATE/post-health-$host.count"
  count=0
  [[ ! -f "$count_file" ]] || count=$(command cat -- "$count_file")
  count=$((count + 1))
  printf "%s\n" "$count" >"$count_file"
  if (( count <= ${MOCK_POST_TRANSPORT_FAILURES:-0} )); then
    printf "ssh: connect to host %s port 22: Connection timed out\n" "$host" >&2
    exit 255
  fi
  if [[ "${MOCK_POST_HOSTKEY_FAILURE:-false}" == true ]]; then
    printf "Host key verification failed.\n" >&2
    exit 255
  fi
  if [[ "${MOCK_POST_WRONG_IDENTITY:-false}" == true || -f "$MOCK_STATE/wrong-identity" ]]; then
    host="wrong-host"
  fi
fi

printf "hostname=%s\n" "$host"
printf "arch=%s\n" "$arch"
printf "current=%s\n" "$current"
printf "systemd=running\n"
printf "failed=0\n"
printf "tailscale=active\n"
printf "tailscale_backend=Running\n"
printf "k3s=active\n"
printf "sudo=ok\n"
MOCK
)"
}

set_live_old() {
  local case_dir=$1 host=$2
  printf '/nix/store/%s-old\n' "$host" >"$case_dir/live/$host"
}

run_reconciler() {
  local case_dir=$1
  shift
  install_mocks "$case_dir"
  set +e
  env \
    NIX_BIN="$case_dir/mocks/nix" \
    NIX_STORE_BIN="$case_dir/mocks/nix-store" \
    ZSTD_BIN="$case_dir/mocks/zstd" \
    SSH_BIN="$case_dir/mocks/ssh" \
    GIT_BIN="$case_dir/mocks/git" \
    DEPLOY_BIN="$case_dir/mocks/deploy" \
    MOCK_SOURCE_SHA="$SOURCE_SHA" \
    MOCK_INVENTORY="$case_dir/inventory.json" \
    MOCK_RELEASES="$case_dir/releases" \
    MOCK_STATE="$case_dir/state" \
    MOCK_LIVE="$case_dir/live" \
    MOCK_POST_WRONG_IDENTITY="${MOCK_POST_WRONG_IDENTITY:-false}" \
    MOCK_POST_HOSTKEY_FAILURE="${MOCK_POST_HOSTKEY_FAILURE:-false}" \
    MOCK_POST_TRANSPORT_FAILURES="${MOCK_POST_TRANSPORT_FAILURES:-0}" \
    MOCK_POST_NODE_NOT_READY="${MOCK_POST_NODE_NOT_READY:-0}" \
    FLEET_RECONCILE_RETRY_ATTEMPTS=5 \
    FLEET_RECONCILE_RETRY_BASE_SECONDS=0 \
    FLEET_RECONCILE_RETRY_JITTER_SECONDS=0 \
    "$RECONCILER" \
      --release "$case_dir/releases/x86_64-linux" \
      --release "$case_dir/releases/aarch64-linux" \
      --source-sha "$SOURCE_SHA" \
      --allow-dirty \
      "$@" >"$case_dir/stdout" 2>"$case_dir/stderr"
  RUN_STATUS=$?
  set -e
}

assert_status() {
  local expected=$1
  [[ "$RUN_STATUS" == "$expected" ]] || {
    printf 'expected status %s, got %s\n' "$expected" "$RUN_STATUS" >&2
    return 1
  }
}

assert_success() {
  [[ "$RUN_STATUS" == 0 ]] || {
    printf 'command failed with status %s:\n' "$RUN_STATUS" >&2
    sed -n '1,200p' "$CASE_DIR/stderr" >&2
    return 1
  }
}

assert_failure() {
  [[ "$RUN_STATUS" != 0 ]] || {
    printf 'command unexpectedly succeeded\n' >&2
    return 1
  }
}

assert_contains() {
  local file=$1 expected=$2
  grep -F -- "$expected" "$file" >/dev/null || {
    printf 'missing expected text %q in %s:\n' "$expected" "$file" >&2
    sed -n '1,200p' "$file" >&2
    return 1
  }
}

assert_not_contains() {
  local file=$1 unexpected=$2
  if grep -F -- "$unexpected" "$file" >/dev/null; then
    printf 'unexpected text %q in %s:\n' "$unexpected" "$file" >&2
    sed -n '1,200p' "$file" >&2
    return 1
  fi
}

run_test() {
  local name=$1 function=$2
  if [[ -n "${FLEET_TEST_FILTER:-}" && "$name" != *"$FLEET_TEST_FILTER"* ]]; then
    return 0
  fi
  set +e
  (set -Eeuo pipefail; CASE_DIR=''; "$function")
  status=$?
  set -e
  if (( status == 0 )); then
    passes=$((passes + 1))
    printf 'ok %s - %s\n' "$passes" "$name"
  else
    failures=$((failures + 1))
    printf 'not ok %s - %s\n' "$((passes + failures))" "$name"
  fi
}

test_valid_verify_only() {
  CASE_DIR=$(create_case valid-verify)
  run_reconciler "$CASE_DIR" --verify-only
  assert_success
  assert_contains "$CASE_DIR/stderr" 'release verification/import complete'
  [[ ! -e "$CASE_DIR/state/ssh.log" ]]
}

test_rejects_unexpected_artifact_file() {
  CASE_DIR=$(create_case unexpected-file)
  : >"$CASE_DIR/releases/x86_64-linux/extra"
  run_reconciler "$CASE_DIR" --verify-only
  assert_failure
  assert_contains "$CASE_DIR/stderr" 'unexpected release file: extra'
  [[ ! -e "$CASE_DIR/state/nix-store.log" ]]
}

test_rejects_checksum_mismatch() {
  CASE_DIR=$(create_case checksum-mismatch)
  printf 'tampered\n' >>"$CASE_DIR/releases/aarch64-linux/closure.nar.zst"
  run_reconciler "$CASE_DIR" --verify-only
  assert_failure
  assert_contains "$CASE_DIR/stderr" 'checksum mismatch'
}

test_rejects_source_binding_mismatch() {
  CASE_DIR=$(create_case source-mismatch)
  jq '.source_sha = "0000000000000000000000000000000000000000"' \
    "$CASE_DIR/releases/x86_64-linux/manifest.json" >"$CASE_DIR/manifest.tmp"
  mv -- "$CASE_DIR/manifest.tmp" "$CASE_DIR/releases/x86_64-linux/manifest.json"
  refresh_checksums "$CASE_DIR/releases/x86_64-linux"
  run_reconciler "$CASE_DIR" --verify-only
  assert_failure
  assert_contains "$CASE_DIR/stderr" 'source SHA mismatch'
}

test_rejects_manifest_without_run_identity() {
  CASE_DIR=$(create_case missing-run-identity)
  jq 'del(.created_by_run)' "$CASE_DIR/releases/x86_64-linux/manifest.json" >"$CASE_DIR/manifest.tmp"
  mv -- "$CASE_DIR/manifest.tmp" "$CASE_DIR/releases/x86_64-linux/manifest.json"
  refresh_checksums "$CASE_DIR/releases/x86_64-linux"
  run_reconciler "$CASE_DIR" --verify-only
  assert_failure
  assert_contains "$CASE_DIR/stderr" 'manifest schema validation failed'
}

test_accepts_store_names_with_nix_special_characters() {
  CASE_DIR=$(create_case store-name-characters)
  jq '
    .hosts["hp348"].toplevel = "/nix/store/abc?name=1-toplevel" |
    .hosts["hp348"].activation = "/nix/store/abc?name=1-activation" |
    .hosts["hp348"].activation_drv = "/nix/store/abc?name=1-activation.drv"
  ' "$CASE_DIR/releases/x86_64-linux/manifest.json" >"$CASE_DIR/manifest.tmp"
  mv -- "$CASE_DIR/manifest.tmp" "$CASE_DIR/releases/x86_64-linux/manifest.json"
  refresh_checksums "$CASE_DIR/releases/x86_64-linux"
  run_reconciler "$CASE_DIR" --verify-only
  assert_success
}

test_escapes_store_paths_in_generated_nix() {
  CASE_DIR=$(create_case escaped-store-name)
  set_live_old "$CASE_DIR" oracle-eu-micro2
  jq '
    .hosts["oracle-eu-micro2"].activation = "/nix/store/abc${unsafe}-activation" |
    .hosts["oracle-eu-micro2"].activation_drv = "/nix/store/abc${unsafe}-activation.drv"
  ' "$CASE_DIR/releases/x86_64-linux/manifest.json" >"$CASE_DIR/manifest.tmp"
  mv -- "$CASE_DIR/manifest.tmp" "$CASE_DIR/releases/x86_64-linux/manifest.json"
  refresh_checksums "$CASE_DIR/releases/x86_64-linux"
  run_reconciler "$CASE_DIR" --known-hosts "$CASE_DIR/known_hosts" --deploy --host oracle-eu-micro2
  assert_success
  assert_contains "$CASE_DIR/state/deploy-oracle-eu-micro2.nix" 'abc\${unsafe}-activation'
}

test_shell_quotes_store_paths_for_remote_checks() {
  CASE_DIR=$(create_case shell-quoted-store-name)
  set_live_old "$CASE_DIR" oracle-eu-micro2
  jq '
    .hosts["oracle-eu-micro2"].toplevel = "/nix/store/abc\u0027unsafe-toplevel" |
    .hosts["oracle-eu-micro2"].activation = "/nix/store/abc\u0027unsafe-activation" |
    .hosts["oracle-eu-micro2"].activation_drv = "/nix/store/abc\u0027unsafe-activation.drv"
  ' "$CASE_DIR/releases/x86_64-linux/manifest.json" >"$CASE_DIR/manifest.tmp"
  mv -- "$CASE_DIR/manifest.tmp" "$CASE_DIR/releases/x86_64-linux/manifest.json"
  refresh_checksums "$CASE_DIR/releases/x86_64-linux"
  run_reconciler "$CASE_DIR" --known-hosts "$CASE_DIR/known_hosts" --deploy --host oracle-eu-micro2
  assert_success
  assert_contains "$CASE_DIR/state/ssh.log" \
    "nix path-info '/nix/store/abc'\\''unsafe-toplevel' '/nix/store/abc'\\''unsafe-activation' >/dev/null"
}

test_rejects_inventory_metadata_mismatch() {
  CASE_DIR=$(create_case inventory-mismatch)
  jq '.hosts["hp348"].wave = "control-plane"' \
    "$CASE_DIR/releases/x86_64-linux/manifest.json" >"$CASE_DIR/manifest.tmp"
  mv -- "$CASE_DIR/manifest.tmp" "$CASE_DIR/releases/x86_64-linux/manifest.json"
  refresh_checksums "$CASE_DIR/releases/x86_64-linux"
  run_reconciler "$CASE_DIR" --verify-only
  assert_failure
  assert_contains "$CASE_DIR/stderr" 'release metadata differs for hp348'
}

test_rejects_activation_deriver_mismatch() {
  CASE_DIR=$(create_case deriver-mismatch)
  jq '.hosts["hp348"].activation_drv = "/nix/store/unrelated-activation.drv"' \
    "$CASE_DIR/releases/x86_64-linux/manifest.json" >"$CASE_DIR/manifest.tmp"
  mv -- "$CASE_DIR/manifest.tmp" "$CASE_DIR/releases/x86_64-linux/manifest.json"
  refresh_checksums "$CASE_DIR/releases/x86_64-linux"
  run_reconciler "$CASE_DIR" --verify-only
  assert_failure
  assert_contains "$CASE_DIR/stderr" 'activation deriver mismatch for hp348'
  [[ ! -e "$CASE_DIR/state/ssh.log" ]]
}

test_rejects_same_count_archive_path_substitution() {
  CASE_DIR=$(create_case archive-path-substitution)
  printf '%s\n' '/nix/store/hp348-toplevel' \
    >"$CASE_DIR/state/archive-drop-x86_64-linux"
  printf '%s\n' '/nix/store/unrelated-extra-path' \
    >"$CASE_DIR/state/archive-extra-x86_64-linux"
  run_reconciler "$CASE_DIR" --verify-only
  assert_failure
  assert_contains "$CASE_DIR/stderr" \
    'x86_64-linux archive path set differs from declared root closures'
  [[ ! -e "$CASE_DIR/state/ssh.log" ]]
}

test_rejects_host_in_wrong_architecture_artifact() {
  CASE_DIR=$(create_case wrong-architecture)
  jq -s '
    .[0] as $x | .[1] as $a |
    ($x.hosts["oracle-eu-micro2"]) as $xh |
    ($a.hosts["oracle-eu-arm1"]) as $ah |
    [($x | del(.hosts["oracle-eu-micro2"]) | .hosts["oracle-eu-arm1"] = $ah),
     ($a | del(.hosts["oracle-eu-arm1"]) | .hosts["oracle-eu-micro2"] = $xh)]
  ' "$CASE_DIR/releases/x86_64-linux/manifest.json" \
    "$CASE_DIR/releases/aarch64-linux/manifest.json" >"$CASE_DIR/swapped.json"
  jq '.[0]' "$CASE_DIR/swapped.json" >"$CASE_DIR/releases/x86_64-linux/manifest.json"
  jq '.[1]' "$CASE_DIR/swapped.json" >"$CASE_DIR/releases/aarch64-linux/manifest.json"
  refresh_checksums "$CASE_DIR/releases/x86_64-linux"
  refresh_checksums "$CASE_DIR/releases/aarch64-linux"
  run_reconciler "$CASE_DIR" --verify-only
  assert_failure
  assert_contains "$CASE_DIR/stderr" 'manifest schema validation failed'
}

test_target_selection_preserves_inventory_order() {
  CASE_DIR=$(create_case target-order)
  run_reconciler "$CASE_DIR" --known-hosts "$CASE_DIR/known_hosts" --check-only \
    --host rpi --host oracle-eu-micro1
  assert_success
  mapfile -t hosts < <(awk -F '\t' '$2 ~ /^set -eu/ {print $1}' "$CASE_DIR/state/ssh.log")
  actual=$(IFS=' '; printf '%s' "${hosts[*]}")
  [[ "$actual" == 'oracle-eu-micro1 rpi s145' ]] || {
    printf 'unexpected preflight order: %s\n' "$actual" >&2
    return 1
  }
  assert_contains "$CASE_DIR/state/ssh.log" \
    "sudo k3s kubectl get node 'oracle-eu-micro1' -o json"
  [[ ! -e "$CASE_DIR/state/nix.log" ]]
}

test_changed_unselected_canary_blocks_worker() {
  CASE_DIR=$(create_case changed-canary)
  set_live_old "$CASE_DIR" oracle-eu-micro2
  set_live_old "$CASE_DIR" oracle-eu-micro1
  run_reconciler "$CASE_DIR" --known-hosts "$CASE_DIR/known_hosts" --deploy \
    --host oracle-eu-micro1
  assert_failure
  assert_contains "$CASE_DIR/stderr" 'required canary oracle-eu-micro2 is not at the desired path'
  [[ ! -e "$CASE_DIR/state/nix.log" ]]
}

test_x86_canary_can_lead_arm_canary() {
  CASE_DIR=$(create_case x86-canary-first)
  set_live_old "$CASE_DIR" oracle-eu-micro2
  set_live_old "$CASE_DIR" oracle-eu-arm1
  run_reconciler "$CASE_DIR" --known-hosts "$CASE_DIR/known_hosts" --deploy \
    --host oracle-eu-micro2
  assert_success
  assert_contains "$CASE_DIR/state/nix.log" 'ssh://duck@oracle-eu-micro2'
  assert_not_contains "$CASE_DIR/state/nix.log" 'ssh://duck@oracle-eu-arm1'
}

test_arm_canary_requires_x86_canary() {
  CASE_DIR=$(create_case arm-canary-dependency)
  set_live_old "$CASE_DIR" oracle-eu-micro2
  set_live_old "$CASE_DIR" oracle-eu-arm1
  run_reconciler "$CASE_DIR" --known-hosts "$CASE_DIR/known_hosts" --deploy \
    --host oracle-eu-arm1
  assert_failure
  assert_contains "$CASE_DIR/stderr" \
    'required canary oracle-eu-micro2 is not at the desired path; select it first'
  [[ ! -e "$CASE_DIR/state/nix.log" ]]
}

test_control_plane_preflights_all_dependencies() {
  CASE_DIR=$(create_case control-plane-gates)
  set_live_old "$CASE_DIR" s145
  run_reconciler "$CASE_DIR" --known-hosts "$CASE_DIR/known_hosts" --deploy --host s145
  assert_success
  mapfile -t hosts < <(awk -F '\t' '$2 ~ /^set -eu/ {print $1}' "$CASE_DIR/state/ssh.log")
  expected='oracle-eu-micro2 oracle-eu-arm1 oracle-eu-micro1 oracle-in-micro1 oracle-in-micro2 oracle-in-arm1 rpi hp348 nuc7i3 s145 s145'
  actual=$(IFS=' '; printf '%s' "${hosts[*]}")
  [[ "$actual" == "$expected" ]] || {
    printf 'unexpected control-plane gate order: %s\n' "$actual" >&2
    return 1
  }
  assert_contains "$CASE_DIR/state/nix.log" 'ssh://duck@s145'
  assert_not_contains "$CASE_DIR/state/nix.log" 'ssh://duck@hp348'
}

test_changed_worker_blocks_control_plane() {
  CASE_DIR=$(create_case changed-worker-control-plane)
  set_live_old "$CASE_DIR" oracle-in-arm1
  set_live_old "$CASE_DIR" s145
  run_reconciler "$CASE_DIR" --known-hosts "$CASE_DIR/known_hosts" --deploy --host s145
  assert_failure
  assert_contains "$CASE_DIR/stderr" \
    'required worker oracle-in-arm1 is not at the desired path; select it first'
  [[ ! -e "$CASE_DIR/state/nix.log" ]]
}

test_post_activation_ssh_retries_transient_failure() {
  CASE_DIR=$(create_case post-ssh-retry)
  set_live_old "$CASE_DIR" oracle-eu-micro2
  MOCK_POST_TRANSPORT_FAILURES=1 run_reconciler "$CASE_DIR" \
    --known-hosts "$CASE_DIR/known_hosts" --deploy --host oracle-eu-micro2
  assert_success
  [[ "$(cat "$CASE_DIR/state/post-health-oracle-eu-micro2.count")" == 2 ]]
  assert_contains "$CASE_DIR/stderr" 'health attempt 1/5 failed for oracle-eu-micro2'
}

test_identity_mismatch_is_not_retried() {
  CASE_DIR=$(create_case identity-no-retry)
  set_live_old "$CASE_DIR" oracle-eu-micro2
  : >"$CASE_DIR/state/wrong-identity"
  run_reconciler "$CASE_DIR" \
    --known-hosts "$CASE_DIR/known_hosts" --deploy --host oracle-eu-micro2
  assert_failure
  assert_contains "$CASE_DIR/stderr" 'SSH identity mismatch for oracle-eu-micro2'
  [[ "$(cat "$CASE_DIR/state/post-health-oracle-eu-micro2.count")" == 1 ]]
}

test_host_key_failure_is_not_retried() {
  CASE_DIR=$(create_case hostkey-no-retry)
  set_live_old "$CASE_DIR" oracle-eu-micro2
  export MOCK_POST_HOSTKEY_FAILURE=true
  run_reconciler "$CASE_DIR" \
    --known-hosts "$CASE_DIR/known_hosts" --deploy --host oracle-eu-micro2
  unset MOCK_POST_HOSTKEY_FAILURE
  assert_failure
  assert_contains "$CASE_DIR/stderr" 'non-retryable SSH failure for oracle-eu-micro2'
  [[ "$(cat "$CASE_DIR/state/post-health-oracle-eu-micro2.count")" == 1 ]]
}

test_node_ready_retries_after_activation() {
  CASE_DIR=$(create_case node-retry)
  set_live_old "$CASE_DIR" oracle-eu-micro2
  MOCK_POST_NODE_NOT_READY=1 run_reconciler "$CASE_DIR" \
    --known-hosts "$CASE_DIR/known_hosts" --deploy --host oracle-eu-micro2
  assert_success
  [[ "$(cat "$CASE_DIR/state/post-node-oracle-eu-micro2.count")" == 2 ]]
  assert_contains "$CASE_DIR/stderr" 'node Ready attempt 1/5 failed for oracle-eu-micro2'
}

test_deploy_invocation_uses_requested_ssh_user_and_strict_options() {
  CASE_DIR=$(create_case deploy-invocation)
  set_live_old "$CASE_DIR" oracle-eu-micro2
  run_reconciler "$CASE_DIR" --known-hosts "$CASE_DIR/known_hosts" \
    --ssh-key "$CASE_DIR/ssh-key" --ssh-user ci-runner --deploy --host oracle-eu-micro2
  assert_success
  assert_contains "$CASE_DIR/state/nix.log" 'ssh://ci-runner@oracle-eu-micro2'
  assert_contains "$CASE_DIR/state/nix.log" '--offline'
  assert_contains "$CASE_DIR/state/nix.log" '--option builders'
  assert_contains "$CASE_DIR/state/nix.log" '--option substitute false'
  assert_contains "$CASE_DIR/state/deploy.log" 'deploy --skip-checks --file'
  assert_contains "$CASE_DIR/state/deploy.log" '--fast-connection true'
  assert_contains "$CASE_DIR/state/deploy.log" '--option builders'
  assert_contains "$CASE_DIR/state/deploy.log" '--option max-jobs 0'
  assert_contains "$CASE_DIR/state/deploy.log" '--option substituters'
  assert_contains "$CASE_DIR/state/deploy.log" '--option substitute false'
  assert_contains "$CASE_DIR/state/deploy-nix-config" 'substituters ='
  assert_contains "$CASE_DIR/state/deploy-nix-config" 'trusted-public-keys ='
  assert_contains "$CASE_DIR/state/deploy-nix-config" 'substitute = false'
  assert_contains "$CASE_DIR/state/deploy-nix-config" 'builders ='
  assert_contains "$CASE_DIR/state/deploy-nix-config" 'max-jobs = 0'
  assert_not_contains "$CASE_DIR/state/nix.log" 'run '
  assert_not_contains "$CASE_DIR/state/nix.log" 'develop '
  assert_contains "$CASE_DIR/state/nix.log" 'NIX_SSHOPTS=-o BatchMode=yes'
  assert_contains "$CASE_DIR/state/nix.log" '-o ControlMaster=no'
  assert_contains "$CASE_DIR/state/deploy-oracle-eu-micro2.nix" 'sshUser = "ci-runner";'
  assert_contains "$CASE_DIR/state/deploy-oracle-eu-micro2.nix" 'remoteBuild = false;'
  assert_contains "$CASE_DIR/state/deploy-oracle-eu-micro2.nix" 'magicRollback = true;'
  assert_contains "$CASE_DIR/state/deploy-oracle-eu-micro2.nix" \
    'path = { outPath = "/nix/store/oracle-eu-micro2-activation"; drvPath = "/nix/store/oracle-eu-micro2-activation.drv"; };'
  assert_contains "$CASE_DIR/state/deploy-oracle-eu-micro2.nix" 'StrictHostKeyChecking=yes'
  assert_contains "$CASE_DIR/state/deploy-oracle-eu-micro2.nix" 'ControlMaster=no'
  assert_contains "$CASE_DIR/state/deploy-oracle-eu-micro2.nix" 'ssh-key'
}

run_test 'valid artifacts verify and import without SSH' test_valid_verify_only
run_test 'unexpected artifact files are rejected before import' test_rejects_unexpected_artifact_file
run_test 'checksum mismatch is rejected' test_rejects_checksum_mismatch
run_test 'source SHA binding is enforced' test_rejects_source_binding_mismatch
run_test 'release run identity is required' test_rejects_manifest_without_run_identity
run_test 'Nix store path names accept valid special characters' test_accepts_store_names_with_nix_special_characters
run_test 'generated deploy definitions escape store paths' test_escapes_store_paths_in_generated_nix
run_test 'remote path checks shell-quote store names' test_shell_quotes_store_paths_for_remote_checks
run_test 'inventory metadata binding is enforced' test_rejects_inventory_metadata_mismatch
run_test 'activation outputs stay bound to their exported derivers' test_rejects_activation_deriver_mismatch
run_test 'archive paths exactly match declared root closures' test_rejects_same_count_archive_path_substitution
run_test 'host records cannot cross architecture artifacts' test_rejects_host_in_wrong_architecture_artifact
run_test 'selected hosts retain inventory rollout order' test_target_selection_preserves_inventory_order
run_test 'a changed unselected canary blocks a worker deployment' test_changed_unselected_canary_blocks_worker
run_test 'the x86 canary can deploy before the ARM canary' test_x86_canary_can_lead_arm_canary
run_test 'the ARM canary requires the x86 canary gate' test_arm_canary_requires_x86_canary
run_test 'control-plane deployment preflights every dependency first' test_control_plane_preflights_all_dependencies
run_test 'a changed worker blocks a control-plane-only deployment' test_changed_worker_blocks_control_plane
run_test 'post-activation SSH retries transient convergence failure' test_post_activation_ssh_retries_transient_failure
run_test 'identity mismatch is never retried' test_identity_mismatch_is_not_retried
run_test 'host-key failure is never retried' test_host_key_failure_is_not_retried
run_test 'Kubernetes node Ready uses bounded retries' test_node_ready_retries_after_activation
run_test 'deploy invocation preserves SSH and rollback policy' test_deploy_invocation_uses_requested_ssh_user_and_strict_options

printf '1..%s\n' "$((passes + failures))"
printf '%s passed; %s failed\n' "$passes" "$failures"
(( failures == 0 ))
