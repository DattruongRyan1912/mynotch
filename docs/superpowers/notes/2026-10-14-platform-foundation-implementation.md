# Ghi chú triển khai: Nền tảng và điểm nối nền tảng

- **Ngày:** 2026-10-14
- **Spec:** [Nền tảng (dự án con 0)](../specs/2026-10-13-foundation-design.html) và [Điểm nối nền tảng (dự án con 0.5)](../specs/2026-10-13-platform-seams-design.html) (spec 0.5 đã có mục "Ghi chú triển khai" riêng, §6; tài liệu này không lặp lại toàn bộ). Spec không bị sửa; chỗ đã lỗi thời nằm ở mục "Sửa lại spec".
- **Package:** `Packages/MyNotchCore` (kèm target `MyNotchTestSupport`), `Packages/NotchUI`, `Packages/Modules/Battery` (module mẫu, id `battery`, order 900), thư mục `App/`, `project.yml`, `scripts/`.
- **Commit chính:** nền tảng từ `04c5d16` (spec) tới `80225c0`; điểm nối 0.5: `ee6f4fa` (B1), `95eb95b` và `c134e8a` (B2, B5), `6884c77` (B3), `b3b861a` và `cf94688` (B4), `241bd5f` (B6), `5a54158` (A1, A3), `1c10ef5` và `8d01bf0` (A2, A4), `15dbd8b` và `50d4924` (Settings và Dock), `8b20c03` (review cuối), `3fc9482` (hàng đợi Services và phím giả), `fcfea3c` (dọn plist test), `bf5549f` (re-export `KeyboardShortcuts`). Sau review cuối: `2b613fe` (Services từ chối khi không ai xử lý), `009871c` (facade `ModulePresenter`), `2bb5fc1` (`ScratchFolders` cho test), `bd74589` (app chọn kho cài đặt và backend phím thật), `20aa4bd` (chỉnh nhỏ Settings và build), `9f2d14b` (`ModuleHotkeys.unregister`).
- **Test tự động:** MyNotchCore 119, NotchUI 77, Battery 23 theo các báo cáo vòng sửa cuối và `H3-fix2-report` (`verify.sh` qua sau mỗi đợt; Core 105 ở `8a2b842`, 114 sau `bd74589`, 119 sau `9f2d14b`). Chưa chạy lại khi viết tài liệu này.
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
- `HotkeyBackend` tiêm được: `RegistryHarness` dùng bản giả trong bộ nhớ nên test module không đăng ký phím Carbon thật hay ghi mặc định KeyboardShortcuts; có `harness.hotkeyBackend.trigger(...)`. Từ `bd74589` `SettingsStore` và `HotkeyRegistry` không còn tham số mặc định trỏ vào kho thật: `AppDelegate` truyền `SettingsStore(defaults: .standard)` và `HotkeyRegistry(backend: KeyboardShortcutsBackend())`, nên một test gọi nhầm `SettingsStore()` hay `HotkeyRegistry()` không chạm được cài đặt hay phím thật (biên dịch không qua).
- `ModulePresenter` (`009871c`): `context.presenter` là facade theo module do registry dựng cho từng context. Chỉ có `open()` (tab của chính module), `showToast` và `close`; cả ba không làm gì sau khi module dừng (`cancelAll()` vô hiệu nó như các facade khác). `NotchPresenter` vẫn là protocol phía coordinator. Hai chỗ gọi (Translation, Clipboard) đổi từ `open(tab: descriptor.id)` thành `open()`.
- `ModuleHotkeys.unregister(_:)` (`9f2d14b`, [Shortcuts](2026-10-14-shortcuts-implementation.html)) và `ServiceRegistry.finishStartup()` (`2b613fe`, [Dịch](2026-10-14-translation-implementation.html)).
- `ScratchFolders` trong `MyNotchTestSupport` (`2bb5fc1`): `reserve(label)` trả về đường dẫn `MyNotchTests-<label>-<uuid>` dưới thư mục tạm, `removeAll()` chạy từ `atexit`. `RegistryHarness.storageRoot` và các test Shelf, AgentOpener, LyricsService dùng nó. `IsolatedDefaults` từ chối tên suite có `/`.

