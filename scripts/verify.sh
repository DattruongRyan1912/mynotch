#!/bin/bash
# Full local gate: regenerate the project, test every package, build the app.
set -euo pipefail
cd "$(dirname "$0")/.."

# makeIsolatedDefaults() leaves one MyNotchTests.<uuid> suite on disk per test.
# cfprefsd writes them a few seconds after each test process exits, so clean up at both ends.
cleanup_test_defaults() {
    find "$HOME/Library/Preferences" -maxdepth 1 -name 'MyNotchTests.*.plist' -delete || true
}
cleanup_test_defaults
trap cleanup_test_defaults EXIT

echo "==> xcodegen generate"
xcodegen generate --quiet

for manifest in Packages/MyNotchCore/Package.swift Packages/NotchUI/Package.swift Packages/Modules/*/Package.swift; do
    package=$(dirname "$manifest")
    echo "==> swift test ($package)"
    (cd "$package" && swift test --quiet)
done

echo "==> xcodebuild build"
xcodebuild -project MyNotch.xcodeproj -scheme MyNotch -configuration Debug \
    -destination "platform=macOS,arch=$(uname -m)" -derivedDataPath .build/xcode build -quiet

echo "All checks passed."
