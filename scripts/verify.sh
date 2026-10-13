#!/bin/bash
# Full local gate: regenerate the project, test every package, build the app.
set -euo pipefail
cd "$(dirname "$0")/.."

# makeIsolatedDefaults() leaves one MyNotchTests.<uuid> suite on disk per test.
cleanup_test_defaults() {
    find "$HOME/Library/Preferences" -maxdepth 1 -name 'MyNotchTests.*.plist' -delete
}
trap cleanup_test_defaults EXIT

echo "==> xcodegen generate"
xcodegen generate --quiet

for package in Packages/MyNotchCore Packages/NotchUI Packages/Modules/*/; do
    echo "==> swift test ($package)"
    (cd "$package" && swift test --quiet)
done

echo "==> xcodebuild build"
xcodebuild -project MyNotch.xcodeproj -scheme MyNotch -configuration Debug \
    -destination 'platform=macOS' -derivedDataPath .build/xcode build -quiet

echo "All checks passed."
