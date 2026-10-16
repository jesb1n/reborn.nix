#!/usr/bin/env bash
# PostToolUse hook: after Claude edits a .nix file, check it parses; for
# nix-darwin host files (hosts/*-darwin/) also evaluate that darwin system,
# and for flake.nix evaluate every darwin host. Exit 2 feeds the error back
# to Claude.
set -u
export PATH="/nix/var/nix/profiles/default/bin:/run/current-system/sw/bin:/etc/profiles/per-user/${USER:-$(id -un)}/bin:$PATH"

f=$(jq -r '.tool_input.file_path // .tool_response.filePath // empty')
[[ "$f" == *.nix && -f "$f" ]] || exit 0

if ! out=$(nix-instantiate --parse "$f" 2>&1 >/dev/null); then
  printf 'Nix parse error in %s:\n%s\n' "$f" "$out" >&2
  exit 2
fi

darwin_hosts=()
case "$f" in
  */anywhere/hosts/pro-darwin/*.nix) darwin_hosts=(pro-darwin) ;;
  */anywhere/hosts/air-darwin/*.nix) darwin_hosts=(air-darwin) ;;
  */anywhere/flake.nix) darwin_hosts=(pro-darwin air-darwin) ;;
esac

if ((${#darwin_hosts[@]})); then
  root=$(git -C "$(dirname "$f")" rev-parse --show-toplevel) || exit 0
  for host in "${darwin_hosts[@]}"; do
    if ! out=$(cd "$root/anywhere" && nix eval --raw ".#darwinConfigurations.$host.system.drvPath" 2>&1 >/dev/null); then
      printf '%s evaluation failed after editing %s (new files must be git-added first):\n%s\n' \
        "$host" "$f" "$(printf '%s\n' "$out" | grep -vE '^(warning|Pass )' | tail -25)" >&2
      exit 2
    fi
  done
fi
exit 0
