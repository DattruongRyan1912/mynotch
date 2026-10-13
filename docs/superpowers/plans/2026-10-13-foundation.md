# MyNotch Nền tảng (dự án con 0): Kế hoạch triển khai

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Dựng khung app MyNotch: cửa sổ notch trên mọi màn hình, hệ thống module bật/tắt độc lập, Settings, menu bar, và module mẫu Battery.

**Architecture:** Ba Swift package local (`MyNotchCore` → `NotchUI` → `Modules/Battery`) và một target app mỏng sinh bằng XcodeGen. Module chỉ phụ thuộc `MyNotchCore` + `NotchUI` và chỉ được ghép trong `App/ModuleList.swift`. Mọi package dùng `.defaultIsolation(MainActor.self)`; thời gian được inject qua `Scheduler` để test hover, toast và hết hạn activity mà không phải chờ thật.

**Tech Stack:** Swift 6.3 (Xcode 26.6), macOS 26 SDK, SwiftUI + AppKit, Swift Testing, XcodeGen 2.46, KeyboardShortcuts 3.1.0, IOKit.

**Spec:** [`docs/superpowers/specs/2026-10-13-foundation-design.md`](../specs/2026-10-13-foundation-design.md)

**Đã kiểm chứng trước:** toàn bộ code trong kế hoạch được chạy lại tuần tự từ thư mục trống (2026-10-13). Ở mọi task, bước "phải fail" fail đúng lỗi biên dịch dự kiến, bước "phải pass" pass; tổng cộng 47 unit test và `xcodebuild` thành công.

---

## Quy ước

- Mọi lệnh chạy từ thư mục gốc repo `~/Project/MyNotch`.
- Chép **nguyên văn** nội dung file trong từng bước. Không đổi tên kiểu hay hàm: các task sau dựa vào đúng tên đó.
- Commit sau mỗi task với đúng message đã ghi. Không thêm dòng ghi công AI vào commit.
- Nếu `swift test` báo `cannot find '<Tên>' in scope` cho một symbol nằm ở **package local khác** dù file đã có: xoá thư mục `.build` của package đang test (ví dụ `rm -rf Packages/NotchUI/.build`) rồi chạy lại. SwiftPM đôi khi giữ danh sách file cũ của dependency dạng đường dẫn.

## Sơ đồ file

| File | Trách nhiệm |
|---|---|
| `Packages/MyNotchCore/Sources/MyNotchCore/Scheduling/Scheduler.swift` | `Scheduler`, `ScheduledAction`, `TaskScheduler` |
| `…/MyNotchCore/Settings/*` | `SettingKey`, `SettingsStore`, `ModuleSettings` |
| `…/MyNotchCore/Module/*` | `ModuleID`, `ModuleDescriptor`, `ModuleError`, `ModuleState`, `NotchTab`, `FeatureModule`, `NotchPresenter`, `ModuleContext`, `ModuleRegistry`, `Log` |
| `…/MyNotchCore/Activity/*` | `LiveActivity`, `ActivityPriority`, `ActivityCenter`, `ActivityPublisher` |
| `…/MyNotchCore/Permissions/*` | `Permission`, `PermissionStatus`, `PermissionCenter`, `SystemPermissionCenter` |
| `…/MyNotchCore/Hotkeys/HotkeyRegistry.swift` | `HotkeyRegistry`, `ModuleHotkeys` |
| `Packages/MyNotchCore/Sources/MyNotchTestSupport/*` | `ManualScheduler`, `makeIsolatedDefaults`, `FakePermissionCenter`, `FakePresenter`, `RegistryHarness` |
| `Packages/NotchUI/Sources/NotchUI/Geometry/*` | `ScreenDescriptor`, `NotchLayoutConfig`, `InterfaceSettings`, `DisplayMode`, `NotchGeometry` |
| `…/NotchUI/State/*` | `NotchState`, `NotchViewModel` |
| `…/NotchUI/Fullscreen/*` | `WindowInfo`, `FullscreenRule`, `FullscreenDetector` |
| `…/NotchUI/Views/*` | `NotchTokens`, `NotchShape`, `TabBar`, `NotchRootView` |
| `…/NotchUI/Window/*` | `NotchPanel`, `FirstMouseHostingView`, `NotchHoverTracker`, `NotchWindowController` |
| `…/NotchUI/Screens/*` | `NSScreen.displayID/displayUUID`, `ScreenManager`, `NotchCoordinator` |
| `Packages/Modules/Battery/Sources/BatteryModule/*` | `PowerSourceSnapshot`, `PowerSourceParser`, `PowerSourceReading`, `IOKitPowerSource`, `BatteryActivityPolicy`, các view, `BatteryModule` |
| `App/*` | `main.swift`, `AppDelegate`, `ModuleList`, `AppSettings`, `LaunchAtLogin`, `StatusItemController`, `Settings/*` |
| `project.yml` | Sinh `MyNotch.xcodeproj` (không commit) cùng `App/Info.plist`, `App/MyNotch.entitlements` |
| `scripts/verify.sh` | Cổng kiểm tra cục bộ |

## Task 0: Kiểm tra công cụ

- [ ] **Step 1: Xác nhận Xcode và XcodeGen**

```bash
xcode-select -p && xcodebuild -version && xcodegen --version
```

Expected: `/Applications/Xcode-26.6.0.app/Contents/Developer`, `Xcode 26.6`, `Version: 2.46.0`. Nếu thiếu XcodeGen: `brew install xcodegen`.

- [ ] **Step 2: Xác nhận repo sạch**

```bash
git status --short
```

Expected: không có dòng nào.


## Task 1: Khởi tạo package MyNotchCore và Scheduler

Tạo package lõi cùng target `MyNotchTestSupport`. `Scheduler` là cách duy nhất các thành phần chờ theo thời gian, để test điều khiển được thời gian bằng `ManualScheduler`. Lần đầu chạy, SwiftPM sẽ tải KeyboardShortcuts 3.1.0.

**Files:**
- Create: `Packages/MyNotchCore/Package.swift`
- Create: `Packages/MyNotchCore/Sources/MyNotchCore/Scheduling/Scheduler.swift`
- Create: `Packages/MyNotchCore/Sources/MyNotchTestSupport/ManualScheduler.swift`
- Test: `Packages/MyNotchCore/Tests/MyNotchCoreTests/ManualSchedulerTests.swift`

- [ ] **Step 1: Tạo khung package**

`Packages/MyNotchCore/Package.swift`:

```swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MyNotchCore",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "MyNotchCore", targets: ["MyNotchCore"]),
        .library(name: "MyNotchTestSupport", targets: ["MyNotchTestSupport"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", exact: "3.1.0"),
    ],
    targets: [
        .target(
            name: "MyNotchCore",
            dependencies: ["KeyboardShortcuts"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .target(
            name: "MyNotchTestSupport",
            dependencies: ["MyNotchCore"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(
            name: "MyNotchCoreTests",
            dependencies: ["MyNotchCore", "MyNotchTestSupport"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
    ]
)
```

`Packages/MyNotchCore/Sources/MyNotchCore/Scheduling/Scheduler.swift`:

```swift
/// Handle to a scheduled action; cancelling prevents it from running.
public final class ScheduledAction {
    public private(set) var isCancelled = false
    private let onCancel: () -> Void

    public init(onCancel: @escaping () -> Void = {}) { self.onCancel = onCancel }

    public func cancel() {
        guard !isCancelled else { return }
        isCancelled = true
        onCancel()
    }
}

/// Runs an action after a delay. Injected so delays are testable.
public protocol Scheduler: AnyObject {
    @discardableResult
    func schedule(after delay: Duration, _ action: @escaping @MainActor () -> Void) -> ScheduledAction
}

/// Production scheduler backed by `Task.sleep`.
public final class TaskScheduler: Scheduler {
    public init() {}

    @discardableResult
    public func schedule(after delay: Duration, _ action: @escaping @MainActor () -> Void) -> ScheduledAction {
        var task: Task<Void, Never>?
        let handle = ScheduledAction { task?.cancel() }
        task = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, !handle.isCancelled else { return }
            action()
        }
        return handle
    }
}
```

- [ ] **Step 2: Viết test (chưa có code nên phải fail)**

`Packages/MyNotchCore/Tests/MyNotchCoreTests/ManualSchedulerTests.swift`:

```swift
import Testing
@testable import MyNotchCore
import MyNotchTestSupport

@Suite struct ManualSchedulerTests {
    @Test func runsDueActionsInOrderAndSkipsCancelled() {
        let scheduler = ManualScheduler()
        var log: [String] = []
        scheduler.schedule(after: .milliseconds(200)) { log.append("b") }
        scheduler.schedule(after: .milliseconds(100)) { log.append("a") }
        let cancelled = scheduler.schedule(after: .milliseconds(150)) { log.append("x") }
        cancelled.cancel()
        scheduler.advance(by: .milliseconds(150))
        #expect(log == ["a"])
        scheduler.advance(by: .milliseconds(50))
        #expect(log == ["a", "b"])
        #expect(scheduler.pendingCount == 0)
    }
}
```

- [ ] **Step 3: Chạy test, xác nhận fail**

```bash
swift test --package-path Packages/MyNotchCore --filter 'ManualSchedulerTests'
```

Expected: FAIL, lỗi biên dịch `cannot find 'ManualScheduler' in scope` (hoặc `no such module 'MyNotchTestSupport'`).

- [ ] **Step 4: Viết code**

`Packages/MyNotchCore/Sources/MyNotchTestSupport/ManualScheduler.swift`:

```swift
import MyNotchCore

/// Deterministic scheduler for tests: time only moves when `advance(by:)` is called.
public final class ManualScheduler: Scheduler {
    private struct Entry {
        let id: Int
        let fireAt: Duration
        let action: @MainActor () -> Void
        let handle: ScheduledAction
    }

    public private(set) var now: Duration = .zero
    private var entries: [Entry] = []
    private var nextID = 0

    public init() {}

    @discardableResult
    public func schedule(after delay: Duration, _ action: @escaping @MainActor () -> Void) -> ScheduledAction {
        let handle = ScheduledAction()
        entries.append(Entry(id: nextID, fireAt: now + delay, action: action, handle: handle))
        nextID += 1
        return handle
    }

    /// Moves time forward, running due actions in time order (ties in scheduling order).
    public func advance(by duration: Duration) {
        let target = now + duration
        while let next = entries
            .filter({ $0.fireAt <= target && !$0.handle.isCancelled })
            .min(by: { ($0.fireAt, $0.id) < ($1.fireAt, $1.id) }) {
            entries.removeAll { $0.id == next.id }
            now = next.fireAt
            next.action()
        }
        entries.removeAll { $0.handle.isCancelled }
        now = target
    }

    /// Number of scheduled actions that have neither fired nor been cancelled.
    public var pendingCount: Int { entries.filter { !$0.handle.isCancelled }.count }
}
```

- [ ] **Step 5: Chạy test, xác nhận pass**

```bash
swift test --package-path Packages/MyNotchCore --filter 'ManualSchedulerTests'
```

Expected: `✔ Test run with 1 test in 1 suite passed`.

- [ ] **Step 6: Commit**

```bash
git add Packages/MyNotchCore/Package.swift Packages/MyNotchCore/Sources/MyNotchCore/Scheduling/Scheduler.swift Packages/MyNotchCore/Tests/MyNotchCoreTests/ManualSchedulerTests.swift Packages/MyNotchCore/Sources/MyNotchTestSupport/ManualScheduler.swift
git commit -m "feat(core): add Scheduler and ManualScheduler test support"
```


## Task 2: SettingKey và SettingsStore

Lưu cài đặt có kiểu trên `UserDefaults` dạng JSON, có giá trị mặc định và kẹp khoảng. `SettingsStore` là `@Observable`: mỗi lần ghi tăng `revision` để mọi view đang đọc cài đặt được vẽ lại.

**Files:**
- Create: `Packages/MyNotchCore/Sources/MyNotchTestSupport/IsolatedDefaults.swift`
- Create: `Packages/MyNotchCore/Sources/MyNotchCore/Settings/SettingKey.swift`
- Create: `Packages/MyNotchCore/Sources/MyNotchCore/Settings/SettingsStore.swift`
- Test: `Packages/MyNotchCore/Tests/MyNotchCoreTests/SettingsStoreTests.swift`

- [ ] **Step 1: Viết test (chưa có code nên phải fail)**

`Packages/MyNotchCore/Tests/MyNotchCoreTests/SettingsStoreTests.swift`:

```swift
import Testing
@testable import MyNotchCore
import MyNotchTestSupport

@Suite struct SettingsStoreTests {
    @Test func returnsDefaultUntilSet() {
        let store = SettingsStore(defaults: makeIsolatedDefaults())
        let key = SettingKey("interface.openDelayMs", default: 150)
        #expect(store.value(key) == 150)
        store.set(400, for: key)
        #expect(store.value(key) == 400)
        store.reset(key)
        #expect(store.value(key) == 150)
    }

    @Test func clampsOutOfRangeValues() {
        let store = SettingsStore(defaults: makeIsolatedDefaults())
        let key = SettingKey("interface.closeDelayMs", default: 300, clampedTo: 0...1000)
        store.set(5_000, for: key)
        #expect(store.value(key) == 1000)
    }

    @Test func roundTripsCodableValues() {
        let store = SettingsStore(defaults: makeIsolatedDefaults())
        let key = SettingKey<[String]>("app.recent", default: [])
        store.set(["a", "b"], for: key)
        #expect(store.value(key) == ["a", "b"])
    }
}
```

- [ ] **Step 2: Chạy test, xác nhận fail**

```bash
swift test --package-path Packages/MyNotchCore --filter 'SettingsStoreTests'
```

Expected: FAIL, lỗi biên dịch `cannot find 'SettingsStore' in scope`.

- [ ] **Step 3: Viết code**

`Packages/MyNotchCore/Sources/MyNotchTestSupport/IsolatedDefaults.swift`:

```swift
import Foundation

/// A fresh, empty UserDefaults suite per call.
public func makeIsolatedDefaults() -> UserDefaults {
    let suite = "MyNotchTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return defaults
}
```

`Packages/MyNotchCore/Sources/MyNotchCore/Settings/SettingKey.swift`:

```swift
/// Typed settings key with a default value and an optional normalization (e.g. clamping).
nonisolated public struct SettingKey<Value: Codable & Sendable>: Sendable {
    public let name: String
    public let defaultValue: Value
    let normalize: @Sendable (Value) -> Value

    public init(_ name: String, default defaultValue: Value) {
        self.name = name
        self.defaultValue = defaultValue
        self.normalize = { $0 }
    }
}

extension SettingKey where Value: Comparable {
    /// A key whose stored value is clamped into `range` when read.
    public init(_ name: String, default defaultValue: Value, clampedTo range: ClosedRange<Value>) {
        self.name = name
        self.defaultValue = defaultValue
        self.normalize = { min(max($0, range.lowerBound), range.upperBound) }
    }
}
```

`Packages/MyNotchCore/Sources/MyNotchCore/Settings/SettingsStore.swift`:

```swift
import Foundation
import Observation
import SwiftUI

/// JSON-encoded settings on top of `UserDefaults`, observable by SwiftUI.
@Observable
public final class SettingsStore {
    @ObservationIgnored private let defaults: UserDefaults
    /// Bumped on every write so views reading any setting refresh.
    private var revision = 0

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func value<Value>(_ key: SettingKey<Value>) -> Value {
        _ = revision
        guard let data = defaults.data(forKey: key.name),
              let decoded = try? JSONDecoder().decode(Value.self, from: data) else {
            return key.defaultValue
        }
        return key.normalize(decoded)
    }

    public func set<Value>(_ value: Value, for key: SettingKey<Value>) {
        guard let data = try? JSONEncoder().encode(key.normalize(value)) else { return }
        defaults.set(data, forKey: key.name)
        revision += 1
    }

    public func reset<Value>(_ key: SettingKey<Value>) {
        defaults.removeObject(forKey: key.name)
        revision += 1
    }

    public func binding<Value>(_ key: SettingKey<Value>) -> Binding<Value> {
        Binding(get: { self.value(key) }, set: { self.set($0, for: key) })
    }
}
```

- [ ] **Step 4: Chạy test, xác nhận pass**

```bash
swift test --package-path Packages/MyNotchCore --filter 'SettingsStoreTests'
```

Expected: `✔ Test run with 3 tests in 1 suite passed`.

- [ ] **Step 5: Commit**

```bash
git add Packages/MyNotchCore/Tests/MyNotchCoreTests/SettingsStoreTests.swift Packages/MyNotchCore/Sources/MyNotchTestSupport/IsolatedDefaults.swift Packages/MyNotchCore/Sources/MyNotchCore/Settings/SettingKey.swift Packages/MyNotchCore/Sources/MyNotchCore/Settings/SettingsStore.swift
git commit -m "feat(core): add typed SettingsStore"
```


## Task 3: Kiểu dữ liệu lõi của module

Các kiểu giá trị dùng chung. Kiểu dữ liệu thuần được đánh dấu `nonisolated` vì package dùng `defaultIsolation(MainActor)`; thiếu chữ này, conformance `Equatable` sẽ bị cô lập vào MainActor và không dùng được ở ngữ cảnh khác.

**Files:**
- Create: `Packages/MyNotchCore/Sources/MyNotchCore/Module/ModuleID.swift`
- Create: `Packages/MyNotchCore/Sources/MyNotchCore/Permissions/Permission.swift`
- Create: `Packages/MyNotchCore/Sources/MyNotchCore/Module/ModuleDescriptor.swift`
- Create: `Packages/MyNotchCore/Sources/MyNotchCore/Module/ModuleError.swift`
- Create: `Packages/MyNotchCore/Sources/MyNotchCore/Module/ModuleState.swift`
- Create: `Packages/MyNotchCore/Sources/MyNotchCore/Module/NotchTab.swift`
- Create: `Packages/MyNotchCore/Sources/MyNotchCore/Activity/LiveActivity.swift`
- Create: `Packages/MyNotchCore/Sources/MyNotchCore/Module/Log.swift`
- Test: `Packages/MyNotchCore/Tests/MyNotchCoreTests/CoreTypesTests.swift`

- [ ] **Step 1: Viết test (chưa có code nên phải fail)**

`Packages/MyNotchCore/Tests/MyNotchCoreTests/CoreTypesTests.swift`:

