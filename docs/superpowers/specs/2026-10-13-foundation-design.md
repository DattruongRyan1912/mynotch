# MyNotch — Thiết kế Nền tảng (dự án con 0)

- **Ngày:** 2026-10-13
- **Trạng thái:** Đã duyệt thiết kế, chờ review spec
- **Phạm vi:** dự án con 0 trong lộ trình MyNotch: khung ứng dụng, cửa sổ notch, hệ thống module và module mẫu Battery

## 1. Bối cảnh và mục tiêu

MyNotch là ứng dụng notch cho macOS, viết mới từ đầu, dùng cá nhân và dễ tùy biến. Tính năng tham chiếu là OneNotch: media, clipboard, chụp màn hình/OCR, dịch, trạng thái AI agent, live activities, lịch.

Kết quả điều tra OneNotch 2.0.5 (build 67) bằng REA:

- OneNotch kế thừa từ **boring.notch** (GPL-3.0). Bằng chứng: 36 tên type trùng hệt, 6 type đổi tên từ `Boring*` sang `OneNotch*`, `boring.m4a` và `mediaremote-adapter.pl` giống nhau từng byte, cùng protocol XPC helper.
- Các phần OneNotch bổ sung riêng (clipboard, screenshot, translation, AI…) là mã độc quyền và có license trả phí.

**Mục tiêu của dự án con 0:**
- Dựng nền tảng để mỗi tính năng sau này là một module độc lập, bật/tắt được và thêm/sửa được mà không đụng tới module khác.
- Kiểm chứng toàn bộ vòng đời module bằng một module thật nhưng nhỏ: Battery.

## 2. Phạm vi

**Trong phạm vi:**

- Project XcodeGen, target app và các Swift package `MyNotchCore`, `NotchUI`, `BatteryModule`.
- Cửa sổ notch trên mọi màn hình: notch thật hoặc notch ảo. Có ba trạng thái `closed`, `compact`, `open`. Mở/đóng bằng rê chuột, click và phím tắt.
- Hệ thống module: `FeatureModule`, `ModuleContext`, `ModuleRegistry`, cơ chế phát live activity, tab, toast.
- Settings window (General, Interface, Modules, About), lưu cài đặt, phím tắt, trung tâm quyền, menu bar, khởi động cùng máy, log.
- Module Battery.
- Unit test, `scripts/verify.sh` và checklist kiểm thử tay.

**Ngoài phạm vi** (thuộc các dự án con sau, hoặc không làm):

- Clipboard, Media, Screenshot/OCR, Translation, AI agent, Calendar, các live activity khác, Shelf, Lock screen. Mỗi mục có spec riêng.
- Đồng bộ iCloud: CloudKit cần tài khoản Apple Developer trả phí.
- License, telemetry, Sentry, Sparkle auto-update.
- Sao chép mã từ binary OneNotch. Mọi tính năng phải viết theo kiểu clean-room, chỉ dùng API công khai của Apple và thư viện mã nguồn mở.

## 3. Ràng buộc kỹ thuật

| Mục | Giá trị |
|---|---|
| macOS tối thiểu | 26.0 (deployment target `26.0`) |
| Công cụ | Xcode 26.6 (17F113), Swift 6.3, Swift 6 language mode, strict concurrency `complete` |
| Sinh project | XcodeGen (`project.yml`); không commit `MyNotch.xcodeproj` |
| Bundle ID / tên | `io.lucasvu.mynotch` / `MyNotch` |
| Ký | Apple Development (Apple ID miễn phí), `DEVELOPMENT_TEAM` đặt trong `project.yml` |
| Sandbox | Tắt; Hardened Runtime bật |
| Dock | Ẩn (`LSUIElement = YES`); chỉ có icon menu bar |
| Mạng / telemetry | Không gửi dữ liệu ra ngoài |
| License mã của MyNotch | Dùng cá nhân. Đoạn nào lấy từ boring.notch phải giữ header GPL-3.0 và ghi nguồn |

