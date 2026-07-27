#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CORE_ROOT="$ROOT/Vendor/mihomo"
BUILD_ROOT="$CORE_ROOT/.build-mihomo"
OUTPUT="$ROOT/Vendor/MihomoCore.xcframework"
IOS_MINIMUM=17.0
MACOS_MINIMUM=14.0

bash "$ROOT/scripts/sync-mihomo-core-version.sh"

build_archive() {
    local name="$1"
    local sdk="$2"
    local goos="$3"
    local goarch="$4"
    local target="$5"
    local minimum_flag="$6"
    local output_dir="$BUILD_ROOT/$name"
    local sdk_root
    local compiler

    sdk_root="$(xcrun --sdk "$sdk" --show-sdk-path)"
    compiler="$(xcrun --sdk "$sdk" --find clang)"
    mkdir -p "$output_dir"

    (
        cd "$CORE_ROOT"
        GOOS="$goos" \
        GOARCH="$goarch" \
        CGO_ENABLED=1 \
        CC="$compiler" \
        CGO_CFLAGS="-isysroot $sdk_root $minimum_flag -target $target" \
        CGO_LDFLAGS="-isysroot $sdk_root $minimum_flag -target $target" \
        go build -tags "with_gvisor" -buildmode=c-archive \
            -o "$output_dir/libswihomo_core.a" ./bridge
    )
}

build_archive "ios-arm64" "iphoneos" "ios" "arm64" "arm64-apple-ios$IOS_MINIMUM" "-miphoneos-version-min=$IOS_MINIMUM"
build_archive "ios-simulator-arm64" "iphonesimulator" "ios" "arm64" "arm64-apple-ios$IOS_MINIMUM-simulator" "-mios-simulator-version-min=$IOS_MINIMUM"
build_archive "ios-simulator-amd64" "iphonesimulator" "ios" "amd64" "x86_64-apple-ios$IOS_MINIMUM-simulator" "-mios-simulator-version-min=$IOS_MINIMUM"
build_archive "macos-arm64" "macosx" "darwin" "arm64" "arm64-apple-macos$MACOS_MINIMUM" "-mmacosx-version-min=$MACOS_MINIMUM"
build_archive "macos-amd64" "macosx" "darwin" "amd64" "x86_64-apple-macos$MACOS_MINIMUM" "-mmacosx-version-min=$MACOS_MINIMUM"

mkdir -p "$BUILD_ROOT/ios-simulator-universal" "$BUILD_ROOT/macos-universal" "$BUILD_ROOT/headers"
lipo -create \
    "$BUILD_ROOT/ios-simulator-arm64/libswihomo_core.a" \
    "$BUILD_ROOT/ios-simulator-amd64/libswihomo_core.a" \
    -output "$BUILD_ROOT/ios-simulator-universal/libswihomo_core.a"
lipo -create \
    "$BUILD_ROOT/macos-arm64/libswihomo_core.a" \
    "$BUILD_ROOT/macos-amd64/libswihomo_core.a" \
    -output "$BUILD_ROOT/macos-universal/libswihomo_core.a"
cp "$BUILD_ROOT/ios-arm64/libswihomo_core.h" "$BUILD_ROOT/headers/swihomo_core.h"

rm -rf "$OUTPUT"
xcodebuild -create-xcframework \
    -library "$BUILD_ROOT/ios-arm64/libswihomo_core.a" -headers "$BUILD_ROOT/headers" \
    -library "$BUILD_ROOT/ios-simulator-universal/libswihomo_core.a" -headers "$BUILD_ROOT/headers" \
    -library "$BUILD_ROOT/macos-universal/libswihomo_core.a" -headers "$BUILD_ROOT/headers" \
    -output "$OUTPUT"