```swift
import CoreGraphics
import SwiftUI
import Testing
@testable import MyNotchCore

@Suite struct CoreTypesTests {
    @Test func tabHeightIsClampedWithDefault() {
        func tab(_ height: CGFloat?) -> NotchTab {
            NotchTab(id: "x", title: "X", systemImage: "circle", preferredHeight: height, content: AnyView(EmptyView()))
        }
        #expect(tab(nil).contentHeight == 190)
        #expect(tab(50).contentHeight == 120)
        #expect(tab(500).contentHeight == 300)
    }

    @Test func moduleErrorsMapToStates() {
        #expect(ModuleState(.needsPermission(.accessibility)) == .needsPermission(.accessibility))
        #expect(ModuleState(.unavailable(reason: "r")) == .unavailable(reason: "r"))
        #expect(ModuleState(.failed(reason: "f")) == .failed(reason: "f"))
    }

    @Test func permissionsDeepLinkToPrivacyPanes() {
        #expect(Permission.accessibility.settingsURL.hasSuffix("?Privacy_Accessibility"))
        #expect(Permission.automation(bundleID: "com.spotify.client").settingsURL.hasSuffix("?Privacy_Automation"))
    }

    @Test func priorityOrdering() {
        #expect(ActivityPriority.low < .normal && .normal < .high && .high < .critical)
    }
}
```

- [ ] **Step 2: Chạy test, xác nhận fail**

```bash
swift test --package-path Packages/MyNotchCore --filter 'CoreTypesTests'
```

Expected: FAIL, lỗi biên dịch `cannot find 'NotchTab' in scope`.

- [ ] **Step 3: Viết code**

`Packages/MyNotchCore/Sources/MyNotchCore/Module/ModuleID.swift`:

```swift
/// Stable identifier of a feature module, e.g. "battery". Lowercase ASCII letters and digits only.
nonisolated public struct ModuleID: Hashable, Sendable, Codable, ExpressibleByStringLiteral, CustomStringConvertible {
    public let rawValue: String

    public init(_ rawValue: String) {
        precondition(
            !rawValue.isEmpty && rawValue.allSatisfy { $0.isASCII && ($0.isLowercase || $0.isNumber) },
            "ModuleID must be non-empty lowercase ASCII letters or digits: \(rawValue)"
        )
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) { self.init(value) }

    public var description: String { rawValue }
}
```

`Packages/MyNotchCore/Sources/MyNotchCore/Permissions/Permission.swift`:

```swift
/// System permissions a module can require.
nonisolated public enum Permission: Hashable, Sendable, Codable {
    case accessibility
    case screenRecording
    case calendars
    case reminders
    case bluetooth
    case automation(bundleID: String)
    case microphone

    public var displayName: String {
        switch self {
        case .accessibility: "Accessibility"
        case .screenRecording: "Screen Recording"
        case .calendars: "Calendars"
        case .reminders: "Reminders"
        case .bluetooth: "Bluetooth"
        case .automation(let bundleID): "Automation (\(bundleID))"
        case .microphone: "Microphone"
        }
    }

    /// Deep link into the matching System Settings privacy pane.
    public var settingsURL: String {
        let base = "x-apple.systempreferences:com.apple.preference.security?"
        return switch self {
        case .accessibility: base + "Privacy_Accessibility"
        case .screenRecording: base + "Privacy_ScreenCapture"
        case .calendars: base + "Privacy_Calendars"
        case .reminders: base + "Privacy_Reminders"
        case .bluetooth: base + "Privacy_Bluetooth"
        case .automation: base + "Privacy_Automation"
        case .microphone: base + "Privacy_Microphone"
        }
    }
}

nonisolated public enum PermissionStatus: Sendable, Equatable {
    case granted
    case denied
    case notDetermined
}
```

`Packages/MyNotchCore/Sources/MyNotchCore/Module/ModuleDescriptor.swift`:

```swift
/// Static facts about a module, shown in Settings and used by the registry.
nonisolated public struct ModuleDescriptor: Sendable {
    public let id: ModuleID
    public let displayName: String
    public let systemImage: String
    public let defaultEnabled: Bool
    public let permissions: [Permission]
    public let order: Int

    public init(
        id: ModuleID,
        displayName: String,
        systemImage: String,
        defaultEnabled: Bool,
        permissions: [Permission] = [],
        order: Int
    ) {
        self.id = id
        self.displayName = displayName
        self.systemImage = systemImage
        self.defaultEnabled = defaultEnabled
        self.permissions = permissions
        self.order = order
    }
}
```

`Packages/MyNotchCore/Sources/MyNotchCore/Module/ModuleError.swift`:

```swift
/// The only errors a module may report. The registry maps them to `ModuleState`.
nonisolated public enum ModuleError: Error, Sendable, Equatable {
    case needsPermission(Permission)
    case unavailable(reason: String)
    case failed(reason: String)
}
```

`Packages/MyNotchCore/Sources/MyNotchCore/Module/ModuleState.swift`:

```swift
/// Lifecycle state of a module, owned by `ModuleRegistry`.
nonisolated public enum ModuleState: Equatable, Sendable {
    case disabled
    case starting
    case running
    case stopping
    case needsPermission(Permission)
    case unavailable(reason: String)
    case failed(reason: String)

    init(_ error: ModuleError) {
        switch error {
        case .needsPermission(let permission): self = .needsPermission(permission)
        case .unavailable(let reason): self = .unavailable(reason: reason)
        case .failed(let reason): self = .failed(reason: reason)
        }
    }
}
```

`Packages/MyNotchCore/Sources/MyNotchCore/Module/NotchTab.swift`:

```swift
import SwiftUI

/// Content a running module shows when the notch is open.
public struct NotchTab: Identifiable {
    nonisolated public static let defaultHeight: CGFloat = 190
    nonisolated public static let heightRange: ClosedRange<CGFloat> = 120...300

    public let id: ModuleID
    public let title: String
    public let systemImage: String
    public let preferredHeight: CGFloat?
    public let content: AnyView

    public init(id: ModuleID, title: String, systemImage: String, preferredHeight: CGFloat? = nil, content: AnyView) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.preferredHeight = preferredHeight
        self.content = content
    }

    /// Content height after applying the default and the allowed range.
    public var contentHeight: CGFloat {
        min(max(preferredHeight ?? Self.defaultHeight, Self.heightRange.lowerBound), Self.heightRange.upperBound)
    }
}
```

`Packages/MyNotchCore/Sources/MyNotchCore/Activity/LiveActivity.swift`:

```swift
import SwiftUI

nonisolated public enum ActivityPriority: Int, Comparable, Sendable {
    case low, normal, high, critical

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Small content shown beside the notch while it is closed.
public struct LiveActivity: Identifiable {
    public let id: String
    public let priority: ActivityPriority
    public let leading: AnyView
    public let trailing: AnyView
    public let expiresAfter: Duration?

    public init(
        id: String,
        priority: ActivityPriority = .normal,
        expiresAfter: Duration? = nil,
        leading: AnyView,
        trailing: AnyView
    ) {
        self.id = id
        self.priority = priority
        self.expiresAfter = expiresAfter
        self.leading = leading
        self.trailing = trailing
    }
}
```

`Packages/MyNotchCore/Sources/MyNotchCore/Module/Log.swift`:

```swift
import os

/// Central `os.Logger` factory. Never log user content.
public enum Log {
    public static let subsystem = "io.lucasvu.mynotch"

    public static func logger(category: String) -> Logger {
        Logger(subsystem: subsystem, category: category)
    }
}
```

- [ ] **Step 4: Chạy test, xác nhận pass**

```bash
swift test --package-path Packages/MyNotchCore --filter 'CoreTypesTests'
```

Expected: `✔ Test run with 4 tests in 1 suite passed`.

- [ ] **Step 5: Commit**

```bash
git add Packages/MyNotchCore/Tests/MyNotchCoreTests/CoreTypesTests.swift Packages/MyNotchCore/Sources/MyNotchCore/Module/ModuleID.swift Packages/MyNotchCore/Sources/MyNotchCore/Permissions/Permission.swift Packages/MyNotchCore/Sources/MyNotchCore/Module/ModuleDescriptor.swift Packages/MyNotchCore/Sources/MyNotchCore/Module/ModuleError.swift Packages/MyNotchCore/Sources/MyNotchCore/Module/ModuleState.swift Packages/MyNotchCore/Sources/MyNotchCore/Module/NotchTab.swift Packages/MyNotchCore/Sources/MyNotchCore/Activity/LiveActivity.swift Packages/MyNotchCore/Sources/MyNotchCore/Module/Log.swift
git commit -m "feat(core): add module, permission and activity value types"
```


## Task 4: ActivityCenter

Giữ live activity của mọi module, chọn activity có ưu tiên cao nhất (bằng nhau thì cái mới nhất), tự gỡ activity hết hạn. `ActivityPublisher` là mặt tiền theo từng module, nên module không thể gỡ activity của module khác.

**Files:**
- Create: `Packages/MyNotchCore/Sources/MyNotchCore/Activity/ActivityCenter.swift`
- Test: `Packages/MyNotchCore/Tests/MyNotchCoreTests/TestHelpers.swift`
- Test: `Packages/MyNotchCore/Tests/MyNotchCoreTests/ActivityCenterTests.swift`

- [ ] **Step 1: Viết test (chưa có code nên phải fail)**

`Packages/MyNotchCore/Tests/MyNotchCoreTests/TestHelpers.swift`:

```swift
import SwiftUI
@testable import MyNotchCore

func activity(_ id: String, _ priority: ActivityPriority = .normal, expiresAfter: Duration? = nil) -> LiveActivity {
    LiveActivity(id: id, priority: priority, expiresAfter: expiresAfter, leading: AnyView(EmptyView()), trailing: AnyView(EmptyView()))
}
```

`Packages/MyNotchCore/Tests/MyNotchCoreTests/ActivityCenterTests.swift`:

```swift
import Testing
@testable import MyNotchCore
import MyNotchTestSupport

@Suite struct ActivityCenterTests {
    @Test func highestPriorityWinsThenMostRecent() {
        let center = ActivityCenter(scheduler: ManualScheduler())
        center.set(activity("a", .normal), from: "one")
        center.set(activity("b", .high), from: "two")
        #expect(center.current?.id == "two/b")
        center.set(activity("c", .high), from: "one")
        #expect(center.current?.id == "one/c")
        center.clear(id: "c", from: "one")
        #expect(center.current?.id == "two/b")
    }

    @Test func expiresAfterLifetime() {
        let scheduler = ManualScheduler()
        let center = ActivityCenter(scheduler: scheduler)
        center.set(activity("charging", expiresAfter: .seconds(4)), from: "battery")
        scheduler.advance(by: .seconds(3))
        #expect(center.current?.id == "battery/charging")
        scheduler.advance(by: .seconds(1))
        #expect(center.current == nil)
    }

    @Test func replacingAnActivityRestartsItsLifetime() {
        let scheduler = ManualScheduler()
        let center = ActivityCenter(scheduler: scheduler)
        center.set(activity("x", expiresAfter: .seconds(4)), from: "m")
        scheduler.advance(by: .seconds(3))
        center.set(activity("x", expiresAfter: .seconds(4)), from: "m")
        scheduler.advance(by: .seconds(3))
        #expect(center.current?.id == "m/x")
    }

    @Test func clearAllRemovesOnlyThatModule() {
        let center = ActivityCenter(scheduler: ManualScheduler())
        center.set(activity("a"), from: "one")
        center.set(activity("b"), from: "two")
        center.clearAll(from: "two")
        #expect(center.entries.map(\.id) == ["one/a"])
    }
}
```

- [ ] **Step 2: Chạy test, xác nhận fail**

```bash
swift test --package-path Packages/MyNotchCore --filter 'ActivityCenterTests'
```

Expected: FAIL, lỗi biên dịch `cannot find 'ActivityCenter' in scope`.

- [ ] **Step 3: Viết code**

`Packages/MyNotchCore/Sources/MyNotchCore/Activity/ActivityCenter.swift`:

```swift
import Observation

/// Holds every module's live activities and exposes the one to display.
@Observable
public final class ActivityCenter {
    public struct Entry: Identifiable {
        public let module: ModuleID
        public let activity: LiveActivity
        let sequence: Int
        public var id: String { "\(module.rawValue)/\(activity.id)" }
    }

    /// Highest priority entry; ties go to the most recently set.
    public private(set) var current: Entry?
    public private(set) var entries: [Entry] = []

    @ObservationIgnored private let scheduler: any Scheduler
    @ObservationIgnored private var expiries: [String: ScheduledAction] = [:]
    @ObservationIgnored private var sequence = 0

    public init(scheduler: any Scheduler) {
        self.scheduler = scheduler
    }

    public func set(_ activity: LiveActivity, from module: ModuleID) {
        sequence += 1
        let entry = Entry(module: module, activity: activity, sequence: sequence)
        entries.removeAll { $0.id == entry.id }
        entries.append(entry)
        expiries.removeValue(forKey: entry.id)?.cancel()
        if let lifetime = activity.expiresAfter {
            let expectedSequence = entry.sequence
            expiries[entry.id] = scheduler.schedule(after: lifetime) { [weak self] in
                guard let self, self.entries.contains(where: { $0.id == entry.id && $0.sequence == expectedSequence }) else { return }
                self.clear(id: activity.id, from: module)
            }
        }
        recompute()
    }

    public func clear(id: String, from module: ModuleID) {
        let key = "\(module.rawValue)/\(id)"
        expiries.removeValue(forKey: key)?.cancel()
        entries.removeAll { $0.id == key }
        recompute()
    }

    public func clearAll(from module: ModuleID) {
        for entry in entries where entry.module == module {
            expiries.removeValue(forKey: entry.id)?.cancel()
        }
        entries.removeAll { $0.module == module }
        recompute()
    }

    private func recompute() {
        current = entries.max { ($0.activity.priority, $0.sequence) < ($1.activity.priority, $1.sequence) }
    }
}

/// Module-scoped facade over `ActivityCenter`.
public final class ActivityPublisher {
    private let center: ActivityCenter
    private let module: ModuleID

    init(center: ActivityCenter, module: ModuleID) {
        self.center = center
        self.module = module
    }

    public func set(_ activity: LiveActivity) { center.set(activity, from: module) }
    public func clear(id: String) { center.clear(id: id, from: module) }
    public func clearAll() { center.clearAll(from: module) }
}
```

- [ ] **Step 4: Chạy test, xác nhận pass**

```bash
swift test --package-path Packages/MyNotchCore --filter 'ActivityCenterTests'
```

Expected: `✔ Test run with 4 tests in 1 suite passed`.

- [ ] **Step 5: Commit**

```bash
git add Packages/MyNotchCore/Tests/MyNotchCoreTests/TestHelpers.swift Packages/MyNotchCore/Tests/MyNotchCoreTests/ActivityCenterTests.swift Packages/MyNotchCore/Sources/MyNotchCore/Activity/ActivityCenter.swift
git commit -m "feat(core): add ActivityCenter with priority and expiry"
```


## Task 5: Hợp đồng module: quyền, cài đặt module, phím tắt, context

Mọi thứ module nhận qua `ModuleContext`. `ModuleSettings` chặn key ngoài namespace `module.<id>.`. `HotkeyRegistry` đặt tên phím tắt dạng `<owner>_<name>` vì KeyboardShortcuts cấm dấu chấm. `SystemPermissionCenter` chỉ kiểm tra, không bao giờ bật hộp thoại xin quyền.

**Files:**
- Create: `Packages/MyNotchCore/Sources/MyNotchCore/Permissions/PermissionCenter.swift`
- Create: `Packages/MyNotchCore/Sources/MyNotchCore/Permissions/SystemPermissionCenter.swift`
- Create: `Packages/MyNotchCore/Sources/MyNotchCore/Settings/ModuleSettings.swift`
- Create: `Packages/MyNotchCore/Sources/MyNotchCore/Hotkeys/HotkeyRegistry.swift`
- Create: `Packages/MyNotchCore/Sources/MyNotchCore/Module/NotchPresenter.swift`
- Create: `Packages/MyNotchCore/Sources/MyNotchCore/Module/FeatureModule.swift`
- Create: `Packages/MyNotchCore/Sources/MyNotchCore/Module/ModuleContext.swift`
- Test: `Packages/MyNotchCore/Tests/MyNotchCoreTests/ModuleSettingsTests.swift`
- Test: `Packages/MyNotchCore/Tests/MyNotchCoreTests/HotkeyRegistryTests.swift`

- [ ] **Step 1: Viết test (chưa có code nên phải fail)**

`Packages/MyNotchCore/Tests/MyNotchCoreTests/ModuleSettingsTests.swift`:

```swift
import Testing
@testable import MyNotchCore
import MyNotchTestSupport

@Suite struct ModuleSettingsTests {
    @Test func moduleSettingsArePrefixed() {
        let store = SettingsStore(defaults: makeIsolatedDefaults())
        let battery = ModuleSettings(store: store, module: "battery")
        let key = battery.key("lowThreshold", default: 20, clampedTo: 5...50)
        #expect(key.name == "module.battery.lowThreshold")
        battery.set(80, for: key)
        #expect(battery.value(key) == 50)
    }
}
```

`Packages/MyNotchCore/Tests/MyNotchCoreTests/HotkeyRegistryTests.swift`:

```swift
import Testing
@testable import MyNotchCore

@Suite struct HotkeyRegistryTests {
    @Test func namesAreScopedByOwner() {
        #expect(HotkeyRegistry.qualifiedName("toggleNotch", owner: nil) == "app_toggleNotch")
        #expect(HotkeyRegistry.qualifiedName("openTab", owner: "battery") == "battery_openTab")
    }
}
```

- [ ] **Step 2: Chạy test, xác nhận fail**

```bash
swift test --package-path Packages/MyNotchCore --filter 'ModuleSettingsTests|HotkeyRegistryTests'
```

Expected: FAIL, lỗi biên dịch `cannot find 'ModuleSettings' in scope`.

- [ ] **Step 3: Viết code**

`Packages/MyNotchCore/Sources/MyNotchCore/Permissions/PermissionCenter.swift`:

```swift
/// Checks permission status without prompting, and opens System Settings.
public protocol PermissionCenter: AnyObject {
    func status(of permission: Permission) -> PermissionStatus
    func openSystemSettings(for permission: Permission)
}
```

`Packages/MyNotchCore/Sources/MyNotchCore/Permissions/SystemPermissionCenter.swift`:

