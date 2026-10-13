# MyNotch — Khay file, Phím tắt Shortcuts, Hẹn giờ (dự án con 8)

- **Ngày:** 2026-10-13
- **Trạng thái:** Thiết kế
- **Nguồn:** AppKit/SwiftUI drag & drop, `NSSharingService`, CLI `/usr/bin/shortcuts` (đã kiểm tra trên máy).

Ba module độc lập: `Shelf`, `Shortcuts`, `Timer`. Không cần quyền hệ thống.

## 1. Điểm nối nền tảng: thả file lên notch

Hiện notch chỉ nhận chuột trong vùng notch + 8 pt, và nội dung tab chỉ tồn tại khi notch mở. Cần thêm vào NotchUI:

- `NotchTab` thêm `dropTypes: [UTType] = []`; module nhận dữ liệu thả vào qua `onDrop: (([NSItemProvider]) -> Bool)?`.
- **Phát hiện kéo file:** `NotchHoverTracker` theo dõi `.leftMouseDragged` (đã có) và so `NSPasteboard(name: .drag).changeCount`. Khi đang kéo mà con trỏ tới gần notch, cho panel nhận chuột trong một vùng rộng hơn (notch + 40 pt). Khi đó notch:
  - mở tab của module có `dropTypes` khớp đầu tiên;
  - gọi `setDragging(true)` cho tới khi thả hoặc rời đi.
- `NotchRootView` gắn `.onDrop(of:isTargeted:)` ở mọi trạng thái và chuyển dữ liệu cho tab đang mở.

## 2. Khay file (`Shelf`)

- Thả file, thư mục, ảnh, link hoặc văn bản lên notch → lưu vào khay.
  - File: `url.bookmarkData()` (app không sandbox nên không cần security scope).
  - Lời hứa file (Photos, Mail): `NSFilePromiseReceiver`, chép vào `storage.directory/promised/`.
  - Văn bản và link lưu trực tiếp.
- Tab "Khay": lưới thẻ (icon, tên). Mỗi thẻ có:
  - kéo ra ngoài;
  - AirDrop: `NSSharingService(named: .sendViaAirDrop)`; app kích hoạt tạm thời để sheet hiện;
  - Chia sẻ… (`NSSharingServicePicker`), Mở, Hiện trong Finder, Xoá khỏi khay;
  - "Xoá tất cả".
- Lưu khay vào `storage.directory/shelf.json`. Bookmark hỏng (file đã bị xoá hoặc chuyển) thì bị bỏ khi tải.
- Cài đặt:
  - `clearOnQuit` (false);
  - `maxItems` (50);
  - `removeAfterDragOut` (false).

## 3. Shortcuts

- Lấy danh sách `shortcuts list --show-identifiers` (cache, làm mới khi mở tab và theo nút làm mới).
- Người dùng chọn các shortcut ưa thích trong Settings; tab "Shortcuts" hiện chúng dạng nút, lưu theo identifier.
- Chạy: `Process` với mảng đối số (không qua shell), ngoài main actor, có thể huỷ, timeout 60 giây.
- Kết quả hiện bằng activity:
  - "Đã chạy X" khi thành công;
  - lỗi kèm thông điệp ngắn khi thất bại;
  - nếu có output dạng văn bản: copy được qua toast.
- Mỗi shortcut ưa thích có thể gán phím tắt toàn cục (đăng ký động qua `ModuleHotkeys`).

## 4. Hẹn giờ (`Timer`)

- Đếm ngược theo preset (1, 5, 10, 25 phút, tuỳ chỉnh) và bấm giờ.
- Lưu `endDate` theo giờ thực, nên không lệch khi máy ngủ. Trạng thái được ghi vào `storage`, nên app mở lại vẫn còn.
- Bấm giờ: thời gian tích luỹ + mốc `ContinuousClock`.
- Live activity khi đang chạy:
  - đồng hồ cát bên trái;
  - thời gian còn lại bên phải, vẽ bằng `Text(timerInterval:)`, không gọi `set` mỗi giây.
- Hết giờ: activity ưu tiên `.high` "Hết giờ" + âm thanh `NSSound(named: "Glass")`, giữ tới khi người dùng bấm hoặc sau 30 giây.
- Tab "Hẹn giờ": các preset, thời gian lớn, nút tạm dừng/tiếp tục/huỷ, thêm 1 phút.
- Phím tắt: không đặt mặc định.

## 5. Kiểm thử

| Phần | Test tự động |
|---|---|
| Phát hiện kéo | Thuần: vùng nhận khi đang kéo vs khi không kéo |
| Shelf store | Thêm/xoá, bookmark hỏng bị bỏ, giới hạn số mục, lưu/tải |
| Shortcuts | Parser output `shortcuts list`; runner với `Process` giả (thành công, lỗi, timeout) |
| Timer | ManualScheduler + đồng hồ giả: đếm ngược, tạm dừng/tiếp tục, khôi phục sau khi mở lại, hết giờ |

**Kiểm thử tay:** kéo file từ Finder lên notch đang đóng; ảnh từ Photos; AirDrop; chạy shortcut thật; hẹn giờ qua lúc máy ngủ.