## 2. Sai khác so với spec và lý do

Chi tiết A1 đến B6 đã nằm ở §6 của spec 0.5. Tóm tắt:

- **A1:** click vào bất kỳ cửa sổ nào khác của MyNotch (Settings, alert, menu) cũng tính là "ngoài notch"; module phải ghim notch khi mở UI phụ.
- **A2:** notch chỉ chiếm bàn phím khi được mở có chủ ý (click, phím tắt, module gọi `context.presenter.open()`), không khi mở do rê chuột. Toast che tab nhận bàn phím vẫn giữ bàn phím và chiều cao tab. Mất key window thì đóng như click ngoài (trừ khi ghim hoặc đang kéo). Esc đóng qua cả `cancelOperation` và `.onExitCommand`.
- **A3:** toast hết hạn quay lại tab qua cùng logic chọn tab như `open(tab:)`; tab bị che vẫn nằm trong cây view (ẩn) để giữ trạng thái.
- **B1:** `set` với id đã có giữ thứ tự (`sequence`); `Entry.revision` bảo vệ hết hạn khỏi hẹn giờ cũ.
- **B2, B5:** `context.scheduler` là scheduler riêng của module, huỷ mọi việc đã hẹn khi dừng (kể cả khi `start` lỗi).
- **B3:** `ModuleSettingsEnvironment` không có init public; test lấy qua `RegistryHarness.settingsEnvironment(for:)`.
- **B4:** `Permission.isSettingsOnly` (Accessibility, Screen Recording): `grant` luôn gọi `request` trước (để app có trong danh sách System Settings) rồi mới mở Settings nếu vẫn chưa có quyền; nút "Cấp quyền" bị khoá khi đang xin.
- **B6:** sau `shutdown()` mọi đường khởi động module (`bootstrap`, `setEnabled`, retry, `resumeAll`, `refreshPermissions`, `grant`) đều bị chặn.
- **Công cụ:** `verify.sh` dọn thư mục tạm `MyNotchTests-*` và plist `MyNotchTests.*` cũ hơn 15 phút, và tự xoá `.build` của package phụ thuộc khi danh sách file của MyNotchCore hoặc NotchUI đổi. Từ `2bb5fc1` test tự xoá thư mục tạm khi tiến trình thoát (đã đo: không còn `MyNotchTests-*`, `MyNotchShelfTests-*`, `AgentOpenerTests-*`, `LyricsServiceTests-*` mới sau một lần chạy), nên bộ quét của `verify.sh` chỉ còn phục vụ lần chạy bị crash. Cả hai chỉ quét thứ chưa đụng tới 15 phút.
- **Sau review cuối (`20aa4bd`, `bd74589`):** cửa sổ Settings đã thu nhỏ được khôi phục (`deminiaturize`); công tắc khởi động cùng máy tính cả `.requiresApproval` (hiện bật và tắt được); module bị tạm dừng hiện "Tạm dừng" thay cho "Đã tắt"; nút "Cấp quyền" có nhãn trợ năng `Cấp quyền <quyền>`; `GCC_WARN_UNUSED_VARIABLE: NO` riêng cho target MediaRemoteAdapter (file vendor `get.m` có biến không dùng; build không còn cảnh báo).
- **P10 (`fcfea3c`):** `makeIsolatedDefaults()` trả về `IsolatedUserDefaults`, tự xoá domain khi được giải phóng. Vì cfprefsd ghi lại plist rỗng sau khoảng 5 đến 8 giây, mỗi tiến trình test có một handler `atexit` chạy `sh -c 'sleep 20; rm -f <plist MyNotchTests>'` tách rời. `CaptureStore` nhận thumbnail `NSCache` tiêm được (sửa test chập chờn).