```swift
import AppKit
import ApplicationServices
import AVFoundation
import CoreBluetooth
import CoreGraphics
import EventKit

/// Real permission checks backed by the system frameworks. Never prompts.
public final class SystemPermissionCenter: PermissionCenter {
    public init() {}

    public func status(of permission: Permission) -> PermissionStatus {
        switch permission {
        case .accessibility:
            return AXIsProcessTrusted() ? .granted : .denied
        case .screenRecording:
            return CGPreflightScreenCaptureAccess() ? .granted : .denied
        case .calendars:
            return Self.map(EKEventStore.authorizationStatus(for: .event))
        case .reminders:
            return Self.map(EKEventStore.authorizationStatus(for: .reminder))
        case .bluetooth:
            switch CBManager.authorization {
            case .allowedAlways: return .granted
            case .notDetermined: return .notDetermined
            default: return .denied
            }
        case .automation(let bundleID):
            return Self.automationStatus(bundleID: bundleID)
        case .microphone:
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .authorized: return .granted
            case .notDetermined: return .notDetermined
            default: return .denied
            }
        }
    }

    public func openSystemSettings(for permission: Permission) {
        guard let url = URL(string: permission.settingsURL) else { return }
        NSWorkspace.shared.open(url)
    }

    private static func map(_ status: EKAuthorizationStatus) -> PermissionStatus {
        switch status {
        case .fullAccess: .granted
        case .notDetermined: .notDetermined
        default: .denied
        }
    }

    private static func automationStatus(bundleID: String) -> PermissionStatus {
        var target = AEAddressDesc()
        let created = bundleID.withCString { pointer in
            AECreateDesc(DescType(typeApplicationBundleID), pointer, strlen(pointer), &target)
        }
        guard created == noErr else { return .notDetermined }
        defer { AEDisposeDesc(&target) }
        let result = AEDeterminePermissionToAutomateTarget(&target, AEEventClass(typeWildCard), AEEventID(typeWildCard), false)
        switch result {
        case noErr: return .granted
        case OSStatus(errAEEventNotPermitted): return .denied
        default: return .notDetermined   // not running yet, or consent not requested
        }
    }
}
```

`Packages/MyNotchCore/Sources/MyNotchCore/Settings/ModuleSettings.swift`:

```swift
import SwiftUI

/// Settings access confined to the `module.<id>.` namespace.
public struct ModuleSettings {
    private let store: SettingsStore
    private let module: ModuleID

    init(store: SettingsStore, module: ModuleID) {
        self.store = store
        self.module = module
    }

    public func key<Value>(_ name: String, default defaultValue: Value) -> SettingKey<Value> {
        SettingKey(Self.qualifiedName(name, module: module), default: defaultValue)
    }

    public func key<Value: Comparable>(_ name: String, default defaultValue: Value, clampedTo range: ClosedRange<Value>) -> SettingKey<Value> {
        SettingKey(Self.qualifiedName(name, module: module), default: defaultValue, clampedTo: range)
    }

    public func value<Value>(_ key: SettingKey<Value>) -> Value { store.value(checked(key)) }
    public func set<Value>(_ value: Value, for key: SettingKey<Value>) { store.set(value, for: checked(key)) }
    public func binding<Value>(_ key: SettingKey<Value>) -> Binding<Value> { store.binding(checked(key)) }

    static func qualifiedName(_ name: String, module: ModuleID) -> String {
        "module.\(module.rawValue).\(name)"
    }

    private func checked<Value>(_ key: SettingKey<Value>) -> SettingKey<Value> {
        precondition(key.name.hasPrefix("module.\(module.rawValue)."), "Key \(key.name) is outside module \(module)")
        return key
    }
}
```

`Packages/MyNotchCore/Sources/MyNotchCore/Hotkeys/HotkeyRegistry.swift`:

```swift
import KeyboardShortcuts
import Observation
import SwiftUI

/// All global shortcuts of the app and its modules, backed by KeyboardShortcuts.
@Observable
public final class HotkeyRegistry {
    public struct Registration: Identifiable {
        public let name: KeyboardShortcuts.Name
        public let title: String
        public let owner: ModuleID?
        public var id: String { name.rawValue }
    }

    public private(set) var registrations: [Registration] = []

    public init() {}

    /// Registers a shortcut. `localName` must not contain "." (a KeyboardShortcuts rule).
    public func register(
        _ localName: String,
        title: String,
        owner: ModuleID?,
        initial: KeyboardShortcuts.Shortcut? = nil,
        action: @escaping @MainActor () -> Void
    ) {
        let name = KeyboardShortcuts.Name(Self.qualifiedName(localName, owner: owner), initial: initial)
        unregister(name)
        KeyboardShortcuts.onKeyUp(for: name) { MainActor.assumeIsolated { action() } }
        registrations.append(Registration(name: name, title: title, owner: owner))
    }

    public func unregisterAll(owner: ModuleID) {
        for registration in registrations where registration.owner == owner {
            unregister(registration.name)
        }
    }

    /// Groups of registrations that share the same key combination.
    public func conflicts() -> [[Registration]] {
        let assigned = registrations.compactMap { registration in
            KeyboardShortcuts.getShortcut(for: registration.name).map { ($0, registration) }
        }
        return Dictionary(grouping: assigned, by: \.0)
            .values
            .filter { $0.count > 1 }
            .map { $0.map(\.1) }
    }

    static func qualifiedName(_ localName: String, owner: ModuleID?) -> String {
        precondition(!localName.contains("."), "Shortcut names must not contain '.': \(localName)")
        return "\(owner?.rawValue ?? "app")_\(localName)"
    }

    private func unregister(_ name: KeyboardShortcuts.Name) {
        KeyboardShortcuts.removeHandler(for: name)
        registrations.removeAll { $0.name == name }
    }
}

/// Module-scoped facade over `HotkeyRegistry`; shortcuts are removed when the module stops.
public final class ModuleHotkeys {
    private let registry: HotkeyRegistry
    private let module: ModuleID

    init(registry: HotkeyRegistry, module: ModuleID) {
        self.registry = registry
        self.module = module
    }

    public func register(
        _ localName: String,
        title: String,
        initial: KeyboardShortcuts.Shortcut? = nil,
        action: @escaping @MainActor () -> Void
    ) {
        registry.register(localName, title: title, owner: module, initial: initial, action: action)
    }
}
```

`Packages/MyNotchCore/Sources/MyNotchCore/Module/NotchPresenter.swift`:

```swift
import SwiftUI

/// Lets modules drive the notch without knowing about windows or screens.
public protocol NotchPresenter: AnyObject {
    func open(tab: ModuleID)
    func showToast(_ content: AnyView, duration: Duration)
    func close()
}
```

`Packages/MyNotchCore/Sources/MyNotchCore/Module/FeatureModule.swift`:

```swift
import SwiftUI

/// Contract every feature module implements. Modules depend only on MyNotchCore and NotchUI.
public protocol FeatureModule: AnyObject {
    var descriptor: ModuleDescriptor { get }
    func start(_ context: ModuleContext) async throws(ModuleError)
    func stop() async
    func makeTab() -> NotchTab?
    func makeSettingsView() -> AnyView?
}
```

`Packages/MyNotchCore/Sources/MyNotchCore/Module/ModuleContext.swift`:

```swift
import os

/// Everything a module receives from the app. Owned by the registry for one start/stop cycle.
public final class ModuleContext {
    public let id: ModuleID
    public let settings: ModuleSettings
    public let activities: ActivityPublisher
    public let presenter: any NotchPresenter
    public let hotkeys: ModuleHotkeys
    public let permissions: any PermissionCenter
    public let logger: Logger

    private var tasks: [Task<Void, Never>] = []

    init(
        id: ModuleID,
        settings: ModuleSettings,
        activities: ActivityPublisher,
        presenter: any NotchPresenter,
        hotkeys: ModuleHotkeys,
        permissions: any PermissionCenter
    ) {
        self.id = id
        self.settings = settings
        self.activities = activities
        self.presenter = presenter
        self.hotkeys = hotkeys
        self.permissions = permissions
        self.logger = Log.logger(category: id.rawValue)
    }

    /// Runs work that is cancelled automatically when the module stops.
    public func run(_ operation: @escaping @MainActor () async -> Void) {
        tasks.append(Task { await operation() })
    }

    func cancelAll() {
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
    }
}
```

- [ ] **Step 4: Chạy test, xác nhận pass**

```bash
swift test --package-path Packages/MyNotchCore --filter 'ModuleSettingsTests|HotkeyRegistryTests'
```

Expected: `✔ Test run with 2 tests in 2 suites passed`.

- [ ] **Step 5: Commit**

```bash
git add Packages/MyNotchCore/Tests/MyNotchCoreTests/ModuleSettingsTests.swift Packages/MyNotchCore/Tests/MyNotchCoreTests/HotkeyRegistryTests.swift Packages/MyNotchCore/Sources/MyNotchCore/Permissions/PermissionCenter.swift Packages/MyNotchCore/Sources/MyNotchCore/Permissions/SystemPermissionCenter.swift Packages/MyNotchCore/Sources/MyNotchCore/Settings/ModuleSettings.swift Packages/MyNotchCore/Sources/MyNotchCore/Hotkeys/HotkeyRegistry.swift Packages/MyNotchCore/Sources/MyNotchCore/Module/NotchPresenter.swift Packages/MyNotchCore/Sources/MyNotchCore/Module/FeatureModule.swift Packages/MyNotchCore/Sources/MyNotchCore/Module/ModuleContext.swift
git commit -m "feat(core): add FeatureModule contract and ModuleContext"
```


## Task 6: ModuleRegistry

Điều khiển vòng đời module: kiểm quyền trước khi `start`, cô lập lỗi, gỡ activity/phím tắt/tab khi dừng, `retry`, tạm dừng toàn bộ. `RegistryHarness` trong `MyNotchTestSupport` ghép registry với các bản giả để test của mọi package dùng chung.

**Files:**
- Create: `Packages/MyNotchCore/Sources/MyNotchTestSupport/Fakes.swift`
- Create: `Packages/MyNotchCore/Sources/MyNotchCore/Module/ModuleRegistry.swift`
- Test: `Packages/MyNotchCore/Tests/MyNotchCoreTests/FakeModule.swift`
- Test: `Packages/MyNotchCore/Tests/MyNotchCoreTests/ModuleRegistryTests.swift`

- [ ] **Step 1: Viết test (chưa có code nên phải fail)**

`Packages/MyNotchCore/Tests/MyNotchCoreTests/FakeModule.swift`:

```swift
import Foundation
import SwiftUI
@testable import MyNotchCore
import MyNotchTestSupport

final class FakeModule: FeatureModule {
    let descriptor: ModuleDescriptor
    var startError: ModuleError?
    var activityOnStart: LiveActivity?
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var context: ModuleContext?

    init(_ id: ModuleID, order: Int = 0, defaultEnabled: Bool = true, permissions: [Permission] = []) {
        descriptor = ModuleDescriptor(
            id: id, displayName: id.rawValue, systemImage: "circle",
            defaultEnabled: defaultEnabled, permissions: permissions, order: order
        )
    }

    func start(_ context: ModuleContext) async throws(ModuleError) {
        startCount += 1
        self.context = context
        if let activityOnStart { context.activities.set(activityOnStart) }
        if let startError { throw startError }
    }

    func stop() async { stopCount += 1 }

    func makeTab() -> NotchTab? {
        NotchTab(id: descriptor.id, title: descriptor.displayName, systemImage: "circle", content: AnyView(EmptyView()))
    }

    func makeSettingsView() -> AnyView? { nil }
}

typealias Harness = RegistryHarness
```

`Packages/MyNotchCore/Tests/MyNotchCoreTests/ModuleRegistryTests.swift`:

```swift
import Testing
@testable import MyNotchCore
import MyNotchTestSupport

@Suite struct ModuleRegistryTests {
    @Test func bootstrapStartsOnlyEnabledModules() async {
        let on = FakeModule("on", order: 1)
        let off = FakeModule("off", order: 2, defaultEnabled: false)
        let harness = Harness([off, on])
        await harness.registry.bootstrap()
        #expect(harness.registry.state(of: "on") == .running)
        #expect(harness.registry.state(of: "off") == .disabled)
        #expect(harness.registry.tabs.map(\.id) == ["on"])
        #expect(harness.registry.modules.map(\.descriptor.id) == ["on", "off"])
    }

    @Test func failingModuleIsIsolatedAndCleanedUp() async {
        let broken = FakeModule("broken", order: 1)
        broken.startError = .failed(reason: "boom")
        broken.activityOnStart = activity("x")
        let healthy = FakeModule("healthy", order: 2)
        let harness = Harness([broken, healthy])
        await harness.registry.bootstrap()
        #expect(harness.registry.state(of: "broken") == .failed(reason: "boom"))
        #expect(harness.registry.state(of: "healthy") == .running)
        #expect(harness.activities.entries.isEmpty)
        #expect(harness.registry.tabs.map(\.id) == ["healthy"])
    }

    @Test func missingPermissionSkipsStartUntilGranted() async {
        let module = FakeModule("needy", permissions: [.accessibility])
        let harness = Harness([module])
        await harness.registry.bootstrap()
        #expect(harness.registry.state(of: "needy") == .needsPermission(.accessibility))
        #expect(module.startCount == 0)
        harness.permissions.statuses[.accessibility] = .granted
        await harness.registry.refreshPermissions()
        #expect(harness.registry.state(of: "needy") == .running)
    }

    @Test func disablingStopsAndRemovesActivitiesAndTab() async {
        let module = FakeModule("m")
        module.activityOnStart = activity("live")
        let harness = Harness([module])
        await harness.registry.bootstrap()
        #expect(harness.activities.current?.id == "m/live")
        await harness.registry.setEnabled(false, for: "m")
        #expect(module.stopCount == 1)
        #expect(harness.registry.state(of: "m") == .disabled)
        #expect(harness.activities.current == nil)
        #expect(harness.registry.tabs.isEmpty)
        #expect(harness.registry.isEnabled("m") == false)
    }

    @Test func retryRestartsAFailedModule() async {
        let module = FakeModule("m")
        module.startError = .unavailable(reason: "nope")
        let harness = Harness([module])
        await harness.registry.bootstrap()
        module.startError = nil
        await harness.registry.retry("m")
        #expect(harness.registry.state(of: "m") == .running)
        #expect(module.startCount == 2)
    }

    @Test func pauseStopsEverythingWithoutChangingEnabledSetting() async {
        let module = FakeModule("m")
        let harness = Harness([module])
        await harness.registry.bootstrap()
        await harness.registry.pauseAll()
        #expect(harness.registry.state(of: "m") == .disabled)
        #expect(harness.registry.isEnabled("m"))
        await harness.registry.resumeAll()
        #expect(harness.registry.state(of: "m") == .running)
    }
}
```

- [ ] **Step 2: Chạy test, xác nhận fail**

```bash
swift test --package-path Packages/MyNotchCore
```

Expected: FAIL, lỗi biên dịch `cannot find 'ModuleRegistry' in scope`.

- [ ] **Step 3: Viết code**

`Packages/MyNotchCore/Sources/MyNotchTestSupport/Fakes.swift`:

```swift
import MyNotchCore
import SwiftUI

/// Permission center whose answers tests set directly. Unknown permissions are denied.
public final class FakePermissionCenter: PermissionCenter {
    public var statuses: [Permission: PermissionStatus] = [:]
    public init() {}
    public func status(of permission: Permission) -> PermissionStatus { statuses[permission] ?? .denied }
    public func openSystemSettings(for permission: Permission) {}
}

/// Presenter that records requests.
public final class FakePresenter: NotchPresenter {
    public private(set) var openedTabs: [ModuleID] = []
    public private(set) var toastCount = 0
    public init() {}
    public func open(tab: ModuleID) { openedTabs.append(tab) }
    public func showToast(_ content: AnyView, duration: Duration) { toastCount += 1 }
    public func close() {}
}

/// Wires a `ModuleRegistry` with in-memory collaborators.
public struct RegistryHarness {
    public let settings = SettingsStore(defaults: makeIsolatedDefaults())
    public let scheduler = ManualScheduler()
    public let permissions = FakePermissionCenter()
    public let presenter = FakePresenter()
    public let activities: ActivityCenter
    public let registry: ModuleRegistry

    public init(_ modules: [any FeatureModule]) {
        activities = ActivityCenter(scheduler: scheduler)
        registry = ModuleRegistry(
            modules: modules, settings: settings, activities: activities,
            permissions: permissions, hotkeys: HotkeyRegistry(), presenter: presenter
        )
    }
}
```

`Packages/MyNotchCore/Sources/MyNotchCore/Module/ModuleRegistry.swift`:

```swift
import Observation
import SwiftUI

/// Owns module lifecycles. A failing module never affects the others.
@Observable
public final class ModuleRegistry {
    public let modules: [any FeatureModule]
    public private(set) var states: [ModuleID: ModuleState] = [:]
    public private(set) var tabs: [NotchTab] = []
    public private(set) var isPaused = false

    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private let activities: ActivityCenter
    @ObservationIgnored private let permissions: any PermissionCenter
    @ObservationIgnored private let hotkeys: HotkeyRegistry
    @ObservationIgnored private let presenter: any NotchPresenter
    @ObservationIgnored private var contexts: [ModuleID: ModuleContext] = [:]
    @ObservationIgnored private var tabCache: [ModuleID: NotchTab] = [:]

    public init(
        modules: [any FeatureModule],
        settings: SettingsStore,
        activities: ActivityCenter,
        permissions: any PermissionCenter,
        hotkeys: HotkeyRegistry,
        presenter: any NotchPresenter
    ) {
        let sorted = modules.sorted { $0.descriptor.order < $1.descriptor.order }
        precondition(Set(sorted.map(\.descriptor.id)).count == sorted.count, "Duplicate ModuleID")
        self.modules = sorted
        self.settings = settings
        self.activities = activities
        self.permissions = permissions
        self.hotkeys = hotkeys
        self.presenter = presenter
        for module in sorted { states[module.descriptor.id] = .disabled }
    }

    public static func enabledKey(for descriptor: ModuleDescriptor) -> SettingKey<Bool> {
        SettingKey("module.\(descriptor.id.rawValue).enabled", default: descriptor.defaultEnabled)
    }

    public func isEnabled(_ id: ModuleID) -> Bool {
        guard let module = module(id) else { return false }
        return settings.value(Self.enabledKey(for: module.descriptor))
    }

    public func state(of id: ModuleID) -> ModuleState { states[id] ?? .disabled }

    /// Starts every enabled module. Call once at launch.
    public func bootstrap() async {
        for module in modules where isEnabled(module.descriptor.id) {
            await start(module)
        }
    }

    public func setEnabled(_ enabled: Bool, for id: ModuleID) async {
        guard let module = module(id) else { return }
        settings.set(enabled, for: Self.enabledKey(for: module.descriptor))
        if enabled, !isPaused {
            await start(module)
        } else if !enabled {
            await stop(module)
        }
    }

    /// Stops then starts a module again, e.g. after a failure.
    public func retry(_ id: ModuleID) async {
        guard let module = module(id), isEnabled(id), !isPaused else { return }
        await stop(module)
        await start(module)
    }

    /// Restarts enabled modules that were waiting for a permission that is now granted.
    public func refreshPermissions() async {
        guard !isPaused else { return }
        for module in modules {
            guard case .needsPermission = state(of: module.descriptor.id), isEnabled(module.descriptor.id) else { continue }
            await start(module)
        }
    }

    public func pauseAll() async {
        isPaused = true
        for module in modules { await stop(module) }
    }

    public func resumeAll() async {
        isPaused = false
        await bootstrap()
    }

    public func settingsView(for id: ModuleID) -> AnyView? {
        module(id)?.makeSettingsView()
    }

    private func module(_ id: ModuleID) -> (any FeatureModule)? {
        modules.first { $0.descriptor.id == id }
    }

    private func start(_ module: any FeatureModule) async {
        let descriptor = module.descriptor
        let id = descriptor.id
        guard state(of: id) != .running, state(of: id) != .starting else { return }
        if let missing = descriptor.permissions.first(where: { permissions.status(of: $0) != .granted }) {
            states[id] = .needsPermission(missing)
            return
        }
        states[id] = .starting
        let context = ModuleContext(
            id: id,
            settings: ModuleSettings(store: settings, module: id),
            activities: ActivityPublisher(center: activities, module: id),
            presenter: presenter,
            hotkeys: ModuleHotkeys(registry: hotkeys, module: id),
            permissions: permissions
        )
        contexts[id] = context
        do {
            try await module.start(context)
            states[id] = .running
            tabCache[id] = module.makeTab()
        } catch {
            tearDown(id)
            states[id] = ModuleState(error)
            context.logger.error("Module failed to start: \(String(describing: error), privacy: .public)")
        }
        rebuildTabs()
    }

    private func stop(_ module: any FeatureModule) async {
        let id = module.descriptor.id
        if state(of: id) == .running {
            states[id] = .stopping
            await module.stop()
        }
        tearDown(id)
        states[id] = .disabled
        rebuildTabs()
    }

    private func tearDown(_ id: ModuleID) {
        contexts.removeValue(forKey: id)?.cancelAll()
        activities.clearAll(from: id)
        hotkeys.unregisterAll(owner: id)
        tabCache[id] = nil
    }

    private func rebuildTabs() {
        tabs = modules.compactMap { tabCache[$0.descriptor.id] }
    }
}
```

