#!/usr/bin/env bash
set -euo pipefail

# Root directory of MyNotch project
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

echo "=========================================="
echo "🚀 MyNotch - Official Release & Deploy Tool"
echo "=========================================="

# 1. Check for valid Apple Development certificate
echo "🔍 Checking signing identity in Keychain..."
TEAM_ID="B394MAY4QN"
SIGNING_IDENTITY="Apple Development"

if security find-identity -v -p codesigning | grep -q "Apple Development"; then
    FOUND_IDENTITY=$(security find-identity -v -p codesigning | grep "Apple Development" | head -n 1 | awk -F'"' '{print $2}')
    echo "✅ Found valid Apple Development identity: $FOUND_IDENTITY"
else
    echo "⚠️ Warning: No 'Apple Development' identity found in Keychain."
    echo "❌ Refusing to build ad-hoc ('-') to protect macOS TCC permissions."
    echo "Please ensure your developer certificate is installed in Keychain."
    exit 1
fi

# 2. Regenerate Xcode project
echo "⚙️ Regenerating Xcode project with xcodegen..."
xcodegen generate

# 3. Build Release
echo "🔨 Building MyNotch (Release) with official Team certificate..."
xcodebuild -project MyNotch.xcodeproj \
    -scheme MyNotch \
    -configuration Release \
    -derivedDataPath .build/xcode \
    build \
    CODE_SIGN_STYLE="Automatic" \
    CODE_SIGN_IDENTITY="$SIGNING_IDENTITY" \
    DEVELOPMENT_TEAM="$TEAM_ID"

# 4. In-place Release Deployment (NC-MYN-020)
echo "📦 Deploying to /Applications/MyNotch.app..."
killall MyNotch 2>/dev/null || true
killall mynotch-youtube-host 2>/dev/null || true
rm -rf /Applications/MyNotch.app
ditto .build/xcode/Build/Products/Release/MyNotch.app /Applications/MyNotch.app

# 5. Verify Code Signature
echo "🛡️ Verifying code signature..."
codesign --verify --deep --strict --verbose=2 /Applications/MyNotch.app

# 6. Relaunch and check process
echo "▶️ Launching /Applications/MyNotch.app..."
open -a /Applications/MyNotch.app
sleep 1.5

NEW_PID=$(pgrep -f "/Applications/MyNotch.app/Contents/MacOS/MyNotch" || true)
if [ -n "$NEW_PID" ]; then
    echo "✅ Successfully deployed! MyNotch is running with PID: $NEW_PID"
    ps aux | grep -v grep | grep "/Applications/MyNotch.app"
else
    echo "❌ Error: MyNotch process failed to launch."
    exit 1
fi
echo "=========================================="
