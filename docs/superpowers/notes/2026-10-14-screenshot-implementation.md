# Ghi chú triển khai: Chụp màn hình, OCR và trình sửa ảnh

- **Ngày:** 2026-10-14
- **Spec:** [Chụp màn hình + OCR (dự án con 3)](../specs/2026-10-13-screenshot-design.html). Spec không bị sửa; chỗ đã lỗi thời nằm ở mục "Sửa lại spec".
- **Package:** `Packages/Modules/Screenshot`, product `ScreenshotModule`. Module id `screenshot` ("Ảnh chụp", order 300), tab "Ảnh chụp" (cao 200 pt), bật mặc định, quyền bắt buộc `.screenRecording`.
- **Commit chính:** `e0ce3a0` hình học, `31cc797` lưu trữ và OCR, `d6e8710` model và trình sửa, `c25a867` chụp, overlay, module, `611348c` sửa ảnh, `0bd2692` sửa lỗi lưu, `33bbe96` gắn vào app, `75ccd69` sửa thumbnail. Phụ: `b4f009a`, `d57cc9d`, `118d3d5` (chỉ mục ảnh an toàn hơn).
- **Test tự động:** 217 test theo báo cáo `S-fix-report` và báo cáo L1 (`verify.sh` qua ở `8a2b842`). Có OCR thật trên ảnh tổng hợp (Vision, chạy cục bộ). Mọi thứ chạm hệ thống (ScreenCaptureKit, overlay, pasteboard, phím tắt, hộp thoại quyền) đều dùng bản giả. Chưa chạy lại khi viết tài liệu này.
- **Kiểm thử tay:** [mục Ảnh chụp trong checklist gộp](../../manual-test-checklist-all.html#screenshot)

## 1. Đã xây gì so với spec

- `CaptureService` (`ScreenCaptureKitService`) là nơi duy nhất gọi ScreenCaptureKit: chụp đóng băng từng màn (loại trừ MyNotch, SDR, không con trỏ, đúng pixel Retina) và chụp riêng một cửa sổ (tuỳ chọn bóng).
- `GeometryMapper` và `WindowHitTester` thuần, có test nhiều màn và nhiều tỉ lệ. `OverlayInteraction` chứa mọi quyết định của overlay (phím, kéo, chế độ cửa sổ) với hơn 30 test.
- `SelectionOverlayController`: mỗi màn một panel `.screenSaver`, không activating, nhận bàn phím. Esc huỷ, Space đổi vùng và cửa sổ, Return chụp cả màn. Vùng chọn được căn theo lưới pixel của màn, tối thiểu 4 x 4 pixel, bị kẹp trong màn bắt đầu kéo, và bị huỷ nếu bố cục màn hình đổi.
- `CaptureStore`: PNG trong `captures/` cùng `captures.json`, giữ N ảnh gần nhất, thumbnail cache bộ nhớ và đĩa; chỉ mục hỏng thì dựng lại từ file và không bao giờ dọn ảnh khi chỉ mục không đọc được.
- `OCRService`: Vision `RecognizeTextRequest`, `.accurate`, ngôn ngữ mặc định vi-VN và en-US (so khớp theo `languageCode`, bỏ ngôn ngữ không hỗ trợ), phóng 2 lần ảnh nhỏ, chạy ngoài main actor.
- Trình sửa: mũi tên, hình chữ nhật, chữ, bút dạ quang, che vùng (làm pixel thô, không còn pixel gốc), hoàn tác và làm lại. Lưu bản gốc vào `captures/originals/` và chú thích JSON vào `captures/markup/` để sửa lại. Cửa sổ thường: app chuyển `.regular` khi mở và quay về `.accessory` khi đóng, trừ khi Settings còn mở.
- Module: phím tắt ⌃⌥S (chụp) và ⌃⌥O (OCR nhanh), activity "Đã chụp" (3 giây) và "Đã chép N ký tự", tab với menu ngữ cảnh đủ mục, kéo ảnh ra ngoài, cài đặt `module.screenshot.*` (`copyToClipboard` true, `keepCount` 30, `saveLocation` desktop, `windowShadow` true, `ocrLanguages`, `showCapturedActivity` true).
- Info.plist: `NSDesktopFolderUsageDescription` và `NSDownloadsFolderUsageDescription` có từ `7cccd10`. Không cần entitlement mới.

## 2. Sai khác so với spec và lý do

- **Nhãn "Chép", không phải "Copy":** tab dùng "Chép" và "OCR (chép chữ)"; thanh công cụ trình sửa đổi "Copy" thành "Chép" (quy ước chung của Clipboard, Shortcuts và toast "Đã chép ảnh").
- **Activity "Đã chụp" không bấm được:** spec §2.1 bước 6 nói click activity mở tab, nhưng không có cách bắt cú click activity. Tab là nơi tìm ảnh.
- **OCR có thêm trạng thái:** activity "Đang nhận chữ…" và có thể huỷ (Esc trên overlay hoặc chụp mới huỷ OCR trước), vì OCR vùng lớn mất vài giây.
- **API lưu trữ bất đồng bộ:** `add`, `replaceImage`, `thumbnail` và `export` là `async` (mã hoá và sao chép ngoài main actor). `CaptureRecord` có thêm `editedAt` để thumbnail trên thẻ tải lại sau mỗi lần lưu.
- **Kéo ảnh ra ngoài** dùng hard link vào thư mục tạm theo lượt kéo (dự phòng là copy), không copy toàn bộ PNG trên main khi bắt đầu kéo.
- **"Lưu thành…" đè file** dùng `replaceItemAt` thay vì xoá rồi chép, nên chép lỗi thì giữ file cũ.
- **Lưu khi đóng cửa sổ:** `EditorClosing.shouldCloseAfterSave` quyết định có đóng sau khi lưu không; sửa thêm trong lúc đang lưu thì giữ cửa sổ; bấm đóng trong lúc đang lưu thì bị bỏ qua (không hỏi) và cửa sổ tự đóng khi lưu xong.

## 3. Giới hạn đã chấp nhận (Ruling)

Ledger không gắn nhãn `Ruling:` cho Screenshot; bản ghi là "DONE_WITH_CONCERNS", mục nhỏ bị hoãn:

- **Minor 1 hoãn:** copy ảnh vào clipboard mã hoá lại PNG và "Đã chụp" phải chờ. Đo được PNG 0,5 s và TIFF 0,23 s ở 3024 x 1964; PNG 0,85 s và TIFF 0,6 s ở 6016 x 3384, nên activity trễ 1,3 đến 2,3 giây. Dùng lại byte PNG đã lưu cần đổi API `PasteboardWriting`, và đưa activity lên trước clipboard sẽ đảo thứ tự bước 5 và 6 của spec. Cần quyết định thiết kế.
- **Minor 3 hoãn:** việc chép vào `originals/` không nguyên tử (crash giữa chừng để lại bản gốc cụt, "Sửa" hỏng vĩnh viễn), và nếu JSON chú thích thiếu thì trình sửa mở bản gốc trần rồi Lưu ghi đè chú thích đang thấy. Cách sửa an toàn cần cờ "baseline là PNG đã lưu" trong `MarkupEditorSource`; nên là một task riêng.
- **Huy hiệu `hasMarkup`** (biểu tượng bút chì) có thể hiện lại sau khi chỉ mục hỏng được dựng lại, vì lúc đó nó suy từ "bản gốc còn tồn tại". Hoãn ở mức Minor, gộp vào review cuối.
- **Chú thích chưa lưu bị bỏ im lặng** khi module dừng (`closeAll`) hoặc thoát app bằng ⌘Q: không có lúc nào để hỏi. Đã ghi chú trong code.

## 4. Khoảng trống đã biết

- Chưa kiểm chứng: phím và focus của overlay trên nhiều Space và nhiều màn, Space fullscreen và Stage Manager; kích thước ảnh chụp cửa sổ có bóng (`ScreenCaptureKitService` đặt kích thước theo vùng nội dung cửa sổ); focus hộp thoại lưu; luồng hộp thoại quyền Screen Recording trong app. `SelectionOverlayController` và controller cửa sổ trình sửa không có test tự động.
- macOS 15 trở lên hỏi lại quyền Screen Recording định kỳ (khoảng hàng tháng) với app chụp không qua picker hệ thống. Không tránh được; Settings có ghi chú.
- Ký ad-hoc làm macOS quên quyền sau mỗi lần build lại. Xem README mục "Ký app".
- Một reviewer thấy một lần process test Screenshot crash (signal 11) dưới tải nặng, chạy lại thì qua. Chưa tái hiện được nên chưa xác định nguyên nhân.
- Khung đóng băng màn 6K tốn khoảng 80 MB; chỉ giữ trong lúc overlay mở (`detachedCrop` để không giữ cả khung).

## 5. Sửa lại spec (Spec corrections)

- **§2, hàng "Tab"**: nhãn là "Chép", "Lưu vào <vị trí của `saveLocation`>" (Desktop, Downloads hoặc Pictures), "Lưu thành…", "OCR (chép chữ)", "Sửa", "Xoá"; double-click thẻ mở trình sửa.
- **§2, hàng `CaptureStore`**: thêm `originals/`, `markup/`, `editedAt`, API `async`, dựng lại chỉ mục từ file.
- **§2.1 bước 6**: activity "Đã chụp" không mở tab khi click.
- **§2.1, OCR nhanh**: thêm activity "Đang nhận chữ…", huỷ được.
- **§2.3**: Info.plist `NSDesktopFolderUsageDescription` và `NSDownloadsFolderUsageDescription` đã có trong `project.yml`.
- **Dòng trạng thái** "Thiết kế, triển khai sau Media" đã lỗi thời.

## 6. Cần kiểm thử tay

Xem [mục Ảnh chụp trong checklist gộp](../../manual-test-checklist-all.html#screenshot). Các mục đụng quyền: Screen Recording (reset TCC trước khi thử), thư mục Desktop và Downloads khi lưu lần đầu.
