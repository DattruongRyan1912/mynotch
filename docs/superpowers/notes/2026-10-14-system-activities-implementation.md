# Ghi chú triển khai: Live activity hệ thống và âm lượng

- **Ngày:** 2026-10-14
- **Spec:** [Live activity hệ thống + HUD âm lượng (dự án con 7)](../specs/2026-10-13-system-activities-design.html). Spec không bị sửa; chỗ đã lỗi thời nằm ở mục "Sửa lại spec".
- **Package:** `Packages/Modules/SystemActivities`, product `SystemActivitiesModule`. **Module id là `system`** ("Hệ thống", order 700), không có tab, bật mặc định, không có quyền bắt buộc, quyền tuỳ chọn `.bluetooth` và (từ P11b, `335f489`) `.downloadsFolder`.
- **Commit chính:** `7bc718c` các monitor và nhận biết tải xong, `4aad00f` module, `956f5fb` sửa sau review (tải nhỏ, đọc lại pin), `e2b0586` gắn vào app (cùng Shortcuts, Timer, Shelf), `5552a84` đầu dò quyền Downloads và Bluetooth chạy ngoài main thread.
- **Test tự động:** 83 test theo báo cáo vòng sửa cuối (`fix-report`, `verify.sh` qua). Không chạm Bluetooth, CoreAudio hay thư mục Downloads thật trong test (có một thử nghiệm FSEvents thật trong thư mục tạm, đã xoá). Phần gọi IOBluetooth thật không có test tự động. Chưa chạy lại khi viết tài liệu này.
- **Kiểm thử tay:** [mục Hệ thống trong checklist gộp](../../manual-test-checklist-all.html#system-activities)

## 1. Đã xây gì so với spec

Mỗi loại sự kiện có công tắc riêng, hiện thành live activity ngắn bên cạnh notch (mỗi loại một `id` cố định, cập nhật tại chỗ, vừa 64 pt mỗi bên). Mọi monitor đứng sau protocol để test bằng nguồn giả.

- **Bluetooth** (`bluetooth`): `BluetoothMonitor` (IOBluetooth) báo kết nối và ngắt, loại thiết bị (tai nghe, bàn phím, chuột, khác), pin qua selector riêng `batteryPercentSingle/Left/Right/Case` chỉ gọi sau `responds(to:)`. Không hiện "đã kết nối" cho thiết bị đã kết nối từ trước khi monitor chạy. Pin chưa đọc được thì đọc lại sau 0,5, 1 và 2 giây (`BluetoothBatteryRetry`) để bản cập nhật rơi vào trong thời gian activity còn hiện. `start` trả về ngay; lệnh IOBluetooth đầu tiên (`pairedDevices()`, nơi hộp thoại quyền được cho là hiện) chạy ngoài main thread qua `@concurrent`, rồi `register()` (thông báo kết nối và ngắt, danh sách thiết bị đã ghép) chạy trên main actor vì `register(forConnectNotifications:)` cần run loop. `stop()` huỷ lần khởi động đang chờ.
- **Mạng** (`network`): `NWPathMonitor`, bỏ lần báo đầu, debounce 1 giây, "Đã kết nối" hoặc "Mất mạng". Mất mạng ưu tiên `.high` và không hết hạn cho tới khi có mạng lại.
- **Caps Lock** (`capslock`): poll `CGEventSource.flagsState` 4 lần mỗi giây, chỉ phát khi đổi, không cần quyền.
- **Tải xong** (`download`): FSEvents trên `~/Downloads` kèm `DownloadCompletionRule` (Safari `.download`, Chrome `.crdownload`, Firefox `.part` kèm file 0 byte), gom 300 ms, bỏ file ẩn và thư mục. `DownloadsWatching.start` là `async -> Bool`: một lần liệt kê thư mục (đầu dò) chạy trong `Task.detached`, rồi luồng FSEvents được tạo trên main actor, nên file đã có sẵn không sinh activity.
- **Âm lượng** (`volume`): listener CoreAudio trên thiết bị ra mặc định (`VirtualMainVolume`, `Mute`, thử kênh 1 nếu kênh chính không có mute), gắn lại khi đổi thiết bị; thanh mức và biểu tượng tắt tiếng. Chạy song song với HUD hệ thống, không chặn nó.
- **Cài đặt `module.system.*`:** `bluetooth`, `network`, `capsLock`, `downloads`, `volume` (đều true) và `durationSeconds` (2,5; từ 1 đến 6). Monitor chỉ chạy cho loại đang bật và khởi động lại khi công tắc đổi.

## 2. Sai khác so với spec và lý do

- **Id module là `system`, không phải `systemactivities`**, nên khoá là `module.system.*`. Brief là nguồn đúng, spec chưa được cập nhật.
- **Quyền tuỳ chọn `.bluetooth` và `.downloadsFolder`.** Lúc đầu không có case `Permission.downloadsFolder` trong Core; từ P11a (`37ec63d`) có (trạng thái `.unknown` vì macOS không cho kiểm trước mà không hỏi, yêu cầu bằng một lượt liệt kê thư mục ngoài main actor), và P11b khai báo nó cho SystemActivities kèm lý do "Báo khi file tải xong trong Downloads." (Bluetooth: "Hiện thiết bị Bluetooth vừa kết nối hoặc ngắt, kèm pin."); Ảnh chụp dùng chung hàng Downloads. Trang Quyền hiện cả hai. Thư mục Downloads vẫn do macOS tự hỏi khi bắt đầu theo dõi: `DownloadsWatcher.start()` liệt kê thư mục một lần trước khi tạo luồng FSEvents để ép hộp thoại xuất hiện, và trả về async (đầu dò chạy ngoài main thread). Hàng Downloads trên trang Quyền luôn xám "Chưa kiểm tra được" kể cả sau khi cho phép (Minor M4 hoãn của review P11a).
- **Quy tắc tải xong chặt hơn spec** (để file cũ có thuộc tính cách ly không bị coi là tải mới khi Gatekeeper, Spotlight hay đổi tên chạm vào): ứng viên chỉ có thuộc tính nguồn gốc (không thấy file tạm) phải có ngày file trong vòng khoảng 10 giây; ứng viên không bao giờ hoàn tất hết hạn sau 10 phút; `hadPartial` cũng được ghi khi file tạm chỉ được thấy lúc bị xoá (tải nhỏ đổi tên ngay trong một lô FSEvents); các bản đồ trạng thái có giới hạn.
- Bluetooth: `BluetoothConnectionTracker` ghi nhớ thiết bị đã thông báo (không thông báo lại khi macOS báo kết nối lặp), và mỗi lần đọc pin thay thế lần đọc trước của cùng thiết bị.
- Một loại khởi động lỗi (Downloads) chỉ được thử lại khi chính công tắc của nó đổi, không thử lại mỗi khi bất kỳ công tắc nào đổi.
- Không có tab (brief Y2 chốt "NO tab"), nên không xem lại được 5 tải xong gần nhất.

## 3. Giới hạn đã chấp nhận (Ruling)

- **Ruling cũ đã được thay: đầu dò quyền Downloads trên main thread.** Ledger ghi chấp nhận việc notch đơ trong lúc hộp thoại macOS đầu tiên mở (một lần, chỉ khi bật Downloads; chi phí nếu sai là vài giây đơ, cách sửa là `start` bất đồng bộ). Review cuối nâng nó thành Important cùng với đầu dò Bluetooth, và `5552a84` đã làm đúng cách sửa đó cho cả hai. Không còn là giới hạn; phần chưa kiểm chứng nằm ở mục 4.
- Spec còn ghi `module.systemactivities.*` và `.downloadsFolder`: gộp vào mục "Sửa lại spec" dưới đây.

Các mục đã bỏ qua trong vòng sửa (Minor): listener của `VolumeMonitor` giữ thiết bị đã gắn (chỉ hình thức); tham số `interval:` thừa của `CapsLockMonitor`; `CapsLockMonitor` thiếu `isolated deinit` (tick giữ `self` yếu); guard của callback FSEvents chỉ chặn sau `stop()`, chưa chặn callback đến sau khi watcher đã bị giải phóng (không dùng retain/release vì khi đó luồng giữ watcher và `deinit` không bao giờ chạy).

## 4. Khoảng trống đã biết

- Các mốc đọc pin lại 0,5, 1 và 2 giây là suy đoán từ review, chưa đo trên tai nghe thật.
- **Chưa xác minh phần Bluetooth của việc đưa đầu dò ra khỏi main thread.** Không ai chứng minh lệnh IOBluetooth nào gây hộp thoại. Nếu `pairedDevices()` không gây mà `register(forConnectNotifications:)` mới gây, notch vẫn đơ khi hộp thoại Bluetooth đầu tiên mở (không tệ hơn trước). Việc gọi IOBluetooth ngoài main thread cũng là giả định an toàn luồng chưa kiểm: cần thử nhiều lần khởi động. Một cổng chắc chắn hơn nếu cần: chờ `context.permissions.request(.bluetooth)` (hộp thoại CoreBluetooth không chặn) trước khi chạm IOBluetooth.
- Không có Focus (không có API công khai), tên Wi-Fi (cần quyền Vị trí), độ sáng (chỉ có API riêng), và không thay thế HUD hệ thống (muốn chặn phải nuốt phím media bằng event tap, cần Accessibility).
- Chưa có kết quả kiểm thử tay được ghi lại cho: tai nghe hay AirPods, rút cáp mạng, Caps Lock, tải file nhỏ bằng Safari, Chrome và Firefox, phím âm lượng, hộp thoại Downloads và Bluetooth lần đầu (notch và các monitor khác phải còn phản hồi trong lúc hộp thoại mở).
- Callback FSEvents chỉ được chặn sau `stop()`, không chặn callback đến sau khi watcher đã bị giải phóng; `DownloadsWatcher.stop()` một mình không huỷ lần khởi động đang chờ (người gọi phải huỷ task, module làm vậy).

## 5. Sửa lại spec (Spec corrections)

- **§2.1**: khoá cài đặt là `module.system.*` (không phải `module.systemactivities.*`).
- **§2, dòng quyền (cập nhật 2026-10-15)**: `.bluetooth` và `.downloadsFolder` là quyền tuỳ chọn (từ P11a có case `.downloadsFolder`; trạng thái `.unknown`, không kiểm bằng liệt kê thư mục); hộp thoại do đầu dò trong `start()` gây ra, và `start` của Downloads là `async` (đầu dò chạy ngoài main thread) còn của Bluetooth trả về ngay rồi gọi IOBluetooth ngoài main thread.
- **§1, bảng sự kiện, dòng tải xuống**: thêm các điều kiện tươi 10 giây, hết hạn 10 phút và ghi nhận file tạm bị xoá.
- **§1, dòng pin**: thêm đọc lại sau 0,5, 1 và 2 giây. **§2, hàng `NetworkMonitor`**: debounce 1 giây, mất mạng ưu tiên `.high` và không hết hạn.
- **§2, hàng `SystemActivitiesModule`**: id activity là `bluetooth`, `network`, `capslock`, `download`, `volume`.

## 6. Cần kiểm thử tay

Xem [mục Hệ thống trong checklist gộp](../../manual-test-checklist-all.html#system-activities). Các mục đụng quyền hoặc API riêng: Bluetooth (kèm selector pin riêng; hộp thoại lần đầu chưa được xác minh có làm notch đơ không), thư mục Downloads (reset TCC `SystemPolicyDownloadsFolder`).

## 7. Activity trong luật mới (2026-10-14 tối)

Volume, Bluetooth, mạng đã kết nối, Caps Lock và tải xong là `.normal` có hạn theo cài đặt, nên là **notice**: khi nhạc đang phát chúng chiếm notch trong thời gian hiển thị rồi nhạc quay lại, và nhạc nằm ở bubble đầu tiên trong lúc đó (trước đó cái mới nhất cùng ưu tiên thắng, nay là notice mới nhất thắng; xem [ghi chú nền tảng](2026-10-14-platform-foundation-implementation.html), mục 8). Mất mạng vẫn `.high` và không hết hạn. Không có thay đổi trong code module này cho việc đó.
