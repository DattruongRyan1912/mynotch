# Ghi chú triển khai: Widget trên màn hình khoá (thử nghiệm)

- **Ngày:** 2026-10-14
- **Trạng thái:** **thử nghiệm, dùng API riêng của macOS (SkyLight), chưa được kiểm chứng trên màn hình khoá thật.** Module tắt mặc định. Vòng sửa L1 đã vào code (`8a2b842`) và review lại phạm vi hẹp (`re-review-L1-r1.md`) kết luận **Approved**, không có Critical hay Important; mô tả dưới đây khớp mã ở HEAD (đã đối chiếu `LockStateObserver`, `LockScreenModule`, `TimerModule`) và báo cáo `L1-report.md` (kể cả "Fix round 1"). Review đó đọc mã và chạy test, không chạy trên màn hình khoá thật. Không có commit nào đụng module này kể từ `8a2b842`; review cuối cùng (`final/review-core.md`, `review-integration.md`) duyệt phần Core, NotchUI và việc gắn vào app.
- **Spec:** [Widget trên màn hình khoá (dự án con 9)](../specs/2026-10-13-lock-screen-design.html). Spec không bị sửa; chỗ đã lỗi thời nằm ở mục "Sửa lại spec".
- **Package:** `Packages/Modules/LockScreen`, product `LockScreenModule`. Module id `lockscreen` ("Màn hình khoá", order 990), không có tab, **tắt mặc định**, không có quyền. Chạm cả `Packages/MyNotchCore`, `Packages/NotchUI`, và thêm view cho Media, Timer, Battery.
- **Commit chính:** `5a1362a` triển khai, `8a2b842` sửa sau review.
- **Test tự động:** LockScreen 41, NotchUI 77 (trong đó 10 test shim), Timer 36, Battery 23, Media 300, MyNotchCore 119 (105 ở `8a2b842`; phần thêm không thuộc màn hình khoá) theo báo cáo L1 và các báo cáo sau (`verify.sh` qua ở `8a2b842` và ở `a8025b2`). Không test nào khoá màn hình thật, cho màn hình ngủ, gửi thông báo hệ thống thật, tạo space SkyLight, gọi `CGSessionCopyCurrentDictionary` hay gọi hàm SLS thật. Chưa chạy lại khi viết tài liệu này.
- **Kiểm thử tay:** [mục Màn hình khoá trong checklist gộp](../../manual-test-checklist-all.html#lock-screen)
- **Cập nhật sau `156f02d` (2026-10-15):** panel theo cài đặt ẩn khỏi quay màn hình (`e45493e`), nút điều khiển nhạc và công tắc riêng (`daf9715`, `25da7c6`) (mục 7 và 8). LockScreen 58 test. Chưa ai khoá được màn hình để thử.

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
- **§2, hàng `LockScreenPanel`**: 300 x 80 ở bản đầu (340 x 80 từ M12, mục 7), giữa cạnh trên màn hình chính, level `.screenSaver` bên trong space level 400.
- **§2, hàng `LockScreenModule`**: gỡ có trễ 300 ms; shim và space tạo một lần mỗi module; space không bị huỷ tới khi thoát app.
- **§2, "Nội dung lấy từ đâu"**: ba contributor và ưu tiên (Timer `.high`, Media `.normal`, Battery `.low`); Timer chỉ đếm ngược; lọc theo `showMedia`, `showTimer`, `showBattery` và id module.
- **Dòng trạng thái** "Thiết kế, thử nghiệm": đã triển khai ở dạng thử nghiệm, chưa kiểm chứng trên màn hình khoá thật.

## 6. Cần kiểm thử tay

Xem [mục Màn hình khoá trong checklist gộp](../../manual-test-checklist-all.html#lock-screen). Mọi mục ở đó đụng API riêng SkyLight. Mục "macOS có gửi `sessionDidResignActive` khi chỉ khoá màn hình không" không còn quan trọng sau vòng sửa 1.

## 7. Từ `156f02d` đến hết 2026-10-15: ẩn khỏi quay màn hình và điều khiển nhạc (R2e, M12)

Commit `e45493e` (panel màn hình khoá theo cài đặt ẩn khỏi quay màn hình), `daf9715` (nút nhạc trên màn hình khoá), `25da7c6` (công tắc riêng cho nút). Test: LockScreen **58 test** ở `25da7c6` (41 trước, 45 sau `e45493e`, 46 sau `daf9715`), ba lần chạy sạch, 0 cảnh báo; MyNotchCore 257 test. **Không ai khoá được màn hình để thử**: panel nằm trong space SkyLight riêng và chưa có cú click nào được chuyển tới nó.

### 7.1 Ẩn khỏi quay màn hình (R2e `e45493e`)

Review R1a I1: `LockScreenPanel` phớt lờ cài đặt "Ẩn MyNotch khi quay hoặc chia sẻ màn hình". Nay panel tạo một `CaptureHidingFollower` (trạng thái `.compact`: một widget nằm dưới notch thu gọn) trong `init`, trước khi panel có thể hiện, và dừng nó trong `dismiss()`. "Chỉ khi notch đóng" và "Luôn ẩn" giữ nó ngoài bản ghi, "Không ẩn" thì để; đổi cài đặt khi panel đang hiện có hiệu lực ngay. `init` là internal và nhận `NotchInterface` để test tiêm cái của riêng mình. Xem mục 14.1 ghi chú Nền tảng. **Chưa xác minh** với QuickTime, Meet hay Zoom (review R1a I2).

### 7.2 Nút điều khiển nhạc và công tắc riêng (M12)

- **Cách nối:** Media đưa một view SwiftUI qua `context.lockScreen.set(AnyView, priority:, isInteractive: true)` và LockScreen chỉ vẽ `entry.view`, nên các nút nằm trong view của Media và dùng `MediaActions` của chính module; **không có phụ thuộc từ LockScreen sang Media**. View có bìa, tên bài, nghệ sĩ, ba nút trước / phát dừng / sau và thanh tiến trình mảnh không tua được. Nút trước và sau đi qua cùng đường với tab (luật `prohibitsSkip`, `SkipRoute`: cầu nối YouTube nếu có phiên sống, MediaRemote nếu không). Xem mục 16.5 ghi chú Media. Panel rộng **340 pt** (trước 300); thẻ cao tối thiểu 56 pt với đệm dọc 8 pt (trước 56 cố định) để một view cao hơn vẫn vừa trong 80 pt của panel.
- **Ruling (review M12 I1, người điều phối): một công tắc riêng cho nút.** Settings → Màn hình khoá: **"Điều khiển nhạc trên màn hình khoá"** (`showMediaControls`, mặc định **bật**), dưới "Hiện bài đang phát" và mờ khi công tắc đó tắt. Lời giải thích dưới nó mang cảnh báo: **ai ngồi trước bàn phím của một máy đã khoá cũng bấm được nút**; tắt thì chỉ hiện bài. "Hiện bài đang phát" quay lại chỉ mô tả việc hiển thị ("Hiện bìa, tên bài, nghệ sĩ và thanh tiến trình…"). Khi tắt, view chỉ vẽ bài và thanh tiến trình (không giữ lại glyph phát chỉ-đọc cũ, nên không còn gì trông như bấm được).
- **Panel chỉ nhận chuột khi cần** (`LockScreenWindow.takesClicks`, panel khởi đầu `ignoresMouseEvents = true`): chỉ khi entry đang hiện là `isInteractive` **và** công tắc đang bật, được `LockScreenModule` giữ đồng bộ bằng một task `Observations` suốt đời panel. Khi công tắc tắt, hay một view Timer hay Battery đang hiện, hay không entry nào được phép, panel **xuyên chuột**. Panel vẫn là `.nonactivatingPanel`, `canBecomeKey` và `canBecomeMain` false: không bao giờ lấy bàn phím hay kích hoạt MyNotch (`LockScreenHostingView` nhận cú click đầu).
- **Phần MyNotchCore bị đụng (tương thích nguồn):** `LockScreenContentCenter.swift` có `Entry.isInteractive` và `set(_:priority:isInteractive:)` (mặc định false) cùng giá trị môi trường `\.lockScreenControlsEnabled` (mặc định true, do `LockScreenRootView` đặt từ cài đặt, đọc trong body nên đổi có hiệu lực). Nút là danh sách `LockScreenTransport.controls` (trước, phát dừng, sau; mỗi cái có dáng và hành động) và view vẽ đúng danh sách đó nên nối dây kiểm thử được; một cú nhấn thật vào nút SwiftUI không test được (hosting view offscreen không có cây trợ năng).
- **Hạn chế đã biết:** nếu WindowServer không chuyển click tới một cửa sổ trong space đó thì nút vẽ ra mà không làm gì (thanh tiến trình và phần còn lại không bị ảnh hưởng); toàn bộ panel 340 × 80 nhận chuột khi nút bật (không biết entry nào đang hiện nếu không có thay đổi ở Core; trên màn hình khoá không có gì dưới dải đó để bấm); chưa kiểm khi một app Timer hay Battery chiếm panel.

## 8. Cần kiểm thử tay (phần mới)

Xem [mục Màn hình khoá trong checklist gộp](../../manual-test-checklist-all.html#lock-screen): **bật module, khoá màn hình, bật rồi tắt "Điều khiển nhạc trên màn hình khoá"**: bật thì panel có ba nút, một cú click có tác dụng và **ô mật khẩu giữ focus**, thẻ 340 pt không chật (tiêu đề bị cắt?) và vừa dưới notch; tắt thì chỉ còn bìa, tên bài, nghệ sĩ và thanh mảnh và một cú click xuyên xuống dưới; YouTube trong Chrome với extension: Next, Previous nhảy video, và trong lúc quảng cáo thì mờ và không làm gì; ẩn khỏi quay màn hình với widget đang hiện.
