#!/usr/bin/env bash
# PostToolUse hook: after Claude edits a .nix file, check it parses; for
# pro-darwin files also evaluate the whole darwin system. Exit 2 feeds the
# error back to Claude.
set -u
export PATH="/nix/var/nix/profiles/default/bin:/run/current-system/sw/bin:/etc/profiles/per-user/${USER:-$(id -un)}/bin:$PATH"

f=$(jq -r '.tool_input.file_path // .tool_response.filePath // empty')
[[ "$f" == *.nix && -f "$f" ]] || exit 0

if ! out=$(nix-instantiate --parse "$f" 2>&1 >/dev/null); then
  printf 'Nix parse error in %s:\n%s\n' "$f" "$out" >&2
  exit 2
fi

case "$f" in
  */anywhere/hosts/pro-darwin/*.nix | */anywhere/flake.nix)
    root=$(git -C "$(dirname "$f")" rev-parse --show-toplevel) || exit 0
    if ! out=$(cd "$root/anywhere" && nix eval --raw '.#darwinConfigurations.pro-darwin.system.drvPath' 2>&1 >/dev/null); then
      printf 'pro-darwin evaluation failed after editing %s (new files must be git-added first):\n%s\n' \
        "$f" "$(printf '%s\n' "$out" | grep -vE '^(warning|Pass )' | tail -25)" >&2
      exit 2
    fi
    ;;
esac
exit 0
