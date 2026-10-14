# Ghi chú triển khai: Widget trên màn hình khoá (thử nghiệm)

- **Ngày:** 2026-10-14
- **Trạng thái:** **thử nghiệm, dùng API riêng của macOS (SkyLight), chưa được kiểm chứng trên màn hình khoá thật.** Module tắt mặc định. Vòng sửa L1 đã vào code (`8a2b842`) và review lại phạm vi hẹp (`re-review-L1-r1.md`) kết luận **Approved**, không có Critical hay Important; mô tả dưới đây khớp mã ở HEAD (đã đối chiếu `LockStateObserver`, `LockScreenModule`, `TimerModule`) và báo cáo `L1-report.md` (kể cả "Fix round 1"). Review đó đọc mã và chạy test, không chạy trên màn hình khoá thật. Không có commit nào đụng module này kể từ `8a2b842`; review cuối cùng (`final/review-core.md`, `review-integration.md`) duyệt phần Core, NotchUI và việc gắn vào app.
- **Spec:** [Widget trên màn hình khoá (dự án con 9)](../specs/2026-10-13-lock-screen-design.html). Spec không bị sửa; chỗ đã lỗi thời nằm ở mục "Sửa lại spec".
- **Package:** `Packages/Modules/LockScreen`, product `LockScreenModule`. Module id `lockscreen` ("Màn hình khoá", order 990), không có tab, **tắt mặc định**, không có quyền. Chạm cả `Packages/MyNotchCore`, `Packages/NotchUI`, và thêm view cho Media, Timer, Battery.
- **Commit chính:** `5a1362a` triển khai, `8a2b842` sửa sau review.
- **Test tự động:** LockScreen 41, NotchUI 77 (trong đó 10 test shim), Timer 36, Battery 23, Media 300, MyNotchCore 119 (105 ở `8a2b842`; phần thêm không thuộc màn hình khoá) theo báo cáo L1 và các báo cáo sau (`verify.sh` qua ở `8a2b842` và ở `a8025b2`). Không test nào khoá màn hình thật, cho màn hình ngủ, gửi thông báo hệ thống thật, tạo space SkyLight, gọi `CGSessionCopyCurrentDictionary` hay gọi hàm SLS thật. Chưa chạy lại khi viết tài liệu này.
- **Kiểm thử tay:** [mục Màn hình khoá trong checklist gộp](../../manual-test-checklist-all.html#lock-screen)

## 1. Đã xây gì so với spec

- **MyNotchCore:** `LockScreenContentCenter` (`@Observable`; mỗi module một mục; `current` là mục có ưu tiên cao nhất, hoà thì mục thêm gần nhất; `current(allowing:)` lọc theo danh sách module được phép) và `LockScreenPublisher` (`context.lockScreen`: `set(_:priority:)`, `clear()`; vô hiệu sau khi module dừng và dọn mục của module). `ModuleContext` và `ModuleRegistry.init` có thêm tham số `lockScreen` bắt buộc.
- **NotchUI:** `SkyLightShim` (protocol) và `SystemSkyLightShim`: `dlopen` SkyLight cùng `dlsym` sáu symbol (`SLSMainConnectionID`, `SLSSpaceCreate`, `SLSSpaceSetAbsoluteLevel`, `SLSShowSpaces`, `SLSSpaceAddWindowsAndRemoveFromSpaces`, `SLSRemoveWindowsFromSpaces`), không link. `isAvailable` là false nếu thiếu thư viện hoặc bất kỳ symbol nào, khi đó mọi hàm là no-op. `makeLockScreenSpace()` (idempotent) tạo space level tuyệt đối 400 rồi hiện nó; `attach` và `detach` chuyển cửa sổ vào và ra. Không đọc mã trả về nào.
- **Module:** `start` ném `.unavailable` ("macOS này không có hàm SkyLight cần thiết") nếu shim không khả dụng. `LockStateObserver` nghe thông báo phân tán `com.apple.screenIsLocked` và `screenIsUnlocked`, thông báo workspace `screensDidSleep`, `screensDidWake` và `sessionDidBecomeActive`; trạng thái ban đầu từ `CGSessionCopyCurrentDictionary()["CGSSessionScreenIsLocked"]`. Khi khoá và có nội dung được phép, dựng panel (không activating, không bao giờ key, bỏ qua chuột, level `.screenSaver`, 300 x 80, giữa cạnh trên màn hình chính ngay dưới notch), tạo space, hiện và gắn panel. Khi mở khoá hoặc màn hình ngủ, gỡ sau 300 ms (huỷ nếu trạng thái đảo lại), đóng panel; `stop()` gỡ ngay.
- **Cài đặt `module.lockscreen.*`:** `showMedia` (true), `showTimer` (true), `showBattery` (false), kèm dòng cảnh báo "Thử nghiệm — dùng API riêng của macOS". Lọc theo id module; module lạ không bao giờ được hiện.
- **Nội dung (chỉ thông tin không nhạy cảm):** Battery (biểu tượng và phần trăm, `.low`), Timer (đếm ngược, `.high`), Media (ảnh bìa, tên bài, nghệ sĩ, biểu tượng phát hoặc dừng, `.normal`; theo `ActivityPolicy` nên giữ thời gian chờ khi tạm dừng, không phụ thuộc `showActivity`). Lịch, nội dung AI và clipboard không bao giờ lên màn hình khoá.

## 2. Sai khác so với spec và lý do

- **Điều kiện hiện (sau vòng sửa):** `isLocked && !isDisplayAsleep`. Bản đầu còn đòi `isSessionActive`; review chỉ ra nếu macOS 26 gửi `sessionDidResignActive` ngay khi khoá thì widget không bao giờ hiện và không test nào bắt được. `sessionDidResignActive` không còn được quan sát.
- **Đối chiếu khi thức dậy:** khi `screensDidWake` hoặc `sessionDidBecomeActive`, `isLocked` được đặt lại theo `isScreenLocked()`, để thiếu một thông báo mở khoá không để panel kẹt trong space level 400 trên màn hình làm việc.
- **Một shim, một space cho mỗi module:** shim được tạo ở lần `start` đầu và giữ qua `stop`, nên space SkyLight được tạo tối đa một lần cho mỗi tiến trình. Không có `SLSSpaceDestroy` trong danh sách symbol, nên space sống tới khi thoát app.
- **Id space 64 bit:** typedef con trỏ hàm dùng `UInt64`; không còn cắt 32 bit. Tham số cờ vẫn rộng bằng con trỏ.
- **Timer chỉ đưa đếm ngược lên màn hình khoá** (brief: "thời gian còn lại"); bấm giờ không được đưa lên.
- Sửa Timer đi kèm theo review H4 (tạm dừng một đếm ngược vừa hết giờ thì kết thúc nó; ghi log `timer.json` hỏng; cận dưới ổn định của `Text(timerInterval:)`), xem [ghi chú Hẹn giờ](2026-10-14-timer-implementation.html).

## 3. Giới hạn đã chấp nhận (Ruling)

- **Ruling (sau review L1):** điều kiện hiện = `isLocked && !isDisplayAsleep` (bỏ gating theo session, chấp nhận chuyển đổi người dùng nhanh); một shim và một space cho mỗi module; đối chiếu với `isScreenLocked()` khi màn hình thức dậy hoặc session active; id space giữ 64 bit; view Timer chỉ hiện đếm ngược. **Chi phí nếu sai:** khi chuyển đổi người dùng nhanh, panel có thể nằm ở session khác (vô hình ở đó); mọi thứ về hành vi thật trên màn hình khoá (Spaces, level 400, thông báo có đến app accessory không) vẫn cần người kiểm tra.
- **Ruling:** đối chiếu ghi đè `isLocked` từ `isScreenLocked()` khi thức dậy hoặc session active được chấp nhận. **Chi phí nếu sai:** nếu từ điển session chậm hơn thông báo khoá thì widget ẩn tới lần khoá kế tiếp (ít xảy ra).
- **Ruling:** L1 bắt đầu trước khi các sửa review M7 vào main; chỉnh sửa Media giới hạn ở việc đăng ký view màn hình khoá. **Chi phí nếu sai:** một xung đột merge nhỏ ở `MediaModule.swift`. Sau đó các commit lời bài hát (`e8a9b20`, `ba6695c`, `ff26aae`) đã được cherry-pick lên trên `5a1362a` mà không có báo cáo xung đột.

## 4. Khoảng trống đã biết

- **Chữ ký các hàm SkyLight chưa được xác minh bằng cách gọi thật.** Chỉ có mặt của symbol được xác nhận (kiểm tên bằng `dlopen` và `dlsym` trên macOS 26.5.2, không gọi). Độ rộng đối số, giá trị cờ `7` của `SLSSpaceAddWindowsAndRemoveFromSpaces` và `SLSSpaceCreate(cid, 1, nil)` viết từ hiểu biết về ABI C, không từ header. Sai chữ ký nhiều khả năng cho kết quả "không thấy widget". Không có hàm SLS nào chạy nếu màn hình chưa từng khoá khi có nội dung.
- Có báo cáo cộng đồng cách này hỏng trên bản beta macOS 27; vì vậy module tắt mặc định và mọi symbol nạp bằng `dlsym`.
- Panel chỉ dựng lúc khoá. Nhạc bắt đầu phát khi đã khoá và chưa có panel thì không hiện tới lần khoá kế tiếp (panel đã có thì theo nội dung trực tiếp). Chỉ phủ màn hình chính (`NSScreen.screens.first`).
- Thông báo phân tán `screenIsLocked/Unlocked` có tới được app `LSUIElement` (không bao giờ là app active) hay không: chưa biết. Nếu không, cách sửa là `DistributedNotificationCenter.default().suspended = false` hoặc người quan sát dùng `.deliverImmediately` (cần một `NSObject` làm observer).
- Trong 300 ms debounce khi đổi bài, dòng tên bài của view Media trống (ảnh bìa và biểu tượng dùng ảnh chụp activity).
- Chuyển đổi người dùng nhanh: panel có thể nằm ở session khác.
- Việc đối chiếu với `isScreenLocked()` có hai sai lệch có giới hạn (re-review): nếu từ điển session chậm hơn thông báo, lần đối chiếu có thể cho "chưa khoá" và widget ẩn tới lần khoá kế tiếp, hoặc cho "còn khoá" sau khi mở khoá và panel (click xuyên qua) còn đó tới lần khoá, mở khoá hoặc thức dậy kế tiếp. Cả hai tự lành, ít xảy ra, module tắt mặc định. Nếu thấy trễ, đọc lại `isScreenLocked()` một lần sau `hideDelay`.
- Sau ngủ rồi thức khi màn hình khoá đang hiện, việc widget có hiện hay không giờ phụ thuộc `CGSSessionScreenIsLocked` được macOS 26 đặt đúng: cần người kiểm.

## 5. Sửa lại spec (Spec corrections)

- **§2, hàng `LockStateObserver`**: không quan sát `sessionDidResignActive`; điều kiện hiện là `isLocked && !isDisplayAsleep`; đối chiếu với `isScreenLocked()` khi `screensDidWake` và `sessionDidBecomeActive`.
- **§2, hàng `LockScreenPanel`**: 300 x 80, giữa cạnh trên màn hình chính, level `.screenSaver` bên trong space level 400.
- **§2, hàng `LockScreenModule`**: gỡ có trễ 300 ms; shim và space tạo một lần mỗi module; space không bị huỷ tới khi thoát app.
- **§2, "Nội dung lấy từ đâu"**: ba contributor và ưu tiên (Timer `.high`, Media `.normal`, Battery `.low`); Timer chỉ đếm ngược; lọc theo `showMedia`, `showTimer`, `showBattery` và id module.
- **Dòng trạng thái** "Thiết kế, thử nghiệm": đã triển khai ở dạng thử nghiệm, chưa kiểm chứng trên màn hình khoá thật.

## 6. Cần kiểm thử tay

Xem [mục Màn hình khoá trong checklist gộp](../../manual-test-checklist-all.html#lock-screen). Mọi mục ở đó đụng API riêng SkyLight. Mục "macOS có gửi `sessionDidResignActive` khi chỉ khoá màn hình không" không còn quan trọng sau vòng sửa 1.
