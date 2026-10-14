# Ghi chú triển khai: Hẹn giờ và bấm giờ

- **Ngày:** 2026-10-14
- **Spec:** [Khay file, Shortcuts, Hẹn giờ (dự án con 8), §4](../specs/2026-10-13-shelf-shortcuts-timer-design.html). Spec không bị sửa; chỗ đã lỗi thời nằm ở mục "Sửa lại spec".
- **Package:** `Packages/Modules/Timer`, product `TimerModule`. Module id `timer` ("Hẹn giờ", **order 880**, để Battery giữ order 900), tab "Hẹn giờ" (cao 150 pt), live activity `timer`, bật mặc định, không có quyền, không có khoá cài đặt riêng.
- **Commit chính:** `bec55d9` module, `f994113` sửa sau review, `5a1362a` (màn hình khoá, kèm các sửa Timer của review H4), `e2b0586` gắn vào app.
- **Test tự động:** 36 test theo báo cáo L1 (`verify.sh` qua ở `8a2b842`). Test chỉ dùng đồng hồ giả, `ManualScheduler` và bộ phát âm thanh giả. Chưa chạy lại khi viết tài liệu này.
- **Kiểm thử tay:** [mục Hẹn giờ trong checklist gộp](../../manual-test-checklist-all.html#timer)

## 1. Đã xây gì so với spec

- `TimerModel` thuần, `Codable`: đếm ngược theo `endDate` (giờ thực, nên không lệch khi máy ngủ) và bấm giờ (thời gian tích luỹ cộng mốc bắt đầu); chuyển trạng thái bắt đầu, tạm dừng, tiếp tục, huỷ, thêm 1 phút. Lưu vào `storage.directory/timer.json` (ghi nguyên tử), nên mở lại app vẫn còn.
- Live activity khi đang chạy: đồng hồ cát bên trái, thời gian còn lại bên phải bằng `Text(timerInterval:)`, không gọi `set` mỗi giây.
- Hết giờ: activity `.high` "Hết giờ" kèm âm thanh `NSSound(named: "Glass")` đúng một lần, giữ tới khi người dùng bấm hoặc sau 30 giây (`finishedLifetime`).
- Tab: các mẫu 1, 5, 10, 25 phút cùng ô tuỳ chỉnh, thời gian lớn, nút Tạm dừng, Tiếp tục, Huỷ, "+1 phút" (nút "Đóng" khi đã hết giờ), và công tắc "Bấm giờ". Không có phím tắt mặc định.
- Màn hình khoá: Timer đăng ký view đếm ngược (ưu tiên `.high`), xem [ghi chú Màn hình khoá](2026-10-14-lock-screen-implementation.html).

## 2. Sai khác so với spec và lý do

- **Bấm giờ dùng giờ thực `Date`, không dùng mốc `ContinuousClock`** như spec §4. Cần để lưu và khôi phục được qua lần mở lại; có comment trong kiểu `TimerModel`. `elapsed` và `pause` đều kẹp về không khi đồng hồ chạy lùi.
- **Mở lại app không thông báo lại "Hết giờ" đã qua:** `start()` chỉ phát activity khi mô hình lưu chưa ở trạng thái `.finished`. Đếm ngược kết thúc lúc app đóng vẫn được thông báo khi mở lại, và tab vẫn hiện trạng thái đã xong cho tới khi bấm "Đóng". Không thêm ngày "xong lúc" thật vì nó đổi định dạng lưu.
- **Mọi thay đổi làm mới mô hình trước** (`mutate` gọi `refresh(now:)` rồi phát âm nếu vừa xong), nên tạm dừng một đếm ngược vừa đến giờ thì kết thúc nó thay vì dừng ở 0.
- **`timer.json` hỏng được ghi log** (`Logger.error`); thiếu file thì im lặng như lần chạy đầu.
- Số lớn của tab dùng `Text(timerInterval: .distantPast...endDate, countsDown: true)` (cận dưới ổn định) thay cho `Date.now...endDate` tính trong `body`.
- Màn hình khoá chỉ nhận **đếm ngược**; bấm giờ không được đưa lên màn hình khoá (live activity thì giữ nguyên).

## 3. Giới hạn đã chấp nhận (Ruling)

Ledger không có dòng `Ruling:` riêng cho Timer; vòng sửa H1/H3/H4 là "DONE_WITH_CONCERNS". Liên quan đến Timer:

- **Timer phát âm khi `mutate` chạm một đếm ngược đã quá giờ,** kể cả khi thay đổi đó là `cancel` hay `startCountdown` (đồng hồ đã vượt `endDate`). Ghi nhận trong báo cáo L1 như một hệ quả của việc làm mới trước.
- **Ruling L1 (một dòng chung cho cả vòng sửa màn hình khoá):** quy tắc hiện, một shim và một space SkyLight cho mỗi module, đối chiếu `isScreenLocked()` khi thức dậy, id space 64 bit, và "view Timer trên màn hình khoá chỉ hiện đếm ngược" (brief ghi "thời gian còn lại"). Chi phí nếu sai ghi trong [ghi chú Màn hình khoá](2026-10-14-lock-screen-implementation.html).

## 4. Khoảng trống đã biết

- Chuỗi đếm ngược thật sự hiển thị (`Text(timerInterval:)`) không đọc được khi chạy không giao diện; mới đo bằng `NSHostingView` rằng kích thước vừa khớp giống nhau (84 x 45 ở cỡ chữ 38) cho ba dạng cận dưới. Chuỗi thật chỉ "được kỳ vọng đúng".
- Thư mục tạm của test: `RegistryHarness` từng để lại 25 thư mục `MyNotchTests-<uuid>` mỗi lần chạy test Timer. Đã sửa ở `2bb5fc1` (`ScratchFolders` trong `MyNotchTestSupport`, xoá khi tiến trình test thoát); `verify.sh` vẫn quét phần còn lại của một lần chạy bị crash.
- Chưa có kết quả kiểm thử tay được ghi lại cho: mẫu 1, 5, 10, 25 phút, hết giờ và âm Glass, hẹn giờ qua lúc máy ngủ, thoát và mở lại.

## 5. Sửa lại spec (Spec corrections)

- **§4, bấm giờ**: dùng giờ thực `Date`, không phải mốc `ContinuousClock`.
- **§4, hết giờ**: thêm quy tắc không thông báo lại trạng thái đã xong khi mở lại app, và trạng thái xong vẫn thấy trong tab tới khi bấm "Đóng".
- **Order**: 880 (spec không ghi, brief cố định để Battery giữ 900).
- **Dòng trạng thái** "Thiết kế" đã lỗi thời: module đã triển khai và gắn vào app.

## 6. Cần kiểm thử tay

Xem [mục Hẹn giờ trong checklist gộp](../../manual-test-checklist-all.html#timer). Không có quyền hệ thống.
