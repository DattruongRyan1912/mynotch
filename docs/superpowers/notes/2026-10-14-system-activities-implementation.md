# Ghi chú triển khai: Live activity hệ thống và âm lượng

- **Ngày:** 2026-10-14
- **Spec:** [Live activity hệ thống + HUD âm lượng (dự án con 7)](../specs/2026-10-13-system-activities-design.html). Spec không bị sửa; chỗ đã lỗi thời nằm ở mục "Sửa lại spec".
- **Package:** `Packages/Modules/SystemActivities`, product `SystemActivitiesModule`. **Module id là `system`** ("Hệ thống", order 700), không có tab, bật mặc định, không có quyền bắt buộc, quyền tuỳ chọn `.bluetooth` và (từ P11b, `335f489`) `.downloadsFolder`.
- **Commit chính:** `7bc718c` các monitor và nhận biết tải xong, `4aad00f` module, `956f5fb` sửa sau review (tải nhỏ, đọc lại pin), `e2b0586` gắn vào app (cùng Shortcuts, Timer, Shelf), `5552a84` đầu dò quyền Downloads và Bluetooth chạy ngoài main thread.
- **Test tự động:** 83 test theo báo cáo vòng sửa cuối (`fix-report`, `verify.sh` qua). Không chạm Bluetooth, CoreAudio hay thư mục Downloads thật trong test (có một thử nghiệm FSEvents thật trong thư mục tạm, đã xoá). Phần gọi IOBluetooth thật không có test tự động. Chưa chạy lại khi viết tài liệu này.
- **Kiểm thử tay:** [mục Hệ thống trong checklist gộp](../../manual-test-checklist-all.html#system-activities)
- **Cập nhật sau `034e40d` (2026-10-16):** đọc được trên kính sáng và tối: activity không còn truyền `.white` lúc publish (S2 `a62ec60`; mục 9). SystemActivities 218 test. Cổ điển giữ nguyên từng điểm ảnh; cổng `verify.sh` chưa chạy cho commit này (xanh gần nhất ở `6077497`, trước nhiều commit S2). Chưa ai thấy trên kính thật.
- **Cập nhật sau `156f02d` (2026-10-15):** thay HUD âm lượng, độ sáng và đèn bàn phím của macOS (`679ff00`, `1d2de52`) (mục 8). SystemActivities 215 test. Chưa tạo event tap thật và chưa nhìn bằng mắt.

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

## 8. Từ `156f02d` đến hết 2026-10-15: thay HUD âm lượng, độ sáng và đèn bàn phím của macOS (R2c)

Commit `679ff00`, vòng sửa 1 `1d2de52`. Test: SystemActivities **215 test trong 21 suite** (84 trước R2c, 170 sau commit đầu), ba lần chạy sạch, 0 cảnh báo; re-review r1: Approved, 13 trên 14 đột biến (mutation) bị bắt. **Chưa bao giờ tạo một event tap thật và chưa nhìn bằng mắt**; các đường CoreAudio, DisplayServices và CoreBrightness thật chỉ được thăm dò **chỉ đọc** ngoài test (đọc được âm lượng, độ sáng màn hình trong, đèn bàn phím; mỗi lần ghi là giá trị vừa đọc được ghi lại nên không có gì đổi).

### 8.1 Cái gì

- **Cài đặt "Thay HUD của macOS"** (`module.system.replaceHUD`, mặc định **tắt**) với ba công tắc con **"Âm lượng"**, **"Độ sáng"**, **"Đèn bàn phím"** (`hudVolume`, `hudBrightness`, `hudKeyboardLight`, mặc định bật, chỉ hiện khi công tắc chính bật). Công tắc chính tắt thì không đổi gì: bộ theo dõi âm lượng vẫn báo thay đổi và HUD của macOS vẫn hiện.
- **Phím âm lượng** ±1/16 (⌥⇧ thì 1/64, mịn hơn), phím tắt tiếng bật tắt tắt-tiếng và giữ mức; phím âm lượng khi đang tắt tiếng thì bỏ tắt tiếng (như hệ thống). **Độ sáng** và **đèn bàn phím** ±1/16 hay 1/64; phím bật tắt đèn bàn phím về 0 rồi về mức trước đó (về mức đầy nếu không nhớ). Chỉ màn hình trong của máy (không có khi gập nắp hay máy để bàn).
- **Thanh của MyNotch:** activity `volume`, `brightness`, `keyboardLight` cùng một dáng (glyph cùng `LevelBar` mảnh; `sun.min.fill` và `sun.max.fill` cho độ sáng, `light.min` khi 0 và `light.max` cho đèn), hiện **1,5 giây cố định** (`MediaKeyHUD.displayDuration`; không dùng "Hiện trong N giây" của module), cập nhật tại chỗ theo id. Cả nhấn và nhả của một phím đã bật đều bị nuốt; chỉ nhấn (kể cả lặp tự động) mới thực hiện; các công tắc con được đọc ở mỗi lần nhấn nên có hiệu lực ngay, không cài lại tap. **Một phím có điều khiển không có thì không bao giờ bị nuốt** (không màn hình trong, không đèn bàn phím, thiết bị không có âm lượng hay tắt tiếng, một ký hiệu hay lớp riêng đã biến mất). Phím play/pause/next/previous không bao giờ là của ta (là của module Media).
- **Quyền:** `Permission.accessibility` thêm vào `optionalPermissions` của descriptor với lý do "Bắt phím âm lượng, độ sáng và đèn bàn phím để hiện thanh của MyNotch thay cho HUD của macOS." (tuỳ chọn nên không chặn khởi động và không kích hoạt chấm nhắc trên menu bar). **Không có Accessibility thì không có tap nào** (không cả một lần thử), nên mọi phím vẫn của hệ thống; HUD thử lại mỗi 2 giây trên scheduler của module nên cấp quyền xong tự bật không cần chạy lại; tap bị từ chối cũng thử lại như vậy. Dòng gợi ý "Cần quyền Accessibility" và nút "Cấp quyền" nằm ở hàng cài đặt dưới công tắc (module không có tab), đọc quyền không gây hộp thoại, nhắc lại mỗi 2 giây khi hàng hiện, và tự mất khi đã cấp.
- **Các file chính:** `MediaKeyEvent` (8 phím từ hằng `NX_KEYTYPE_*` của `IOKit.hidsystem`; subtype 8, mã phím ở nửa cao của `data1`, trạng thái 0xA và 0xB, bit lặp), `LevelStep` (bước tới đường lưới kế theo hướng bấm, kẹp 0 đến 1, có dung sai cho Float32 lệch một chút), `MediaKeyControls` (các giao thức `EventTapping`, `LevelControlling`, `VolumeControlling`), `MediaKeyHUD` (bộ điều khiển), `SystemEventTap` (`CGEvent.tapCreate(.cgSessionEventTap, .headInsertEventTap, .defaultTap)` chỉ cho `NX_SYSDEFINED`, trên run loop chính), `SystemVolumeControl` và `CoreAudioOutput` (rút ra từ `VolumeMonitor`, hành vi không đổi), `DisplayServicesBrightness` (`DisplayServicesGetBrightness` và `SetBrightness` qua `dlopen`/`dlsym`, lười), `CoreBrightnessKeyboardLight` (`KeyboardBrightnessClient` tra lúc chạy), `MediaKeyAccessibility`.

### 8.2 Ruling và quyết định (kèm chi phí nếu sai)

- **Ruling (review R2c I1): callback của tap chỉ quyết định.** Bản đầu chạm CoreAudio, DisplayServices, CoreBrightness, `dlopen` ngay trong callback (trên main); lần chậm làm macOS vô hiệu hoá tap hay đơ phím. Nay callback chỉ giải mã sự kiện, đọc công tắc con, nhìn một **bộ nhớ đệm** `MediaKeyAvailability` (âm lượng, tắt tiếng, độ sáng, đèn bàn phím) rồi trả về; một test ghim: sau một lần nhấn các bản giả có 0 lần đọc và ghi mà phím vẫn bị nuốt. Việc thật nằm ở `MediaKeyHardware` trên một hàng đợi nối tiếp (`SerialHardwareQueue`, `userInitiated`), kết quả quay về main theo thứ tự; HUD bỏ câu trả lời của lần chạy cũ (bộ đếm `run`). Bộ nhớ đệm bắt đầu rỗng (không nuốt gì) và được điền bằng `probe()` trên hàng đợi khi tap lên, rồi làm mới khi đổi thiết bị đầu ra mặc định, đổi tham số màn hình, máy thức dậy (`HardwareChangeNotifier`), và qua kiểm tra 10 giây (`checkInterval`), không bao giờ ở mỗi lần nhấn; không có tap thì không probe và không nghe.
- **Nhả và lặp ghép đôi:** `held[key]` ghi quyết định của mỗi lần nhấn; lần lặp dùng lại, lần nhả lấy đi (chỉ bị nuốt nếu lần nhấn của nó bị nuốt). Nhả hay lặp không có lần nhấn thì coi như nhấn, hay (nhả) cho qua.
- **Giới hạn cố hữu:** một lỗi mà bộ nhớ đệm chưa biết (thiết bị rút ra từ lần nhìn cuối, một lần ghi bị từ chối) trả về `.failed(loại)`: HUD không hiện gì và từ lần nhấn sau trả loại đó cho hệ thống tới lần nhìn kế. **Lần nhấn phát hiện ra lỗi đã bị nuốt rồi và mất** (không thể kích HUD của hệ thống lại nếu không gửi sự kiện giả). Chi phí: một lần nhấn mất khi rút một thiết bị âm thanh trong lúc HUD bật.
- **Sức khoẻ của tap (M2):** `EventTapping.isAlive`; mỗi 10 giây khi tap lên: không còn tin cậy thì bỏ tap và chờ quyền; không sống thì `reenable()`; vẫn không sống thì tạo lại. Sau `.disabled` rồi bật lại, bộ nhớ phím đang giữ được giữ (một lần nhả của lần nhấn đã nuốt vẫn bị nuốt); tap tạo lại bắt đầu không có gì.
- **Tắt thì xoá cả ba thanh (M4):** `Kind` có danh sách `shows`; loại HUD xoá `volume`, `brightness`, `keyboardLight` (trước đó chúng ở lại tới khi hết hạn). Một câu trả lời muộn từ hàng đợi sau khi tắt không hiện gì.
- **Phím cùng ⌘ hay ⌃ đi qua nguyên vẹn** (nhấn, lặp, nhả): `MediaKeyEvent.init?` trả nil (nhân bản màn hình, điều khiển màn ngoài). ⌥ một mình vẫn là một bước thường (hệ thống sẽ mở pane Âm thanh hay Màn hình với ⌥ cộng phím: không tái hiện). Các bit phụ thuộc thiết bị (0xA00) không đọc là phím sửa.
- **Chống dội (echo):** khi HUD đặt âm lượng, bộ theo dõi âm lượng có sẵn báo cùng thay đổi một lát sau và sẽ `set` lại activity `volume` với 2,5 giây (thanh thành 2,5 giây thay vì 1,5); `MediaKeyHUD.isEcho(_:)` nhớ trạng thái vừa đặt và bỏ báo cáo đúng trạng thái đó. Mọi trạng thái khác được công bố như cũ.
- **Hiển thị theo màn hình là của app, không phải module này:** activity không có đích theo màn hình; nó hiện trên notch mà chế độ màn hình cho phép (mặc định "Tất cả màn hình"; "Màn hình chính" thì chỉ màn chính; "Màn hình đang dùng" thì chỉ màn con trỏ). Nên "trên màn hình đang có con trỏ" đúng với `all` và đang dùng, không đúng với `main`.
- **Tắt tiếng trên thiết bị không có tắt tiếng:** cho phím đi qua hệ thống (nhấn và nhả) thay vì giả.
- **Chưa làm (Minor hoãn):** M3 (thiết bị làm tròn mức ghi theo lưới riêng, ví dụ Bluetooth 128 bước, có thể làm một lần nhấn kẹt trên cùng một đường và làm hỏng so khớp echo; sửa nếu một thiết bị thể hiện ở `MediaKeyHardware.moveVolume`), M7 (`State(initialValue:)` ở hàng cài đặt, không cài tap khi cả ba công tắc con tắt: callback giờ rẻ nên chi phí chỉ là một lần giải mã và ba lần đọc cài đặt cho mỗi sự kiện hệ thống). Mức "trước lúc bật tắt" của đèn bàn phím không còn bị đặt lại khi HUD dừng (vô hại).

### 8.3 Cần kiểm thử tay

Xem [mục Hệ thống trong checklist gộp](../../manual-test-checklist-all.html#system-activities) (nhóm **Thay HUD của macOS**): bật công tắc, cấp Accessibility (hàng "Cần quyền" tự mất sau vài giây, tap tự bật không cần chạy lại); phím âm lượng, tắt tiếng, độ sáng, đèn bàn phím có HUD của macOS **không** hiện và thanh của MyNotch hiện 1,5 giây, giữ phím thì cập nhật mượt, ngay sau khi máy thức dậy hay đổi thiết bị đầu ra; từng công tắc con trả phím lại cho macOS ngay; tắt công tắc hay bỏ MyNotch khỏi Accessibility khi đang chạy không có phím kẹt hay mất; đầu ra không có âm lượng (một số màn HDMI); ⌘ hay ⌃ với phím độ sáng; gập nắp và cắm màn ngoài; chế độ màn hình "Màn hình chính". Quyền: Accessibility (đặt lại bằng `tccutil reset Accessibility io.lucasvu.mynotch`).

## 9. Đọc được trên kính sáng và tối (S2 `a62ec60`, 2026-10-16)

Quy tắc chung và hai thứ S2 thêm vào NotchUI (`NotchTokens.fill(_:)` và `View.notchColorScheme()`): ghi chú Nền tảng, mục 16.5.

- **Thay:** 1 chỗ `.white`, và là một **màu chụp một lần**: module truyền `.white` vào một activity ngay lúc publish, nên màu đóng băng ở giá trị Cổ điển. Nay `tint` là tuỳ chọn, module truyền nil và các view đọc token khi chúng vẽ. Việc này buộc package **phụ thuộc NotchUI** (`Package.swift` thêm một dòng, như các module khác); cổng `verify.sh` build app và là nơi kiểm nó.
- **Test:** `SystemActivitiesGlassTests` (kính sáng, kính tối, Cổ điển). SystemActivities **218 test** (S2). Cổ điển **giống từng điểm ảnh** (băm toàn bộ bitmap trước và sau, hai appearance, bốn lần chạy). Kính do WindowServer vẽ nên không test nào thấy nó: test dựng view trên nền sáng hay tối và đọc màu của chính view. Một lần ở package này một "tâm trạng" của bộ vẽ chưa gặp ở bốn lần chạy trước xuất hiện ở một lần sau; sáu lần chạy sau nữa chỉ cho băm cũ.
- **Cần người kiểm:** hàng "Chữ trên kính" cuối nhóm [Hệ thống](../../manual-test-checklist-all.html#system-activities) của checklist (hình nền sáng, giao diện sáng của macOS, Liquid Glass).
