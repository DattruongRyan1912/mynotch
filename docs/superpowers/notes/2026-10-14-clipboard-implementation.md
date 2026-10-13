# Ghi chú triển khai: Clipboard

- **Ngày:** 2026-10-14
- **Spec:** [Clipboard (dự án con 1)](../specs/2026-10-13-clipboard-design.html). Spec không bị sửa; chỗ đã lỗi thời nằm ở mục "Sửa lại spec".
- **Package:** `Packages/Modules/Clipboard`, product `ClipboardModule`. Module id `clipboard`, tab "Clipboard" (order 100, cao 230 pt, nhận bàn phím), bật mặc định.
- **Commit chính:** `4aa8577` model và classifier, `6146cf6` lịch sử và tìm kiếm, `8ebf5af` lưu trữ, `ea56f9e` pasteboard và dán, `d80c169` module, `54dda24` tab, `c37957c` gắn vào app, `1798f76` sửa chọn thẻ khi tìm.
- **Test tự động:** 196 test theo báo cáo L1 (`verify.sh` qua ở `8a2b842`). Chưa chạy lại khi viết tài liệu này.
- **Kiểm thử tay:** [mục Clipboard trong checklist gộp](../../manual-test-checklist-all.html#clipboard)

## 1. Đã xây gì so với spec

- Đủ phạm vi spec §1: ghi text, rich text (RTF), link, mã màu, ảnh, file; bỏ qua dữ liệu nhạy cảm, app bị loại trừ và trạng thái tạm dừng; lưu JSON cùng ảnh PNG riêng.
- Tab có ô tìm kiếm, lọc theo loại, board, băng chuyền thẻ, điều khiển bàn phím, menu ngữ cảnh, kéo thẻ ra app khác. 12 phép biến đổi văn bản. ⌃⌥V mở tab. Dán trực tiếp bằng ⌘V giả (cần Accessibility, tuỳ chọn).
- Khớp spec: poll 0,3 s qua `context.scheduler`, chỉ đọc nội dung khi `changeCount` đổi, băm SHA-256 để khử trùng, 500 mục, giữ 1 tháng, ảnh 250 MB, mười khoá cài đặt `module.clipboard.*` đúng mặc định.
- Tìm kiếm dùng chỉ mục đã gấp dấu (`ClipboardSearchIndex`), nên gõ không chậm với 5000 mục. Đ và đ được gấp thành d.
- Không cần khoá Info.plist mới. Quyền tuỳ chọn duy nhất là `.accessibility`.

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
- Phân loại chạy đồng bộ trên main actor, kể cả đổi TIFF sang PNG (chỉ khi không có PNG). Comment trong `ClipboardMonitor` ghi đã đo 0,17 s cho TIFF 96 MB. Chưa có số đo trên ảnh lớn hơn.

## 4. Khoảng trống đã biết

- Mẫu kéo thẻ `.onDrag` kèm dò nút chuột (poll) để báo hết kéo vẫn đang dùng, chưa có `NSDraggingSource`. Ledger ghi việc này là "shared helper, later" chung với Screenshot và Shelf.
- Brief C7 yêu cầu thêm mục "Ghi chú triển khai" vào spec và mục Clipboard vào checklist. Việc đó chưa bao giờ được làm; tài liệu này và checklist gộp thay thế.
- Phần giao diện chưa có kết quả kiểm thử tay nào được ghi lại: phím, focus, menu ngữ cảnh ghim notch, kéo thả. Toàn bộ nằm trong checklist.

## 5. Sửa lại spec (Spec corrections)

- §3.7 nói thêm `Permission.pasteboard` vào MyNotchCore. Không có case này trong code. Module tự đọc `NSPasteboard.general.accessBehavior` (không đọc nội dung): Settings hiện hướng dẫn chọn "Luôn cho phép" và tab hiện hướng dẫn khi bị từ chối (`pasteboardDenied`).
- §3.1: quy tắc mã màu không `#`, link và RTF quá lớn như mục 2 ở trên.
- §3.2: giới hạn số mục và ảnh chỉ tính mục chưa ghim.
- §3.3: lưu "trễ 1 giây" nhưng không quá 5 giây kể từ thay đổi đầu; file hỏng đổi tên cả thư mục ảnh.
- §3.4: nhãn menu ngữ cảnh là "Chép", "Chép dạng văn bản thuần", "Biến đổi", "Ghim vào board", "Bỏ ghim" (spec ghi "Copy" và "Copy dạng văn bản thuần").
- §3.4: gợi ý khi thiếu Accessibility là activity `pasteHint` ("⌘V") 3 giây, không phải dòng chữ đầy đủ; thêm toast "Không chép được mục này" khi ghi pasteboard lỗi.
- §3.5: tìm kiếm qua `ClipboardSearchIndex`, không qua `ClipboardSearch.filter` trực tiếp.

## 6. Cần kiểm thử tay

Xem [mục Clipboard trong checklist gộp](../../manual-test-checklist-all.html#clipboard). Các mục đụng quyền: hộp thoại "Dán từ app khác" của macOS, dán trực tiếp cần Accessibility.
