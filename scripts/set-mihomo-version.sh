#!/usr/bin/env bash
# Writes the latest upstream mihomo release tag into the core's embedded version.go.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CORE_ROOT="$ROOT/Vendor/mihomo"
VERSION_FILE="$CORE_ROOT/constant/version.go"

fail() {
    printf 'Error: %s\n' "$1" >&2
    exit 1
}

[[ -f "$VERSION_FILE" ]] || fail "mihomo version.go is missing."

git -C "$CORE_ROOT" fetch --tags --force origin

latest_tag=""
while IFS= read -r tag; do
    [[ "$tag" == "Prerelease-Alpha" ]] && continue
    latest_tag="$tag"
    break
done < <(git -C "$CORE_ROOT" tag --list --sort=-version:refname)

[[ -n "$latest_tag" ]] || fail "no non-Alpha mihomo release tags were found."

version="${latest_tag#v}"
temporary_file="$(mktemp "$VERSION_FILE.XXXXXX")"
trap 'rm -f "$temporary_file"' EXIT

updated=false
while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" =~ ^([[:space:]]*Version[[:space:]]*=[[:space:]]*\")[^\"]*(\".*)$ ]]; then
        printf '%s%s%s\n' "${BASH_REMATCH[1]}" "$version" "${BASH_REMATCH[2]}" >> "$temporary_file"
        updated=true
    else
        printf '%s\n' "$line" >> "$temporary_file"
    fi
done < "$VERSION_FILE"

[[ "$updated" == true ]] || fail "mihomo version.go does not declare a Version value."

mv "$temporary_file" "$VERSION_FILE"
trap - EXIT

printf 'Set embedded mihomo version to %s from tag %s\n' "$version" "$latest_tag"
