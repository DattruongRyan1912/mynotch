# Ghi chú triển khai: Khay file và điểm nối thả file lên notch

- **Ngày:** 2026-10-14
- **Spec:** [Khay file, Shortcuts, Hẹn giờ (dự án con 8), §1 và §2](../specs/2026-10-13-shelf-shortcuts-timer-design.html). Spec không bị sửa; chỗ đã lỗi thời nằm ở mục "Sửa lại spec".
- **Package:** `Packages/Modules/Shelf`, product `ShelfModule`. Module id `shelf` ("Khay", order 800), tab "Khay" (cao 170 pt), bật mặc định, không có quyền. Điểm nối thả file nằm trong `Packages/NotchUI` và `NotchTab` của `Packages/MyNotchCore`.
- **Commit chính:** `09a2548` điểm nối thả file (H1), `378c5d5` sửa H1, `48430fc` Khay (H2), `e2d8575` sửa Khay, `4097fe8` sửa NotchUI (kết thúc kéo khi ẩn), `e2b0586` gắn vào app.
- **Test tự động:** Shelf 38 test, NotchUI 77 test theo báo cáo L1 (`verify.sh` qua ở `8a2b842`). Chưa chạy lại khi viết tài liệu này.
- **Kiểm thử tay:** [mục Khay trong checklist gộp](../../manual-test-checklist-all.html#shelf)

## 1. Đã xây gì so với spec

**Điểm nối thả file (spec §1, NotchUI):**

- `NotchTab` có thêm `dropTypes: [UTType]` và `onDrop: (([NSItemProvider]) -> Bool)?`.
- `NotchHoverTracker` theo dõi `leftMouseDragged` và `leftMouseUp`, và so `changeCount` của pasteboard kéo (`NSPasteboard(name: .drag)`) để biết phiên kéo có dữ liệu. Khi đang kéo, panel nhận chuột trong vùng rộng hơn (`NotchGeometry.dragHitRect`: notch cộng 40 pt mỗi bên và phía dưới). Khi con trỏ vào vùng đó, notch mở tab đầu tiên có `dropTypes` khớp (ưu tiên tab đang hiện) và gọi `setDragging(true)`; rời đi hoặc nhả chuột thì kết thúc.
- `NotchRootView` gắn `.onDrop(of:isTargeted:)` ở mọi trạng thái và chuyển dữ liệu cho tab đang mở.
- Phần thuần có test: `DropRouting.tab(for:tabs:preferring:)` và `DropRouting.dragAction` (phân biệt di chuyển thật với làm mới giao diện), hình học vùng kéo.

**Khay (spec §2):**

- `ShelfStore` lưu `shelf.json` (ghi nguyên tử, giải mã từng mục, giới hạn `maxItems`, bỏ mục có bookmark hỏng khi tải). File: `url.bookmarkData()` (app không sandbox). File được hứa (Photos, Mail): chép vào `storage.directory/promised/<uuid>/`. Văn bản và link lưu trực tiếp.
- Tab: lưới thẻ (biểu tượng, tên). Menu ngữ cảnh: Mở, Hiện trong Finder, AirDrop (`NSSharingService(named: .sendViaAirDrop)`, app kích hoạt tạm thời), Chia sẻ… (`NSSharingServicePicker`, ghim notch khi hiện), Xoá khỏi khay; nút "Xoá tất cả"; kéo thẻ ra ngoài (`setDragging`). Double-click mở mục (ngoài yêu cầu).
- Cài đặt `module.shelf.*`: `clearOnQuit` (false), `maxItems` (50; từ 10 đến 200), `removeAfterDragOut` (false).

## 2. Sai khác so với spec và lý do

- **Không dùng `NSFilePromiseReceiver`:** spec §2 nêu nó, nhưng `.onDrop` của SwiftUI chỉ cho `NSItemProvider`; file được hứa đọc bằng `loadFileRepresentation` rồi chép trong handler (đúng vòng đời file tạm). Chưa thử với Photos hay Mail thật.
- **`clearOnQuit` chạy khi thoát app, không phải mỗi lần module dừng.** Brief gốc nói "xoá khi stop", nhưng `stop()` cũng chạy khi Pause từ menu bar, khi tắt module và khi Retry, nên Pause sẽ xoá khay (và có thể là bản sao duy nhất của một ảnh Photos). Nay một observer `NSApplication.willTerminateNotification` xoá khay khi thoát; registry dừng module trước khi AppKit gửi thông báo này nên observer làm việc từ file trên đĩa. Hệ quả tốt kèm theo: thoát app lúc đang Pause cũng xoá.
- **Thả lại thẻ lên khay không nhân đôi:** `ShelfStore.add` chuyển file đã có (cùng URL) lên đầu thay vì chèn bản thứ hai, nên hai thẻ không chung một thư mục `promised/<uuid>/`.
- **Bản sao file được hứa không bao giờ bị xoá ngay khi kéo ra** (nơi nhận có thể còn đang đọc); lần tải kế tiếp quét thư mục `promised/` và xoá mọi thứ không thuộc mục nào còn giữ.
- Thả đang dở khi module dừng bị loại bỏ kèm bản sao vừa chép; thả hoàn tất sau khi khởi động lại không ghi đè khay mới.
- Văn bản chỉ có khoảng trắng bị từ chối. Thứ tự thả nhiều mục được giữ. `deleteStoredCopy` chỉ xoá `promised/<thư mục>/<file>`. Biểu tượng AirDrop là `airdrop`.
- **Hành vi NotchUI đã đổi (`4097fe8`):** `NotchViewModel.close()` giờ cũng đặt `isDragging = false`. Hệ quả: một lần đóng chủ động (phím tắt, Esc, `NotchHandle.close()`) giữa lúc kéo làm kết thúc chế độ kéo; nếu con trỏ vẫn trên vùng thả thì sự kiện kéo kế tiếp mở lại tab. `mouseDown` đặt lại `dragStartedInside` trước khi kiểm tra visible.
- Kéo bắt đầu từ trong notch (kéo một mục ra khỏi khay) không mở lại hay ghim notch.

## 3. Giới hạn đã chấp nhận (Ruling)

- **I4 (`removeAfterDragOut`) giữ ở mức một phần.** Khi bật tuỳ chọn, kéo bị huỷ (Esc) hoặc nơi nhận từ chối thì thẻ vẫn bị xoá, và bản sao file được hứa được dọn ở lần tải kế tiếp thay vì lúc kéo ra. Cách sửa thật cần một `NSDraggingSource` của AppKit (Clipboard và Screenshot dùng chung mẫu `.onDrag`, nên đáng làm một helper chung sau). Tuỳ chọn mặc định tắt nên mức phơi nhiễm nhỏ. **Chi phí nếu sai:** người dùng bật tuỳ chọn có thể mất một thẻ khi huỷ kéo (file thật không bị đụng, nhưng thẻ văn bản và link mất hẳn). Đã đưa vào checklist.
- Khác: crash hoặc force-quit bỏ qua `clearOnQuit`; module bị tắt suốt phiên chạy không được xoá khi thoát (chưa có observer).
- Đã bỏ qua trong vòng sửa Khay: `.withoutMounting` và cache URL theo từng mục (M2), chấp nhận vì đo được 0,09 ms mỗi lần; heuristic loader (URL trước, loại `.data` đầu tiên); giới hạn kích thước văn bản (quyết định sản phẩm); hạ `maxItems` không cắt ngay (cần observer cài đặt); dọn thư mục tạm của test.
- Đã bỏ qua trong vòng sửa NotchUI: chi phí đọc pasteboard cho mỗi sự kiện kéo, và `isTargeted` chập chờn (reviewer nói vô hại).

## 4. Khoảng trống đã biết

- **Brief H2-fix.md ghi bắt buộc "không resolve bookmark trong `body`", nhưng code vẫn resolve:** `ShelfCardView.body` gọi `state.store?.url(of:)` hai lần mỗi thẻ (`shareItems(for:)` và biểu tượng). Báo cáo sửa xếp mục này là Minor M2 và bỏ qua. Volume mạng không với tới được có thể làm notch khựng.
- Chưa có kết quả kiểm thử tay với dữ liệu thật: kéo từ Photos hoặc Mail, ảnh kéo từ trình duyệt (heuristic có thể coi ảnh là link), sheet AirDrop, picker chia sẻ (`NSSharingService` không có delegate nên không có phản hồi lỗi; `sharingID` có thể làm picker bật lại khi notch bị đóng cưỡng bức).
- Giới hạn `maxItems` thấp hơn số mục hiện có chỉ cắt ở lần thêm hoặc khởi động kế tiếp.

## 5. Sửa lại spec (Spec corrections)

- **§1**: `DropRouting.tab(for:tabs:preferring:)` ưu tiên tab đang hiện; kéo bắt đầu trong notch bị bỏ qua; `NotchViewModel.close()` kết thúc chế độ kéo; làm mới giao diện không bao giờ vào lại chế độ kéo.
- **§2, lời hứa file**: dùng `loadFileRepresentation`, không phải `NSFilePromiseReceiver`.
- **§2, cài đặt `clearOnQuit`**: chạy khi thoát app qua `willTerminateNotification`, không phải mỗi lần module dừng.
- **§2, thẻ**: thả lại một file đã có chuyển nó lên đầu; `removeAfterDragOut` xoá cả khi kéo bị huỷ (xem Ruling).
- **Dòng trạng thái** "Thiết kế" đã lỗi thời: module đã triển khai và gắn vào app.

## 6. Cần kiểm thử tay

Xem [mục Khay trong checklist gộp](../../manual-test-checklist-all.html#shelf). Không có quyền hệ thống; AirDrop và chia sẻ cần thao tác thật.