- [ ] **Step 4: Chạy test, xác nhận pass**

```bash
swift test --package-path Packages/MyNotchCore
```

Expected: `✔ Test run with 20 tests in 7 suites passed`.

- [ ] **Step 5: Commit**

```bash
git add Packages/MyNotchCore/Tests/MyNotchCoreTests/FakeModule.swift Packages/MyNotchCore/Tests/MyNotchCoreTests/ModuleRegistryTests.swift Packages/MyNotchCore/Sources/MyNotchTestSupport/Fakes.swift Packages/MyNotchCore/Sources/MyNotchCore/Module/ModuleRegistry.swift
git commit -m "feat(core): add ModuleRegistry with failure isolation"
```


## Task 7: Package NotchUI: hình học notch

`NotchGeometry` là phép tính thuần: notch thật lấy từ hai vùng auxiliary của `NSScreen`, notch ảo lấy từ cài đặt. Panel luôn có kích thước lớn nhất và neo giữa cạnh trên; `hitRect` là vùng con trỏ được tính là "ở trong notch".

**Files:**
- Create: `Packages/NotchUI/Package.swift`
- Create: `Packages/NotchUI/Sources/NotchUI/Geometry/ScreenDescriptor.swift`
- Create: `Packages/NotchUI/Sources/NotchUI/Geometry/InterfaceSettings.swift`
- Create: `Packages/NotchUI/Sources/NotchUI/State/NotchState.swift`
- Create: `Packages/NotchUI/Sources/NotchUI/Geometry/NotchGeometry.swift`
- Test: `Packages/NotchUI/Tests/NotchUITests/NotchGeometryTests.swift`

- [ ] **Step 1: Tạo khung package**

`Packages/NotchUI/Package.swift`:

```swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "NotchUI",
    platforms: [.macOS(.v26)],
    products: [.library(name: "NotchUI", targets: ["NotchUI"])],
    dependencies: [.package(path: "../MyNotchCore")],
    targets: [
        .target(
            name: "NotchUI",
            dependencies: ["MyNotchCore"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(
            name: "NotchUITests",
            dependencies: ["NotchUI", .product(name: "MyNotchTestSupport", package: "MyNotchCore")],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
    ]
)
```

- [ ] **Step 2: Viết test (chưa có code nên phải fail)**

`Packages/NotchUI/Tests/NotchUITests/NotchGeometryTests.swift`:

```swift
import CoreGraphics
import Testing
@testable import NotchUI

@Suite struct NotchGeometryTests {
    static let macBook14 = ScreenDescriptor(
        frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        safeAreaTop: 32, auxiliaryTopLeftWidth: 662, auxiliaryTopRightWidth: 665, menuBarHeight: 37
    )
    static let external = ScreenDescriptor(
        frame: CGRect(x: 1512, y: 0, width: 1920, height: 1080),
        safeAreaTop: 0, auxiliaryTopLeftWidth: nil, auxiliaryTopRightWidth: nil, menuBarHeight: 25
    )

    @Test func hardwareNotchUsesAuxiliaryAreas() {
        let geometry = NotchGeometry(screen: Self.macBook14, config: NotchLayoutConfig())
        #expect(geometry.kind == .hardware)
        #expect(geometry.notchSize == CGSize(width: 185, height: 32))
    }

    @Test func virtualNotchFallsBackToMenuBarHeight() {
        let geometry = NotchGeometry(screen: Self.external, config: NotchLayoutConfig())
        #expect(geometry.kind == .virtual)
        #expect(geometry.notchSize == CGSize(width: 185, height: 25))
    }

    @Test func virtualNotchClampsConfiguredSize() {
        let config = NotchLayoutConfig(virtualNotchWidth: 999, virtualNotchHeight: 10)
        let geometry = NotchGeometry(screen: Self.external, config: config)
        #expect(geometry.notchSize == CGSize(width: 300, height: 24))
    }

    @Test func shapeSizesPerState() {
        let geometry = NotchGeometry(screen: Self.macBook14, config: NotchLayoutConfig())
        #expect(geometry.shapeSize(for: .closed) == CGSize(width: 197, height: 32))
        #expect(geometry.shapeSize(for: .compact) == CGSize(width: 325, height: 32))
        #expect(geometry.shapeSize(for: .open(nil), contentHeight: 190) == CGSize(width: 600, height: 222))
        #expect(geometry.shapeSize(for: .open(nil), contentHeight: 900) == CGSize(width: 600, height: 332))
    }

    @Test func panelIsTopCentredAndMaxSized() {
        let geometry = NotchGeometry(screen: Self.external, config: NotchLayoutConfig())
        let frame = geometry.panelFrame(in: Self.external.frame)
        #expect(frame == CGRect(x: 1512 + 960 - 360, y: 1080 - 325, width: 720, height: 325))
    }

    @Test func hitRectIsShapePlusPadding() {
        let geometry = NotchGeometry(screen: Self.macBook14, config: NotchLayoutConfig())
        let rect = geometry.hitRect(for: .closed, in: Self.macBook14.frame)
        #expect(rect == CGRect(x: 756 - 98.5 - 8, y: 982 - 32 - 8, width: 197 + 16, height: 32 + 16))
    }
}
```

- [ ] **Step 3: Chạy test, xác nhận fail**

```bash
swift test --package-path Packages/NotchUI --filter 'NotchGeometryTests'
```

Expected: FAIL, lỗi biên dịch `cannot find 'ScreenDescriptor' in scope`.

- [ ] **Step 4: Viết code**

`Packages/NotchUI/Sources/NotchUI/Geometry/ScreenDescriptor.swift`:

```swift
import AppKit

/// The screen facts geometry needs, decoupled from `NSScreen` for testing.
nonisolated public struct ScreenDescriptor: Equatable, Sendable {
    public var frame: CGRect
    public var safeAreaTop: CGFloat
    public var auxiliaryTopLeftWidth: CGFloat?
    public var auxiliaryTopRightWidth: CGFloat?
    public var menuBarHeight: CGFloat

    public init(frame: CGRect, safeAreaTop: CGFloat, auxiliaryTopLeftWidth: CGFloat?, auxiliaryTopRightWidth: CGFloat?, menuBarHeight: CGFloat) {
        self.frame = frame
        self.safeAreaTop = safeAreaTop
        self.auxiliaryTopLeftWidth = auxiliaryTopLeftWidth
        self.auxiliaryTopRightWidth = auxiliaryTopRightWidth
        self.menuBarHeight = menuBarHeight
    }
}

extension ScreenDescriptor {
    public init(_ screen: NSScreen) {
        self.init(
            frame: screen.frame,
            safeAreaTop: screen.safeAreaInsets.top,
            auxiliaryTopLeftWidth: screen.auxiliaryTopLeftArea?.width,
            auxiliaryTopRightWidth: screen.auxiliaryTopRightArea?.width,
            // Auto-hidden menu bars report 0; fall back to the standard height.
            menuBarHeight: max(screen.frame.maxY - screen.visibleFrame.maxY, 24)
        )
    }
}
```

`Packages/NotchUI/Sources/NotchUI/Geometry/InterfaceSettings.swift`:

```swift
import CoreGraphics
import MyNotchCore

nonisolated public enum DisplayMode: String, Codable, Sendable, CaseIterable {
    case all, main, cursor
}

/// Global interface settings (`interface.*`).
public enum InterfaceSettings {
    public static let displayMode = SettingKey("interface.displayMode", default: DisplayMode.all)
    public static let virtualNotchWidth = SettingKey("interface.virtualNotchWidth", default: 185.0, clampedTo: 120...300)
    /// 0 means "same as the menu bar".
    public static let virtualNotchHeight = SettingKey("interface.virtualNotchHeight", default: 0.0, clampedTo: 0...40)
    public static let openWidth = SettingKey("interface.openWidth", default: 600.0, clampedTo: 480...720)
    public static let openDelayMs = SettingKey("interface.openDelayMs", default: 150, clampedTo: 0...1000)
    public static let closeDelayMs = SettingKey("interface.closeDelayMs", default: 300, clampedTo: 0...1000)
    public static let hideInFullscreen = SettingKey("interface.hideInFullscreen", default: true)
}

/// Geometry inputs read from settings.
nonisolated public struct NotchLayoutConfig: Equatable, Sendable {
    public var virtualNotchWidth: CGFloat = 185
    /// nil = menu bar height.
    public var virtualNotchHeight: CGFloat?
    public var compactSideWidth: CGFloat = 64
    public var openWidth: CGFloat = 600

    public init(virtualNotchWidth: CGFloat = 185, virtualNotchHeight: CGFloat? = nil, compactSideWidth: CGFloat = 64, openWidth: CGFloat = 600) {
        self.virtualNotchWidth = virtualNotchWidth
        self.virtualNotchHeight = virtualNotchHeight
        self.compactSideWidth = compactSideWidth
        self.openWidth = openWidth
    }
}

extension NotchLayoutConfig {
    public init(settings: SettingsStore) {
        let height = settings.value(InterfaceSettings.virtualNotchHeight)
        self.init(
            virtualNotchWidth: settings.value(InterfaceSettings.virtualNotchWidth),
            virtualNotchHeight: height == 0 ? nil : max(height, 24),
            openWidth: settings.value(InterfaceSettings.openWidth)
        )
    }
}
```

`Packages/NotchUI/Sources/NotchUI/State/NotchState.swift`:

```swift
import MyNotchCore

nonisolated public enum NotchState: Equatable, Sendable {
    case closed
    case compact
    case open(ModuleID?)
    case toast

    public var isExpanded: Bool {
        switch self {
        case .open, .toast: true
        case .closed, .compact: false
        }
    }
}
```

`Packages/NotchUI/Sources/NotchUI/Geometry/NotchGeometry.swift`:

```swift
import CoreGraphics
import MyNotchCore

nonisolated public enum NotchKind: Equatable, Sendable { case hardware, virtual }

/// Pure size and placement math for one screen's notch.
nonisolated public struct NotchGeometry: Equatable, Sendable {
    public static let maxOpenWidth: CGFloat = 720
    public static let hitPadding: CGFloat = 8

    public let kind: NotchKind
    /// Size of the physical (or virtual) notch body.
    public let notchSize: CGSize
    public let config: NotchLayoutConfig

    public init(screen: ScreenDescriptor, config: NotchLayoutConfig) {
        self.config = config
        if screen.safeAreaTop > 0, let left = screen.auxiliaryTopLeftWidth, let right = screen.auxiliaryTopRightWidth {
            kind = .hardware
            notchSize = CGSize(width: screen.frame.width - left - right, height: screen.safeAreaTop)
        } else {
            kind = .virtual
            let width = min(max(config.virtualNotchWidth, 120), 300)
            let height = min(max(config.virtualNotchHeight ?? screen.menuBarHeight, 24), 40)
            notchSize = CGSize(width: width, height: height)
        }
    }

    public func cornerRadii(for state: NotchState) -> (top: CGFloat, bottom: CGFloat) {
        state.isExpanded ? (8, 24) : (6, 10)
    }

    /// Full shape size, including the top "ears" that blend into the menu bar.
    public func shapeSize(for state: NotchState, contentHeight: CGFloat = NotchTab.defaultHeight) -> CGSize {
        let ears = 2 * cornerRadii(for: state).top
        switch state {
        case .closed:
            return CGSize(width: notchSize.width + ears, height: notchSize.height)
        case .compact:
            return CGSize(width: notchSize.width + ears + 2 * config.compactSideWidth, height: notchSize.height)
        case .open, .toast:
            let width = min(max(config.openWidth, 480), Self.maxOpenWidth)
            let content = min(max(contentHeight, NotchTab.heightRange.lowerBound), NotchTab.heightRange.upperBound)
            return CGSize(width: width, height: notchSize.height + content)
        }
    }

    /// Fixed panel size: the largest the notch can ever get.
    public var panelSize: CGSize {
        CGSize(width: Self.maxOpenWidth, height: notchSize.height + NotchTab.heightRange.upperBound)
    }

    /// Panel frame anchored to the top centre of `screenFrame` (AppKit coordinates).
    public func panelFrame(in screenFrame: CGRect) -> CGRect {
        CGRect(
            x: screenFrame.midX - panelSize.width / 2,
            y: screenFrame.maxY - panelSize.height,
            width: panelSize.width,
            height: panelSize.height
        )
    }

    /// Area (screen coordinates) where the pointer counts as "inside" the notch.
    public func hitRect(for state: NotchState, contentHeight: CGFloat = NotchTab.defaultHeight, in screenFrame: CGRect) -> CGRect {
        let size = shapeSize(for: state, contentHeight: contentHeight)
        return CGRect(
            x: screenFrame.midX - size.width / 2,
            y: screenFrame.maxY - size.height,
            width: size.width,
            height: size.height
        ).insetBy(dx: -Self.hitPadding, dy: -Self.hitPadding)
    }
}
```

- [ ] **Step 5: Chạy test, xác nhận pass**

```bash
swift test --package-path Packages/NotchUI --filter 'NotchGeometryTests'
```

Expected: `✔ Test run with 6 tests in 1 suite passed`.

- [ ] **Step 6: Commit**

```bash
git add Packages/NotchUI/Package.swift Packages/NotchUI/Tests/NotchUITests/NotchGeometryTests.swift Packages/NotchUI/Sources/NotchUI/Geometry/ScreenDescriptor.swift Packages/NotchUI/Sources/NotchUI/Geometry/InterfaceSettings.swift Packages/NotchUI/Sources/NotchUI/State/NotchState.swift Packages/NotchUI/Sources/NotchUI/Geometry/NotchGeometry.swift
git commit -m "feat(notch-ui): add notch geometry"
```


## Task 8: NotchViewModel (state machine)

State machine của một màn hình. `compact` không được lưu: `displayState` trả về `compact` khi đang đóng mà có activity. Ghim và kéo-thả huỷ lệnh đóng đang chờ.

**Files:**
- Create: `Packages/NotchUI/Sources/NotchUI/State/NotchViewModel.swift`
- Test: `Packages/NotchUI/Tests/NotchUITests/NotchViewModelTests.swift`

- [ ] **Step 1: Viết test (chưa có code nên phải fail)**

`Packages/NotchUI/Tests/NotchUITests/NotchViewModelTests.swift`:

```swift
import MyNotchCore
import MyNotchTestSupport
import SwiftUI
import Testing
@testable import NotchUI

@Suite struct NotchViewModelTests {
    let scheduler = ManualScheduler()

    func makeModel(tabs: [ModuleID] = ["battery", "clipboard"]) -> NotchViewModel {
        NotchViewModel(scheduler: scheduler, availableTabs: { tabs }, delays: { (.milliseconds(150), .milliseconds(300)) })
    }

    @Test func hoverOpensAfterDelay() {
        let model = makeModel()
        model.pointerEntered()
        scheduler.advance(by: .milliseconds(149))
        #expect(model.state == .closed)
        scheduler.advance(by: .milliseconds(1))
        #expect(model.state == .open("battery"))
    }

    @Test func leavingBeforeDelayCancelsOpen() {
        let model = makeModel()
        model.pointerEntered()
        scheduler.advance(by: .milliseconds(100))
        model.pointerExited()
        scheduler.advance(by: .seconds(1))
        #expect(model.state == .closed)
    }

    @Test func leavingClosesAfterDelayUnlessReentered() {
        let model = makeModel()
        model.click()
        model.pointerExited()
        scheduler.advance(by: .milliseconds(200))
        model.pointerEntered()
        scheduler.advance(by: .seconds(1))
        #expect(model.state.isExpanded)
        model.pointerExited()
        scheduler.advance(by: .milliseconds(300))
        #expect(model.state == .closed)
    }

    @Test func pinnedAndDraggingKeepItOpen() {
        let model = makeModel()
        model.click()
        model.isPinned = true
        model.pointerExited()
        scheduler.advance(by: .seconds(1))
        #expect(model.state.isExpanded)
        model.isPinned = false
        model.setDragging(true)
        scheduler.advance(by: .seconds(1))
        #expect(model.state.isExpanded)
        model.setDragging(false)
        scheduler.advance(by: .milliseconds(300))
        #expect(model.state == .closed)
    }

    @Test func remembersLastTab() {
        let model = makeModel()
        model.open(tab: "clipboard")
        model.close()
        model.click()
        #expect(model.state == .open("clipboard"))
    }

    @Test func unknownTabFallsBackToFirst() {
        let model = makeModel()
        model.open(tab: "missing")
        #expect(model.state == .open("battery"))
    }

    @Test func toggleOpensAndCloses() {
        let model = makeModel()
        model.toggle()
        #expect(model.state.isExpanded)
        model.toggle()
        #expect(model.state == .closed)
    }

    @Test func activityTurnsClosedIntoCompact() {
        let model = makeModel()
        model.hasActivity = true
        #expect(model.displayState == .compact)
        model.click()
        #expect(model.displayState == .open("battery"))
        model.close()
        #expect(model.displayState == .compact)
    }

    @Test func toastClosesAfterDurationUnlessPointerInside() {
        let model = makeModel()
        model.showToast(AnyView(EmptyView()), duration: .seconds(2))
        #expect(model.state == .toast)
        scheduler.advance(by: .seconds(2))
        #expect(model.state == .closed)

        model.showToast(AnyView(EmptyView()), duration: .seconds(2))
        model.pointerEntered()
        scheduler.advance(by: .seconds(2))
        #expect(model.state == .toast)
        model.pointerExited()
        scheduler.advance(by: .milliseconds(300))
        #expect(model.state == .closed)
    }
}
```

