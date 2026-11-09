#!/usr/bin/env zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"
OBJ_DIR="$BUILD_DIR/obj"
APP_BUNDLE="$BUILD_DIR/Pico.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"

mkdir -p "$OBJ_DIR" "$MACOS_DIR"
touch "$BUILD_DIR/.metadata_never_index"

echo "==> [1/4] Compilazione CShim (clang -Oz)..."
clang -Oz -Wall -Wextra \
    -arch arm64 \
    -mmacosx-version-min=14.0 \
    -c "$ROOT_DIR/Sources/CShim/CShim.c" \
    -o "$OBJ_DIR/CShim.o"

echo "==> [2/4] Compilazione Swift + Linking (swiftc -Osize)..."
swiftc -Osize -whole-module-optimization \
    -target arm64-apple-macosx14.0 \
    -import-objc-header "$ROOT_DIR/Sources/CShim/CShim.h" \
    -framework AppKit \
    -framework Foundation \
    -framework IOKit \
    "$OBJ_DIR/CShim.o" \
    "$ROOT_DIR"/Sources/Metrics/*.swift \
    "$ROOT_DIR"/Sources/App/*.swift \
    -o "$MACOS_DIR/Pico"

echo "==> [3/4] Copia Info.plist, Risorse e Firma Ad-Hoc..."
cp "$ROOT_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
mkdir -p "$CONTENTS_DIR/Resources"
if [ -f "$ROOT_DIR/Resources/AppIcon.icns" ]; then
    cp "$ROOT_DIR/Resources/AppIcon.icns" "$CONTENTS_DIR/Resources/AppIcon.icns"
fi
codesign -s - --force --identifier "local.gabriele.pico" "$APP_BUNDLE"

echo "==> [4/4] Build completata: $APP_BUNDLE"
