#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SOURCES="$ROOT_DIR/Sources/ScreenSetter"
TEMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/screen-setter-window-tests.XXXXXX")
trap 'rm -rf "$TEMP_DIR"' EXIT HUP INT TERM

# The full UI runs offscreen with sample data; no real display engine or updater.
OUTPUT_DIR=${1:-$TEMP_DIR/renders}
set --
for source in "$SOURCES"/*.swift "$SOURCES"/Settings/*.swift; do
    case "$source" in */main.swift) continue ;; esac
    set -- "$@" "$source"
done
swiftc -parse-as-library \
    -target "$(uname -m)-apple-macosx26.0" \
    -module-cache-path "$TEMP_DIR/swift-cache" \
    -framework AppKit -framework SwiftUI -framework ServiceManagement \
    -framework ColorSync -framework Carbon \
    -F "$ROOT_DIR/Vendor/Sparkle" -framework Sparkle \
    -Xlinker -rpath -Xlinker "$ROOT_DIR/Vendor/Sparkle" \
    "$@" "$ROOT_DIR/Tests/WindowSizingTests.swift" \
    -o "$TEMP_DIR/window-sizing-tests"
"$TEMP_DIR/window-sizing-tests" "$OUTPUT_DIR"
