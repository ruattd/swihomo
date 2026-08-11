#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CORE_ROOT="$ROOT/Vendor/mihomo"

if [[ ! -d "$CORE_ROOT" ]]; then
    printf 'Error: core worktree does not exist: %s\n' "$CORE_ROOT" >&2
    exit 1
fi

if ! git -C "$CORE_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    printf 'Error: core path is not a Git worktree: %s\n' "$CORE_ROOT" >&2
    exit 1
fi

STATUS="$(git -C "$CORE_ROOT" status --porcelain --untracked-files=all)"
if [[ -n "$STATUS" ]]; then
    printf 'Error: core worktree is not clean; refusing to modify it.\n%s\n' "$STATUS" >&2
    exit 1
fi

git -C "$CORE_ROOT" fetch origin Alpha

if git -C "$CORE_ROOT" show-ref --verify --quiet refs/heads/Alpha; then
    git -C "$CORE_ROOT" checkout Alpha
    git -C "$CORE_ROOT" merge --ff-only origin/Alpha
else
    git -C "$CORE_ROOT" checkout --track -b Alpha origin/Alpha
fi

if ! git -C "$CORE_ROOT" show-ref --verify --quiet refs/heads/swihomo; then
    printf 'Error: local swihomo branch does not exist.\n' >&2
    exit 1
fi

git -C "$CORE_ROOT" checkout swihomo
git -C "$CORE_ROOT" rebase Alpha

ALPHA_SHA="$(git -C "$CORE_ROOT" rev-parse --short Alpha)"
printf 'Core sync succeeded: Alpha is at %s; swihomo has been rebased.\n' "$ALPHA_SHA"
