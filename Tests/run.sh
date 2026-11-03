#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SOURCES="$ROOT_DIR/Sources/ScreenSetter"
TEMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/screen-setter-tests.XXXXXX")
trap 'rm -rf "$TEMP_DIR"' EXIT HUP INT TERM

# Core model, persistence, and engine only: no app shell or Settings UI.
swiftc \
    -parse-as-library \
    -module-cache-path "$TEMP_DIR/swift-cache" \
    "$SOURCES/Library.swift" \
    "$SOURCES/LibraryRepository.swift" \
    "$SOURCES/LayoutStore.swift" \
    "$SOURCES/Arrangement.swift" \
    "$SOURCES/LayoutProfiles.swift" \
    "$SOURCES/LayoutTypes.swift" \
    "$SOURCES/DisplayEngine.swift" \
    -framework AppKit -framework CoreGraphics -framework ColorSync \
    "$ROOT_DIR/Tests/ProfileTests.swift" \
    -o "$TEMP_DIR/profile-tests"

"$TEMP_DIR/profile-tests"
