#!/bin/bash
# Full local gate: regenerate the project, test every package, build the app.
set -euo pipefail
cd "$(dirname "$0")/.."

# makeIsolatedDefaults() leaves one MyNotchTests.<uuid> suite on disk per test, and RegistryHarness storage
# leaves a MyNotchTests-<uuid> temporary folder once a module creates its directories.
# cfprefsd writes the suites a few seconds after each test process exits, so clean up at both ends.
cleanup_test_files() {
    find "$HOME/Library/Preferences" -maxdepth 1 -name 'MyNotchTests.*.plist' -delete || true
    find "${TMPDIR:-$(getconf DARWIN_USER_TEMP_DIR)}" -maxdepth 1 -name 'MyNotchTests-*' -exec rm -rf {} + || true
}
cleanup_test_files
trap cleanup_test_files EXIT

echo "==> xcodegen generate"
xcodegen generate --quiet

# SwiftPM keeps a stale file list for local path dependencies, so a file added to or removed from
# MyNotchCore/NotchUI breaks the dependents' incremental builds. Drop their .build when that list changes.
shared_sources=$(find Packages/MyNotchCore/Sources Packages/NotchUI/Sources -name '*.swift' | sort | shasum | cut -d' ' -f1)

for manifest in Packages/MyNotchCore/Package.swift Packages/NotchUI/Package.swift Packages/Modules/*/Package.swift; do
    package=$(dirname "$manifest")
    if [ "$package" != Packages/MyNotchCore ] && [ "$(cat "$package/.build/mynotch-shared-sources" 2>/dev/null)" != "$shared_sources" ]; then
        rm -rf "$package/.build"
    fi
    echo "==> swift test ($package)"
    (cd "$package" && swift test --quiet)
    [ "$package" = Packages/MyNotchCore ] || echo "$shared_sources" > "$package/.build/mynotch-shared-sources"
done

echo "==> xcodebuild build"
xcodebuild -project MyNotch.xcodeproj -scheme MyNotch -configuration Debug \
    -destination "platform=macOS,arch=$(uname -m)" -derivedDataPath .build/xcode build -quiet

echo "All checks passed."
