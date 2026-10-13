# Ghi chú triển khai: Nền tảng và điểm nối nền tảng

- **Ngày:** 2026-10-14
- **Spec:** [Nền tảng (dự án con 0)](../specs/2026-10-13-foundation-design.html) và [Điểm nối nền tảng (dự án con 0.5)](../specs/2026-10-13-platform-seams-design.html) (spec 0.5 đã có mục "Ghi chú triển khai" riêng, §6; tài liệu này không lặp lại toàn bộ). Spec không bị sửa; chỗ đã lỗi thời nằm ở mục "Sửa lại spec".
- **Package:** `Packages/MyNotchCore` (kèm target `MyNotchTestSupport`), `Packages/NotchUI`, `Packages/Modules/Battery` (module mẫu, id `battery`, order 900), thư mục `App/`, `project.yml`, `scripts/`.
- **Commit chính:** nền tảng từ `04c5d16` (spec) tới `80225c0`; điểm nối 0.5: `ee6f4fa` (B1), `95eb95b` và `c134e8a` (B2, B5), `6884c77` (B3), `b3b861a` và `cf94688` (B4), `241bd5f` (B6), `5a54158` (A1, A3), `1c10ef5` và `8d01bf0` (A2, A4), `15dbd8b` và `50d4924` (Settings và Dock), `8b20c03` (review cuối), `3fc9482` (hàng đợi Services và phím giả), `fcfea3c` (dọn plist test), `bf5549f` (re-export `KeyboardShortcuts`).
- **Test tự động:** MyNotchCore 105, NotchUI 77, Battery 23 theo báo cáo L1 (`verify.sh` qua ở `8a2b842`). Chưa chạy lại khi viết tài liệu này.
- **Kiểm thử tay:** [Nền tảng](../../manual-test-checklist-all.html#nen-tang) (34 mục, nguyên văn từ checklist cũ) và [Điểm nối nền tảng](../../manual-test-checklist-all.html#seams)

## 1. Đã xây gì so với spec

**Nền tảng (spec 0):**

- **MyNotchCore:** `FeatureModule`, `ModuleContext`, `ModuleRegistry` (vòng đời `disabled`, `starting`, `running`, `needsPermission`, `unavailable`, `failed`, cách ly lỗi giữa các module), `SettingsStore` và `ModuleSettings` (khoá `module.<id>.*`), `ActivityCenter` (ưu tiên và hết hạn), `HotkeyRegistry` bọc KeyboardShortcuts 3.1.0, `PermissionCenter`, `Scheduler` với `TaskScheduler` và `ManualScheduler`.
- **NotchUI:** `NotchGeometry` (notch thật và ảo), `NotchViewModel` (state machine `closed`, `compact`, `open`, ghim, kéo, toast), `FullscreenDetector`, `NotchPanel` mỗi màn một cái, `ScreenManager`, `NotchRootView`.
- **App:** menu bar (Open Settings…, Hide Notch, Pause All Modules, Quit MyNotch), Settings (General, Interface, Modules, About), khởi động cùng máy, phím tắt ⌃⌥N, `ModuleList.swift` là nơi duy nhất ghép module.
- **Battery:** module mẫu (activity sạc và pin yếu, tab, ngưỡng 5 đến 50%).
- **Công cụ:** `scripts/verify.sh` (`xcodegen generate`, `swift test` mọi package, `xcodebuild` Debug), `scripts/md2html.py`.

**Điểm nối 0.5 (A1 đến A4, B1 đến B6, đã triển khai đủ):** đóng notch khi click ngoài, tab nhận bàn phím (`acceptsKeyboard`), toast không phá tab đang mở, `NotchHandle` (`@Environment(\.notch)`), live activity cập nhật tại chỗ cộng `raise(id:)`, `ModuleStorage` và `StorageRoot`, `makeSettingsView(_:)` dùng được khi module tắt, `PermissionCenter.request` cùng `optionalPermissions`, `Scheduler` riêng cho module, `ModuleRegistry.shutdown()` khi thoát app. Cửa sổ Settings làm app hiện icon Dock khi mở.

**Điểm nối bổ sung sau spec 0.5 (mô tả ở ghi chú của module dùng nó):**

- `ServiceRegistry` và `ModuleServices` cho macOS Services, hàng đợi 10 giây ([Dịch](2026-10-14-translation-implementation.html)).
- Điểm nối thả file: `NotchTab.dropTypes` và `onDrop`, `DropRouting`, `NotchGeometry.dragHitRect` ([Khay](2026-10-14-shelf-implementation.html)).
- `LockScreenContentCenter`, `ModuleContext.lockScreen`, `SkyLightShim` ([Màn hình khoá](2026-10-14-lock-screen-implementation.html)).
- Nhúng `MediaRemoteAdapter.framework` và script perl, `App/MediaAdapterLocation.swift` ([Media](2026-10-14-media-implementation.html)); target `mynotch-hook` ([AI agents](2026-10-14-ai-agents-implementation.html)).
- `HotkeyBackend` tiêm được: `RegistryHarness` dùng bản giả trong bộ nhớ nên test module không đăng ký phím Carbon thật hay ghi mặc định KeyboardShortcuts; có `harness.hotkeyBackend.trigger(...)`.

## 2. Sai khác so với spec và lý do

Chi tiết A1 đến B6 đã nằm ở §6 của spec 0.5. Tóm tắt:

- **A1:** click vào bất kỳ cửa sổ nào khác của MyNotch (Settings, alert, menu) cũng tính là "ngoài notch"; module phải ghim notch khi mở UI phụ.
- **A2:** notch chỉ chiếm bàn phím khi được mở có chủ ý (click, phím tắt, module gọi `open(tab:)`), không khi mở do rê chuột. Toast che tab nhận bàn phím vẫn giữ bàn phím và chiều cao tab. Mất key window thì đóng như click ngoài (trừ khi ghim hoặc đang kéo). Esc đóng qua cả `cancelOperation` và `.onExitCommand`.
- **A3:** toast hết hạn quay lại tab qua cùng logic chọn tab như `open(tab:)`; tab bị che vẫn nằm trong cây view (ẩn) để giữ trạng thái.
- **B1:** `set` với id đã có giữ thứ tự (`sequence`); `Entry.revision` bảo vệ hết hạn khỏi hẹn giờ cũ.
- **B2, B5:** `context.scheduler` là scheduler riêng của module, huỷ mọi việc đã hẹn khi dừng (kể cả khi `start` lỗi).
- **B3:** `ModuleSettingsEnvironment` không có init public; test lấy qua `RegistryHarness.settingsEnvironment(for:)`.
- **B4:** `Permission.isSettingsOnly` (Accessibility, Screen Recording): `grant` luôn gọi `request` trước (để app có trong danh sách System Settings) rồi mới mở Settings nếu vẫn chưa có quyền; nút "Cấp quyền" bị khoá khi đang xin.
- **B6:** sau `shutdown()` mọi đường khởi động module (`bootstrap`, `setEnabled`, retry, `resumeAll`, `refreshPermissions`, `grant`) đều bị chặn.
- **Công cụ:** `verify.sh` dọn thư mục tạm `MyNotchTests-*` và plist `MyNotchTests.*` cũ hơn 15 phút, và tự xoá `.build` của package phụ thuộc khi danh sách file của MyNotchCore hoặc NotchUI đổi.
- **P10 (`fcfea3c`):** `makeIsolatedDefaults()` trả về `IsolatedUserDefaults`, tự xoá domain khi được giải phóng. Vì cfprefsd ghi lại plist rỗng sau khoảng 5 đến 8 giây, mỗi tiến trình test có một handler `atexit` chạy `sh -c 'sleep 20; rm -f <plist MyNotchTests>'` tách rời. `CaptureStore` nhận thumbnail `NSCache` tiêm được (sửa test chập chờn).

## 3. Giới hạn đã chấp nhận (Ruling)

Ledger không có dòng `Ruling:` riêng cho nền tảng (mục "Rulings" của nó còn ghi "none yet"). Các điểm sau đến từ ledger, handoff và báo cáo:

- **Ký ad-hoc.** App ký ad-hoc ("Sign to Run Locally"), nên macOS quên các quyền đã cấp mỗi lần build lại. Người dùng có chứng chỉ Apple Development nhưng thiếu chứng chỉ trung gian WWDR G3; xem README mục "Ký app" để chuyển. Chi phí: phải cấp lại quyền sau mỗi lần build.
- **Bản Debug ký ad-hoc không có cờ Hardened Runtime** (`runtime`) cho cả app lẫn helper (W1). Chưa kiểm bản Release.
- **Bộ quét plist của P10 chưa được review** và khá lạ (tiến trình `sh` tách rời chạy 20 giây). Gợi ý của ghi chú P10: cân nhắc xem chỉ `verify.sh` dọn có đủ không. Còn khoảng 921 plist cũ lúc ghi handoff; `verify.sh` xoá dần.
- **`RegistryHarness` để lại thư mục `MyNotchTests-<uuid>`** khi module tạo thư mục lưu trữ; bỏ qua ở vòng sửa H1/H3/H4, `verify.sh` dọn bù.
- **Info.plist khai báo sẵn nhưng chưa module nào dùng:** `NSAppleEventsUsageDescription`, `NSMicrophoneUsageDescription` (và entitlement tương ứng); và các case `Permission.automation` và `.microphone`. Thiếu usage description thì app crash khi xin quyền, nên khai báo trước; chưa có đường kích hoạt từ giao diện nên chưa kiểm được.

## 4. Khoảng trống đã biết

- Danh sách 34 mục kiểm thử tay của nền tảng chưa được người dùng điền kết quả (HANDOFF mục 3).
- A2 và A4 phụ thuộc AppKit key window nên chỉ kiểm bằng tay (các mục Clipboard trong checklist gộp).
- Nút "Cấp quyền" cho Automation và Microphone không có đường kích hoạt từ module nào; các luồng `request` còn lại (Accessibility, Screen Recording, Lịch, Lời nhắc, Bluetooth) chỉ chạy với module thật.
- `AgentSocket` ghi cứng bundle id `io.lucasvu.mynotch`; đổi bundle id của app phải đổi cả ở đó.
- Hộp thoại thật của macOS cho mọi quyền chưa được thử.

## 5. Sửa lại spec (Spec corrections)

Spec 0 (`foundation-design`):

- **Dòng trạng thái** "Đã duyệt thiết kế, chờ review spec": đã triển khai.
- **§4.3, `FeatureModule`**: `makeSettingsView()` thành `makeSettingsView(_ environment: ModuleSettingsEnvironment) -> AnyView?`. `ModuleContext` có thêm `storage`, `scheduler`, `services`, `lockScreen`. `ModuleDescriptor` có thêm `optionalPermissions`. `NotchTab` có thêm `acceptsKeyboard`, `dropTypes`, `onDrop`. `ModuleRegistry.init` nhận thêm `lockScreen`, `scheduler`, `storageRoot`, `services`.
- **§5.4, ưu tiên activity**: hoà thì "activity được thêm hoặc `raise` gần nhất thắng" (không còn "`set` gần nhất"); `set` lại một id giữ nguyên thứ tự.
- **§5.4, toast**: toast che tab đang mở thì quay lại đúng tab đó khi hết hạn.
- **§6.5, quyền**: `PermissionCenter` có `request(_:)`; Accessibility và Screen Recording là `isSettingsOnly`; câu "hiện là không có quyền nào" đã lỗi thời (Screenshot cần Screen Recording, Lịch cần Lịch, nhiều module có quyền tuỳ chọn).
- **§4.1, cây thư mục**: thêm `Tools/mynotch-hook`, `Vendor/mediaremote-adapter`, các package module khác.
- **§11, lộ trình**: tất cả dự án con 1 đến 9 đã triển khai; chụp cuộn (3c) không làm, và OCR chạy trong chính tiến trình app, không trong XPC helper.

Spec 0.5 (`platform-seams-design`): §6 của nó đã có ghi chú triển khai; thêm `Permission.isSettingsOnly` đã nằm ở §6 (B4). Thêm `HotkeyBackend` tiêm được và `ServiceRegistry` vào danh sách điểm nối.

## 6. Cần kiểm thử tay

Xem [Nền tảng](../../manual-test-checklist-all.html#nen-tang) và [Điểm nối nền tảng](../../manual-test-checklist-all.html#seams). Các mục đụng quyền: hộp thoại cấp quyền cho Accessibility, Screen Recording, Lịch, Bluetooth khi bấm "Cấp quyền" trong Settings.
