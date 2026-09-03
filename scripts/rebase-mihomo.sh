#!/usr/bin/env bash
# Rebases the swihomo customization line onto the latest upstream Alpha and pushes
# both the rebased branch and the sync base. All update sources are remote refs;
# the only local branch this script creates or updates is swihomo.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CORE_ROOT="$ROOT/Vendor/mihomo"
BASE_BRANCH="swihomo-alpha-base"

fail() {
    printf 'Error: %s\n' "$1" >&2
    exit 1
}

[[ -d "$CORE_ROOT" ]] || fail "core worktree does not exist: $CORE_ROOT"
git -C "$CORE_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1 || \
    fail "core path is not a Git worktree: $CORE_ROOT"

STATUS="$(git -C "$CORE_ROOT" status --porcelain --untracked-files=all)"
[[ -z "$STATUS" ]] || fail "core worktree is not clean; refusing to modify it."$'\n'"$STATUS"

# Fetch every remote branch this script uses before touching anything.
git -C "$CORE_ROOT" fetch origin \
    "+refs/heads/Alpha:refs/remotes/origin/Alpha" \
    "+refs/heads/swihomo:refs/remotes/origin/swihomo"
if git -C "$CORE_ROOT" ls-remote --exit-code --heads origin "$BASE_BRANCH" >/dev/null 2>&1; then
    git -C "$CORE_ROOT" fetch origin "+refs/heads/$BASE_BRANCH:refs/remotes/origin/$BASE_BRANCH"
    HAS_REMOTE_BASE=true
else
    HAS_REMOTE_BASE=false
fi

CURRENT_ALPHA="$(git -C "$CORE_ROOT" rev-parse origin/Alpha)"

# Update only the local swihomo branch, rebasing it onto the remote Alpha.
if git -C "$CORE_ROOT" merge-base --is-ancestor "$CURRENT_ALPHA" origin/swihomo; then
    git -C "$CORE_ROOT" switch -C swihomo origin/swihomo
    printf 'swihomo already contains Alpha %s; no rebase needed.\n' \
        "$(git -C "$CORE_ROOT" rev-parse --short "$CURRENT_ALPHA")"
else
    [[ "$HAS_REMOTE_BASE" == true ]] || \
        fail "origin/$BASE_BRANCH does not exist; cannot determine the rebase range."
    git -C "$CORE_ROOT" merge-base --is-ancestor "origin/$BASE_BRANCH" origin/swihomo || \
        fail "origin/$BASE_BRANCH is not an ancestor of origin/swihomo; refusing an ambiguous range."
    git -C "$CORE_ROOT" switch -C swihomo origin/swihomo
    git -C "$CORE_ROOT" rebase --onto origin/Alpha "origin/$BASE_BRANCH"
fi

# Push the rebased branch, then save the base we rebased onto back to the remote.
git -C "$CORE_ROOT" push --force-with-lease="refs/heads/swihomo:origin/swihomo" \
    origin "refs/heads/swihomo:refs/heads/swihomo"
if [[ "$HAS_REMOTE_BASE" == true ]]; then
    git -C "$CORE_ROOT" push --force-with-lease="refs/heads/$BASE_BRANCH:origin/$BASE_BRANCH" \
        origin "origin/Alpha:refs/heads/$BASE_BRANCH"
else
    git -C "$CORE_ROOT" push origin "origin/Alpha:refs/heads/$BASE_BRANCH"
fi

# Every local branch other than swihomo is scratch state — remove it, whether it
# predates this run or was created during it.
while IFS= read -r branch; do
    [[ "$branch" == "swihomo" ]] && continue
    git -C "$CORE_ROOT" branch -D "$branch" >/dev/null
done < <(git -C "$CORE_ROOT" for-each-ref --format='%(refname:short)' refs/heads)

printf 'Core sync succeeded: swihomo rebased onto Alpha %s and pushed.\n' \
    "$(git -C "$CORE_ROOT" rev-parse --short "$CURRENT_ALPHA")"
