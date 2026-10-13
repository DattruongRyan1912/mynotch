# Ghi chú triển khai: Live activity hệ thống và âm lượng

- **Ngày:** 2026-10-14
- **Spec:** [Live activity hệ thống + HUD âm lượng (dự án con 7)](../specs/2026-10-13-system-activities-design.html). Spec không bị sửa; chỗ đã lỗi thời nằm ở mục "Sửa lại spec".
- **Package:** `Packages/Modules/SystemActivities`, product `SystemActivitiesModule`. **Module id là `system`** ("Hệ thống", order 700), không có tab, bật mặc định, không có quyền bắt buộc, quyền tuỳ chọn `.bluetooth`.
- **Commit chính:** `7bc718c` các monitor và nhận biết tải xong, `4aad00f` module, `956f5fb` sửa sau review, `e2b0586` gắn vào app (cùng Shortcuts, Timer, Shelf).
- **Test tự động:** 77 test theo báo cáo `Y-fix-report` và báo cáo L1 (`verify.sh` qua ở `8a2b842`). Không chạm Bluetooth, CoreAudio hay thư mục Downloads thật trong test (có một thử nghiệm FSEvents thật trong thư mục tạm, đã xoá). Chưa chạy lại khi viết tài liệu này.
- **Kiểm thử tay:** [mục Hệ thống trong checklist gộp](../../manual-test-checklist-all.html#system-activities)

## 1. Đã xây gì so với spec

Mỗi loại sự kiện có công tắc riêng, hiện thành live activity ngắn bên cạnh notch (mỗi loại một `id` cố định, cập nhật tại chỗ, vừa 64 pt mỗi bên). Mọi monitor đứng sau protocol để test bằng nguồn giả.

- **Bluetooth** (`bluetooth`): `BluetoothMonitor` (IOBluetooth) báo kết nối và ngắt, loại thiết bị (tai nghe, bàn phím, chuột, khác), pin qua selector riêng `batteryPercentSingle/Left/Right/Case` chỉ gọi sau `responds(to:)`. Không hiện "đã kết nối" cho thiết bị đã kết nối từ trước khi monitor chạy. Pin chưa đọc được thì đọc lại sau 0,5, 1 và 2 giây (`BluetoothBatteryRetry`) để bản cập nhật rơi vào trong thời gian activity còn hiện.
- **Mạng** (`network`): `NWPathMonitor`, bỏ lần báo đầu, debounce 1 giây, "Đã kết nối" hoặc "Mất mạng". Mất mạng ưu tiên `.high` và không hết hạn cho tới khi có mạng lại.
- **Caps Lock** (`capslock`): poll `CGEventSource.flagsState` 4 lần mỗi giây, chỉ phát khi đổi, không cần quyền.
- **Tải xong** (`download`): FSEvents trên `~/Downloads` kèm `DownloadCompletionRule` (Safari `.download`, Chrome `.crdownload`, Firefox `.part` kèm file 0 byte), gom 300 ms, bỏ file ẩn và thư mục.
- **Âm lượng** (`volume`): listener CoreAudio trên thiết bị ra mặc định (`VirtualMainVolume`, `Mute`, thử kênh 1 nếu kênh chính không có mute), gắn lại khi đổi thiết bị; thanh mức và biểu tượng tắt tiếng. Chạy song song với HUD hệ thống, không chặn nó.
- **Cài đặt `module.system.*`:** `bluetooth`, `network`, `capsLock`, `downloads`, `volume` (đều true) và `durationSeconds` (2,5; từ 1 đến 6). Monitor chỉ chạy cho loại đang bật và khởi động lại khi công tắc đổi.

## 2. Sai khác so với spec và lý do

- **Id module là `system`, không phải `systemactivities`**, nên khoá là `module.system.*`. Brief là nguồn đúng, spec chưa được cập nhật.
- **Chỉ có quyền tuỳ chọn `.bluetooth`.** Không có case `Permission.downloadsFolder` trong Core. Thư mục Downloads do macOS tự hỏi khi bắt đầu theo dõi; `DownloadsWatcher.start()` liệt kê thư mục một lần trước khi tạo luồng FSEvents để ép hộp thoại xuất hiện, và trả về false khi bị từ chối (ghi log "Downloads folder cannot be watched").
- **Quy tắc tải xong chặt hơn spec** (để file cũ có thuộc tính cách ly không bị coi là tải mới khi Gatekeeper, Spotlight hay đổi tên chạm vào): ứng viên chỉ có thuộc tính nguồn gốc (không thấy file tạm) phải có ngày file trong vòng khoảng 10 giây; ứng viên không bao giờ hoàn tất hết hạn sau 10 phút; `hadPartial` cũng được ghi khi file tạm chỉ được thấy lúc bị xoá (tải nhỏ đổi tên ngay trong một lô FSEvents); các bản đồ trạng thái có giới hạn.
- Bluetooth: `BluetoothConnectionTracker` ghi nhớ thiết bị đã thông báo (không thông báo lại khi macOS báo kết nối lặp), và mỗi lần đọc pin thay thế lần đọc trước của cùng thiết bị.
- Một loại khởi động lỗi (Downloads) chỉ được thử lại khi chính công tắc của nó đổi, không thử lại mỗi khi bất kỳ công tắc nào đổi.
- Không có tab (brief Y2 chốt "NO tab"), nên không xem lại được 5 tải xong gần nhất.

## 3. Giới hạn đã chấp nhận (Ruling)

- **Đầu dò quyền Downloads chạy trên main thread.** Notch bị đơ trong lúc hộp thoại đầu tiên của macOS đang mở. Chấp nhận: chỉ một lần, chỉ khi người dùng bật Downloads. **Cần người kiểm tra** (reset TCC, thử Cho phép và Không cho phép). **Chi phí nếu sai:** vài giây notch đơ ở lần bật đầu tiên; cách sửa là `start` bất đồng bộ.
- Spec còn ghi `module.systemactivities.*` và `.downloadsFolder`: gộp vào mục "Sửa lại spec" dưới đây.

Các mục đã bỏ qua trong vòng sửa (Minor): listener của `VolumeMonitor` giữ thiết bị đã gắn (chỉ hình thức); tham số `interval:` thừa của `CapsLockMonitor`; `CapsLockMonitor` thiếu `isolated deinit` (tick giữ `self` yếu); guard của callback FSEvents chỉ chặn sau `stop()`, chưa chặn callback đến sau khi watcher đã bị giải phóng (không dùng retain/release vì khi đó luồng giữ watcher và `deinit` không bao giờ chạy).

## 4. Khoảng trống đã biết

- Các mốc đọc pin lại 0,5, 1 và 2 giây là suy đoán từ review, chưa đo trên tai nghe thật.
- Không có Focus (không có API công khai), tên Wi-Fi (cần quyền Vị trí), độ sáng (chỉ có API riêng), và không thay thế HUD hệ thống (muốn chặn phải nuốt phím media bằng event tap, cần Accessibility).
- Chưa có kết quả kiểm thử tay được ghi lại cho: tai nghe hay AirPods, rút cáp mạng, Caps Lock, tải file nhỏ bằng Safari, Chrome và Firefox, phím âm lượng, hộp thoại Downloads.

## 5. Sửa lại spec (Spec corrections)

- **§2.1**: khoá cài đặt là `module.system.*` (không phải `module.systemactivities.*`).
- **§2, dòng quyền**: chỉ `.bluetooth` là quyền tuỳ chọn; không thêm case `.downloadsFolder` vào `Permission` và không kiểm trạng thái bằng liệt kê thư mục; hộp thoại do đầu dò `start()` gây ra.
- **§1, bảng sự kiện, dòng tải xuống**: thêm các điều kiện tươi 10 giây, hết hạn 10 phút và ghi nhận file tạm bị xoá.
- **§1, dòng pin**: thêm đọc lại sau 0,5, 1 và 2 giây. **§2, hàng `NetworkMonitor`**: debounce 1 giây, mất mạng ưu tiên `.high` và không hết hạn.
- **§2, hàng `SystemActivitiesModule`**: id activity là `bluetooth`, `network`, `capslock`, `download`, `volume`.

## 6. Cần kiểm thử tay

Xem [mục Hệ thống trong checklist gộp](../../manual-test-checklist-all.html#system-activities). Các mục đụng quyền hoặc API riêng: Bluetooth (kèm selector pin riêng), thư mục Downloads (reset TCC `SystemPolicyDownloadsFolder`).
