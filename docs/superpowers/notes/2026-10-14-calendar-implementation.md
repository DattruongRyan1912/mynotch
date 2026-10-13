# Ghi chú triển khai: Lịch và Lời nhắc

- **Ngày:** 2026-10-14
- **Spec:** [Lịch và Lời nhắc (dự án con 6)](../specs/2026-10-13-calendar-design.html). Spec không bị sửa; chỗ đã lỗi thời nằm ở mục "Sửa lại spec".
- **Package:** `Packages/Modules/Calendar`, product `CalendarModule`. Module id `calendar` ("Lịch", order 600), tab "Lịch" (cao 220 pt), live activity `meeting`, bật mặc định. Quyền bắt buộc `.calendars`, quyền tuỳ chọn `.reminders`.
- **Commit chính:** `77a535c` agenda và nhận link họp, `fc35c95` module, `d35eb2a` sửa sau review, `f14dad6` gắn vào app.
- **Test tự động:** 151 test theo báo cáo L1 (`verify.sh` qua ở `8a2b842`). Không dùng EventKit thật trong test. Chưa chạy lại khi viết tài liệu này.
- **Kiểm thử tay:** [mục Lịch trong checklist gộp](../../manual-test-checklist-all.html#calendar)

## 1. Đã xây gì so với spec

- `CalendarService` (actor) giữ một `EKEventStore`, ánh xạ sang các struct `Sendable` (`AgendaEvent`, `AgendaReminder`, `CalendarInfo`), đứng sau protocol `CalendarDataSource` để test bằng nguồn giả. `events(matching:)` đồng bộ nên chạy ngoài main.
- `AgendaBuilder` thuần (lọc sự kiện huỷ hoặc đã từ chối, tách sự kiện cả ngày, xử lý sự kiện qua nửa đêm), `MeetingLinkDetector` thuần (Zoom, Google Meet, Teams, Webex, FaceTime; thứ tự `URL`, `location`, `notes`), `UpcomingMeetingPolicy` thuần (từ trước giờ bắt đầu tới 5 phút sau; có "Bỏ qua").
- Module làm mới khi có `EKEventStoreChanged` (qua `ChangeCoalescer` gom 1 giây), khi qua ngày mới, khi máy thức dậy, và theo nhịp phút cho đếm ngược.
- Activity `meeting`: chấm màu lịch kèm biểu tượng đồng hồ bên trái, "N phút" hoặc "Đang diễn ra" bên phải; ưu tiên `.high` trong 1 phút trước giờ bắt đầu, `.normal` còn lại; cập nhật tại chỗ.
- Tab "Lịch": ngày hôm nay kiểu Việt, thẻ "Sắp tới" (nút "Tham gia" khi có link họp, nút "Bỏ qua"), danh sách sự kiện hôm nay (cả ngày trước, sự kiện đã qua mờ đi), lời nhắc đến hạn hôm nay và quá hạn có ô tích hoàn thành khi `showReminders` bật và đã cấp quyền. Click sự kiện mở `ical://ekevent/<calendarItemIdentifier>`, không mở được thì mở Calendar.app.
- Cài đặt `module.calendar.*`: `showReminders` (false; bật thì xin quyền Reminders), `meetingLeadMinutes` (5, từ 1 đến 30), `hiddenCalendarIDs` (rỗng), `showAllDay` (true).

## 2. Sai khác so với spec và lý do

- **Activity họp không dùng `next` của `AgendaBuilder`.** Spec chọn "kế tiếp" là sự kiện không cả ngày đầu tiên có `endDate > now`. Một sự kiện dài đã bắt đầu từ trước (workshop 9 đến 17 giờ) sẽ giữ vai trò `next` và che mất một cuộc họp bắt đầu sau đó. Activity họp nay lấy từ các sự kiện sắp diễn ra trong cửa sổ `meetingLeadMinutes`, **không phân biệt ngày** (cuộc họp 00:10 ngày mai với lead 30 phút hiện lúc 23:40), hoặc đang diễn ra và bắt đầu cách đây không quá 5 phút.
- **Bộ hẹn giờ căn theo đầu phút** (spec chỉ nói "mỗi phút một lần"). Trước đây tính 60 giây từ lúc module khởi động nên đếm ngược có thể trễ tới 59 giây.
- **Không debounce hai lần:** `ChangeCoalescer` đã gom thay đổi của nguồn dữ liệu 1 giây (có thêm hạn tối đa), nên module chỉ debounce 1 giây cho các thông báo còn lại (ngày mới, thức dậy).
- `CalendarDataSource` có thêm `calendars()` (danh sách lịch cho các công tắc `hiddenCalendarIDs`). `AgendaEvent` có `calendarItemIdentifier` và `calendarID`.
- **Làm mới ngay sau khi cấp quyền:** `CalendarService` chỉ tạo store sau khi có quyền, và không có thông báo thay đổi nào đến trước đó, nên module tự làm mới ngay khi quyền được cấp, dù cấp từ registry hay từ dòng trong Settings. Trang Settings tải lại danh sách lịch khi hiện và sau khi cấp quyền (`accessRevision`).
- Test của `ChangeCoalescer` dùng đồng hồ tiêm vào (không phụ thuộc độ chính xác của `Task.sleep`), sau khi hai test cũ chập chờn khi máy bận.

## 3. Giới hạn đã chấp nhận (Ruling)

Ledger không có dòng `Ruling:` nào cho Lịch; K2 và K3-fix được review và duyệt (HANDOFF mục 8). Điểm cần biết:

- Reminders chỉ được xin khi người dùng bật `showReminders`, để tránh hai hộp thoại liên tiếp.

## 4. Khoảng trống đã biết

- `ical://ekevent/...` là đường dẫn không được công bố; không mở được thì mở Calendar.app (dự phòng theo thiết kế). Chưa kiểm xem nó có mở đúng sự kiện không.
- Danh sách lịch trong Settings chỉ tải được khi đã cấp quyền; chưa cấp thì hiện gợi ý.
- Ngoài phạm vi: tạo hoặc sửa sự kiện, danh sách người tham dự, lịch bên thứ ba ngoài EventKit.
- Chưa có kết quả kiểm thử tay được ghi lại cho: hộp thoại quyền Lịch và Lời nhắc, sự kiện thật có link Meet hoặc Zoom, nút "Tham gia", hoàn thành lời nhắc, đổi lịch trong Calendar.app thì tab cập nhật, giao diện trang Settings.

## 5. Sửa lại spec (Spec corrections)

- **§2, hàng `AgendaBuilder`**: `next` vẫn có trong `Agenda` nhưng không còn nuôi activity họp; activity lấy từ sự kiện trong cửa sổ lead, không phân biệt ngày.
- **§2, hàng `CalendarModule`**: bộ đếm theo nhịp phút căn đầu phút; thay đổi từ nguồn dữ liệu đi qua `ChangeCoalescer`, không debounce thêm.
- **§2, hàng `CalendarService`**: giao diện nguồn dữ liệu có thêm `calendars()`; store chỉ được tạo sau khi có quyền.
- **Dòng trạng thái** "Thiết kế" đã lỗi thời: module đã triển khai và gắn vào app.

## 6. Cần kiểm thử tay

Xem [mục Lịch trong checklist gộp](../../manual-test-checklist-all.html#calendar). Các mục đụng quyền: Lịch và Lời nhắc (reset TCC trước khi thử hộp thoại).
