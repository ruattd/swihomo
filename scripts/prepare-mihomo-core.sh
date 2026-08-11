#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CORE_ROOT="$ROOT/Vendor/mihomo"
OUTPUT="$ROOT/Vendor/MihomoCore.xcframework"
GO_VERSION="1.26.5"
GO_TOOL_ROOT="${TMPDIR:-/tmp}/swihomo-go"
GO_ROOT="$GO_TOOL_ROOT/go$GO_VERSION"

fail() {
    printf 'Core preparation failed: %s\n' "$1" >&2
    exit 1
}

if [[ "$#" -eq 0 ]]; then
    MODE="full"
elif [[ "$#" -eq 1 && "$1" == "--submodule-only" ]]; then
    MODE="submodule-only"
else
    fail "Unsupported argument(s): $*"
fi

ensure_go() {
    if [[ -x "$GO_ROOT/bin/go" ]]; then
        export GOROOT="$GO_ROOT"
        export PATH="$GOROOT/bin:$PATH"
    else
        local archive
        local expected_sha256
        local architecture

        case "$(uname -m)" in
            arm64)
                architecture="arm64"
                expected_sha256="efb87ff28af9a188d0536ef5d42e63dd52ba8263cd7344a993cc48dd11dedb6a"
                ;;
            x86_64)
                architecture="amd64"
                expected_sha256="6231d8d3b8f5552ec6cbf6d685bdd5482e1e703214b120e89b3bf0d7bf1ef725"
                ;;
            *) fail "Unsupported macOS architecture: $(uname -m)" ;;
        esac

        mkdir -p "$GO_TOOL_ROOT"
        archive="$(mktemp "$GO_TOOL_ROOT/go$GO_VERSION.darwin-$architecture.XXXXXX")"
        printf 'Downloading Go %s for %s...\n' "$GO_VERSION" "$architecture"
        curl -fsSL --retry 3 "https://go.dev/dl/go$GO_VERSION.darwin-$architecture.tar.gz" --output "$archive"

        [[ "$(shasum -a 256 "$archive" | awk '{ print $1 }')" == "$expected_sha256" ]] || \
            fail "Downloaded Go archive did not match its expected SHA-256."

        rm -rf "$GO_ROOT" "$GO_TOOL_ROOT/go"
        tar -xzf "$archive" -C "$GO_TOOL_ROOT"
        mv "$GO_TOOL_ROOT/go" "$GO_ROOT"
        rm -f "$archive"

        export GOROOT="$GO_ROOT"
        export PATH="$GOROOT/bin:$PATH"
    fi

    case "$(go version)" in
        "go version go$GO_VERSION "*) ;;
        *) fail "Expected Go $GO_VERSION, found: $(go version)" ;;
    esac
    printf 'Using %s\n' "$(go version)"
}

sync_mihomo_version() {
    local version_file="$CORE_ROOT/constant/version.go"
    local latest_tag=""
    local tag
    local version
    local temporary_file
    local line
    local updated=false

    [[ -f "$version_file" ]] || fail "mihomo version.go is missing."

    git -C "$CORE_ROOT" fetch --tags --force origin
    while IFS= read -r tag; do
        [[ "$tag" == "Prerelease-Alpha" ]] && continue
        latest_tag="$tag"
        break
    done < <(git -C "$CORE_ROOT" tag --list --sort=-version:refname)

    [[ -n "$latest_tag" ]] || fail "No non-Alpha mihomo release tags were found."
    version="${latest_tag#v}"
    temporary_file="$(mktemp "$version_file.XXXXXX")"

    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" =~ ^([[:space:]]*Version[[:space:]]*=[[:space:]]*\")[^\"]*(\".*)$ ]]; then
            printf '%s%s%s\n' "${BASH_REMATCH[1]}" "$version" "${BASH_REMATCH[2]}" >> "$temporary_file"
            updated=true
        else
            printf '%s\n' "$line" >> "$temporary_file"
        fi
    done < "$version_file"

    [[ "$updated" == true ]] || {
        rm -f "$temporary_file"
        fail "mihomo version.go does not declare a Version value."
    }

    mv "$temporary_file" "$version_file"
    printf 'Set embedded mihomo version to %s from tag %s\n' "$version" "$latest_tag"
}

prepare_submodule() {
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
}

[[ -f "$ROOT/.gitmodules" ]] || fail "Missing .gitmodules."
command -v git >/dev/null || fail "Git is unavailable."

if [[ "$MODE" == "submodule-only" ]]; then
    prepare_submodule
    exit 0
fi

command -v curl >/dev/null || fail "curl is unavailable."
command -v shasum >/dev/null || fail "shasum is unavailable."
command -v tar >/dev/null || fail "tar is unavailable."

ensure_go

prepare_submodule
sync_mihomo_version

printf 'Building embedded mihomo core...\n'
bash "$ROOT/scripts/build-mihomo-core.sh"

[[ -f "$OUTPUT/Info.plist" ]] || fail "MihomoCore.xcframework was not created."
printf 'Built %s\n' "$OUTPUT"
