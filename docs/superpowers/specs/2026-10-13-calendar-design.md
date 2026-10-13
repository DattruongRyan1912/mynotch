# MyNotch — Lịch và Lời nhắc (dự án con 6)

- **Ngày:** 2026-10-13
- **Trạng thái:** Thiết kế
- **Nguồn:** EventKit trong SDK macOS 26.5. API full-access đã được xác minh.

## 1. Mục tiêu

**Trong phạm vi:**

- Tab "Lịch":
  - sự kiện hôm nay và sự kiện kế tiếp trong 7 ngày;
  - lời nhắc chưa xong đến hạn hôm nay, kể cả quá hạn.
- Live activity "Họp sau N phút": hiện từ 5 phút trước giờ bắt đầu, có nút "Tham gia" khi tìm thấy link họp.
- Đánh dấu hoàn thành lời nhắc; mở sự kiện trong Calendar.

**Ngoài phạm vi:** tạo hoặc sửa sự kiện, danh sách người tham dự, tích hợp lịch bên thứ ba ngoài EventKit.

## 2. Thiết kế

Package `Packages/Modules/Calendar`, product `CalendarModule`.

**Quyền:**

| Quyền | Loại | Ghi chú |
|---|---|---|
| `.calendars` | Bắt buộc | |
| `.reminders` | Tuỳ chọn | Chỉ xin khi người dùng bật mục lời nhắc, tránh hai hộp thoại liên tiếp |

`project.yml` đã có usage description và entitlement `com.apple.security.personal-information.calendars` từ dự án con 0.5. Lời nhắc không cần entitlement riêng.

| Thành phần | Vai trò |
|---|---|
| `CalendarService` | Actor nonisolated, giữ một `EKEventStore`. Ánh xạ sang struct `Sendable` (`AgendaEvent`, `AgendaReminder`). `events(matching:)` là hàm đồng bộ nên chạy ngoài main. |
| `AgendaBuilder` | Thuần: lọc sự kiện bị huỷ hoặc mình đã từ chối, tách sự kiện cả ngày, chọn "kế tiếp" (sự kiện không phải cả ngày đầu tiên có `endDate > now`). |
| `MeetingLinkDetector` | Thuần: tìm link họp lần lượt trong `URL`, `location`, `notes` theo bảng mẫu (Zoom, Google Meet, Teams, Webex, FaceTime). |
| `UpcomingMeetingPolicy` | Thuần: khi nào hiện, cập nhật hoặc ẩn activity họp (từ 5 phút trước tới 5 phút sau giờ bắt đầu, hoặc tới khi người dùng bấm Tham gia). |
| `CalendarModule` | Làm mới khi có `EKEventStoreChanged` (gom 1 giây), khi qua ngày mới (`NSCalendarDayChanged`), khi máy thức dậy, và mỗi phút một lần cho đếm ngược. |

**Mở sự kiện:** `ical://ekevent/<calendarItemIdentifier>`. Đây là đường dẫn không được công bố; nếu không mở được thì mở Calendar.app.

### 2.1 Cài đặt (`module.calendar.*`)

| Khoá | Mặc định |
|---|---|
| `showReminders` | false (bật thì xin quyền Reminders) |
| `meetingLeadMinutes` | 5 (1…30) |
| `hiddenCalendarIDs` | [] |
| `showAllDay` | true |

## 3. Kiểm thử

| Phần | Test tự động |
|---|---|
| `AgendaBuilder` | Huỷ/từ chối bị bỏ, cả ngày, chọn kế tiếp, qua nửa đêm |
| `MeetingLinkDetector` | Từng nhà cung cấp, thứ tự ưu tiên `URL` > `location` > `notes`, không khớp |
| `UpcomingMeetingPolicy` | ManualScheduler: trước 5 phút, đúng giờ, quá 5 phút, đã bấm Tham gia |
| Module | `CalendarService` giả |

**Kiểm thử tay:** hộp thoại quyền; sự kiện thật có link Meet/Zoom; hoàn thành lời nhắc; đổi lịch trong Calendar.app thì tab cập nhật.
