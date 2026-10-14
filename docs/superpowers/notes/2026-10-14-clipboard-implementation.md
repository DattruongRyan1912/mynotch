# Ghi chú triển khai: Clipboard

- **Ngày:** 2026-10-14
- **Spec:** [Clipboard (dự án con 1)](../specs/2026-10-13-clipboard-design.html). Spec chỉ được sửa ở các chỗ C8 thêm (cửa sổ Thư viện, gợi ý quyền, mặc định dán: mục 5); chỗ khác đã lỗi thời nằm ở mục "Sửa lại spec".
- **Package:** `Packages/Modules/Clipboard`, product `ClipboardModule`. Module id `clipboard`, tab "Clipboard" (order 100, cao 230 pt, nhận bàn phím), bật mặc định.
- **Commit chính:** `4aa8577` model và classifier, `6146cf6` lịch sử và tìm kiếm, `8ebf5af` lưu trữ, `ea56f9e` pasteboard và dán, `d80c169` module, `54dda24` tab, `c37957c` gắn vào app, `1798f76` sửa chọn thẻ khi tìm, `009871c` mở tab qua `context.presenter.open()` (một dòng trong `ClipboardModule.swift`). Sau đó (2026-10-14 tối): cửa sổ Thư viện `7e3e26e`, dán là mặc định kèm gợi ý Accessibility `3f3d804`, khai báo quyền và lý do `335f489`.
- **Test tự động:** 281 test theo báo cáo P11b (196 trước Thư viện; 271 sau `7e3e26e`; 280 sau `3f3d804`; 281 với `declaresThePermissionsItUsesAndWhy`); `verify.sh` qua ở `594063d`. Chưa chạy lại khi viết tài liệu này.
- **Kiểm thử tay:** [mục Clipboard trong checklist gộp](../../manual-test-checklist-all.html#clipboard)

## 1. Đã xây gì so với spec

- Đủ phạm vi spec §1: ghi text, rich text (RTF), link, mã màu, ảnh, file; bỏ qua dữ liệu nhạy cảm, app bị loại trừ và trạng thái tạm dừng; lưu JSON cùng ảnh PNG riêng.
- Tab có ô tìm kiếm, lọc theo loại, board, băng chuyền thẻ, điều khiển bàn phím, menu ngữ cảnh, kéo thẻ ra app khác. 12 phép biến đổi văn bản. ⌃⌥V mở tab. Dán trực tiếp bằng ⌘V giả (cần Accessibility, tuỳ chọn). Cửa sổ Thư viện (⌃⌥⇧V, nút trong tab, menu bar): mục 6.
- Khớp spec: poll 0,3 s qua `context.scheduler`, chỉ đọc nội dung khi `changeCount` đổi, băm SHA-256 để khử trùng, 500 mục, giữ 1 tháng, ảnh 250 MB, mười khoá cài đặt `module.clipboard.*` đúng mặc định.
- Tìm kiếm dùng chỉ mục đã gấp dấu (`ClipboardSearchIndex`), nên gõ không chậm với 5000 mục. Đ và đ được gấp thành d.
- Không cần khoá Info.plist mới. Quyền tuỳ chọn khai báo (P11b): `.accessibility` ("Dán mục bạn chọn vào app đang dùng (giả lập ⌘V).") và `.pasteboard` ("Ghi lại mọi lần chép mà macOS không hỏi lại."), hiện ở trang Quyền của Settings; `.pasteboard` chỉ mở pane, không có API xin.

## 2. Sai khác so với spec và lý do

Nguồn: `mntasks/clipboard/deviations.md` và các lần review.

- Mã màu không có `#` phải có ít nhất một chữ số và một chữ A-F, để không nhận nhầm OTP `123456`, ngày `20251013` hay từ `facade`.
- Link `http/https` phải có host, `mailto:` phải có địa chỉ. Chuỗi `http://` trống là văn bản.
- RTF lớn hơn 2 MB được lưu thành văn bản thuần.
- Copy trùng nội dung thì giữ bản mới nhất (rich text và văn bản thuần cùng hash).
- Giới hạn số mục và dung lượng ảnh chỉ tính mục chưa ghim. Mục đã ghim không bị dọn và không chiếm hạn mức (spec nói mục trong board không bị dọn, nhưng không nói về hạn mức).
- Đọc lịch sử từng mục một: một mục lỗi chỉ làm mất riêng mục đó.
- Biến đổi JSON giữ nguyên số (Decimal) và sắp xếp khoá. "Bỏ khoảng trắng thừa" giữ thụt đầu dòng. Base64 giải mã chấp nhận base64url.
- Tìm kiếm: chỉ mục cache theo id và hash, tối đa 20 000 ký tự mỗi mục. File chỉ tìm theo tên file.
- Chưa có quyền Accessibility mà chọn "dán": mục được chép, notch đóng ngay và hiện activity `pasteHint` trong 3 giây (biểu tượng clipboard bên trái, bàn phím kèm "⌘V" bên phải, vừa khung 64 pt), không phải dòng chữ "Đã chép — nhấn ⌘V để dán" của spec. Ghi pasteboard lỗi thì notch giữ mở và hiện toast "Không chép được mục này".
- Lưu: trễ 1 giây sau thay đổi cuối nhưng không quá 5 giây kể từ thay đổi đầu tiên. Mã hoá và ghi file chạy ngoài main thread. `boards.json` ghi trước `history.json`.
- File lịch sử hỏng được đổi tên cùng thư mục ảnh (`images.corrupt-<thời điểm>/`) để khôi phục được. Tên file ảnh chỉ chấp nhận dạng `<sha256>.png`.

## 3. Giới hạn đã chấp nhận (Ruling)

Ledger không có dòng `Ruling:` nào riêng cho Clipboard. Các điểm sau là quyết định thiết kế đã ghi trong brief:

- Chỉ đọc item đầu tiên trên pasteboard (cộng mọi file URL), như phần lớn app quản lý clipboard.
- **Ruling (C8, người dùng yêu cầu từ ảnh chụp thư viện của app tham chiếu):** mở thư viện bằng nút trong tab Clipboard, phím tắt module ⌃⌥⇧V và mục menu bar; thanh bên Tất cả, Boards, Loại (Văn bản gồm rich text, Link, Ảnh, Màu, File), Ứng dụng; lưới và danh sách, sắp xếp, thanh trượt cỡ thẻ, lọc loại, Board mới. Nhóm "Ảnh chụp" (gộp ảnh của module Screenshot) hoãn vì là việc của hai module. **Chi phí nếu sai:** ảnh chụp chưa hiện trong thư viện. Dòng "Cửa sổ Library riêng" trong phần ngoài phạm vi của spec đã bị thay.
- **Ruling (người dùng, 2026-10-14):** `clickAction` mặc định đổi từ `copy` sang `paste`, kèm gợi ý Accessibility trong tab và thư viện. Lý do: bấm một mục không dán vào con trỏ vì `clickAction` mặc định là `copy` và dán cần Accessibility (mất sau lần reset TCC; Accessibility không bao giờ hỏi lại). **Chi phí nếu sai:** ai chưa từng chọn gì thấy hành vi đổi (người đã lưu `copy` thì giữ nguyên).
- Phân loại chạy đồng bộ trên main actor, kể cả đổi TIFF sang PNG (chỉ khi không có PNG). Comment trong `ClipboardMonitor` ghi đã đo 0,17 s cho TIFF 96 MB. Chưa có số đo trên ảnh lớn hơn.

## 4. Khoảng trống đã biết

- Mẫu kéo thẻ `.onDrag` kèm dò nút chuột (poll) để báo hết kéo vẫn đang dùng, chưa có `NSDraggingSource`. Khay đã chuyển sang nguồn kéo AppKit (`ShelfDragSource.swift`, `a21e9a6`) vì cần biết kéo có hoàn tất không; Clipboard và Screenshot không xoá gì sau khi kéo nên chưa cần, nhưng helper đó có thể tái dùng.
- Bản sao ảnh và file tạo khi kéo thẻ ra (`$TMPDIR/MyNotch Clipboard Drags/<uuid>/`) không bao giờ được quét: hệ thống dọn thư mục tạm (khoảng 3 ngày) và "xoá lịch sử", tắt module hay thoát app không xoá chúng (review tích hợp, Minor, hoãn). Screenshot chỉ quét thư mục tương tự ở lần khởi động kế tiếp.
- Brief C7 yêu cầu thêm mục "Ghi chú triển khai" vào spec và mục Clipboard vào checklist. Việc đó chưa bao giờ được làm; tài liệu này và checklist gộp thay thế.
- Phần giao diện chưa có kết quả kiểm thử tay nào được ghi lại: phím, focus, menu ngữ cảnh ghim notch, kéo thả. Toàn bộ nằm trong checklist.
- **Minor đã hoãn của review C8** (Approved, 0 Critical, 0 Important, 9 Minor; các mục chính): `raise(id: "pasteHint")` thừa và chú thích trên nó đã cũ (mục 7); ⌘V gửi vô điều kiện 250 ms sau `NSApp.deactivate()` từ thư viện, nếu focus không rời thì phím rơi vào chính thư viện (tiếng bíp hoặc chữ vào ô tìm) và notice bị xoá nên lỗi im lặng (cách rẻ: bỏ qua khi app trước mặt vẫn là MyNotch rồi rơi về "Đã chép — nhấn ⌘V"); vòng thăm dò 2 giây của gợi ý chạy suốt đời cửa sổ kể cả khi thu nhỏ hay khi gợi ý đã hết; lỗi ghi pasteboard hay lỗi biến đổi gọi `presenter.showToast` làm notch bật mở trên desktop cạnh dòng thông báo riêng của thư viện (hai lần); ⌘A đặt focus ở mục cuối nên cuộn xuống đáy một lịch sử dài; Delete sau ⌘A xoá mọi mục chưa ghim không hỏi (5000 mục một phím); ⌘F không focus ô tìm kiếm và gõ khi chưa focus không làm gì.
- **Chưa nhìn bằng mắt (C8):** thanh bên (mục, huy hiệu, icon app, vùng thả), thanh tiêu đề (một nút ẩn hiện thanh bên chứ không hai hay không có, tiêu đề phụ "<lựa chọn> · N mục", ô tìm kiếm), sáng và tối, thanh trượt cỡ thẻ, chuyển lưới và danh sách; dán từ thư viện vào app phía sau trong 250 ms; thẻ trong notch vẫn giống trước (`ClipboardContentPreview` dùng chung); gợi ý trên hàng board khi notch hẹp (`openWidth` cho tới 480 pt, gợi ý `fixedSize` khoảng 300 pt có thể ép thanh board).

## 5. Sửa lại spec (Spec corrections)

- §3.7 nói thêm `Permission.pasteboard` vào MyNotchCore. Lúc viết ghi chú này code không có case đó; từ P11a (`37ec63d`) có (pane-only, trạng thái đọc từ `NSPasteboard.general.accessBehavior`) và Clipboard khai báo nó là quyền tuỳ chọn (`335f489`). Module vẫn tự đọc `accessBehavior` (không đọc nội dung): Settings hiện hướng dẫn chọn "Luôn cho phép" và tab hiện hướng dẫn khi bị từ chối (`pasteboardDenied`).
- §3.1: quy tắc mã màu không `#`, link và RTF quá lớn như mục 2 ở trên.
- §3.2: giới hạn số mục và ảnh chỉ tính mục chưa ghim.
- §3.3: lưu "trễ 1 giây" nhưng không quá 5 giây kể từ thay đổi đầu; file hỏng đổi tên cả thư mục ảnh.
- §3.4: nhãn menu ngữ cảnh là "Chép", "Chép dạng văn bản thuần", "Biến đổi", "Ghim vào board", "Bỏ ghim" (spec ghi "Copy" và "Copy dạng văn bản thuần").
- §3.4: gợi ý khi thiếu Accessibility là activity `pasteHint` ("⌘V") 3 giây, không phải dòng chữ đầy đủ; thêm toast "Không chép được mục này" khi ghi pasteboard lỗi.
- §3.5: tìm kiếm qua `ClipboardSearchIndex`, không qua `ClipboardSearch.filter` trực tiếp.
- **Đã sửa thẳng trong spec (C8, ngoại lệ so với quy tắc không sửa spec):** dòng phạm vi (cửa sổ Thư viện, ⌃⌥⇧V), dòng ngoài phạm vi (bỏ "Cửa sổ Library riêng", thêm nhóm "Ảnh chụp" của thư viện), §3.4 (gợi ý quyền, thêm 2026-10-14), §3.6 (`clickAction` mặc định `paste`) và §3.8 (cửa sổ Thư viện). Mục 6 và 7 dưới đây là phần ghi chú triển khai của các chỗ đó.
- **§3.4, activity**: `copied` (1,5 giây) và `pasteHint` (3 giây) là notice của luật activity mới (xem [ghi chú nền tảng](2026-10-14-platform-foundation-implementation.html), mục 8): chiếm notch vài giây kể cả khi nhạc đang phát.
- **§3, trạng thái**: thêm `FeatureModule.menuItems` làm mục "Thư viện Clipboard…" trên menu bar.

## 6. Cửa sổ Thư viện (C8, 2026-10-14)

Người dùng bỏ "Cửa sổ Library riêng" khỏi danh sách ngoài phạm vi; spec §3.8 mô tả bản đã làm. Commit: `feat(clipboard): add the clipboard library window`. Mã nằm ở `Packages/Modules/Clipboard/Sources/ClipboardModule/Library/`.

- Model thuần (`ClipboardLibraryModel`, `ClipboardLibraryContent`) theo dõi `ClipboardState` qua `observeHistory` chỉ khi cửa sổ mở; cửa sổ (`ClipboardLibraryWindowController`) tạo mới mỗi lần mở và bỏ view khi đóng. Test model bằng `ClipboardState` và `ClipboardLibraryActions` giả, không có pasteboard hay cửa sổ thật.
- Menu bar: module chưa có cách thêm mục vào menu của status item, nên `FeatureModule` có thêm `menuItems` (mặc định rỗng; `ModuleRegistry.menuItems` chỉ lấy của module đang chạy) và `App/StatusItemController.swift` vẽ chúng đầu menu mỗi lần mở. Đây là thay đổi ở MyNotchCore và App duy nhất của C8.
- Thanh bên là `List` của SwiftUI; bản dựng ngoài màn hình không vẽ được nó, nên chưa nhìn thấy kết quả.
- Cửa sổ chứa `NavigationSplitView` trong `NSHostingController` (`sceneBridgingOptions = .all`). Khi dựng thử trong một cửa sổ trong suốt (không hiện ra màn hình), thanh công cụ và tiêu đề phụ vào được `NSWindow`, nhưng `navigationTitle` không đổi tiêu đề cửa sổ và `NSToolbar` không có nút ẩn/hiện thanh bên. Nên cửa sổ đặt tiêu đề "Thư viện Clipboard", tiêu đề phụ "<lựa chọn> · N mục" và tự thêm nút thanh bên (`.toolbar(removing: .sidebarToggle)` để không thành hai nút). Chưa nhìn thấy cửa sổ thật.
- `ClipboardLibraryActivation` chép lại logic của `EditorActivation` (Screenshot) vì module không import nhau.
- Dán từ cửa sổ dựa vào `NSApp.deactivate()` để app phía sau nhận lại phím trong 250 ms: chưa thử trên máy thật.

## 7. Dán là mặc định và gợi ý quyền (2026-10-14)

Commit: `feat(clipboard): paste by default and show how to allow it`.

- `clickAction` mặc định đổi từ `copy` sang `paste` (spec §3.6). Chỉ đổi giá trị mặc định: ai đã lưu `copy` thì vẫn là `copy`, và Settings vẫn có cả hai lựa chọn.
- Gợi ý quyền (spec §3.4): `ClipboardState.needsAccessibility` do `ClipboardModule.refreshAccessibility()` đặt (click là dán và `isTrusted()` sai); `ClipboardAccessibilityHint` hiện ở tab và ở cửa sổ Thư viện, nút "Cấp quyền" đi qua `requestAccessibility()` và `context.permissions` (`request(.accessibility)` rồi `openSystemSettings(for:)`), nên test dùng `FakePermissionCenter`, không có hộp thoại hay URL thật.
- Vị trí ở tab: cạnh hàng board, không phải một dòng riêng ở trên cùng. Vùng nội dung của tab 230 pt chỉ có 186 pt (trừ đệm 14 pt và thanh tab 30 pt) và hàng tìm kiếm, hàng board, thẻ đã dùng hết; dựng thử ngoài màn hình cho thấy thêm một dòng nữa làm thẻ bị cắt. Chiều cao của tab là hằng số nên chưa thể co giãn theo gợi ý.
- Kiểm tra lại mỗi 2 giây chỉ khi view còn hiện (`.task` của tab và của cửa sổ); quyền được cấp trong System Settings thì dòng biến mất trong tối đa 2 giây.
- **Activity là notice (UI2b).** `copied` (1,5 giây) và `pasteHint` (3 giây) có `expiresAfter` nên là notice: chiếm notch vài giây kể cả khi nhạc đang phát, rồi nhạc quay lại; gợi ý "⌘V" vì vậy không bị nhạc che. `context.activities.raise(id: "pasteHint")` (thêm ở `3f3d804` khi luật "cái đến đầu tiên thắng" của UI2a làm đỏ test `activateWithPasteWithoutAccessibilityOnlyCopiesClosesAndShowsTheHint`) vẫn còn nhưng thừa (bỏ đi thì mọi test vẫn qua) và chú thích bên trên đã cũ; nó chỉ giữ một notice đến sau khỏi che gợi ý trong 3 giây.
- **Khai báo quyền (P11b, `335f489`).** `optionalPermissions: [.accessibility, .pasteboard]` kèm hai lý do ở trên; trang Quyền hiện dòng "Dán từ app khác" ở hàng "Tuỳ chọn" kèm nút "Mở Cài đặt" (chưa kiểm neo `Privacy_Pasteboard`).

## 8. Cần kiểm thử tay

Xem [mục Clipboard trong checklist gộp](../../manual-test-checklist-all.html#clipboard). Các mục đụng quyền: hộp thoại "Dán từ app khác" của macOS, dán trực tiếp cần Accessibility.