- [ ] **Step 2: Chạy test, xác nhận fail**

```bash
swift test --package-path Packages/NotchUI --filter 'NotchViewModelTests'
```

Expected: FAIL, lỗi biên dịch `cannot find 'NotchViewModel' in scope`.

- [ ] **Step 3: Viết code**

`Packages/NotchUI/Sources/NotchUI/State/NotchViewModel.swift`:

```swift
import MyNotchCore
import Observation
import SwiftUI

/// Per-screen notch state machine. Time is injected through `Scheduler`.
@Observable
public final class NotchViewModel {
    public private(set) var state: NotchState = .closed
    public private(set) var toastContent: AnyView?
    public private(set) var lastTab: ModuleID?
    public private(set) var isPointerInside = false
    /// Set by the owner when the activity center has something to show.
    public var hasActivity = false
    public var isPinned = false {
        didSet { isPinned ? pendingClose?.cancel() : scheduleCloseIfPointerOutside() }
    }
    public private(set) var isDragging = false

    /// What the view should render: `closed` becomes `compact` while an activity is live.
    public var displayState: NotchState {
        state == .closed && hasActivity ? .compact : state
    }

    @ObservationIgnored private let scheduler: any Scheduler
    @ObservationIgnored private let availableTabs: () -> [ModuleID]
    @ObservationIgnored private let delays: () -> (open: Duration, close: Duration)
    @ObservationIgnored private var pendingOpen: ScheduledAction?
    @ObservationIgnored private var pendingClose: ScheduledAction?

    public init(
        scheduler: any Scheduler,
        availableTabs: @escaping () -> [ModuleID],
        delays: @escaping () -> (open: Duration, close: Duration)
    ) {
        self.scheduler = scheduler
        self.availableTabs = availableTabs
        self.delays = delays
    }

    public func pointerEntered() {
        isPointerInside = true
        pendingClose?.cancel()
        guard !state.isExpanded, pendingOpen == nil else { return }
        pendingOpen = scheduler.schedule(after: delays().open) { [weak self] in
            self?.pendingOpen = nil
            self?.open(tab: nil)
        }
    }

    public func pointerExited() {
        isPointerInside = false
        pendingOpen?.cancel()
        pendingOpen = nil
        scheduleCloseIfPointerOutside()
    }

    public func click() {
        if !state.isExpanded { open(tab: nil) }
    }

    public func toggle() {
        state.isExpanded ? close() : open(tab: nil)
    }

    /// Opens `tab`, or the last used tab, or the first available one.
    public func open(tab: ModuleID?) {
        pendingOpen?.cancel()
        pendingOpen = nil
        pendingClose?.cancel()
        let tabs = availableTabs()
        let resolved = [tab, lastTab].compactMap { $0 }.first(where: tabs.contains) ?? tabs.first
        lastTab = resolved ?? lastTab
        toastContent = nil
        state = .open(resolved)
    }

    public func showToast(_ content: AnyView, duration: Duration) {
        pendingClose?.cancel()
        toastContent = content
        state = .toast
        pendingClose = scheduler.schedule(after: duration) { [weak self] in
            guard let self, !self.isPointerInside, !self.isPinned else { return }
            self.close()
        }
    }

    public func close() {
        pendingOpen?.cancel()
        pendingOpen = nil
        pendingClose?.cancel()
        toastContent = nil
        state = .closed
    }

    public func setDragging(_ dragging: Bool) {
        isDragging = dragging
        dragging ? pendingClose?.cancel() : scheduleCloseIfPointerOutside()
    }

    private func scheduleCloseIfPointerOutside() {
        guard state.isExpanded, !isPointerInside, !isPinned, !isDragging else { return }
        pendingClose?.cancel()
        pendingClose = scheduler.schedule(after: delays().close) { [weak self] in
            self?.close()
        }
    }
}
```

- [ ] **Step 4: Chạy test, xác nhận pass**

```bash
swift test --package-path Packages/NotchUI --filter 'NotchViewModelTests'
```

Expected: `✔ Test run with 9 tests in 1 suite passed`.

- [ ] **Step 5: Commit**

```bash
git add Packages/NotchUI/Tests/NotchUITests/NotchViewModelTests.swift Packages/NotchUI/Sources/NotchUI/State/NotchViewModel.swift
git commit -m "feat(notch-ui): add notch state machine"
```


## Task 9: Nhận diện fullscreen

Quy tắc thuần `FullscreenRule` được test riêng; `FullscreenDetector` đọc danh sách cửa sổ thật (chỉ bounds, không cần quyền Screen Recording) mỗi khi đổi Space hoặc đổi app, và đọc lại sau 500ms.

**Files:**
- Create: `Packages/NotchUI/Sources/NotchUI/Fullscreen/FullscreenRule.swift`
- Create: `Packages/NotchUI/Sources/NotchUI/Screens/DisplayIdentity.swift`
- Create: `Packages/NotchUI/Sources/NotchUI/Fullscreen/FullscreenDetector.swift`
- Test: `Packages/NotchUI/Tests/NotchUITests/FullscreenRuleTests.swift`

- [ ] **Step 1: Viết test (chưa có code nên phải fail)**

`Packages/NotchUI/Tests/NotchUITests/FullscreenRuleTests.swift`:

```swift
import CoreGraphics
import Testing
@testable import NotchUI

@Suite struct FullscreenRuleTests {
    let display = CGRect(x: 0, y: 0, width: 1512, height: 982)

    @Test func frontmostWindowCoveringDisplayIsFullscreen() {
        let windows = [WindowInfo(ownerPID: 42, layer: 0, bounds: display)]
        #expect(FullscreenRule.isFullscreen(windows: windows, frontmostPID: 42, displayBounds: display))
    }

    @Test func otherAppsOrLayersDoNotCount() {
        let windows = [
            WindowInfo(ownerPID: 7, layer: 0, bounds: display),
            WindowInfo(ownerPID: 42, layer: 25, bounds: display),
        ]
        #expect(!FullscreenRule.isFullscreen(windows: windows, frontmostPID: 42, displayBounds: display))
    }

    @Test func maximisedButNotFullscreenWindowDoesNotCount() {
        let windows = [WindowInfo(ownerPID: 42, layer: 0, bounds: CGRect(x: 0, y: 37, width: 1512, height: 945))]
        #expect(!FullscreenRule.isFullscreen(windows: windows, frontmostPID: 42, displayBounds: display))
    }
}
```

- [ ] **Step 2: Chạy test, xác nhận fail**

```bash
swift test --package-path Packages/NotchUI --filter 'FullscreenRuleTests'
```

Expected: FAIL, lỗi biên dịch `cannot find 'WindowInfo' in scope`.

- [ ] **Step 3: Viết code**

`Packages/NotchUI/Sources/NotchUI/Fullscreen/FullscreenRule.swift`:

```swift
import CoreGraphics

/// One on-screen window, as reported by `CGWindowListCopyWindowInfo` (global top-left coordinates).
nonisolated public struct WindowInfo: Equatable, Sendable {
    public var ownerPID: pid_t
    public var layer: Int
    public var bounds: CGRect

    public init(ownerPID: pid_t, layer: Int, bounds: CGRect) {
        self.ownerPID = ownerPID
        self.layer = layer
        self.bounds = bounds
    }
}

nonisolated public enum FullscreenRule {
    /// True when the frontmost app has a normal-layer window covering the whole display.
    public static func isFullscreen(windows: [WindowInfo], frontmostPID: pid_t, displayBounds: CGRect) -> Bool {
        windows.contains { window in
            window.ownerPID == frontmostPID
                && window.layer == 0
                && abs(window.bounds.minX - displayBounds.minX) <= 1
                && abs(window.bounds.minY - displayBounds.minY) <= 1
                && abs(window.bounds.width - displayBounds.width) <= 1
                && abs(window.bounds.height - displayBounds.height) <= 1
        }
    }
}
```

`Packages/NotchUI/Sources/NotchUI/Screens/DisplayIdentity.swift`:

```swift
import AppKit

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    /// Stable across reconnects, unlike screen order or display IDs.
    var displayUUID: String? {
        guard let displayID, let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, uuid) as String
    }
}
```

`Packages/NotchUI/Sources/NotchUI/Fullscreen/FullscreenDetector.swift`:

```swift
import AppKit

/// Watches Space and app changes and reports which displays are covered by a fullscreen app.
final class FullscreenDetector {
    private var observers: [NSObjectProtocol] = []
    private var recheck: Task<Void, Never>?
    private let onChange: (Set<CGDirectDisplayID>) -> Void

    init(onChange: @escaping (Set<CGDirectDisplayID>) -> Void) {
        self.onChange = onChange
    }

    func start() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didActivateApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.evaluateSoon() }
            })
        }
        evaluate()
    }

    func stop() {
        observers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        observers.removeAll()
        recheck?.cancel()
    }

    /// Evaluate now and again after the Space transition animation settles.
    private func evaluateSoon() {
        evaluate()
        recheck?.cancel()
        recheck = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.evaluate()
        }
    }

    private func evaluate() {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else {
            onChange([])
            return
        }
        let windows = Self.onScreenWindows()
        let covered = NSScreen.screens.compactMap(\.displayID).filter { displayID in
            FullscreenRule.isFullscreen(windows: windows, frontmostPID: pid, displayBounds: CGDisplayBounds(displayID))
        }
        onChange(Set(covered))
    }

    private static func onScreenWindows() -> [WindowInfo] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        return list.compactMap { info in
            guard let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  let layer = info[kCGWindowLayer as String] as? Int,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict) else { return nil }
            return WindowInfo(ownerPID: pid, layer: layer, bounds: bounds)
        }
    }
}
```

- [ ] **Step 4: Chạy test, xác nhận pass**

```bash
swift test --package-path Packages/NotchUI --filter 'FullscreenRuleTests'
```

Expected: `✔ Test run with 3 tests in 1 suite passed`.

- [ ] **Step 5: Commit**

```bash
git add Packages/NotchUI/Tests/NotchUITests/FullscreenRuleTests.swift Packages/NotchUI/Sources/NotchUI/Fullscreen/FullscreenRule.swift Packages/NotchUI/Sources/NotchUI/Screens/DisplayIdentity.swift Packages/NotchUI/Sources/NotchUI/Fullscreen/FullscreenDetector.swift
git commit -m "feat(notch-ui): detect fullscreen apps per display"
```


## Task 10: Giao diện notch

Hình notch, thanh tab và view gốc. Phần này là SwiftUI nên kiểm chứng bằng build; hành vi hiển thị được kiểm tra tay ở Task 17.

**Files:**
- Create: `Packages/NotchUI/Sources/NotchUI/Views/NotchTokens.swift`
- Create: `Packages/NotchUI/Sources/NotchUI/Views/NotchShape.swift`
- Create: `Packages/NotchUI/Sources/NotchUI/Views/TabBar.swift`
- Create: `Packages/NotchUI/Sources/NotchUI/Views/NotchRootView.swift`

- [ ] **Step 1: Viết code**

`Packages/NotchUI/Sources/NotchUI/Views/NotchTokens.swift`:

```swift
import SwiftUI

/// Shared look of the notch. Modules use these instead of hard-coded values.
public enum NotchTokens {
    public static let background = Color.black
    public static let accent = Color(red: 0.49, green: 0.36, blue: 1.0)
    public static let primaryText = Color.white
    public static let secondaryText = Color.white.opacity(0.6)
    public static let padding: CGFloat = 14
    public static let spring = Animation.spring(response: 0.38, dampingFraction: 0.8)
}
```

`Packages/NotchUI/Sources/NotchUI/Views/NotchShape.swift`:

```swift
import SwiftUI

/// Notch outline: concave "ears" at the top that blend into the menu bar, rounded bottom corners.
public struct NotchShape: Shape {
    public var topRadius: CGFloat
    public var bottomRadius: CGFloat

    public init(topRadius: CGFloat, bottomRadius: CGFloat) {
        self.topRadius = topRadius
        self.bottomRadius = bottomRadius
    }

    public var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set { topRadius = newValue.first; bottomRadius = newValue.second }
    }

    public func path(in rect: CGRect) -> Path {
        let top = min(topRadius, rect.width / 4)
        let bottom = min(bottomRadius, rect.height / 2, (rect.width - 2 * top) / 2)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.minX + top, y: rect.minY + top), control: CGPoint(x: rect.minX + top, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + top, y: rect.maxY - bottom))
        path.addQuadCurve(to: CGPoint(x: rect.minX + top + bottom, y: rect.maxY), control: CGPoint(x: rect.minX + top, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - top - bottom, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - top, y: rect.maxY - bottom), control: CGPoint(x: rect.maxX - top, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - top, y: rect.minY + top))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY), control: CGPoint(x: rect.maxX - top, y: rect.minY))
        path.closeSubpath()
        return path
    }
}
```

`Packages/NotchUI/Sources/NotchUI/Views/TabBar.swift`:

```swift
import MyNotchCore
import SwiftUI

struct TabBar: View {
    let tabs: [NotchTab]
    let selected: ModuleID?
    let onSelect: (ModuleID) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(tabs) { tab in
                Button { onSelect(tab.id) } label: {
                    Label(tab.title, systemImage: tab.systemImage)
                        .labelStyle(.iconOnly)
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 30, height: 24)
                        .foregroundStyle(tab.id == selected ? NotchTokens.primaryText : NotchTokens.secondaryText)
                        .background(tab.id == selected ? Color.white.opacity(0.14) : .clear, in: Capsule())
                }
                .buttonStyle(.plain)
                .help(tab.title)
            }
        }
    }
}
```

`Packages/NotchUI/Sources/NotchUI/Views/NotchRootView.swift`:

```swift
import MyNotchCore
import SwiftUI

/// Root SwiftUI view hosted in each notch panel.
struct NotchRootView: View {
    let model: NotchViewModel
    let activities: ActivityCenter
    let registry: ModuleRegistry
    let geometry: NotchGeometry

    private var state: NotchState { model.displayState }

    private var selectedTab: NotchTab? {
        guard case .open(let id) = state, let id else { return nil }
        return registry.tabs.first { $0.id == id }
    }

    private var contentHeight: CGFloat { selectedTab?.contentHeight ?? NotchTab.defaultHeight }

    var body: some View {
        let size = geometry.shapeSize(for: state, contentHeight: contentHeight)
        let radii = geometry.cornerRadii(for: state)
        ZStack(alignment: .top) {
            NotchShape(topRadius: radii.top, bottomRadius: radii.bottom)
                .fill(NotchTokens.background)
            content
                .padding(.horizontal, radii.top)
        }
        .frame(width: size.width, height: size.height)
        .contentShape(NotchShape(topRadius: radii.top, bottomRadius: radii.bottom))
        .onTapGesture { model.click() }
        .animation(NotchTokens.spring, value: state)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder private var content: some View {
        switch state {
        case .closed:
            EmptyView()
        case .compact:
            if let entry = activities.current {
                HStack(spacing: 0) {
                    entry.activity.leading.frame(width: geometry.config.compactSideWidth)
                    Spacer(minLength: geometry.notchSize.width)
                    entry.activity.trailing.frame(width: geometry.config.compactSideWidth)
                }
                .frame(height: geometry.notchSize.height)
                .transition(.opacity)
            }
        case .open:
            expanded {
                if registry.tabs.count >= 2 {
                    TabBar(tabs: registry.tabs, selected: selectedTab?.id) { model.open(tab: $0) }
                        .padding(.bottom, 6)
                }
                if let selectedTab {
                    selectedTab.content.frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Text("Chưa có module nào đang chạy")
                        .foregroundStyle(NotchTokens.secondaryText)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        case .toast:
            expanded { model.toastContent }
        }
    }

    private func expanded<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: geometry.notchSize.height)
            content()
        }
        .padding([.horizontal, .bottom], NotchTokens.padding)
        .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)).animation(NotchTokens.spring.delay(0.08)))
    }
}
```

- [ ] **Step 2: Build / kiểm chứng**

```bash
swift build --package-path Packages/NotchUI
```

Expected: `Build complete!`.

- [ ] **Step 3: Commit**

```bash
git add Packages/NotchUI/Sources/NotchUI/Views/NotchTokens.swift Packages/NotchUI/Sources/NotchUI/Views/NotchShape.swift Packages/NotchUI/Sources/NotchUI/Views/TabBar.swift Packages/NotchUI/Sources/NotchUI/Views/NotchRootView.swift
git commit -m "feat(notch-ui): add notch shape and root view"
```


## Task 11: Cửa sổ notch và quản lý màn hình

Mỗi màn hình một `NotchPanel` cố định kích thước. Global/local mouse monitor báo vị trí con trỏ; panel chỉ nhận chuột khi con trỏ nằm trong `hitRect`, ngoài ra click xuyên qua. `ScreenManager` đồng bộ panel theo màn hình (UUID), chế độ hiển thị và fullscreen. `NotchCoordinator` là `NotchPresenter` thật.

**Files:**
- Create: `Packages/NotchUI/Sources/NotchUI/Window/NotchPanel.swift`
- Create: `Packages/NotchUI/Sources/NotchUI/Window/NotchHoverTracker.swift`
- Create: `Packages/NotchUI/Sources/NotchUI/Window/NotchWindowController.swift`
- Create: `Packages/NotchUI/Sources/NotchUI/Screens/ScreenManager.swift`
- Create: `Packages/NotchUI/Sources/NotchUI/Screens/NotchCoordinator.swift`

- [ ] **Step 1: Viết code**

`Packages/NotchUI/Sources/NotchUI/Window/NotchPanel.swift`:

```swift
import AppKit
import SwiftUI

/// Borderless, non-activating panel that floats above the menu bar on every Space.
final class NotchPanel: NSPanel {
    init(frame: CGRect) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .mainMenu + 3
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isMovable = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
    }

    /// Tabs that need typing (e.g. a search field) can opt in later.
    var allowsKeyStatus = false
    override var canBecomeKey: Bool { allowsKeyStatus }
    override var canBecomeMain: Bool { false }
}

/// Hosting view that accepts the first click even though the app is not active.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
```

`Packages/NotchUI/Sources/NotchUI/Window/NotchHoverTracker.swift`:

