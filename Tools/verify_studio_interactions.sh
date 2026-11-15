#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

echo "========================================================"
echo "🧪 MyNotch Studio - Empirical Interaction Verification"
echo "========================================================"

# 1. Clear old verification log and evidence
TMP_LOG="/tmp/studio_verification.log"
TMP_EVIDENCE="/tmp/mynotch_evidence"
rm -f "$TMP_LOG"
rm -rf "$TMP_EVIDENCE"
mkdir -p "$TMP_EVIDENCE"

# 2. Ensure latest Debug MyNotch is running for empirical verification
if [ -d "$REPO_ROOT/.build/xcode/Build/Products/Debug/MyNotch.app" ]; then
    DERIVED_DEBUG="$REPO_ROOT/.build/xcode/Build/Products/Debug/MyNotch.app"
else
    DERIVED_DEBUG=$(find /Users/ryantruong/Library/Developer/Xcode/DerivedData/MyNotch-*/Build/Products/Debug/MyNotch.app -maxdepth 0 2>/dev/null | head -n 1 || true)
fi
if [ -n "$DERIVED_DEBUG" ]; then
    echo "🔄 Launching fresh Debug app from $DERIVED_DEBUG with --verify-studio..."
    killall MyNotch 2>/dev/null || true
    sleep 1
    open -n "$DERIVED_DEBUG" --args --verify-studio
    sleep 2
fi
PID=$(pgrep -f "MyNotch.app/Contents/MacOS/MyNotch" | head -n 1 || true)
echo "✅ Target MyNotch PID: $PID"

# 3. App executes verification automatically via --verify-studio argument
echo "📡 Verification running via --verify-studio bootstrap..."

# 4. Wait for log generation
echo "⏳ Waiting for empirical test execution and evidence capture..."
MAX_WAIT=20
WAITED=0
while [ $WAITED -lt $MAX_WAIT ]; do
    if [ -f "$TMP_LOG" ] && grep -q "KẾT THÚC KIỂM THỬ THỰC NGHIỆM" "$TMP_LOG"; then
        break
    fi
    sleep 0.5
    WAITED=$((WAITED + 1))
done

if [ -f "$TMP_LOG" ]; then
    echo ""
    echo "==================== RAW EMPIRICAL LOG ===================="
    cat "$TMP_LOG"
    echo "============================================================"
    echo ""
else
    echo "⚠️ Warning: Verification log not generated within ${MAX_WAIT}s. Note: Debug observers require a Debug build."
fi

# 5. Sync evidence snapshots if captured
if [ -f "$TMP_EVIDENCE/dashboard_battery_studio.png" ]; then
    cp "$TMP_EVIDENCE/dashboard_battery_studio.png" docs/evidence/dashboard_battery_studio.png
    echo "📸 Updated docs/evidence/dashboard_battery_studio.png ($(wc -c < docs/evidence/dashboard_battery_studio.png) bytes)"
fi
if [ -f "$TMP_EVIDENCE/dashboard_todo_studio.png" ]; then
    cp "$TMP_EVIDENCE/dashboard_todo_studio.png" docs/evidence/dashboard_todo_studio.png
    echo "📸 Updated docs/evidence/dashboard_todo_studio.png ($(wc -c < docs/evidence/dashboard_todo_studio.png) bytes)"
fi
for THEME_IMG in dashboard_theme_soft_ui.png dashboard_theme_liquid_glass.png dashboard_theme_stripe_light.png; do
    if [ -f "$TMP_EVIDENCE/$THEME_IMG" ]; then
        cp "$TMP_EVIDENCE/$THEME_IMG" "docs/evidence/$THEME_IMG"
        echo "📸 Updated docs/evidence/$THEME_IMG ($(wc -c < "docs/evidence/$THEME_IMG") bytes)"
    fi
done

echo ""
echo "✅ Verification script completed successfully."