## 3. Giới hạn đã chấp nhận (Ruling)

Ledger không có dòng `Ruling:` riêng cho nền tảng (mục "Rulings" của nó còn ghi "none yet"). Các điểm sau đến từ ledger, handoff và báo cáo:

- **Ký ad-hoc.** App ký ad-hoc ("Sign to Run Locally"), nên macOS quên các quyền đã cấp mỗi lần build lại. Người dùng có chứng chỉ Apple Development nhưng thiếu chứng chỉ trung gian WWDR G3; xem README mục "Ký app" để chuyển. Chi phí: phải cấp lại quyền sau mỗi lần build.
- **Bản Debug ký ad-hoc không có cờ Hardened Runtime** (`runtime`) cho cả app lẫn helper (W1). Chưa kiểm bản Release.
- **Bộ quét plist của P10 chưa được review** và khá lạ (tiến trình `sh` tách rời chạy 20 giây). Gợi ý của ghi chú P10: cân nhắc xem chỉ `verify.sh` dọn có đủ không. Còn khoảng 921 plist cũ lúc ghi handoff; `verify.sh` xoá dần.
- **Info.plist khai báo sẵn nhưng chưa module nào dùng:** `NSAppleEventsUsageDescription`, `NSMicrophoneUsageDescription` (và entitlement tương ứng); và các case `Permission.automation` và `.microphone`. Thiếu usage description thì app crash khi xin quyền, nên khai báo trước; chưa có đường kích hoạt từ giao diện nên chưa kiểm được. Review tích hợp ghi đây là bề mặt quyền thừa vô hại (chuỗi Apple Events hứa "điều khiển trình phát nhạc"); giữ, không cắt.
- **Entitlement do Xcode chèn (review tích hợp, Minor, hoãn):** bản Release app mang `get-task-allow` và helper mang thêm `com.apple.application-identifier`. Ký ad-hoc vẫn chạy (helper thoát mã 0). Đường ký Apple Development của README chưa được thử: một entitlement bị hạn chế mà không có profile trên một công cụ dòng lệnh có thể bị từ chối; cách sửa là `CODE_SIGN_INJECT_BASE_ENTITLEMENTS: NO`, rồi chạy helper một lần sau khi đổi danh tính.
- **Ruling (Services):** từ chối yêu cầu Services không ai xử lý chỉ áp dụng sau giai đoạn khởi động; khởi động nguội qua Service khi module Dịch tắt vẫn im lặng. Xem [ghi chú Dịch](2026-10-14-translation-implementation.html).

## 4. Khoảng trống đã biết

- Danh sách 34 mục kiểm thử tay của nền tảng chưa được người dùng điền kết quả (HANDOFF mục 3).
- A2 và A4 phụ thuộc AppKit key window nên chỉ kiểm bằng tay (các mục Clipboard trong checklist gộp).
- Nút "Cấp quyền" cho Automation và Microphone không có đường kích hoạt từ module nào; các luồng `request` còn lại (Accessibility, Screen Recording, Lịch, Lời nhắc, Bluetooth) chỉ chạy với module thật.
- `AgentSocket` ghi cứng bundle id `io.lucasvu.mynotch`; đổi bundle id của app phải đổi cả ở đó.
- Hộp thoại thật của macOS cho mọi quyền chưa được thử.
- Các Minor của review cuối đã hoãn (không có Critical hay Important còn lại): tab đang mở biến mất khi module của nó dừng trong lúc notch được ghim hoặc đang kéo (`state` giữ id cũ, ghim không được nhả); panel bị ẩn vẫn giữ cây activity (chưa đo); quy tắc "app chuyển `.regular`" lặp ở ba chỗ (Settings, trình cài ngôn ngữ, trình sửa ảnh) và `ShelfModule` kích hoạt app cho AirDrop không trả focus; `ModuleError.needsPermission` ném từ `start` bị thử lại mỗi 2 giây và không có hàng cấp quyền nếu quyền không nằm trong `descriptor.permissions` (không module nào dùng); mọi module đọc được view màn hình khoá của module khác qua `LockScreenContentCenter` (chỉ LockScreen cần); `NotchHoverTracker.stop()`, `FullscreenDetector.stop()`, `raise` không có chỗ gọi ngoài test; VoiceOver không mở được notch trừ bằng phím tắt (hình root không có nhãn hay hành động); các khoảng giá trị giao diện lặp ở ba nơi.
- Bản sao tạo khi kéo thẻ Clipboard hoặc Screenshot ra ngoài nằm trong thư mục tạm lâu hơn nút "xoá lịch sử" (xem hai ghi chú đó).

