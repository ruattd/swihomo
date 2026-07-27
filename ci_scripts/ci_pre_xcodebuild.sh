#!/usr/bin/env bash
set -euo pipefail

ROOT="${CI_PRIMARY_REPOSITORY_PATH:-$(cd "$(dirname "$0")/.." && pwd)}"
CORE_ROOT="$ROOT/Vendor/mihomo"
OUTPUT="$ROOT/Vendor/MihomoCore.xcframework"

fail() {
    printf 'Xcode Cloud pre-build failed: %s\n' "$1" >&2
    exit 1
}

[[ -f "$ROOT/.gitmodules" ]] || fail "Missing .gitmodules."
command -v git >/dev/null || fail "Git is unavailable."
command -v go >/dev/null || fail "Go is required to build the embedded mihomo core."

git -C "$ROOT" submodule sync --recursive
git -C "$ROOT" submodule update --init --recursive

SUBMODULE_STATUS="$(git -C "$ROOT" submodule status --recursive)"
[[ -n "$SUBMODULE_STATUS" ]] || fail "No Git submodules were found."
printf 'Verified Git submodules:\n%s\n' "$SUBMODULE_STATUS"

while IFS= read -r line; do
    case "$line" in
        [-+U]*) fail "Submodule is not checked out at the commit recorded by the parent repository: $line" ;;
    esac
done <<< "$SUBMODULE_STATUS"

[[ -f "$CORE_ROOT/go.mod" ]] || fail "mihomo submodule is missing its Go module."

printf 'Building embedded mihomo core...\n'
bash "$ROOT/scripts/build-mihomo-core.sh"

[[ -f "$OUTPUT/Info.plist" ]] || fail "MihomoCore.xcframework was not created."
printf 'Built %s\n' "$OUTPUT"