```swift
import AppKit

/// Reports pointer movement anywhere on screen. Mouse monitors need no Accessibility permission.
final class NotchHoverTracker {
    private var monitors: [Any] = []
    private let onMove: (CGPoint) -> Void

    init(onMove: @escaping (CGPoint) -> Void) {
        self.onMove = onMove
    }

    func start() {
        guard monitors.isEmpty else { return }
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.onMove(NSEvent.mouseLocation) }
        }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.onMove(NSEvent.mouseLocation) }
            return event
        }) {
            monitors.append(local)
        }
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
    }
}
```

`Packages/NotchUI/Sources/NotchUI/Window/NotchWindowController.swift`:

```swift
import AppKit
import MyNotchCore
import SwiftUI

/// Owns one screen's panel, view model and pointer hit-testing.
final class NotchWindowController {
    let displayID: CGDirectDisplayID
    let model: NotchViewModel
    private(set) var geometry: NotchGeometry
    private var screenFrame: CGRect
    private let panel: NotchPanel
    private let registry: ModuleRegistry
    private let activities: ActivityCenter
    private var isVisible = false

    init(
        displayID: CGDirectDisplayID,
        screen: ScreenDescriptor,
        config: NotchLayoutConfig,
        scheduler: any Scheduler,
        registry: ModuleRegistry,
        activities: ActivityCenter,
        delays: @escaping () -> (open: Duration, close: Duration)
    ) {
        self.displayID = displayID
        self.registry = registry
        self.activities = activities
        screenFrame = screen.frame
        geometry = NotchGeometry(screen: screen, config: config)
        model = NotchViewModel(scheduler: scheduler, availableTabs: { [weak registry] in registry?.tabs.map(\.id) ?? [] }, delays: delays)
        panel = NotchPanel(frame: geometry.panelFrame(in: screen.frame))
        installContent()
        observeActivities()
    }

    func update(screen: ScreenDescriptor, config: NotchLayoutConfig) {
        screenFrame = screen.frame
        geometry = NotchGeometry(screen: screen, config: config)
        panel.setFrame(geometry.panelFrame(in: screen.frame), display: true)
        installContent()
    }

    func setVisible(_ visible: Bool) {
        guard visible != isVisible else { return }
        isVisible = visible
        if visible {
            panel.alphaValue = 1
            panel.orderFrontRegardless()
        } else {
            model.close()
            panel.ignoresMouseEvents = true
            panel.orderOut(nil)
        }
    }

    /// Called for every pointer move; flips click-through and drives hover state.
    func pointerMoved(to point: CGPoint) {
        guard isVisible else { return }
        let inside = currentHitRect().contains(point)
        panel.ignoresMouseEvents = !inside
        if inside, !model.isPointerInside {
            model.pointerEntered()
        } else if !inside, model.isPointerInside {
            model.pointerExited()
        }
    }

    func close() {
        panel.orderOut(nil)
        panel.close()
    }

    private func currentHitRect() -> CGRect {
        let state = model.displayState
        var height = NotchTab.defaultHeight
        if case .open(let id) = state, let tab = registry.tabs.first(where: { $0.id == id }) {
            height = tab.contentHeight
        }
        return geometry.hitRect(for: state, contentHeight: height, in: screenFrame)
    }

    private func installContent() {
        let root = NotchRootView(model: model, activities: activities, registry: registry, geometry: geometry)
        let hosting = FirstMouseHostingView(rootView: root)
        hosting.frame = CGRect(origin: .zero, size: geometry.panelSize)
        panel.contentView = hosting
    }

    private func observeActivities() {
        Task { [weak self, activities] in
            for await hasActivity in Observations({ activities.current != nil }) {
                self?.model.hasActivity = hasActivity
            }
        }
    }
}
```

`Packages/NotchUI/Sources/NotchUI/Screens/ScreenManager.swift`:

```swift
import AppKit
import MyNotchCore

/// Creates one notch per screen, keeps them in sync with displays, settings and fullscreen state.
public final class ScreenManager {
    private let registry: ModuleRegistry
    private let activities: ActivityCenter
    private let settings: SettingsStore
    private let scheduler: any Scheduler
    private var controllers: [String: NotchWindowController] = [:]
    private var fullscreenDisplays: Set<CGDirectDisplayID> = []
    private var cursorDisplay: CGDirectDisplayID?
    private var observers: [NSObjectProtocol] = []
    private lazy var hoverTracker = NotchHoverTracker { [weak self] point in self?.pointerMoved(to: point) }
    private lazy var fullscreenDetector = FullscreenDetector { [weak self] displays in
        self?.fullscreenDisplays = displays
        self?.applyVisibility()
    }

    /// User toggle from the menu bar ("Show/Hide Notch").
    public var isHiddenByUser = false {
        didSet { applyVisibility() }
    }

    public init(registry: ModuleRegistry, activities: ActivityCenter, settings: SettingsStore, scheduler: any Scheduler) {
        self.registry = registry
        self.activities = activities
        self.settings = settings
        self.scheduler = scheduler
    }

    public func start() {
        let app = NotificationCenter.default
        observers.append(app.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.syncScreens() }
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.syncScreens() }
        })
        syncScreens()
        hoverTracker.start()
        fullscreenDetector.start()
        observeSettings()
    }

    /// Controller for the screen under the pointer, falling back to the main screen.
    func activeController() -> NotchWindowController? {
        let point = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
        return screen?.displayUUID.flatMap { controllers[$0] }
    }

    func allControllers() -> [NotchWindowController] { Array(controllers.values) }

    private func syncScreens() {
        let config = NotchLayoutConfig(settings: settings)
        var seen: Set<String> = []
        for screen in NSScreen.screens {
            guard let uuid = screen.displayUUID, let displayID = screen.displayID else { continue }
            seen.insert(uuid)
            let descriptor = ScreenDescriptor(screen)
            if let controller = controllers[uuid] {
                controller.update(screen: descriptor, config: config)
            } else {
                controllers[uuid] = NotchWindowController(
                    displayID: displayID, screen: descriptor, config: config, scheduler: scheduler,
                    registry: registry, activities: activities, delays: { [settings] in Self.delays(settings) }
                )
            }
        }
        for (uuid, controller) in controllers where !seen.contains(uuid) {
            controller.close()
            controllers[uuid] = nil
        }
        applyVisibility()
    }

    private func applyVisibility() {
        let mode = settings.value(InterfaceSettings.displayMode)
        let hideInFullscreen = settings.value(InterfaceSettings.hideInFullscreen)
        let mainID = NSScreen.screens.first?.displayID
        for controller in controllers.values {
            let id = controller.displayID
            let allowedByMode = switch mode {
            case .all: true
            case .main: id == mainID
            case .cursor: id == (cursorDisplay ?? mainID)
            }
            let hiddenByFullscreen = hideInFullscreen && fullscreenDisplays.contains(id)
            controller.setVisible(allowedByMode && !isHiddenByUser && !hiddenByFullscreen)
        }
    }

    private func pointerMoved(to point: CGPoint) {
        let display = NSScreen.screens.first { $0.frame.contains(point) }?.displayID
        if display != cursorDisplay {
            cursorDisplay = display
            if settings.value(InterfaceSettings.displayMode) == .cursor { applyVisibility() }
        }
        controllers.values.forEach { $0.pointerMoved(to: point) }
    }

    private func observeSettings() {
        Task { [weak self, settings] in
            for await _ in Observations({ NotchLayoutConfig(settings: settings) }) {
                self?.syncScreens()
            }
        }
        Task { [weak self, settings] in
            for await _ in Observations({ (settings.value(InterfaceSettings.displayMode), settings.value(InterfaceSettings.hideInFullscreen)) }) {
                self?.applyVisibility()
            }
        }
    }

    private static func delays(_ settings: SettingsStore) -> (open: Duration, close: Duration) {
        (.milliseconds(settings.value(InterfaceSettings.openDelayMs)), .milliseconds(settings.value(InterfaceSettings.closeDelayMs)))
    }
}
```

`Packages/NotchUI/Sources/NotchUI/Screens/NotchCoordinator.swift`:

```swift
import MyNotchCore
import SwiftUI

/// `NotchPresenter` used by modules and the app; routes requests to the active screen's notch.
public final class NotchCoordinator: NotchPresenter {
    public weak var screens: ScreenManager?

    public init() {}

    public func open(tab: ModuleID) { screens?.activeController()?.model.open(tab: tab) }

    public func showToast(_ content: AnyView, duration: Duration) {
        screens?.activeController()?.model.showToast(content, duration: duration)
    }

    public func close() { screens?.allControllers().forEach { $0.model.close() } }

    /// Bound to the global "Toggle notch" shortcut.
    public func toggle() { screens?.activeController()?.model.toggle() }
}
```

- [ ] **Step 2: Build / kiểm chứng**

```bash
swift build --package-path Packages/NotchUI && swift test --package-path Packages/NotchUI
```

Expected: `Build complete!` rồi `✔ Test run with 18 tests in 3 suites passed`.

- [ ] **Step 3: Commit**

```bash
git add Packages/NotchUI/Sources/NotchUI/Window/NotchPanel.swift Packages/NotchUI/Sources/NotchUI/Window/NotchHoverTracker.swift Packages/NotchUI/Sources/NotchUI/Window/NotchWindowController.swift Packages/NotchUI/Sources/NotchUI/Screens/ScreenManager.swift Packages/NotchUI/Sources/NotchUI/Screens/NotchCoordinator.swift
git commit -m "feat(notch-ui): add per-screen notch panels and coordinator"
```


## Task 12: Package Battery: đọc thông tin pin

`PowerSourceParser` đọc dictionary IOKit bằng key dạng chuỗi (trong `IOPSKeys.h`) để test không cần IOKit. IOKit trả `-1` cho thời gian khi còn đang ước tính.

**Files:**
- Create: `Packages/Modules/Battery/Package.swift`
- Create: `Packages/Modules/Battery/Sources/BatteryModule/PowerSourceSnapshot.swift`
- Create: `Packages/Modules/Battery/Sources/BatteryModule/PowerSourceParser.swift`
- Test: `Packages/Modules/Battery/Tests/BatteryModuleTests/PowerSourceParserTests.swift`

- [ ] **Step 1: Tạo khung package**

`Packages/Modules/Battery/Package.swift`:

```swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "BatteryModule",
    platforms: [.macOS(.v26)],
    products: [.library(name: "BatteryModule", targets: ["BatteryModule"])],
    dependencies: [
        .package(path: "../../MyNotchCore"),
        .package(path: "../../NotchUI"),
    ],
    targets: [
        .target(
            name: "BatteryModule",
            dependencies: ["MyNotchCore", "NotchUI"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(
            name: "BatteryModuleTests",
            dependencies: ["BatteryModule", .product(name: "MyNotchTestSupport", package: "MyNotchCore")],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
    ]
)
```

- [ ] **Step 2: Viết test (chưa có code nên phải fail)**

`Packages/Modules/Battery/Tests/BatteryModuleTests/PowerSourceParserTests.swift`:

```swift
import Testing
@testable import BatteryModule

@Suite struct PowerSourceParserTests {
    @Test func parsesInternalBattery() {
        let snapshot = PowerSourceParser.parse([[
            "Type": "InternalBattery",
            "Current Capacity": 41, "Max Capacity": 50,
            "Is Charging": true, "Power Source State": "AC Power",
            "Time to Empty": -1, "Time to Full Charge": 35,
        ]])
        #expect(snapshot == PowerSourceSnapshot(percent: 82, isCharging: true, isOnAC: true, minutesToEmpty: nil, minutesToFull: 35))
    }

    @Test func returnsNilWithoutInternalBattery() {
        #expect(PowerSourceParser.parse([]) == nil)
        #expect(PowerSourceParser.parse([["Type": "UPS", "Current Capacity": 10, "Max Capacity": 100]]) == nil)
    }
}
```

- [ ] **Step 3: Chạy test, xác nhận fail**

```bash
swift test --package-path Packages/Modules/Battery --filter 'PowerSourceParserTests'
```

Expected: FAIL, lỗi biên dịch `cannot find 'PowerSourceParser' in scope`.

- [ ] **Step 4: Viết code**

`Packages/Modules/Battery/Sources/BatteryModule/PowerSourceSnapshot.swift`:

```swift
/// One reading of the internal battery.
nonisolated public struct PowerSourceSnapshot: Equatable, Sendable {
    public var percent: Int
    public var isCharging: Bool
    /// Plugged into a power adapter (may be "not charging" when held at a limit).
    public var isOnAC: Bool
    /// Minutes, nil while macOS is still estimating.
    public var minutesToEmpty: Int?
    public var minutesToFull: Int?

    public init(percent: Int, isCharging: Bool, isOnAC: Bool, minutesToEmpty: Int? = nil, minutesToFull: Int? = nil) {
        self.percent = percent
        self.isCharging = isCharging
        self.isOnAC = isOnAC
        self.minutesToEmpty = minutesToEmpty
        self.minutesToFull = minutesToFull
    }
}
```

`Packages/Modules/Battery/Sources/BatteryModule/PowerSourceParser.swift`:

```swift
/// Converts IOKit power source descriptions (string keys from IOPSKeys.h) into snapshots.
nonisolated enum PowerSourceParser {
    /// Returns the internal battery, or nil when the Mac has none.
    static func parse(_ descriptions: [[String: Any]]) -> PowerSourceSnapshot? {
        guard let battery = descriptions.first(where: { ($0["Type"] as? String) == "InternalBattery" }),
              let current = battery["Current Capacity"] as? Int,
              let max = battery["Max Capacity"] as? Int, max > 0 else { return nil }
        return PowerSourceSnapshot(
            percent: Int((Double(current) / Double(max) * 100).rounded()),
            isCharging: battery["Is Charging"] as? Bool ?? false,
            isOnAC: (battery["Power Source State"] as? String) == "AC Power",
            minutesToEmpty: positive(battery["Time to Empty"]),
            minutesToFull: positive(battery["Time to Full Charge"])
        )
    }

    /// IOKit reports -1 while estimating.
    private static func positive(_ value: Any?) -> Int? {
        guard let minutes = value as? Int, minutes >= 0 else { return nil }
        return minutes
    }
}
```

- [ ] **Step 5: Chạy test, xác nhận pass**

```bash
swift test --package-path Packages/Modules/Battery --filter 'PowerSourceParserTests'
```

Expected: `✔ Test run with 2 tests in 1 suite passed`.

- [ ] **Step 6: Commit**

```bash
git add Packages/Modules/Battery/Package.swift Packages/Modules/Battery/Tests/BatteryModuleTests/PowerSourceParserTests.swift Packages/Modules/Battery/Sources/BatteryModule/PowerSourceSnapshot.swift Packages/Modules/Battery/Sources/BatteryModule/PowerSourceParser.swift
git commit -m "feat(battery): parse IOKit power source descriptions"
```


## Task 13: Chính sách live activity của pin

Quyết định hiện activity "đang sạc" (chỉ khi vừa chuyển từ pin sang adapter) và "pin yếu" (có độ trễ 5% khi tắt để không nhấp nháy quanh ngưỡng).

**Files:**
- Create: `Packages/Modules/Battery/Sources/BatteryModule/BatteryActivityPolicy.swift`
- Test: `Packages/Modules/Battery/Tests/BatteryModuleTests/BatteryActivityPolicyTests.swift`

- [ ] **Step 1: Viết test (chưa có code nên phải fail)**

`Packages/Modules/Battery/Tests/BatteryModuleTests/BatteryActivityPolicyTests.swift`:

```swift
import Testing
@testable import BatteryModule

@Suite struct BatteryActivityPolicyTests {
    let policy = BatteryActivityPolicy(lowThreshold: 20, notifyOnCharge: true)

    func onBattery(_ percent: Int) -> PowerSourceSnapshot { PowerSourceSnapshot(percent: percent, isCharging: false, isOnAC: false) }
    func onAC(_ percent: Int) -> PowerSourceSnapshot { PowerSourceSnapshot(percent: percent, isCharging: true, isOnAC: true) }

    @Test func pluggingInShowsChargingOnlyOnTransition() {
        #expect(policy.decide(previous: onBattery(50), current: onAC(50), lowActive: false).showCharging)
        #expect(!policy.decide(previous: onAC(50), current: onAC(51), lowActive: false).showCharging)
        #expect(!policy.decide(previous: nil, current: onAC(50), lowActive: false).showCharging)
    }

    @Test func chargingNotificationCanBeDisabled() {
        let quiet = BatteryActivityPolicy(lowThreshold: 20, notifyOnCharge: false)
        #expect(!quiet.decide(previous: onBattery(50), current: onAC(50), lowActive: false).showCharging)
    }

    @Test func lowBatteryUsesThresholdAndHysteresis() {
        #expect(policy.decide(previous: nil, current: onBattery(20), lowActive: false).lowActive)
        #expect(!policy.decide(previous: nil, current: onBattery(21), lowActive: false).lowActive)
        #expect(policy.decide(previous: nil, current: onBattery(25), lowActive: true).lowActive)
        #expect(!policy.decide(previous: nil, current: onBattery(26), lowActive: true).lowActive)
        #expect(!policy.decide(previous: nil, current: onAC(10), lowActive: true).lowActive)
    }
}
```

- [ ] **Step 2: Chạy test, xác nhận fail**

```bash
swift test --package-path Packages/Modules/Battery --filter 'BatteryActivityPolicyTests'
```

Expected: FAIL, lỗi biên dịch `cannot find 'BatteryActivityPolicy' in scope`.

- [ ] **Step 3: Viết code**

`Packages/Modules/Battery/Sources/BatteryModule/BatteryActivityPolicy.swift`:

```swift
/// Decides which battery live activities should be visible.
nonisolated struct BatteryActivityPolicy: Equatable, Sendable {
    /// Low-battery stays visible until the level rises this far above the threshold.
    static let hysteresis = 5

    var lowThreshold: Int
    var notifyOnCharge: Bool

    struct Decision: Equatable, Sendable {
        var showCharging: Bool
        var lowActive: Bool
    }

    func decide(previous: PowerSourceSnapshot?, current: PowerSourceSnapshot, lowActive: Bool) -> Decision {
        let pluggedIn = previous.map { !$0.isOnAC && current.isOnAC } ?? false
        let low: Bool
        if current.isOnAC {
            low = false
        } else if current.percent <= lowThreshold {
            low = true
        } else if lowActive, current.percent <= lowThreshold + Self.hysteresis {
            low = true
        } else {
            low = false
        }
        return Decision(showCharging: notifyOnCharge && pluggedIn, lowActive: low)
    }
}
```

- [ ] **Step 4: Chạy test, xác nhận pass**

```bash
swift test --package-path Packages/Modules/Battery --filter 'BatteryActivityPolicyTests'
```

