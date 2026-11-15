# MyNotch — Live activity hệ thống + HUD âm lượng (dự án con 7)

- **Ngày:** 2026-10-13
- **Trạng thái:** Thiết kế
- **Nguồn:** SDK macOS 26.5. Các API công khai đã được kiểm tra trên máy; API riêng chỉ ghi nhận, không dùng mặc định.

## 1. Mục tiêu

Một module "Hệ thống". Mỗi loại sự kiện bật/tắt riêng và hiện thành live activity ngắn (2–3 giây) bên cạnh notch. Activity cập nhật tại chỗ theo quy ước B1.

| Sự kiện | API | Quyền | Mặc định |
|---|---|---|---|
| Thiết bị Bluetooth kết nối/ngắt | `IOBluetoothDevice.register(forConnectNotifications:selector:)` + đăng ký ngắt cho từng thiết bị | Bluetooth (`NSBluetoothAlwaysUsageDescription`, đã có) | bật |
| Pin tai nghe/AirPods | Selector riêng `batteryPercentSingle/Left/Right/Case` của `IOBluetoothDevice`, chỉ gọi sau khi `responds(to:)` | như trên | bật; không có số liệu thì chỉ hiện tên thiết bị |
| Mạng có/mất, Wi-Fi ↔ dây | `NWPathMonitor` | không | bật |
| Caps Lock bật/tắt | Poll `CGEventSource.flagsState(.combinedSessionState)` 4 lần/giây qua `context.scheduler` (không cần quyền; theo dõi phím toàn cục thì cần Accessibility) | không | bật |
| Tải xuống xong (`~/Downloads`) | FSEvents theo file. Xong khi: file tạm `.download`/`.crdownload`/`.part` biến mất, file đích tồn tại với kích thước > 0, kích thước đứng yên 1 giây | Files & Folders → `NSDownloadsFolderUsageDescription` | bật |
| Âm lượng | Listener CoreAudio trên thiết bị ra mặc định (`VirtualMainVolume`, `Mute`), gắn lại khi đổi thiết bị | không | bật |

**HUD âm lượng:** chỉ hiện song song với HUD hệ thống (activity có thanh mức âm lượng), không chặn HUD hệ thống. Muốn chặn thì phải nuốt phím media bằng event tap, cần Accessibility và có rủi ro kẹt bàn phím, nên không làm.

**Ngoài phạm vi:**

- Focus: không có API công khai. Sau này có thể làm qua App Intents `SetFocusFilterIntent`.
- Tên Wi-Fi: cần quyền Vị trí.
- Độ sáng màn hình: chỉ có API riêng.
- Thay thế hoàn toàn HUD hệ thống.

## 2. Thiết kế

Package `Packages/Modules/SystemActivities`, product `SystemActivitiesModule`. Quyền bắt buộc: không có. Quyền tuỳ chọn: `.bluetooth`, `.downloadsFolder` (thêm case mới vào `Permission`, trạng thái kiểm tra bằng cách thử liệt kê thư mục).

| Thành phần | Vai trò |
|---|---|
| `BluetoothMonitor` | Kết nối/ngắt kết nối, loại thiết bị (tai nghe, bàn phím…), pin nếu có |
| `NetworkMonitor` | Trạng thái và loại kết nối; bỏ qua lần báo đầu tiên lúc khởi động |
| `CapsLockMonitor` | Poll; chỉ phát khi trạng thái đổi |
| `DownloadsWatcher` + `DownloadCompletionRule` (thuần) | Theo quy tắc ở trên, gom 300 ms, bỏ file ẩn |
| `VolumeMonitor` | Mức 0–1, tắt tiếng; bỏ qua thiết bị không có điều khiển âm lượng |
| `SystemActivitiesModule` | Tạo activity: icon + chữ ngắn, hoặc thanh mức cho âm lượng; mỗi loại một `id` cố định để cập nhật tại chỗ |

Mỗi monitor ẩn sau một protocol để test bằng nguồn giả.

### 2.1 Cài đặt (`module.systemactivities.*`)

Mỗi loại một toggle: `bluetooth`, `network`, `capsLock`, `downloads`, `volume`. Thêm `durationSeconds` (2.5, khoảng 1…6).

## 3. Kiểm thử

| Phần | Test tự động |
|---|---|
| `DownloadCompletionRule` | Safari, Chrome, Firefox (file giữ chỗ 0 byte), file ẩn, kích thước còn thay đổi |
| `CapsLockMonitor` | Nguồn cờ giả + ManualScheduler: chỉ phát khi đổi |
| `NetworkMonitor` | Chuỗi trạng thái giả: bỏ lần đầu, phát khi đổi |
| Module | Mỗi nguồn giả → đúng activity id, nội dung, thời gian hết hạn; toggle tắt thì không phát |

**Kiểm thử tay:** AirPods/tai nghe Bluetooth; rút cáp mạng hoặc tắt Wi-Fi; Caps Lock; tải file bằng Safari và Chrome; chỉnh âm lượng bằng phím.
