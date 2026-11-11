#!/usr/bin/env bash
set -euo pipefail

# Scripts/install.sh — Compile and install Pico in /Applications

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET_APP="/Applications/Pico.app"

echo "=========================================="
echo "    Pico — Install in /Applications       "
echo "=========================================="

# 1. Compilation
echo "==> [1/4] Compiling release bundle..."
"${REPO_DIR}/Scripts/build.sh"

# 2. Terminate active instances
echo "==> [2/4] Terminating existing Pico processes..."
pkill -x Pico 2>/dev/null || true
sleep 0.5

# 3. Copy to /Applications
echo "==> [3/4] Installing to ${TARGET_APP}..."
rm -rf "${TARGET_APP}"
cp -R "${REPO_DIR}/build/Pico.app" "/Applications/"
xattr -dr com.apple.quarantine "${TARGET_APP}" 2>/dev/null || true
codesign -s - --force "${TARGET_APP}"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "${REPO_DIR}/build/Pico.app" 2>/dev/null || true
rm -rf "${REPO_DIR}/build/Pico.app"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "${TARGET_APP}" 2>/dev/null || true

# 4. Diagnostic verification of login item
echo "==> [4/4] Verifying SMAppService status..."
"${TARGET_APP}/Contents/MacOS/Pico" --test-login-item

# 5. Launch installed application
echo ""
echo "==> Launching Pico from /Applications/Pico.app..."
open "${TARGET_APP}"

echo ""
echo "=========================================="
echo "    Installation completed successfully!  "
echo "=========================================="
echo "Pico is now running in the menu bar."
echo "To verify launch at login:"
echo "  1. In System Settings -> General -> Login Items,"
echo "     ensure Pico is active under 'Open at Login'."
