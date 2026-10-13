# MyNotch — Điểm nối nền tảng (dự án con 0.5)

- **Ngày:** 2026-10-13
- **Trạng thái:** Triển khai trên nhánh `feat/modules` (nối tiếp `feat/foundation`)
- **Nguồn:** review cuối toàn nhánh nền tảng. Các module tiếp theo cần những điểm nối mà nền tảng còn thiếu.

## 1. Mục tiêu

Bổ sung đúng các API mà Clipboard và các module sau cần, không làm lại kiến trúc. Mọi thay đổi giữ nguyên quy tắc phụ thuộc: module chỉ thấy `MyNotchCore` và `NotchUI`.

| # | Nhu cầu | Module cần đầu tiên |
|---|---|---|
| A1 | Notch mở bằng phím tắt phải đóng được khi click ra ngoài | Clipboard |
| A2 | Tab nhận bàn phím (ô tìm kiếm, phím mũi tên, Esc) | Clipboard |
| A3 | Toast xuất hiện khi tab đang mở không được phá tab | Clipboard, Screenshot |
| A4 | Nội dung tab ghim notch / báo đang kéo / tự đóng notch | Clipboard, Shelf |
| B1 | Live activity cập nhật liên tục không nhảy thứ tự | Media, Timer |
| B2 | Thư mục dữ liệu riêng cho module | Clipboard |
| B3 | Cài đặt module dùng được cả khi module đang tắt | Clipboard, Translation, AI |
| B4 | Xin quyền hệ thống (không chỉ mở System Settings) | Clipboard (Accessibility), Calendar |
| B5 | `Scheduler` cho module (polling, debounce, timer) | Clipboard |
| B6 | Thoát app có dừng module để lưu dữ liệu | Clipboard, Shelf |

## 2. NotchUI

### A1. Đóng khi click ra ngoài

- `NotchHoverTracker` theo dõi thêm `.leftMouseDown` và `.rightMouseDown` (global + local). Mouse monitor không cần quyền Accessibility.
- `ScreenManager` chuyển sự kiện tới từng controller: `mouseDown(at:)`.
- Controller đóng notch khi **cả ba** điều kiện đúng: notch đang mở rộng (`open` hoặc `toast`), điểm click nằm ngoài `hitRect` hiện tại, và notch không bị ghim (`isPinned == false`).
- Ghim (`isPinned`) dùng khi module mở menu ngữ cảnh hoặc popover, vì click vào menu nằm ngoài vùng notch.

### A2. Tab nhận bàn phím

- `NotchTab` thêm tham số `acceptsKeyboard: Bool = false`.
- Khi `displayState == .open(id)` và tab `id` có `acceptsKeyboard`, panel được phép thành key window (`allowsKeyStatus = true`, `makeKey()`). Panel vẫn là `nonactivatingPanel` nên app đang dùng vẫn active, giống Spotlight.
- Khi rời tab đó hoặc notch đóng: `allowsKeyStatus = false`; nếu panel đang key thì `orderOut` rồi `orderFrontRegardless` để trả bàn phím về app trước.
- Esc (`cancelOperation(_:)`) đóng notch.
- Khi panel mất key (người dùng click sang app khác) và notch không bị ghim thì notch đóng.
- Module tự đặt focus bằng `@FocusState` trong view của mình.

### A3. Toast khi tab đang mở

- `showToast` khi state là `.open(tab)` ghi nhớ state đó. Toast hết hạn thì quay lại `.open(tab)` thay vì đóng; sau đó áp dụng quy tắc đóng thông thường (con trỏ ở ngoài thì hẹn giờ đóng).
- Toast khi notch đóng giữ hành vi cũ.
- Thông báo nhỏ kiểu HUD dùng `LiveActivity` với `expiresAfter`, không dùng toast (toast có kích thước của tab mặc định).

### A4. `NotchHandle` trong environment

```swift
public struct NotchHandle {
    public func setPinned(_ pinned: Bool)
    public func setDragging(_ dragging: Bool)
    public func close()
}
extension EnvironmentValues { public var notch: NotchHandle }   // mặc định: handle không làm gì
```

`NotchRootView` gắn `.environment(\.notch, …)` cho nội dung tab và toast. Handle giữ tham chiếu yếu tới `NotchViewModel`.

### Sửa nhỏ đi kèm

- Gesture tap mở notch chỉ hoạt động khi notch chưa mở (`including: .subviews` khi đang mở), để không tranh gesture với nội dung tab.
- `ScreenManager` cache khung các màn hình khi đồng bộ màn hình, không gọi `NSScreen.screens` ở mỗi lần rê chuột.

## 3. MyNotchCore

### B1. Live activity cập nhật tại chỗ

- `ActivityCenter.set` với id đã tồn tại: **thay nội dung tại chỗ, giữ nguyên thứ tự** (không tăng `sequence`). Hạn `expiresAfter` tính lại từ lần `set` mới.
- Thêm `raise(id:)` (và `ActivityPublisher.raise(id:)`) để chủ động đưa activity lên trên các activity cùng mức ưu tiên.
- `Entry` có `revision` tăng ở mỗi lần `set`; `current` chỉ được gán lại khi entry thắng thay đổi (id, sequence hoặc revision), nên xoá một activity không phải `current` không làm view vẽ lại.
- Quy ước: nội dung đổi liên tục (tiến độ phát nhạc, đếm ngược) do model `@Observable` của module điều khiển bên trong view của activity. Gọi `set` tối đa khoảng 1 lần/giây.

### B2. `ModuleStorage`