Expected: `✔ Test run with 3 tests in 1 suite passed`.

- [ ] **Step 5: Commit**

```bash
git add Packages/Modules/Battery/Tests/BatteryModuleTests/BatteryActivityPolicyTests.swift Packages/Modules/Battery/Sources/BatteryModule/BatteryActivityPolicy.swift
git commit -m "feat(battery): add charging and low-battery policy"
```


## Task 14: BatteryModule

Module mẫu hoàn chỉnh: đọc pin qua IOKit, đăng ký run loop source để nhận thay đổi, phát activity, cung cấp tab và trang cài đặt. Test chạy module thật qua `RegistryHarness` với nguồn pin giả.

**Files:**
- Create: `Packages/Modules/Battery/Sources/BatteryModule/PowerSourceReading.swift`
- Create: `Packages/Modules/Battery/Sources/BatteryModule/BatteryViews.swift`
- Create: `Packages/Modules/Battery/Sources/BatteryModule/BatteryModule.swift`
- Test: `Packages/Modules/Battery/Tests/BatteryModuleTests/BatteryModuleTests.swift`

- [ ] **Step 1: Viết test (chưa có code nên phải fail)**

`Packages/Modules/Battery/Tests/BatteryModuleTests/BatteryModuleTests.swift`:

```swift
import MyNotchCore
import MyNotchTestSupport
import Testing
@testable import BatteryModule

final class FakePowerSource: PowerSourceReading {
    var snapshot: PowerSourceSnapshot?
    private var onChange: (@MainActor () -> Void)?

    init(_ snapshot: PowerSourceSnapshot?) { self.snapshot = snapshot }

    func read() -> PowerSourceSnapshot? { snapshot }
    func startObserving(_ onChange: @escaping @MainActor () -> Void) { self.onChange = onChange }
    func stopObserving() { onChange = nil }

    func emit(_ snapshot: PowerSourceSnapshot) {
        self.snapshot = snapshot
        onChange?()
    }
}

@Suite struct BatteryModuleTests {
    @Test func desktopMacReportsUnavailable() async {
        let harness = RegistryHarness([BatteryModule(reader: FakePowerSource(nil))])
        await harness.registry.bootstrap()
        #expect(harness.registry.state(of: "battery") == .unavailable(reason: "Máy không có pin"))
    }

    @Test func pluggingInPublishesChargingActivityThatExpires() async {
        let source = FakePowerSource(PowerSourceSnapshot(percent: 60, isCharging: false, isOnAC: false))
        let harness = RegistryHarness([BatteryModule(reader: source)])
        await harness.registry.bootstrap()
        #expect(harness.registry.state(of: "battery") == .running)
        #expect(harness.activities.current == nil)

        source.emit(PowerSourceSnapshot(percent: 60, isCharging: true, isOnAC: true))
        #expect(harness.activities.current?.id == "battery/charging")
        harness.scheduler.advance(by: .seconds(4))
        #expect(harness.activities.current == nil)
    }

    @Test func lowBatteryActivityClearsWhenPluggedIn() async {
        let source = FakePowerSource(PowerSourceSnapshot(percent: 15, isCharging: false, isOnAC: false))
        let harness = RegistryHarness([BatteryModule(reader: source)])
        await harness.registry.bootstrap()
        #expect(harness.activities.current?.id == "battery/low")
        source.emit(PowerSourceSnapshot(percent: 15, isCharging: true, isOnAC: true))
        #expect(harness.activities.entries.map(\.id) == ["battery/charging"])
    }

    @Test func disablingRemovesActivitiesAndStopsObserving() async {
        let source = FakePowerSource(PowerSourceSnapshot(percent: 15, isCharging: false, isOnAC: false))
        let harness = RegistryHarness([BatteryModule(reader: source)])
        await harness.registry.bootstrap()
        await harness.registry.setEnabled(false, for: "battery")
        #expect(harness.activities.current == nil)
        source.emit(PowerSourceSnapshot(percent: 10, isCharging: false, isOnAC: false))
        #expect(harness.activities.current == nil)
    }
}
```

- [ ] **Step 2: Chạy test, xác nhận fail**

```bash
swift test --package-path Packages/Modules/Battery
```

Expected: FAIL, lỗi biên dịch `cannot find 'BatteryModule' in scope`.

- [ ] **Step 3: Viết code**

`Packages/Modules/Battery/Sources/BatteryModule/PowerSourceReading.swift`:

```swift
import IOKit.ps

/// Source of battery readings; faked in tests.
public protocol PowerSourceReading: AnyObject {
    func read() -> PowerSourceSnapshot?
    /// Calls `onChange` whenever macOS reports a power source change, until `stopObserving()`.
    func startObserving(_ onChange: @escaping @MainActor () -> Void)
    func stopObserving()
}

/// Reads the internal battery through IOKit power source APIs.
public final class IOKitPowerSource: PowerSourceReading {
    private var runLoopSource: CFRunLoopSource?
    private var onChange: (@MainActor () -> Void)?

    public init() {}

    public func read() -> PowerSourceSnapshot? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        let descriptions = list.compactMap { source in
            IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any]
        }
        return PowerSourceParser.parse(descriptions)
    }

    public func startObserving(_ onChange: @escaping @MainActor () -> Void) {
        stopObserving()
        self.onChange = onChange
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let reader = Unmanaged<IOKitPowerSource>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { reader.onChange?() }
        }, context)?.takeRetainedValue() else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        runLoopSource = source
    }

    public func stopObserving() {
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .defaultMode) }
        runLoopSource = nil
        onChange = nil
    }
}
```

`Packages/Modules/Battery/Sources/BatteryModule/BatteryViews.swift`:

```swift
import NotchUI
import SwiftUI

struct BatteryTabView: View {
    let state: BatteryState

    var body: some View {
        if let snapshot = state.snapshot {
            HStack(spacing: 18) {
                Image(systemName: Self.symbol(for: snapshot))
                    .font(.system(size: 44, weight: .regular))
                    .foregroundStyle(snapshot.percent <= 20 && !snapshot.isOnAC ? .red : NotchTokens.primaryText)
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(snapshot.percent)%")
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .foregroundStyle(NotchTokens.primaryText)
                    Text(Self.status(for: snapshot))
                        .font(.callout)
                        .foregroundStyle(NotchTokens.secondaryText)
                    Text(snapshot.isOnAC ? "Nguồn: bộ sạc" : "Nguồn: pin")
                        .font(.caption)
                        .foregroundStyle(NotchTokens.secondaryText)
                }
                Spacer()
            }
            .padding(.top, 8)
        }
    }

    static func symbol(for snapshot: PowerSourceSnapshot) -> String {
        if snapshot.isCharging { return "battery.100percent.bolt" }
        return switch snapshot.percent {
        case ..<13: "battery.0percent"
        case ..<38: "battery.25percent"
        case ..<63: "battery.50percent"
        case ..<88: "battery.75percent"
        default: "battery.100percent"
        }
    }

    static func status(for snapshot: PowerSourceSnapshot) -> String {
        if snapshot.isCharging {
            return snapshot.minutesToFull.map { "Đang sạc · đầy sau \(format($0))" } ?? "Đang sạc"
        }
        if snapshot.isOnAC { return "Đã cắm sạc · không sạc" }
        return snapshot.minutesToEmpty.map { "Còn khoảng \(format($0))" } ?? "Đang tính thời gian còn lại"
    }

    static func format(_ minutes: Int) -> String {
        minutes >= 60 ? "\(minutes / 60) giờ \(minutes % 60) phút" : "\(minutes) phút"
    }
}

struct BatteryActivityIcon: View {
    let systemImage: String
    let tint: Color

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(tint)
    }
}

struct BatteryActivityPercent: View {
    let percent: Int
    let tint: Color

    var body: some View {
        Text("\(percent)%")
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(tint)
    }
}

struct BatterySettingsView: View {
    @Binding var lowThreshold: Int
    @Binding var notifyOnCharge: Bool

    var body: some View {
        Form {
            Stepper("Ngưỡng pin yếu: \(lowThreshold)%", value: $lowThreshold, in: 5...50, step: 5)
            Toggle("Thông báo khi cắm sạc", isOn: $notifyOnCharge)
        }
        .formStyle(.grouped)
    }
}
```

`Packages/Modules/Battery/Sources/BatteryModule/BatteryModule.swift`:

```swift
import MyNotchCore
import NotchUI
import Observation
import SwiftUI

@Observable
final class BatteryState {
    var snapshot: PowerSourceSnapshot?
}

/// Reference module: battery tab plus "charging" and "low battery" live activities.
public final class BatteryModule: FeatureModule {
    public let descriptor = ModuleDescriptor(
        id: "battery",
        displayName: "Battery",
        systemImage: "battery.100percent.bolt",
        defaultEnabled: true,
        order: 900
    )

    let state = BatteryState()
    private let reader: any PowerSourceReading
    private var context: ModuleContext?
    private var lowActive = false
    private var settingKeys: (lowThreshold: SettingKey<Int>, notifyOnCharge: SettingKey<Bool>)?

    public init(reader: any PowerSourceReading = IOKitPowerSource()) {
        self.reader = reader
    }

    public func start(_ context: ModuleContext) async throws(ModuleError) {
        guard let snapshot = reader.read() else {
            throw .unavailable(reason: "Máy không có pin")
        }
        self.context = context
        settingKeys = (
            context.settings.key("lowThreshold", default: 20, clampedTo: 5...50),
            context.settings.key("notifyOnCharge", default: true)
        )
        lowActive = false
        apply(snapshot, previous: nil)
        reader.startObserving { [weak self] in self?.refresh() }
    }

    public func stop() async {
        reader.stopObserving()
        context = nil
        state.snapshot = nil
        lowActive = false
    }

    public func makeTab() -> NotchTab? {
        NotchTab(id: descriptor.id, title: "Battery", systemImage: "battery.100percent", preferredHeight: 120, content: AnyView(BatteryTabView(state: state)))
    }

    public func makeSettingsView() -> AnyView? {
        guard let context, let keys = settingKeys else {
            return AnyView(Text("Bật module để chỉnh cài đặt").foregroundStyle(.secondary))
        }
        return AnyView(BatterySettingsView(
            lowThreshold: context.settings.binding(keys.lowThreshold),
            notifyOnCharge: context.settings.binding(keys.notifyOnCharge)
        ))
    }

    func refresh() {
        guard let snapshot = reader.read() else { return }
        apply(snapshot, previous: state.snapshot)
    }

    private func apply(_ snapshot: PowerSourceSnapshot, previous: PowerSourceSnapshot?) {
        state.snapshot = snapshot
        guard let context, let keys = settingKeys else { return }
        let policy = BatteryActivityPolicy(
            lowThreshold: context.settings.value(keys.lowThreshold),
            notifyOnCharge: context.settings.value(keys.notifyOnCharge)
        )
        let decision = policy.decide(previous: previous, current: snapshot, lowActive: lowActive)
        if decision.showCharging {
            context.activities.set(LiveActivity(
                id: "charging", priority: .normal, expiresAfter: .seconds(4),
                leading: AnyView(BatteryActivityIcon(systemImage: "bolt.fill", tint: .green)),
                trailing: AnyView(BatteryActivityPercent(percent: snapshot.percent, tint: .green))
            ))
        }
        if decision.lowActive {
            context.activities.set(LiveActivity(
                id: "low", priority: .high,
                leading: AnyView(BatteryActivityIcon(systemImage: "battery.25percent", tint: .red)),
                trailing: AnyView(BatteryActivityPercent(percent: snapshot.percent, tint: .red))
            ))
        } else if lowActive {
            context.activities.clear(id: "low")
        }
        lowActive = decision.lowActive
    }
}
```

- [ ] **Step 4: Chạy test, xác nhận pass**

```bash
swift test --package-path Packages/Modules/Battery
```

Expected: `✔ Test run with 9 tests in 3 suites passed`.

- [ ] **Step 5: Commit**

```bash
git add Packages/Modules/Battery/Tests/BatteryModuleTests/BatteryModuleTests.swift Packages/Modules/Battery/Sources/BatteryModule/PowerSourceReading.swift Packages/Modules/Battery/Sources/BatteryModule/BatteryViews.swift Packages/Modules/Battery/Sources/BatteryModule/BatteryModule.swift
git commit -m "feat(battery): add Battery reference module"
```


## Task 15: Target app, menu bar và Settings

`project.yml` sinh `MyNotch.xcodeproj` (không commit). `main.swift` chạy app ở chế độ `.accessory` (không có Dock). `AppDelegate` là composition root; `ModuleList.swift` là nơi duy nhất ghép module.

**Files:**
- Create: `project.yml`
- Create: `App/main.swift`
- Create: `App/AppSettings.swift`
- Create: `App/ModuleList.swift`
- Create: `App/LaunchAtLogin.swift`
- Create: `App/StatusItemController.swift`
- Create: `App/AppDelegate.swift`
- Create: `App/Settings/SettingsWindowController.swift`
- Create: `App/Settings/SettingsRootView.swift`
- Create: `App/Settings/GeneralSettingsPage.swift`
- Create: `App/Settings/InterfaceSettingsPage.swift`
- Create: `App/Settings/ModuleSettingsPage.swift`
- Create: `App/Settings/AboutPage.swift`

- [ ] **Step 1: Viết code**

`project.yml`:

```yaml
name: MyNotch
options:
  bundleIdPrefix: io.lucasvu
  deploymentTarget:
    macOS: "26.0"
  createIntermediateGroups: true
settings:
  base:
    SWIFT_VERSION: "6.0"
    SWIFT_DEFAULT_ACTOR_ISOLATION: MainActor
    SWIFT_STRICT_CONCURRENCY: complete
    MARKETING_VERSION: "0.1.0"
    CURRENT_PROJECT_VERSION: "1"
packages:
  MyNotchCore:
    path: Packages/MyNotchCore
  NotchUI:
    path: Packages/NotchUI
  BatteryModule:
    path: Packages/Modules/Battery
  KeyboardShortcuts:
    url: https://github.com/sindresorhus/KeyboardShortcuts
    exactVersion: 3.1.0
targets:
  MyNotch:
    type: application
    platform: macOS
    sources:
      - path: App
    dependencies:
      - package: MyNotchCore
      - package: NotchUI
      - package: BatteryModule
      - package: KeyboardShortcuts
    info:
      path: App/Info.plist
      properties:
        CFBundleDisplayName: MyNotch
        CFBundleShortVersionString: $(MARKETING_VERSION)
        CFBundleVersion: $(CURRENT_PROJECT_VERSION)
        LSUIElement: true
        LSMinimumSystemVersion: "26.0"
        NSHumanReadableCopyright: "MyNotch — personal build"
    entitlements:
      path: App/MyNotch.entitlements
      properties:
        com.apple.security.app-sandbox: false
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: io.lucasvu.mynotch
        PRODUCT_NAME: MyNotch
        ENABLE_HARDENED_RUNTIME: YES
        CODE_SIGN_STYLE: Automatic
        # Ad-hoc ("Sign to Run Locally"). Set DEVELOPMENT_TEAM once modules need stable TCC permissions.
        CODE_SIGN_IDENTITY: "-"
        COMBINE_HIDPI_IMAGES: YES
```

`App/main.swift`:

```swift
import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
```

`App/AppSettings.swift`:

```swift
import MyNotchCore

/// App-wide settings (`app.*`).
enum AppSettings {
    static let showMenuBarIcon = SettingKey("app.showMenuBarIcon", default: true)
}
```

`App/ModuleList.swift`:

```swift
import BatteryModule
import MyNotchCore

/// The ONLY place modules are wired into the app. Add one line per new module.
enum ModuleList {
    static func make() -> [any FeatureModule] {
        [
            BatteryModule(),
        ]
    }
}
```

`App/LaunchAtLogin.swift`:

```swift
import ServiceManagement

/// Thin wrapper over `SMAppService.mainApp`.
enum LaunchAtLogin {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    /// Returns an error message when macOS refuses the change.
    static func set(_ enabled: Bool) -> String? {
        do {
            enabled ? try SMAppService.mainApp.register() : try SMAppService.mainApp.unregister()
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}
```

`App/StatusItemController.swift`:

```swift
import AppKit
import MyNotchCore
import NotchUI

/// Menu bar icon and menu.
final class StatusItemController: NSObject {
    private let settings: SettingsStore
    private let registry: ModuleRegistry
    private let screens: ScreenManager
    private let openSettings: () -> Void
    private var item: NSStatusItem?

    init(settings: SettingsStore, registry: ModuleRegistry, screens: ScreenManager, openSettings: @escaping () -> Void) {
        self.settings = settings
        self.registry = registry
        self.screens = screens
        self.openSettings = openSettings
        super.init()
        observeVisibility()
    }

    private func observeVisibility() {
        Task { [weak self, settings] in
            for await visible in Observations({ settings.value(AppSettings.showMenuBarIcon) }) {
                self?.setVisible(visible)
            }
        }
    }

    private func setVisible(_ visible: Bool) {
        if visible, item == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            item.button?.image = NSImage(systemSymbolName: "rectangle.topthird.inset.filled", accessibilityDescription: "MyNotch")
            item.menu = makeMenu()
            self.item = item
        } else if !visible, let item {
            NSStatusBar.system.removeStatusItem(item)
            self.item = nil
        }
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(withTitle: "Open Settings…", action: #selector(openSettingsAction), keyEquivalent: ",").target = self
        menu.addItem(withTitle: "Hide Notch", action: #selector(toggleNotchVisibility), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Pause All Modules", action: #selector(togglePause), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit MyNotch", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return menu
    }

    @objc private func openSettingsAction() { openSettings() }

    @objc private func toggleNotchVisibility() { screens.isHiddenByUser.toggle() }

    @objc private func togglePause() {
        Task { [registry] in registry.isPaused ? await registry.resumeAll() : await registry.pauseAll() }
    }
}

extension StatusItemController: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.item(at: 1)?.title = screens.isHiddenByUser ? "Show Notch" : "Hide Notch"
        menu.item(at: 2)?.state = registry.isPaused ? .on : .off
    }
}
```

`App/AppDelegate.swift`:

