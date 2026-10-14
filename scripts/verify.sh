#!/bin/bash
# Full local gate: regenerate the project, test every package, build the app.
set -euo pipefail
cd "$(dirname "$0")/.."

# makeIsolatedDefaults() removes its MyNotchTests.<uuid> suite when released, but a test process that ends within
# seconds of that leaves the plist behind. Test folders are all MyNotchTests-<label>-<uuid> (ScratchFolders in
# MyNotchTestSupport) and removed when the test process exits, so one only survives a run that crashed.
# cfprefsd writes the suites a few seconds after each test process exits, so clean up at both ends.
# Only items untouched for 15 minutes go, so test runs in other worktrees are never disturbed.
cleanup_test_files() {
    # cfprefsd is asked to forget each domain first, otherwise `defaults domains` keeps listing it.
    find "$HOME/Library/Preferences" -maxdepth 1 -name 'MyNotchTests.*.plist' -mmin +15 -print0 |
        while IFS= read -r -d '' plist; do
            defaults delete "$(basename "$plist" .plist)" >/dev/null 2>&1 || true
            rm -f "$plist"
        done || true
    find "${TMPDIR:-$(getconf DARWIN_USER_TEMP_DIR)}" -maxdepth 1 -name 'MyNotchTests-*' -mmin +15 -exec rm -rf {} + || true
}
cleanup_test_files
trap cleanup_test_files EXIT

echo "==> xcodegen generate"
xcodegen generate --quiet

# SwiftPM keeps a stale file list for local path dependencies, so a source, resource or manifest added to or
# removed from MyNotchCore/NotchUI breaks the dependents' incremental builds. Drop their .build when that list changes.
shared_sources=$(find Packages/MyNotchCore Packages/NotchUI -path '*/.build' -prune -o -type f \( -path '*/Sources/*' -o -name Package.swift \) -print | LC_ALL=C sort | shasum | cut -d' ' -f1)

for manifest in Packages/MyNotchCore/Package.swift Packages/NotchUI/Package.swift Packages/DebugTools/Package.swift Packages/Modules/*/Package.swift; do
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
