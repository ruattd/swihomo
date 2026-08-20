#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CORE_ROOT="$ROOT/Vendor/mihomo"
ALPHA_BASE_BRANCH="swihomo-alpha-base"
SYNC_COMMITTER_NAME="swihomo-automation[bot]"
SYNC_COMMITTER_EMAIL="315911239+swihomo-automation[bot]@users.noreply.github.com"

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

bootstrap_alpha_base() {
    local commit committer_name committer_email

    while IFS=$'\t' read -r commit committer_name committer_email; do
        if [[ "$committer_name" == "$SYNC_COMMITTER_NAME" && "$committer_email" == "$SYNC_COMMITTER_EMAIL" ]]; then
            git -C "$CORE_ROOT" rev-parse "$commit^"
            return
        fi
    done < <(git -C "$CORE_ROOT" log --first-parent --reverse --format='%H%x09%cn%x09%ce' swihomo)

    return 1
}

git -C "$CORE_ROOT" fetch origin +refs/heads/Alpha:refs/remotes/origin/Alpha
CURRENT_ALPHA="$(git -C "$CORE_ROOT" rev-parse origin/Alpha)"

if ! git -C "$CORE_ROOT" show-ref --verify --quiet refs/heads/swihomo; then
    printf 'Error: local swihomo branch does not exist.\n' >&2
    exit 1
fi

PREVIOUS_ALPHA=""
HAS_REMOTE_ALPHA_BASE=false
if git -C "$CORE_ROOT" ls-remote --exit-code --heads origin "$ALPHA_BASE_BRANCH" >/dev/null; then
    git -C "$CORE_ROOT" fetch origin "+refs/heads/$ALPHA_BASE_BRANCH:refs/remotes/origin/$ALPHA_BASE_BRANCH"
    PREVIOUS_ALPHA="$(git -C "$CORE_ROOT" rev-parse "origin/$ALPHA_BASE_BRANCH")"
    HAS_REMOTE_ALPHA_BASE=true
else
    remote_status=$?
    if (( remote_status != 2 )); then
        printf 'Error: unable to inspect remote %s reference.\n' "$ALPHA_BASE_BRANCH" >&2
        exit 1
    fi
fi

if ! git -C "$CORE_ROOT" merge-base --is-ancestor "$CURRENT_ALPHA" swihomo; then
    if [[ -z "$PREVIOUS_ALPHA" ]] || ! git -C "$CORE_ROOT" merge-base --is-ancestor "$PREVIOUS_ALPHA" swihomo; then
        if ! PREVIOUS_ALPHA="$(bootstrap_alpha_base)"; then
            printf 'Error: no usable Alpha sync base exists; refusing to replay an ambiguous swihomo range.\n' >&2
            exit 1
        fi
    fi

    if ! git -C "$CORE_ROOT" merge-base --is-ancestor "$PREVIOUS_ALPHA" swihomo; then
        printf 'Error: Alpha sync base is not an ancestor of swihomo; refusing to replay an ambiguous range.\n' >&2
        exit 1
    fi

    git -C "$CORE_ROOT" checkout -B Alpha "$CURRENT_ALPHA"
    git -C "$CORE_ROOT" checkout swihomo
    git -C "$CORE_ROOT" rebase --onto "$CURRENT_ALPHA" "$PREVIOUS_ALPHA"
fi

git -C "$CORE_ROOT" branch -f "$ALPHA_BASE_BRANCH" "$CURRENT_ALPHA"
if [[ "$HAS_REMOTE_ALPHA_BASE" == true ]]; then
    git -C "$CORE_ROOT" branch --set-upstream-to="origin/$ALPHA_BASE_BRANCH" "$ALPHA_BASE_BRANCH" >/dev/null
fi

ALPHA_SHA="$(git -C "$CORE_ROOT" rev-parse --short "$CURRENT_ALPHA")"
printf 'Core sync succeeded: Alpha is at %s; swihomo is aligned.\n' "$ALPHA_SHA"