```swift
nonisolated public struct ModuleStorage: Sendable {
    public let directory: URL        // ~/Library/Application Support/io.lucasvu.mynotch/Modules/<id>/
    public let cachesDirectory: URL  // ~/Library/Caches/io.lucasvu.mynotch/Modules/<id>/
    public func ensureDirectories() throws   // tạo nếu chưa có
}
nonisolated public struct StorageRoot: Sendable {
    public let applicationSupport: URL
    public let caches: URL
    public static func standard(bundleID: String) -> StorageRoot
    public func storage(for id: ModuleID) -> ModuleStorage
}
```

- `ModuleRegistry.init` nhận thêm `storageRoot: StorageRoot`. `RegistryHarness` dùng thư mục tạm riêng cho mỗi harness.
- Dữ liệu lớn (lịch sử clipboard, ảnh chụp) không lưu trong `SettingsStore`/UserDefaults.

### B3. Cài đặt khi module tắt

`FeatureModule.makeSettingsView()` đổi thành:

```swift
func makeSettingsView(_ environment: ModuleSettingsEnvironment) -> AnyView?

public struct ModuleSettingsEnvironment {
    public let settings: ModuleSettings
    public let storage: ModuleStorage
    public let permissions: any PermissionCenter
    public let isRunning: Bool
}
```

- Registry tạo một `ModuleSettings` cho mỗi module ngay khi khởi tạo và dùng chung cho context lẫn trang Settings.
- Battery bỏ dòng "Cài đặt hiện khi module đang chạy" và luôn hiện các dòng cài đặt.

### B4. Xin quyền

- `PermissionCenter` thêm `func request(_ permission: Permission) async -> PermissionStatus`.
- `SystemPermissionCenter.request`:

| Quyền | Cách xin |
|---|---|
| Accessibility | `AXIsProcessTrustedWithOptions` với prompt; trả trạng thái hiện tại (người dùng bật trong System Settings) |
| Screen Recording | `CGRequestScreenCaptureAccess()` |
| Calendars / Reminders | `EKEventStore.requestFullAccessToEvents/Reminders()` |
| Bluetooth | Tạo `CBCentralManager`, chờ callback trạng thái đầu tiên rồi đọc `CBManager.authorization` |
| Automation | `AEDeterminePermissionToAutomateTarget(…, askUserIfNeeded: true)` chạy ngoài main thread |
| Microphone | `AVCaptureDevice.requestAccess(for: .audio)` |

- `ModuleDescriptor` thêm `optionalPermissions: [Permission] = []`: hiện trong Settings kèm trạng thái và nút cấp quyền, không chặn module khởi động. Module tự kiểm tra trước khi dùng.
- `ModuleRegistry.grant(_ permission:) async`: nếu `.notDetermined` thì `request`, còn lại mở System Settings; sau đó `refreshPermissions()`.
- Trang Settings của module dùng `grant` cho cả quyền bắt buộc lẫn tuỳ chọn và tự làm mới trạng thái mỗi 2 giây khi đang hiện (TCC không gửi thông báo khi quyền đổi).
- App theo dõi `registry.states`: khi có module `.needsPermission`, gọi `refreshPermissions()` mỗi 2 giây cho tới khi không còn.
- `project.yml` khai báo sẵn usage description (Calendars, Reminders, Bluetooth, Apple Events, Microphone) và entitlement Hardened Runtime tương ứng (`com.apple.security.personal-information.calendars`, `com.apple.security.automation.apple-events`, `com.apple.security.device.audio-input`, `com.apple.security.device.bluetooth`). Thiếu usage description thì app crash khi xin quyền.

### B5. Scheduler cho module

`ModuleContext` thêm `public let scheduler: any Scheduler`. `ModuleRegistry.init` nhận `scheduler`. App truyền `TaskScheduler`, test truyền `ManualScheduler`.

### B6. Thoát app

- `ModuleRegistry.shutdown() async`: dừng mọi module đang chạy, không đổi cờ `enabled`, sau đó không khởi động lại module nào.
- `AppDelegate.applicationShouldTerminate` trả `.terminateLater`, chờ `shutdown()` tối đa 3 giây rồi `reply(toApplicationShouldTerminate: true)`.

## 4. Khung ứng dụng

- Khi cửa sổ Settings mở, app chuyển sang `.regular` (có icon Dock và ⌘Tab); khi đóng, quay lại `.accessory`.
- README: mục "Thêm một module" thêm bước khai báo usage description/entitlement khi module cần quyền mới.

## 5. Kiểm thử

| Phần | Test tự động |
|---|---|
| A1 | `NotchViewModel`/controller: click ngoài khi mở → đóng; khi ghim → giữ; khi đóng → bỏ qua |
| A3 | Toast trên tab đang mở hết hạn → quay lại đúng tab; toast khi đóng → đóng như cũ |
| B1 | `set` lặp lại giữ thứ tự; `raise` đưa lên; xoá entry không phải current không đổi `current`; hết hạn tính lại |
| B2 | Đường dẫn đúng namespace; `ensureDirectories` tạo thư mục; harness dùng thư mục tạm |
| B3 | Settings view có được khi module tắt; settings dùng chung với context |
| B4 | `grant`: `.notDetermined` → gọi `request`; `.denied` → mở System Settings; sau đó module khởi động lại |
| B5 | Module dùng `context.scheduler` (fake module) |
| B6 | `shutdown` dừng module đang chạy, không đổi `enabled`, `bootstrap`/`setEnabled` sau đó không khởi động |

A2 và A4 phụ thuộc AppKit key window, kiểm thử tay trong checklist của Clipboard.
