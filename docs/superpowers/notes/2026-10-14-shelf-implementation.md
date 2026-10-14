# Ghi chú triển khai: Khay file và điểm nối thả file lên notch

- **Ngày:** 2026-10-14
- **Spec:** [Khay file, Shortcuts, Hẹn giờ (dự án con 8), §1 và §2](../specs/2026-10-13-shelf-shortcuts-timer-design.html). Spec không bị sửa; chỗ đã lỗi thời nằm ở mục "Sửa lại spec".
- **Package:** `Packages/Modules/Shelf`, product `ShelfModule`. Module id `shelf` ("Khay", order 800), tab "Khay" (cao 170 pt), bật mặc định, không có quyền. Điểm nối thả file nằm trong `Packages/NotchUI` và `NotchTab` của `Packages/MyNotchCore`.
- **Commit chính:** `09a2548` điểm nối thả file (H1), `378c5d5` sửa H1, `48430fc` Khay (H2), `e2d8575` sửa Khay vòng 1, `a21e9a6` sửa Khay vòng 2 (nguồn kéo AppKit, cache URL), `4097fe8` sửa NotchUI (kết thúc kéo khi ẩn), `e2b0586` gắn vào app.
- **Test tự động:** Shelf 62 test (báo cáo `H2-fix2-report`), NotchUI 77 (báo cáo L1); `verify.sh` qua sau mỗi đợt sửa. Phiên kéo thật của AppKit và hit testing dưới chuột thật không chạy được trong test, nên phần đó chỉ kiểm bằng tay. Chưa chạy lại khi viết tài liệu này.
- **Kiểm thử tay:** [mục Khay trong checklist gộp](../../manual-test-checklist-all.html#shelf)

## 1. Đã xây gì so với spec

**Điểm nối thả file (spec §1, NotchUI):**

- `NotchTab` có thêm `dropTypes: [UTType]` và `onDrop: (([NSItemProvider]) -> Bool)?`.
- `NotchHoverTracker` theo dõi `leftMouseDragged` và `leftMouseUp`, và so `changeCount` của pasteboard kéo (`NSPasteboard(name: .drag)`) để biết phiên kéo có dữ liệu. Khi đang kéo, panel nhận chuột trong vùng rộng hơn (`NotchGeometry.dragHitRect`: notch cộng 40 pt mỗi bên và phía dưới). Khi con trỏ vào vùng đó, notch mở tab đầu tiên có `dropTypes` khớp (ưu tiên tab đang hiện) và gọi `setDragging(true)`; rời đi hoặc nhả chuột thì kết thúc.
- `NotchRootView` gắn `.onDrop(of:isTargeted:)` ở mọi trạng thái và chuyển dữ liệu cho tab đang mở.
- Phần thuần có test: `DropRouting.tab(for:tabs:preferring:)` và `DropRouting.dragAction` (phân biệt di chuyển thật với làm mới giao diện), hình học vùng kéo.

**Khay (spec §2):**

- `ShelfStore` lưu `shelf.json` (ghi nguyên tử, giải mã từng mục, giới hạn `maxItems`, bỏ mục có bookmark hỏng khi tải). File: `url.bookmarkData()` (app không sandbox). File được hứa (Photos, Mail): chép vào `storage.directory/promised/<uuid>/`. Văn bản và link lưu trực tiếp.
- **Cache vị trí file:** `ShelfStore` giữ `locations: [UUID: URL]`, điền một lần lúc tải (lần resolve vốn đã cần để bỏ bookmark hỏng) và một lần lúc thêm. `url(of:)` chỉ đọc cache, nên `body` không bao giờ resolve bookmark. `refreshedURL(of:)` resolve lại cho hành động cần file thật (bắt đầu kéo, mở, hiện trong Finder, chia sẻ, AirDrop), cập nhật cache, bookmark (khi hệ thống báo cũ) và tên; `refreshLocations()` chạy khi tab hiện (`onAppear`).
- **Kéo thẻ ra ngoài là nguồn kéo AppKit thật:** lớp trong suốt `ShelfDragSourceView` (`NSViewRepresentable` phủ lên thẻ, file `ShelfDragSource.swift`) gọi `beginDraggingSession` với `ShelfDragSession` (`NSDraggingSource`). Chỉ cho phép `copy`, `link`, `generic`, không bao giờ `move` hay `delete`. Lớp chỉ nhận cú nhấn chuột trái thường (`hitTest`), nên menu ngữ cảnh (chuột phải, ctrl-click) và cuộn ngang vẫn chạy; double-click mở mục; nhận chuột ngay lần nhấn đầu (notch không bao giờ là cửa sổ active). Dữ liệu kéo là `NSPasteboardWriting` (`NSString`, hoặc `NSURL` cho link và file). Hình xem trước là biểu tượng 40 x 40 của thẻ. `setDragging(true)` ngay trước phiên và `setDragging(false)` ở callback kết thúc, nên notch giữ mở khi kéo và thả ra sau đó, không còn dò nút chuột.
- Tab: lưới thẻ (biểu tượng, tên). Menu ngữ cảnh: Mở, Hiện trong Finder, AirDrop (`NSSharingService(named: .sendViaAirDrop)`, app kích hoạt tạm thời), Chia sẻ… (`NSSharingServicePicker`, ghim notch khi hiện), Xoá khỏi khay; nút "Xoá tất cả". Danh sách chia sẻ chỉ được dựng khi bấm chọn, không dựng mỗi lần vẽ.
- Cài đặt `module.shelf.*`: `clearOnQuit` (false), `maxItems` (50; từ 10 đến 200), `removeAfterDragOut` (false).

## 2. Sai khác so với spec và lý do

- **Không dùng `NSFilePromiseReceiver`:** spec §2 nêu nó, nhưng `.onDrop` của SwiftUI chỉ cho `NSItemProvider`; file được hứa đọc bằng `loadFileRepresentation` rồi chép trong handler (đúng vòng đời file tạm). Chưa thử với Photos hay Mail thật.
- **`removeAfterDragOut` chỉ xoá thẻ sau một lần kéo hoàn tất** (`ShelfDragOutcome.removesCard`: tuỳ chọn bật và `operation` không rỗng). Esc, hoặc thả vào nơi từ chối, kết thúc với `operation` rỗng và không xoá gì (thẻ văn bản, link, file và file được hứa đều còn). Thẻ đã được thả lại lên khay trong lúc kéo thì đã bị chuyển lên đầu, không còn khớp và được giữ. Bản đầu dùng `.onDrag` của SwiftUI kèm dò nút chuột, không biết kéo kết thúc ra sao, nên xoá cả khi huỷ; đó là lỗ hổng mất dữ liệu đã được sửa ở `a21e9a6`.
- **Bản sao file được hứa không bao giờ bị xoá ngay khi kéo ra** (nơi nhận có thể còn đang đọc). Lần tải kế tiếp của store (khởi động, resume, bật lại module) quét thư mục `promised/` và xoá mọi thứ không thuộc mục nào còn giữ (`removeOrphanedCopies`). Một lần quét này cũng dọn bản sao của mục bị cắt vì `maxItems`, của lần thả lỗi và của thư mục rỗng. Hệ quả: ảnh Photos đã kéo ra nằm trên đĩa tới lần tải kế tiếp.
- **`clearOnQuit` chạy khi thoát app, không phải mỗi lần module dừng.** Brief gốc nói "xoá khi stop", nhưng `stop()` cũng chạy khi Pause từ menu bar, khi tắt module và khi Retry, nên Pause sẽ xoá khay (và có thể là bản sao duy nhất của một ảnh Photos). Nay một observer `NSApplication.willTerminateNotification` xoá khay khi thoát (`queue: nil`, vì một block xếp vào main queue có thể chưa chạy khi tiến trình thoát); registry dừng module trước khi AppKit gửi thông báo này nên observer làm việc từ file trên đĩa. Hệ quả tốt kèm theo: thoát app lúc đang Pause cũng xoá.
- **`.withoutMounting` khi resolve bookmark** (`[.withoutUI, .withoutMounting]`): file trên chia sẻ mạng chưa được mount lúc MyNotch khởi động bị bỏ khỏi khay khi tải. Trước đây nó được mount âm thầm trong lúc main thread chờ. Ổ ngoài đã rút thì trước đây cũng bị bỏ như vậy.
- **Thả lại thẻ lên khay không nhân đôi:** cùng file (cùng URL trong cache), cùng văn bản hay cùng link đều được chuyển lên đầu (giữ id, đổi `addedAt`) thay vì chèn bản thứ hai, nên hai thẻ không chung một thư mục `promised/<uuid>/`.
- Thả đang dở khi module dừng bị loại bỏ kèm bản sao vừa chép; thả hoàn tất sau khi khởi động lại không ghi đè khay mới. Thả không đọc được gì thì ghi log (chỉ loại type, không có nội dung).
- Văn bản chỉ có khoảng trắng bị từ chối. Thứ tự thả nhiều mục được giữ. `deleteStoredCopy` chỉ xoá `promised/<thư mục>/<file>`. Biểu tượng AirDrop là `airdrop`. Double-click mở mục (ngoài yêu cầu).
- **Hành vi NotchUI đã đổi (`4097fe8`):** `NotchViewModel.close()` giờ cũng đặt `isDragging = false`. Hệ quả: một lần đóng chủ động (phím tắt, Esc, `NotchHandle.close()`) giữa lúc kéo làm kết thúc chế độ kéo; nếu con trỏ vẫn trên vùng thả thì sự kiện kéo kế tiếp mở lại tab. `mouseDown` đặt lại `dragStartedInside` trước khi kiểm tra visible, và `dragTypes` được xoá khi ẩn.
- Kéo bắt đầu từ trong notch (kéo một mục ra khỏi khay) không mở lại hay ghim notch.

## 3. Giới hạn đã chấp nhận (Ruling)

- **Ruling (`.withoutMounting`):** file trên chia sẻ mạng chưa mount lúc khởi động bị bỏ khỏi khay, chấp nhận theo brief. **Chi phí nếu sai:** thẻ của một file ở ổ mạng chưa mount biến mất sau khi mở lại app (file thật không bị đụng).
- **Ruling cũ về I4 đã bị đảo ngược.** Ledger ban đầu ghi "I4 giữ ở mức một phần": kéo bị huỷ vẫn xoá thẻ, chỉ cần `NSDraggingSource` khi có thời gian, chi phí là mất thẻ văn bản hoặc link. Sau đó ledger đảo lại Ruling này (người dùng muốn làm hết hàng đợi, và đường mất dữ liệu không nên tồn tại) và `a21e9a6` đã làm nguồn kéo AppKit. Không còn giới hạn nào về việc này, ngoài chuyện nó chưa được kiểm bằng phiên kéo thật.
- Khác: crash hoặc force-quit bỏ qua `clearOnQuit`; module bị tắt suốt phiên chạy không được xoá khi thoát (chưa có observer).
- Đã bỏ qua trong các vòng sửa: heuristic loader (URL trước, loại `.data` đầu tiên, cần kéo thật từ Photos, Mail, trình duyệt); giới hạn kích thước văn bản (quyết định sản phẩm); hạ `maxItems` không cắt ngay (cần observer cài đặt); chi tiết chia sẻ (bỏ ghim khi chọn, xoá `sharingID` khi đóng cưỡng bức, vòng đời `NSSharingService`).
- Đã bỏ qua trong vòng sửa NotchUI: chi phí đọc pasteboard cho mỗi sự kiện kéo, và `isTargeted` chập chờn (reviewer nói vô hại).

## 4. Khoảng trống đã biết

- Chưa có kết quả kiểm thử tay với dữ liệu thật: phiên kéo AppKit (bắt đầu ở lần nhấn đầu, notch giữ mở và đóng lại bình thường, Esc, thả vào nơi từ chối), kéo từ Photos hoặc Mail, ảnh kéo từ trình duyệt (heuristic có thể coi ảnh là link), sheet AirDrop, picker chia sẻ (`NSSharingService` không có delegate nên không có phản hồi lỗi; `sharingID` có thể làm picker bật lại khi notch bị đóng cưỡng bức).
- Thẻ văn bản hoặc link thả lại lên khay khi `removeAfterDragOut` bật: callback kết thúc có thể đến trước khi lần thêm bất đồng bộ xong, nên thẻ cũ bị xoá trước và thẻ mới hiện sau một chút. Kết quả vẫn là một thẻ.
- Hình xem trước khi kéo là biểu tượng 40 x 40, không còn ảnh chụp cả thẻ như `.onDrag`.
- Clipboard và Screenshot vẫn dùng `.onDrag` kèm dò nút chuột; `ShelfDragSource.swift` có thể tái dùng cho chúng sau (nằm ngoài package này).
- Giới hạn `maxItems` thấp hơn số mục hiện có chỉ cắt ở lần thêm hoặc khởi động kế tiếp.

## 5. Sửa lại spec (Spec corrections)

- **§1**: `DropRouting.tab(for:tabs:preferring:)` ưu tiên tab đang hiện; kéo bắt đầu trong notch bị bỏ qua; `NotchViewModel.close()` kết thúc chế độ kéo; làm mới giao diện không bao giờ vào lại chế độ kéo.
- **§2, lời hứa file**: dùng `loadFileRepresentation`, không phải `NSFilePromiseReceiver`.
- **§2, cài đặt `clearOnQuit`**: chạy khi thoát app qua `willTerminateNotification`, không phải mỗi lần module dừng.
- **§2, kéo thẻ ra**: nguồn kéo `NSDraggingSource` của AppKit; `removeAfterDragOut` chỉ xoá sau một lần kéo hoàn tất; bản sao file được hứa được quét ở lần tải kế tiếp; hình xem trước 40 x 40; chỉ nhận `copy`, `link`, `generic`.
- **§2, bookmark**: resolve với `.withoutUI` và `.withoutMounting`, cache vị trí theo từng mục, resolve lại khi dùng; file ở ổ chưa mount bị bỏ khi tải.
- **§2, thẻ**: thả lại một file, văn bản hay link đã có chuyển nó lên đầu.
- **Dòng trạng thái** "Thiết kế" đã lỗi thời: module đã triển khai và gắn vào app.

## 6. Cần kiểm thử tay

Xem [mục Khay trong checklist gộp](../../manual-test-checklist-all.html#shelf). Không có quyền hệ thống; AirDrop, chia sẻ và mọi lần kéo cần thao tác thật.