## 5. Sửa lại spec (Spec corrections)

Spec 0 (`foundation-design`):

- **Dòng trạng thái** "Đã duyệt thiết kế, chờ review spec": đã triển khai.
- **§4.3, `FeatureModule`**: `makeSettingsView()` thành `makeSettingsView(_ environment: ModuleSettingsEnvironment) -> AnyView?`. `ModuleContext` có thêm `storage`, `scheduler`, `services`, `lockScreen`. `ModuleDescriptor` có thêm `optionalPermissions`. `NotchTab` có thêm `acceptsKeyboard`, `dropTypes`, `onDrop`. `ModuleRegistry.init` nhận thêm `lockScreen`, `scheduler`, `storageRoot`, `services`.
- **§4.3, `ModuleContext.presenter`**: kiểu `ModulePresenter` (không phải `NotchPresenter` dùng chung): `open()` thay cho `open(tab:)`, chỉ mở tab của chính module, và `showToast`, `close`; vô hiệu sau khi module dừng. `context.hotkeys` có thêm `unregister(_:)` theo tên.
- **§4, `SettingsStore` và `HotkeyRegistry`**: không còn khởi tạo mặc định; truyền `defaults:` và `backend:` rõ ràng (app dùng `.standard` và `KeyboardShortcutsBackend()`).
- **§5.5, ẩn khi fullscreen**: spec ghi panel của màn fullscreen chuyển `alphaValue = 0`; code `orderOut` panel cùng `ignoresMouseEvents = true` (`NotchWindowController.setVisible`), không đặt `alphaValue`. Comment trong code khớp code.
- **§5.4, ưu tiên activity**: hoà thì "activity được thêm hoặc `raise` gần nhất thắng" (không còn "`set` gần nhất"); `set` lại một id giữ nguyên thứ tự.
- **§5.4, toast**: toast che tab đang mở thì quay lại đúng tab đó khi hết hạn.
- **§6.5, quyền**: `PermissionCenter` có `request(_:)`; Accessibility và Screen Recording là `isSettingsOnly`; câu "hiện là không có quyền nào" đã lỗi thời (Screenshot cần Screen Recording, Lịch cần Lịch, nhiều module có quyền tuỳ chọn).
- **§4.1, cây thư mục**: thêm `Tools/mynotch-hook`, `Vendor/mediaremote-adapter`, các package module khác.
- **§11, lộ trình**: tất cả dự án con 1 đến 9 đã triển khai; chụp cuộn (3c) không làm, và OCR chạy trong chính tiến trình app, không trong XPC helper.

Spec 0.5 (`platform-seams-design`): §6 của nó đã có ghi chú triển khai; thêm `Permission.isSettingsOnly` đã nằm ở §6 (B4). Thêm `HotkeyBackend` tiêm được và `ServiceRegistry` vào danh sách điểm nối.

## 6. Cần kiểm thử tay

Xem [Nền tảng](../../manual-test-checklist-all.html#nen-tang) và [Điểm nối nền tảng](../../manual-test-checklist-all.html#seams). Các mục đụng quyền: hộp thoại cấp quyền cho Accessibility, Screen Recording, Lịch, Bluetooth khi bấm "Cấp quyền" trong Settings.