**Thư viện bên thứ ba** (ghim version chính xác lúc triển khai, ghi vào `Package.resolved`, liệt kê ở trang About):

| Thư viện | Dùng cho | License |
|---|---|---|
| [Defaults](https://github.com/sindresorhus/Defaults) | Lưu cài đặt có kiểu | MIT |
| [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) | Phím tắt toàn cục, giao diện ghi phím | MIT |
| [XcodeGen](https://github.com/yonaskolb/XcodeGen) | Sinh `.xcodeproj` (công cụ dev, không nhúng vào app) | MIT |

## 4. Kiến trúc

### 4.1 Cấu trúc thư mục

```
MyNotch/
├── project.yml
├── App/
│   ├── MyNotchApp.swift          # @main, NSApplicationDelegateAdaptor
│   ├── AppDelegate.swift         # composition root: tạo registry, ScreenManager, menu bar
│   ├── ModuleList.swift          # danh sách module, nơi DUY NHẤT ghép module
│   ├── Settings/                 # SettingsWindowController + các trang General/Interface/Modules/About
│   ├── Info.plist
│   └── MyNotch.entitlements
├── Packages/
│   ├── MyNotchCore/              # không phụ thuộc AppKit UI ngoài kiểu cơ bản
│   ├── NotchUI/                  # phụ thuộc MyNotchCore
│   └── Modules/
│       └── Battery/              # package BatteryModule, phụ thuộc MyNotchCore + NotchUI
├── scripts/
│   ├── verify.sh
│   └── md2html.py                # chuyển spec Markdown sang HTML để đọc
└── docs/
    ├── superpowers/specs/
    └── manual-test-checklist.md
```

### 4.2 Quy tắc phụ thuộc

- `MyNotchCore` không phụ thuộc package nội bộ nào.
- `NotchUI` chỉ phụ thuộc `MyNotchCore`.
- Mỗi module chỉ phụ thuộc `MyNotchCore` và `NotchUI`. **Không module nào import module khác.**
- Chỉ `App/` import các module. Thêm một module mới = thêm một package + một dòng trong `ModuleList.swift` + khai báo package trong `project.yml`.

### 4.3 API module (`MyNotchCore`)

```swift
public struct ModuleID: Hashable, Sendable, RawRepresentable { public let rawValue: String }

public struct ModuleDescriptor: Sendable {
    public let id: ModuleID              // ổn định, chữ thường, ví dụ "battery"
    public let displayName: String
    public let systemImage: String       // SF Symbol
    public let defaultEnabled: Bool
    public let permissions: [Permission] // quyền bắt buộc để start()
    public let order: Int                // thứ tự tab và thứ tự trong Settings
}

@MainActor public protocol FeatureModule: AnyObject {
    var descriptor: ModuleDescriptor { get }
    func start(_ context: ModuleContext) async throws(ModuleError)
    func stop() async
    func makeTab() -> NotchTab?          // nil nếu module không có tab
    func makeSettingsView() -> AnyView?  // nil nếu module không có cài đặt riêng
}

@MainActor public final class ModuleContext {
    public let settings: ModuleSettings        // chỉ đọc/ghi key "module.<id>.*"
    public let activities: ActivityPublisher   // set/clear live activity của module
    public let presenter: NotchPresenter       // mở tab, toast, đóng notch
    public let hotkeys: HotkeyRegistry         // đăng ký KeyboardShortcuts.Name + handler
    public let permissions: PermissionCenter   // kiểm tra/xin quyền
    public let logger: Logger                  // os.Logger, category = module id
}
```

**Thay đổi so với bản phác ở bước brainstorm:** live activity không còn là thuộc tính `activity` trên protocol. Module chủ động phát activity qua `context.activities.set(_:)` và gỡ bằng `clear()`. Như vậy registry không phải theo dõi thuộc tính của từng module, và mọi activity của module đó tự động bị gỡ khi module stop.

```swift
public struct LiveActivity: Identifiable {
    public let id: String                  // duy nhất trong phạm vi module
    public let priority: ActivityPriority  // .low < .normal < .high < .critical
    public let leading: AnyView            // ô bên trái notch ở trạng thái compact
    public let trailing: AnyView           // ô bên phải notch
    public let expiresAfter: Duration?     // tự gỡ sau khoảng thời gian, nil = giữ đến khi clear
}

public struct NotchTab: Identifiable {
    public let id: ModuleID
    public let title: String
    public let systemImage: String
    public let preferredHeight: CGFloat?   // bị giới hạn trong [120, 300] pt
    public let content: AnyView
}

@MainActor public protocol NotchPresenter {
    func open(tab: ModuleID)
    func showToast(_ content: AnyView, duration: Duration)
    func close()
}

public enum ModuleError: Error, Sendable {
    case needsPermission(Permission)
    case unavailable(reason: String)
    case failed(reason: String)
}
```

### 4.4 `ModuleRegistry`

`ModuleRegistry` là `@MainActor @Observable`. Nó giữ danh sách module và trạng thái của từng module:

```
disabled → starting → running
                    ↘ needsPermission(Permission) | unavailable(reason) | failed(reason)
running  → stopping → disabled
```

- Lúc app khởi động, registry đọc `module.<id>.enabled`; nếu chưa có giá trị thì dùng `descriptor.defaultEnabled`.
- **Bật module:**
  1. Kiểm tra các quyền trong `descriptor.permissions`. Thiếu quyền nào thì chuyển sang `needsPermission`, không gọi `start`.
  2. Gọi `start(context)` trong một `Task` riêng. Thành công thì chuyển sang `running`. `start` ném `ModuleError` thì chuyển sang trạng thái lỗi tương ứng.
- **Tắt module:**
  1. Gọi `stop()`, đợi tối đa 2 giây.
  2. Hủy task của module.
  3. `ActivityPublisher` gỡ mọi activity của module.
  4. Gỡ tab của module, gỡ các phím tắt module đã đăng ký.
- **Thử lại:** nút Retry trong Settings sẽ tắt rồi bật lại module.
- Lỗi của một module không ảnh hưởng tới các module khác. Registry không bao giờ để lỗi lan lên crash cả app.

## 5. NotchUI

### 5.1 Cửa sổ

- Mỗi màn hình có một `NotchPanel: NSPanel`. Cấu hình:
  - `styleMask: [.borderless, .nonactivatingPanel]`
  - `isOpaque = false`, `backgroundColor = .clear`, `hasShadow = false`
  - `level = .mainMenu + 3` (nằm trên menu bar)
  - `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]`
  - `canBecomeKey = false`, trừ khi tab đang mở cần nhận bàn phím (ví dụ ô tìm kiếm). Khi đó tab tự yêu cầu.
- Kích thước panel cố định bằng **kích thước mở tối đa** (rộng 720pt × cao `notchHeight + 300`pt), neo ở giữa cạnh trên `screen.frame`. Panel không đổi frame khi animate; chỉ nội dung SwiftUI bên trong thay đổi.
- **Click xuyên qua:**
  - Panel mặc định `ignoresMouseEvents = true`.
  - `NotchHoverTracker` dùng `NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged])` cùng local monitor tương ứng để biết con trỏ có nằm trong vùng hình notch hiện tại hay không.
  - Vùng này là `hitRect`: bằng hình notch hiện tại nới ra 8pt mỗi bên. Khi con trỏ vào `hitRect` thì đặt `ignoresMouseEvents = false`; khi ra thì đặt lại `true`.
  - Monitor chuột (không phải phím) không cần quyền Accessibility.

### 5.2 Hình học (`NotchGeometry`)

Đầu vào là `ScreenDescriptor`, một struct lấy từ `NSScreen` để test được: `frame`, `safeAreaTop`, `auxiliaryTopLeftWidth?`, `auxiliaryTopRightWidth?`, `menuBarHeight`.

- **Notch thật** (có `safeAreaTop > 0` và có cả hai vùng auxiliary):
  - `width = frame.width - leftAux - rightAux`
  - `height = safeAreaTop`
- **Notch ảo:**
  - `width = settings.virtualNotchWidth` (mặc định 185, cho phép 120–300)
  - `height = settings.virtualNotchHeight` (mặc định `menuBarHeight`, cho phép 24–40)
- **Kích thước theo trạng thái:**
  - `closed` = kích thước notch
  - `compact` = notch + 2 × `compactSideWidth` (mặc định 64pt mỗi bên)
  - `open` = rộng 600pt (cho phép 480–720), cao `notchHeight + clamp(tab.preferredHeight ?? 190, 120, 300)`
- Bán kính góc: `closed` và `compact` có góc dưới 10pt; `open` có góc dưới 24pt và góc trên 8pt (bo vào cạnh menu bar).

### 5.3 Đa màn hình (`ScreenManager`)

- Định danh màn hình bằng `CGDisplayCreateUUIDFromDisplayID` lấy từ `NSScreenNumber`.
- Lắng nghe `NSApplication.didChangeScreenParametersNotification` và `NSWorkspace.didWakeNotification`. Khi có sự kiện thì đối chiếu tập UUID hiện tại: tạo panel cho màn mới, hủy panel của màn đã rút, cập nhật frame cho màn còn lại.
- Chế độ hiển thị (`interface.displayMode`):
  - `all` (mặc định): mỗi màn một notch.
  - `main`: chỉ màn chính.
  - `cursor`: chỉ màn đang có con trỏ. Kiểm tra lại mỗi khi con trỏ đổi màn.
- Mỗi panel có một `NotchViewModel` riêng. Trạng thái `open` của màn này không ảnh hưởng màn khác.

### 5.4 State machine (`NotchViewModel`)

`NotchViewModel` là `@MainActor @Observable`, gồm:
- `state: closed | compact | open(tabID)`
- `isPinned`
- `isDragging`, dành cho các module có kéo-thả sau này

Hai thông số thời gian, lấy từ cài đặt:
- `openDelay` = 150ms (cho phép 0–1000)
- `closeDelay` = 300ms (cho phép 0–1000)

Đồng hồ được inject dạng `any Clock<Duration>` để test được.

| Từ | Sự kiện | Đến |
|---|---|---|
| `closed`/`compact` | con trỏ ở trong notch liên tục ≥ `openDelay` | `open(lastTab ?? firstTab)` |
| `closed`/`compact` | click vào notch | `open(lastTab ?? firstTab)` |
| bất kỳ | phím tắt "Toggle notch" | `open` nếu đang đóng, ngược lại đóng. Áp dụng cho màn đang có con trỏ |
| `open` | con trỏ rời `hitRect` liên tục ≥ `closeDelay`, và không ghim, không kéo | đóng |
| `open` | `presenter.close()` | đóng |
| bất kỳ | `presenter.open(tab:)` | `open(tab)` |
| `closed` | xuất hiện activity | `compact` |
| `compact` | hết activity | `closed` |

"Đóng" nghĩa là về `compact` nếu đang có activity, ngược lại về `closed`.

**Ưu tiên activity:**
- `compact` hiển thị activity có `priority` cao nhất. Nếu bằng nhau thì activity được `set` gần nhất thắng.
- Các activity còn lại nằm trong hàng đợi.
- Activity có `expiresAfter` tự gỡ khi hết hạn.

**Toast:** `showToast` hiển thị nội dung ở trạng thái `open` không có thanh tab, trong `duration`. Hết thời gian thì đóng, trừ khi con trỏ đang ở trong notch.

### 5.5 Ẩn khi fullscreen (`FullscreenDetector`)

- Cài đặt `interface.hideInFullscreen`, mặc định `true`.
- Các sự kiện kích hoạt kiểm tra lại: `NSWorkspace.activeSpaceDidChangeNotification`, `didActivateApplicationNotification`, và một lần kiểm tra lại 500ms sau mỗi sự kiện, vì animation chuyển Space chưa xong ngay.
- Quy tắc nhận diện: lấy `CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID)`. Nếu có cửa sổ thuộc PID của app phía trước, nằm ở layer 0, và có `kCGWindowBounds` phủ kín bounds của màn đó (sai số 1pt), thì màn đó đang fullscreen. Khi đó panel của màn ấy chuyển `alphaValue = 0` và `ignoresMouseEvents = true`.
- Không cần quyền Screen Recording, vì chỉ đọc bounds, không đọc tên cửa sổ.
- **Rủi ro cần kiểm chứng:** video fullscreen trong Safari, Keynote khi trình chiếu, game. Ghi kết quả vào checklist kiểm thử tay.

### 5.6 Giao diện và animation

- `NotchShape` là `Shape` có `animatableData` gồm bán kính góc trên/dưới, chiều rộng và chiều cao.
- Chuyển trạng thái dùng `.spring(response: 0.38, dampingFraction: 0.8)`. Nội dung tab hiện ra (`opacity` + `scale 0.96 → 1`) sau khi khung notch mở xong khoảng 80ms.
- Nền notch màu đen tuyền để liền với notch phần cứng. Màu nhấn và kiểu chữ lấy từ design tokens của `NotchUI`.
- Thanh tab chỉ hiện khi có từ 2 tab trở lên, nằm trên cùng của vùng mở rộng.

## 6. Khung ứng dụng

### 6.1 Menu bar

`NSStatusItem` dùng SF Symbol `rectangle.topthird.inset.filled`. Menu gồm:
- Open Settings… (⌘,)
- Show/Hide Notch
- Pause All Modules (tắt toàn bộ module tạm thời, không đổi cài đặt enabled)
- Quit MyNotch (⌘Q)

### 6.2 Settings

Dùng `SettingsWindowController` (NSWindow) bọc SwiftUI `NavigationSplitView`.

| Trang | Nội dung |
|---|---|
| General | Khởi động cùng máy (`SMAppService.mainApp`), hiện icon menu bar, phím tắt "Toggle notch" (mặc định ⌃⌥N) |
| Interface | `displayMode`, kích thước notch ảo, `openDelay`, `closeDelay`, `hideInFullscreen`, độ rộng khi mở |
| Modules | Danh sách module theo `order`: công tắc bật/tắt, trạng thái từ registry, các quyền còn thiếu kèm nút "Cấp quyền", nút Retry khi lỗi, và trang `makeSettingsView()` của module |
| About | Phiên bản, bundle ID, danh sách thư viện bên thứ ba và license |

Settings mở từ mục "Open Settings…" trong menu bar. Vì app không có Dock icon và notch không nhận focus, phím ⌘, chỉ có tác dụng khi chính cửa sổ Settings đang được chọn.

### 6.3 Lưu cài đặt

- Dùng `Defaults` trên `UserDefaults.standard`. Key toàn cục có tiền tố `app.` hoặc `interface.`.
- `ModuleSettings` bọc key với tiền tố `module.<id>.`. Module không tạo được key nằm ngoài namespace của nó.

### 6.4 Phím tắt

- `HotkeyRegistry` bọc `KeyboardShortcuts`. Module đăng ký `(name, defaultShortcut?, handler)`. Registry tự gỡ handler khi module stop.
- Settings hiển thị `KeyboardShortcuts.Recorder` cho mọi phím tắt đã đăng ký, và cảnh báo khi hai tên trùng tổ hợp phím.

### 6.5 Quyền (`PermissionCenter`)

| `Permission` | Kiểm tra | Mở System Settings |
|---|---|---|
| `.accessibility` | `AXIsProcessTrusted()` | `x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility` |
| `.screenRecording` | `CGPreflightScreenCaptureAccess()` | `…?Privacy_ScreenCapture` |
| `.calendars` | `EKEventStore.authorizationStatus(for: .event)` | `…?Privacy_Calendars` |
| `.reminders` | `EKEventStore.authorizationStatus(for: .reminder)` | `…?Privacy_Reminders` |
| `.bluetooth` | `CBManager.authorization` | `…?Privacy_Bluetooth` |
| `.automation(bundleID)` | `AEDeterminePermissionToAutomateTarget` (không hỏi) | `…?Privacy_Automation` |
| `.microphone` | `AVCaptureDevice.authorizationStatus(for: .audio)` | `…?Privacy_Microphone` |

- `PermissionCenter` kiểm tra lại trạng thái khi app được kích hoạt lại (`didBecomeActive`) và khi mở Settings. Module đang ở `needsPermission` sẽ tự thử start lại khi quyền vừa được cấp.
- Nền tảng chỉ cài đặt các quyền thật sự cần cho nền tảng và Battery (hiện là không có quyền nào). Các case còn lại được khai báo và kiểm tra trước, để các module sau dùng. **Usage description trong Info.plist của từng quyền được thêm ở dự án con cần quyền đó.**

### 6.6 Log

- Dùng `Logger(subsystem: "io.lucasvu.mynotch", category: <module id | "app" | "notch">)`.
- Chỉ log trạng thái và lỗi, không log nội dung người dùng như clipboard hay văn bản.

## 7. Module mẫu: Battery

- `descriptor`: id `battery`, tên "Battery", icon `battery.100percent.bolt`, `defaultEnabled = true`, không cần quyền nào, `order = 900`.
- **Nguồn dữ liệu:**
  - Đăng ký `IOPSNotificationCreateRunLoopSource` để nhận thông báo khi trạng thái nguồn điện đổi.
  - Đọc `IOPSCopyPowerSourcesInfo` → `IOPSCopyPowerSourcesList` → `IOPSGetPowerSourceDescription`, lấy các key `kIOPSCurrentCapacityKey`, `kIOPSMaxCapacityKey`, `kIOPSIsChargingKey`, `kIOPSPowerSourceStateKey`, `kIOPSTimeToEmptyKey`, `kIOPSTimeToFullChargeKey`.
  - Logic đọc nằm sau protocol `PowerSourceReading` để test được bằng bản giả.
- Máy không có pin (Mac desktop) thì `start` ném `.unavailable(reason: "Máy không có pin")`.
- **Live activity:**
  - Khi chuyển từ pin sang sạc: phát activity `charging` (`priority .normal`, `expiresAfter 4s`). Bên trái là icon tia sét, bên phải là phần trăm pin.
  - Khi pin ≤ `module.battery.lowThreshold` (mặc định 20%) và không sạc: phát activity `low` (`priority .high`), giữ đến khi cắm sạc hoặc pin vượt ngưỡng + 5%.
- **Tab:** phần trăm, trạng thái sạc/xả, thời gian còn lại, nguồn điện (adapter/pin).
- **Settings:** ngưỡng pin yếu (5–50%), bật/tắt thông báo khi cắm sạc.

## 8. Xử lý lỗi

- Mọi đường lỗi của module đều trả `ModuleError`, không `fatalError`, không force-unwrap kết quả API hệ thống.
- Lỗi lúc tạo panel cho một màn hình chỉ được ghi log, rồi bỏ qua màn đó; các màn khác vẫn chạy.
- Giá trị cài đặt ngoài khoảng cho phép bị kẹp (clamp) về biên khi đọc, không làm app crash.
- Không gửi lỗi ra ngoài. Dùng `os.Logger` và crash report của macOS.

## 9. Kiểm thử và kiểm chứng

**Unit test** (Swift Testing, `swift test` trong từng package):

| Package | Nội dung kiểm thử |
|---|---|
| MyNotchCore | Vòng đời registry (bật, tắt, lỗi `start`, thiếu quyền, Retry); lỗi của một module không ảnh hưởng module khác; namespace `ModuleSettings`; `ActivityPublisher` gỡ hết activity khi module stop; hàng đợi ưu tiên và hết hạn activity |
| NotchUI | `NotchGeometry` cho các màn: MacBook 14"/16" có notch, màn ngoài 1920×1080 và 5K không notch, cài đặt notch ảo ngoài biên; bảng chuyển trạng thái `NotchViewModel` với đồng hồ giả (open/close delay, ghim, kéo, toast); quy tắc nhận diện fullscreen từ danh sách cửa sổ giả |
| BatteryModule | Tính phần trăm và trạng thái từ dictionary IOKit giả; phát/gỡ activity `charging` và `low` đúng ngưỡng; báo `.unavailable` khi không có pin |

**`scripts/verify.sh`:** chạy `xcodegen generate` → `swift test` cho từng package → `xcodebuild -scheme MyNotch -configuration Debug build`. Dừng ngay khi có bước lỗi.

**Checklist kiểm thử tay** (`docs/manual-test-checklist.md`): notch thật, notch ảo trên màn ngoài, ba chế độ hiển thị, rê chuột/click/phím tắt, menu bar không bị chặn click, video fullscreen trên Safari, Keynote khi trình chiếu, ngủ/đánh thức, rút/cắm màn hình, bật/tắt Battery trong Settings, khởi động cùng máy.

## 10. Tiêu chí hoàn thành

1. `scripts/verify.sh` chạy hết các bước, không lỗi.
2. App chạy không có icon Dock. Icon menu bar và menu hoạt động.
3. Notch hiển thị đúng kích thước trên màn MacBook và màn ngoài; đổi được `displayMode`.
4. Mở/đóng được bằng rê chuột, click và ⌃⌥N. Click vào menu bar và cửa sổ bên dưới vùng trong suốt vẫn hoạt động.
5. Tự ẩn khi xem video fullscreen trên Safari, và hiện lại khi thoát fullscreen.
6. Battery hiển thị tab. Cắm sạc thì hiện activity `charging`. Tắt Battery trong Settings thì tab và activity biến mất; bật lại thì xuất hiện lại.
7. Bật "Khởi động cùng máy" thì app có trong Login Items và tự chạy sau khi đăng nhập lại.
8. Checklist kiểm thử tay được điền kết quả: mục nào không kiểm được thì ghi rõ lý do.

## 11. Lộ trình các dự án con

| # | Dự án con | Ghi chú |
|---|---|---|
| 0 | Nền tảng + Battery | Spec này |
| 1 | Clipboard | Ưu tiên đầu tiên sau nền tảng |
| 2 | Media | Now Playing qua `mediaremote-adapter` (BSD-3), điều khiển phát, ảnh bìa, lời bài hát, phổ âm |
| 3 | Screenshot + OCR | Có thể tách 3a chụp vùng/cửa sổ + khay ảnh, 3b markup, 3c chụp cuộn + OCR (Vision, chạy trong XPC helper) |
| 4 | Translation | Framework Translation, dịch đoạn chữ đang chọn qua Accessibility |
| 5 | AI agent activity | Hook Claude Code/Codex, usage |
| 6 | Calendar + Reminders | EventKit |
| 7 | Live activities + HUD | Bluetooth, Focus, mạng, Caps Lock, download, HUD âm lượng/độ sáng |
| 8 | Shelf, Shortcuts, Timer | |
| 9 | Lock screen | API riêng SkyLight; rủi ro cao, làm cuối |

## 12. Rủi ro và điểm cần kiểm chứng

| Rủi ro | Cách xử lý |
|---|---|
| Nhận diện fullscreen sai với một số app | Có tùy chọn tắt `hideInFullscreen`; ghi các ca sai vào checklist để tinh chỉnh quy tắc |
| `level = .mainMenu + 3` che menu và popover của hệ thống | Kiểm thử tay. Nếu che thì chỉ nâng level khi notch `open` |
| Global mouse monitor tốn CPU khi rê chuột liên tục | Chỉ tính `hitRect` bằng phép so sánh hình chữ nhật. Kiểm tra CPU trong Activity Monitor khi rê chuột liên tục 30 giây |
| Chứng chỉ Apple Development có thời hạn; hết hạn thì macOS không mở app | Build lại trong Xcode để ký bằng chứng chỉ mới. Ghi chú trong README |
| Phím tắt mặc định ⌃⌥N trùng với app khác | Settings cảnh báo trùng; người dùng gán lại được |
