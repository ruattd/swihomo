#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
    printf 'Usage: %s <marketing-version> <build-number>\n' "$0" >&2
    exit 1
fi

MARKETING_VERSION="$1"
BUILD_NUMBER="$2"

if [[ ! "$MARKETING_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    printf 'Marketing version must use three numeric components, for example 1.0.1.\n' >&2
    exit 1
fi

if [[ ! "$BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]]; then
    printf 'Build number must be a positive integer.\n' >&2
    exit 1
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION_FILE="$ROOT/Config/Version.xcconfig"
TEMP_FILE="$(mktemp "${VERSION_FILE}.XXXXXX")"

trap 'rm -f "$TEMP_FILE"' EXIT

awk \
    -v marketingVersion="$MARKETING_VERSION" \
    -v buildNumber="$BUILD_NUMBER" '
    /^MARKETING_VERSION = / {
        print "MARKETING_VERSION = " marketingVersion
        foundMarketingVersion = 1
        next
    }
    /^CURRENT_PROJECT_VERSION = / {
        print "CURRENT_PROJECT_VERSION = " buildNumber
        foundBuildNumber = 1
        next
    }
    { print }
    END {
        if (!foundMarketingVersion || !foundBuildNumber) {
            exit 1
        }
    }
' "$VERSION_FILE" > "$TEMP_FILE"

mv "$TEMP_FILE" "$VERSION_FILE"
trap - EXIT

printf 'Updated version to %s (%s).\n' "$MARKETING_VERSION" "$BUILD_NUMBER"