```swift
import AppKit
import KeyboardShortcuts
import MyNotchCore
import NotchUI

/// Composition root: builds the shared services and wires them together.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = SettingsStore()
    private let scheduler = TaskScheduler()
    private let permissions = SystemPermissionCenter()
    private let hotkeys = HotkeyRegistry()
    private let coordinator = NotchCoordinator()
    private lazy var activities = ActivityCenter(scheduler: scheduler)
    private lazy var registry = ModuleRegistry(
        modules: ModuleList.make(), settings: settings, activities: activities,
        permissions: permissions, hotkeys: hotkeys, presenter: coordinator
    )
    private lazy var screens = ScreenManager(registry: registry, activities: activities, settings: settings, scheduler: scheduler)
    private lazy var settingsWindow = SettingsWindowController(
        settings: settings, registry: registry, permissions: permissions, hotkeys: hotkeys
    )
    private var statusItem: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        coordinator.screens = screens
        hotkeys.register(
            "toggleNotch", title: "Mở/đóng notch", owner: nil,
            initial: KeyboardShortcuts.Shortcut(.n, modifiers: [.control, .option])
        ) { [weak self] in self?.coordinator.toggle() }
        statusItem = StatusItemController(
            settings: settings, registry: registry, screens: screens,
            openSettings: { [weak self] in self?.settingsWindow.show() }
        )
        screens.start()
        Task { await registry.bootstrap() }
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshPermissions() }
        }
    }

    /// Re-launching the app (e.g. from Finder) opens Settings, so it stays reachable without a menu bar icon.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        settingsWindow.show()
        return true
    }

    private func refreshPermissions() {
        Task { await registry.refreshPermissions() }
    }
}
```

`App/Settings/SettingsWindowController.swift`:

```swift
import AppKit
import MyNotchCore
import SwiftUI

/// Hosts the SwiftUI settings UI in a regular window and brings it to the front.
final class SettingsWindowController {
    private let settings: SettingsStore
    private let registry: ModuleRegistry
    private let permissions: any PermissionCenter
    private let hotkeys: HotkeyRegistry
    private var window: NSWindow?

    init(settings: SettingsStore, registry: ModuleRegistry, permissions: any PermissionCenter, hotkeys: HotkeyRegistry) {
        self.settings = settings
        self.registry = registry
        self.permissions = permissions
        self.hotkeys = hotkeys
    }

    func show() {
        if window == nil {
            let root = SettingsRootView(settings: settings, registry: registry, permissions: permissions, hotkeys: hotkeys)
            let window = NSWindow(contentViewController: NSHostingController(rootView: root))
            window.title = "MyNotch Settings"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            window.setContentSize(NSSize(width: 760, height: 520))
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
```

`App/Settings/SettingsRootView.swift`:

```swift
import MyNotchCore
import SwiftUI

enum SettingsPage: Hashable {
    case general, interface, module(ModuleID), about
}

struct SettingsRootView: View {
    let settings: SettingsStore
    let registry: ModuleRegistry
    let permissions: any PermissionCenter
    let hotkeys: HotkeyRegistry
    @State private var selection: SettingsPage? = .general

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Label("General", systemImage: "gearshape").tag(SettingsPage.general)
                Label("Interface", systemImage: "rectangle.topthird.inset.filled").tag(SettingsPage.interface)
                Section("Modules") {
                    ForEach(registry.modules, id: \.descriptor.id) { module in
                        Label(module.descriptor.displayName, systemImage: module.descriptor.systemImage)
                            .tag(SettingsPage.module(module.descriptor.id))
                    }
                }
                Section {
                    Label("About", systemImage: "info.circle").tag(SettingsPage.about)
                }
            }
            .navigationSplitViewColumnWidth(200)
        } detail: {
            switch selection ?? .general {
            case .general: GeneralSettingsPage(settings: settings, hotkeys: hotkeys)
            case .interface: InterfaceSettingsPage(settings: settings)
            case .module(let id): ModuleSettingsPage(id: id, registry: registry, permissions: permissions)
            case .about: AboutPage()
            }
        }
    }
}
```

`App/Settings/GeneralSettingsPage.swift`:

```swift
import KeyboardShortcuts
import MyNotchCore
import SwiftUI

struct GeneralSettingsPage: View {
    let settings: SettingsStore
    let hotkeys: HotkeyRegistry
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var launchError: String?
    @State private var shortcutRevision = 0

    var body: some View {
        Form {
            Section("Khởi động") {
                Toggle("Khởi động cùng máy", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        launchError = LaunchAtLogin.set(enabled)
                        launchAtLogin = LaunchAtLogin.isEnabled
                    }
                if let launchError {
                    Text(launchError).foregroundStyle(.red).font(.caption)
                }
                Toggle("Hiện icon trên menu bar", isOn: settings.binding(AppSettings.showMenuBarIcon))
                Text("Khi ẩn icon, mở lại MyNotch từ Finder để vào Settings.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Phím tắt") {
                ForEach(hotkeys.registrations) { registration in
                    KeyboardShortcuts.Recorder(registration.title, name: registration.name) { _ in shortcutRevision += 1 }
                }
                let conflicts = shortcutRevision >= 0 ? hotkeys.conflicts() : []
                ForEach(conflicts.indices, id: \.self) { index in
                    Label("Trùng phím: " + conflicts[index].map(\.title).joined(separator: ", "), systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("General")
    }
}
```

`App/Settings/InterfaceSettingsPage.swift`:

```swift
import MyNotchCore
import NotchUI
import SwiftUI

struct InterfaceSettingsPage: View {
    let settings: SettingsStore

    var body: some View {
        Form {
            Section("Hiển thị") {
                Picker("Màn hình", selection: settings.binding(InterfaceSettings.displayMode)) {
                    Text("Tất cả màn hình").tag(DisplayMode.all)
                    Text("Màn hình chính").tag(DisplayMode.main)
                    Text("Màn hình có con trỏ").tag(DisplayMode.cursor)
                }
                Toggle("Ẩn khi app đang fullscreen", isOn: settings.binding(InterfaceSettings.hideInFullscreen))
            }
            Section("Notch ảo (màn hình không có notch)") {
                slider("Chiều rộng", InterfaceSettings.virtualNotchWidth, 120...300, unit: "pt")
                slider("Chiều cao (0 = bằng menu bar)", InterfaceSettings.virtualNotchHeight, 0...40, unit: "pt")
            }
            Section("Khi mở rộng") {
                slider("Chiều rộng", InterfaceSettings.openWidth, 480...720, unit: "pt")
                Stepper("Trễ khi mở: \(settings.value(InterfaceSettings.openDelayMs)) ms",
                        value: settings.binding(InterfaceSettings.openDelayMs), in: 0...1000, step: 50)
                Stepper("Trễ khi đóng: \(settings.value(InterfaceSettings.closeDelayMs)) ms",
                        value: settings.binding(InterfaceSettings.closeDelayMs), in: 0...1000, step: 50)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Interface")
    }

    private func slider(_ title: String, _ key: SettingKey<Double>, _ range: ClosedRange<Double>, unit: String) -> some View {
        LabeledContent("\(title): \(Int(settings.value(key))) \(unit)") {
            Slider(value: settings.binding(key), in: range, step: 1)
        }
    }
}
```

`App/Settings/ModuleSettingsPage.swift`:

```swift
import MyNotchCore
import SwiftUI

struct ModuleSettingsPage: View {
    let id: ModuleID
    let registry: ModuleRegistry
    let permissions: any PermissionCenter

    private var module: (any FeatureModule)? { registry.modules.first { $0.descriptor.id == id } }

    var body: some View {
        if let descriptor = module?.descriptor {
            Form {
                Section {
                    Toggle("Bật \(descriptor.displayName)", isOn: Binding(
                        get: { registry.isEnabled(id) },
                        set: { enabled in Task { await registry.setEnabled(enabled, for: id) } }
                    ))
                    LabeledContent("Trạng thái") { StateBadge(state: registry.state(of: id)) }
                    if case .failed = registry.state(of: id) { retryButton }
                    if case .unavailable = registry.state(of: id) { retryButton }
                }
                if !descriptor.permissions.isEmpty {
                    Section("Quyền hệ thống") {
                        ForEach(descriptor.permissions, id: \.self) { permission in
                            LabeledContent(permission.displayName) {
                                if permissions.status(of: permission) == .granted {
                                    Text("Đã cấp").foregroundStyle(.green)
                                } else {
                                    Button("Cấp quyền") { permissions.openSystemSettings(for: permission) }
                                }
                            }
                        }
                    }
                }
                if let settingsView = registry.settingsView(for: id) {
                    Section("Cài đặt") { settingsView }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(descriptor.displayName)
        }
    }

    private var retryButton: some View {
        Button("Thử lại") { Task { await registry.retry(id) } }
    }
}

private struct StateBadge: View {
    let state: ModuleState

    var body: some View {
        switch state {
        case .running: Text("Đang chạy").foregroundStyle(.green)
        case .disabled: Text("Đã tắt").foregroundStyle(.secondary)
        case .starting: Text("Đang khởi động…")
        case .stopping: Text("Đang dừng…")
        case .needsPermission(let permission): Text("Thiếu quyền \(permission.displayName)").foregroundStyle(.orange)
        case .unavailable(let reason): Text(reason).foregroundStyle(.secondary)
        case .failed(let reason): Text("Lỗi: \(reason)").foregroundStyle(.red)
        }
    }
}
```

`App/Settings/AboutPage.swift`:

```swift
import SwiftUI

struct AboutPage: View {
    private let libraries: [(name: String, license: String, url: String)] = [
        ("KeyboardShortcuts", "MIT", "https://github.com/sindresorhus/KeyboardShortcuts"),
    ]

    var body: some View {
        Form {
            Section {
                LabeledContent("Phiên bản", value: Bundle.main.shortVersion)
                LabeledContent("Bundle ID", value: Bundle.main.bundleIdentifier ?? "-")
            }
            Section("Thư viện bên thứ ba") {
                ForEach(libraries, id: \.name) { library in
                    LabeledContent(library.name) {
                        Link(library.license, destination: URL(string: library.url)!)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("About")
    }
}

private extension Bundle {
    var shortVersion: String {
        let version = object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(version) (\(build))"
    }
}
```

- [ ] **Step 2: Bỏ qua file XcodeGen sinh ra**

Thêm vào cuối `.gitignore`:

```
# Generated by XcodeGen from project.yml
App/Info.plist
App/MyNotch.entitlements
```

- [ ] **Step 3: Build / kiểm chứng**

```bash
xcodegen generate && xcodebuild -project MyNotch.xcodeproj -scheme MyNotch -configuration Debug -destination 'platform=macOS' -derivedDataPath .build/xcode build -quiet
```

Expected: lệnh kết thúc với exit code 0, không in `error:`.

- [ ] **Step 4: Commit**

```bash
git add project.yml App/main.swift App/AppSettings.swift App/ModuleList.swift App/LaunchAtLogin.swift App/StatusItemController.swift App/AppDelegate.swift App/Settings/SettingsWindowController.swift App/Settings/SettingsRootView.swift App/Settings/GeneralSettingsPage.swift App/Settings/InterfaceSettingsPage.swift App/Settings/ModuleSettingsPage.swift App/Settings/AboutPage.swift .gitignore
git commit -m "feat(app): add app shell, menu bar and settings window"
```


## Task 16: Script kiểm chứng và tài liệu

`verify.sh` là cổng kiểm tra cục bộ duy nhất: sinh project, test mọi package, build app.

**Files:**
- Create: `scripts/verify.sh`
- Create: `README.md`
- Create: `docs/manual-test-checklist.md`

- [ ] **Step 1: Viết code**

`scripts/verify.sh`:

```bash
#!/bin/bash
# Full local gate: regenerate the project, test every package, build the app.
set -euo pipefail
cd "$(dirname "$0")/.."

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
```

`README.md`:

~~~~markdown
# MyNotch

Ứng dụng notch cá nhân cho macOS 26+, viết mới từ đầu, chia thành các module bật/tắt độc lập.

## Yêu cầu

- macOS 26.0 trở lên
- Xcode 26.6 (`xcode-select -p` phải trỏ vào Xcode, không phải Command Line Tools)
- XcodeGen: `brew install xcodegen`

## Build và chạy

```bash
xcodegen generate
open MyNotch.xcodeproj
```

Chọn scheme **MyNotch** rồi Run (⌘R). App không có icon Dock; tìm icon trên menu bar.

Kiểm tra toàn bộ (test mọi package rồi build app):

```bash
./scripts/verify.sh
```

## Cấu trúc

| Thư mục | Vai trò |
|---|---|
| `App/` | Target app: khởi động, ghép module (`ModuleList.swift`), menu bar, Settings |
| `Packages/MyNotchCore` | Hợp đồng module, registry, settings, quyền, phím tắt, live activity |
| `Packages/NotchUI` | Cửa sổ notch, hình học, state machine, đa màn hình |
| `Packages/Modules/*` | Mỗi tính năng một package; chỉ phụ thuộc MyNotchCore + NotchUI |
| `docs/superpowers/` | Spec và kế hoạch triển khai |

## Thêm một module

1. Tạo package trong `Packages/Modules/<Tên>/`, viết một class theo `FeatureModule`.
2. Khai báo package trong `project.yml` (mục `packages` và `dependencies` của target MyNotch).
3. Thêm một dòng vào `App/ModuleList.swift`.
4. `xcodegen generate`.

## Ký app

Mặc định app được ký ad-hoc ("Sign to Run Locally"), đủ cho các module không cần quyền hệ thống.
Khi làm module cần quyền (Accessibility, Screen Recording…), đặt `DEVELOPMENT_TEAM` trong `project.yml`
bằng Team ID của Apple ID (Xcode → Settings → Accounts) để macOS nhớ quyền giữa các lần build.

## Xử lý sự cố

- `cannot find '<Tên>' in scope` cho symbol nằm ở một package local khác: xoá thư mục `.build` của package đang build rồi chạy lại.
~~~~

`docs/manual-test-checklist.md`:

```markdown
# Checklist kiểm thử tay — Nền tảng

Điền **Đạt / Không đạt / Không kiểm được (lý do)** và ngày kiểm.

| # | Kịch bản | Kết quả | Ghi chú |
|---|---|---|---|
| 1 | Chạy app: không có icon Dock, có icon menu bar, menu hiện đủ 4 mục | | |
| 2 | Notch thật trên MacBook: notch đen trùng khít notch phần cứng | | |
| 3 | Màn ngoài: notch ảo ở giữa cạnh trên, kích thước theo Settings | | |
| 4 | Interface → Màn hình = Màn hình chính / Có con trỏ / Tất cả: notch hiện đúng màn | | |
| 5 | Rê chuột vào notch ~150ms thì mở; rời ra ~300ms thì đóng | | |
| 6 | Click vào notch thì mở ngay | | |
| 7 | ⌃⌥N mở/đóng notch trên màn đang có con trỏ | | |
| 8 | Khi notch đóng: click menu bar và cửa sổ ngay dưới vùng notch vẫn hoạt động | | |
| 9 | Video fullscreen trên Safari: notch ẩn; thoát fullscreen: hiện lại | | |
| 10 | Keynote khi trình chiếu: notch ẩn | | |
| 11 | Cho máy ngủ rồi đánh thức: notch vẫn đúng vị trí | | |
| 12 | Rút rồi cắm lại màn ngoài: notch biến mất rồi xuất hiện lại đúng chỗ | | |
| 13 | Tab Battery hiển thị %, trạng thái, nguồn điện | | |
| 14 | Cắm sạc: activity tia sét + % hiện khoảng 4 giây | | |
| 15 | Settings → Battery: tắt thì tab/activity biến mất; bật lại thì xuất hiện | | |
| 16 | Settings → General → Khởi động cùng máy: app có trong Login Items và tự chạy sau khi đăng nhập lại | | |
| 17 | Menu bar → Hide Notch / Show Notch; Pause All Modules có dấu tích và dừng Battery | | |
| 18 | Activity Monitor: CPU của MyNotch khi rê chuột liên tục 30 giây | | |
| 19 | Menu và popover của hệ thống (Control Center, Wi-Fi) không bị notch che | | |
```

- [ ] **Step 2: Build / kiểm chứng**

```bash
chmod +x scripts/verify.sh && ./scripts/verify.sh
```

Expected: ba dòng `✔ Test run ... passed` (20, 18 và 9 test) rồi `All checks passed.`.

- [ ] **Step 3: Commit**

```bash
git add scripts/verify.sh README.md docs/manual-test-checklist.md
git commit -m "chore: add verify script, README and manual test checklist"
```


## Task 17: Kiểm thử tay trên máy thật

Unit test không phủ được hiển thị, chuột, đa màn hình và fullscreen. Task này chạy app thật và điền checklist.

**Files:**
- Modify: `docs/manual-test-checklist.md`

- [ ] **Step 1: Thoát OneNotch và build bản chạy thử**

OneNotch cũng chiếm vùng notch nên phải thoát trước (menu bar của OneNotch → Quit).

```bash
xcodegen generate && xcodebuild -project MyNotch.xcodeproj -scheme MyNotch -configuration Debug -destination 'platform=macOS' -derivedDataPath .build/xcode build -quiet && open .build/xcode/Build/Products/Debug/MyNotch.app
```

Expected: icon MyNotch xuất hiện trên menu bar, không có icon Dock.

- [ ] **Step 2: Kiểm tra cửa sổ notch không cần nhìn màn hình**

```bash
cat > /tmp/winlist.swift <<'EOF'
import CoreGraphics
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String: Any]]
for w in list where (w[kCGWindowOwnerName as String] as? String) == "MyNotch" {
    print(w[kCGWindowLayer as String]!, w[kCGWindowBounds as String]!)
}
EOF
swift /tmp/winlist.swift
```

Expected: mỗi màn hình một dòng layer `27`, rộng `720`, nằm giữa cạnh trên màn đó.

- [ ] **Step 3: Đi qua từng mục trong `docs/manual-test-checklist.md`**

Điền cột Kết quả (Đạt / Không đạt / Không kiểm được + lý do) và ngày. Mục nào **Không đạt** thì dùng superpowers:systematic-debugging, sửa, chạy lại `./scripts/verify.sh`, rồi kiểm lại mục đó.

- [ ] **Step 4: Chạy lại cổng kiểm tra**

```bash
./scripts/verify.sh
```

Expected: `All checks passed.`

- [ ] **Step 5: Commit**

```bash
git add docs/manual-test-checklist.md
git commit -m "test: record manual verification of the foundation"
```

## Đối chiếu với tiêu chí hoàn thành (spec mục 10)

| Tiêu chí | Task |
|---|---|
| 1. `verify.sh` chạy hết, không lỗi | 16, 17 |
| 2. Không icon Dock, menu bar hoạt động | 15, 17 (mục 1, 17) |
| 3. Kích thước notch đúng trên MacBook và màn ngoài; đổi `displayMode` | 7, 11, 17 (mục 2–4) |
| 4. Mở/đóng bằng rê chuột, click, ⌃⌥N; click xuyên vùng trong suốt | 8, 11, 15, 17 (mục 5–8) |
| 5. Ẩn khi video fullscreen trên Safari | 9, 11, 17 (mục 9) |
| 6. Battery: tab, activity sạc, bật/tắt | 12–15, 17 (mục 13–15) |
| 7. Khởi động cùng máy | 15, 17 (mục 16) |
| 8. Checklist được điền kết quả | 17 |
