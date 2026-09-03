#!/usr/bin/env bash
# Initializes and updates the repository's Git submodules to the recorded commits.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

fail() {
    printf 'Error: %s\n' "$1" >&2
    exit 1
}

[[ -f "$ROOT/.gitmodules" ]] || fail "missing .gitmodules."
command -v git >/dev/null || fail "Git is unavailable."

git -C "$ROOT" submodule sync --recursive
git -C "$ROOT" submodule update --init --recursive

SUBMODULE_STATUS="$(git -C "$ROOT" submodule status --recursive)"
[[ -n "$SUBMODULE_STATUS" ]] || fail "no Git submodules were found."

while IFS= read -r line; do
    case "$line" in
        [-+U]*) fail "submodule is not checked out at the recorded commit: $line" ;;
    esac
done <<< "$SUBMODULE_STATUS"

printf 'Verified Git submodules:\n%s\n' "$SUBMODULE_STATUS"
