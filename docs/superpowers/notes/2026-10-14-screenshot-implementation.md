# Ghi chú triển khai: Chụp màn hình, OCR và trình sửa ảnh

- **Ngày:** 2026-10-14
- **Spec:** [Chụp màn hình + OCR (dự án con 3)](../specs/2026-10-13-screenshot-design.html). Spec không bị sửa; chỗ đã lỗi thời nằm ở mục "Sửa lại spec".
- **Package:** `Packages/Modules/Screenshot`, product `ScreenshotModule`. Module id `screenshot` ("Ảnh chụp", order 300), tab "Ảnh chụp" (cao 200 pt), bật mặc định, quyền bắt buộc `.screenRecording`, quyền tuỳ chọn `.desktopFolder` và `.downloadsFolder` (từ P11b, `335f489`).
- **Commit chính:** `e0ce3a0` hình học, `31cc797` lưu trữ và OCR, `d6e8710` model và trình sửa, `c25a867` chụp, overlay, module, `611348c` sửa ảnh, `0bd2692` sửa lỗi lưu, `33bbe96` gắn vào app, `75ccd69` sửa thumbnail. Phụ: `b4f009a`, `d57cc9d`, `118d3d5` (chỉ mục ảnh an toàn hơn).
- **Test tự động:** 217 test theo báo cáo `S-fix-report` và báo cáo L1 (`verify.sh` qua ở `8a2b842`). Có OCR thật trên ảnh tổng hợp (Vision, chạy cục bộ). Mọi thứ chạm hệ thống (ScreenCaptureKit, overlay, pasteboard, phím tắt, hộp thoại quyền) đều dùng bản giả. Chưa chạy lại khi viết tài liệu này.
- **Kiểm thử tay:** [mục Ảnh chụp trong checklist gộp](../../manual-test-checklist-all.html#screenshot)
- **Cập nhật sau `156f02d` (2026-10-15):** đánh số bước, kính lúp, thước đo, xoá thông minh và canvas tự mở rộng (`00cb437`, `d6e83ef`) (mục 7 và 8). Screenshot 326 test (`d6e83ef`). Chưa ai nhìn bằng mắt.

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
- Bản sao ảnh tạo khi kéo ảnh ra (`$TMPDIR/MyNotch Screenshot Drags/`, hard link, dự phòng là copy) chỉ được quét ở lần khởi động kế tiếp, nên "xoá" hay tắt module không xoá chúng ngay (review tích hợp, Minor, hoãn).

## 5. Sửa lại spec (Spec corrections)

- **§2, hàng "Tab"**: nhãn là "Chép", "Lưu vào <vị trí của `saveLocation`>" (Desktop, Downloads hoặc Pictures), "Lưu thành…", "OCR (chép chữ)", "Sửa", "Xoá"; double-click thẻ mở trình sửa.
- **§2, hàng `CaptureStore`**: thêm `originals/`, `markup/`, `editedAt`, API `async`, dựng lại chỉ mục từ file.
- **§2.1 bước 6**: activity "Đã chụp" không mở tab khi click.
- **§2.1, OCR nhanh**: thêm activity "Đang nhận chữ…", huỷ được.
- **§2.3**: Info.plist `NSDesktopFolderUsageDescription` và `NSDownloadsFolderUsageDescription` đã có trong `project.yml`.
- **Dòng trạng thái** "Thiết kế, triển khai sau Media" đã lỗi thời.

## 6. Cần kiểm thử tay

Xem [mục Ảnh chụp trong checklist gộp](../../manual-test-checklist-all.html#screenshot). Các mục đụng quyền: Screen Recording (reset TCC trước khi thử), thư mục Desktop và Downloads khi lưu lần đầu.

## Cập nhật 2026-10-15 (quyền và activity)

- **Khai báo quyền (P11b).** Bắt buộc: `.screenRecording` ("Chụp màn hình."). Tuỳ chọn: `.desktopFolder` ("Lưu ảnh vào Desktop (nơi lưu mặc định của “Lưu vào”).") và `.downloadsFolder` ("Lưu ảnh vào Downloads khi chọn nơi lưu là Downloads."); Pictures không cần hộp thoại. Hai hàng thư mục hiện ở trang Quyền với nhãn xám "Chưa kiểm tra được" (macOS không cho kiểm trước) và nút "Cấp quyền" gây hộp thoại lần đầu; Downloads dùng chung với module Hệ thống. Vì Screen Recording là quyền bắt buộc nên thiếu nó module ở `.needsPermission`, tab và phím tắt biến mất cho tới khi cấp, và gợi ý `showPermissionHint` trong module không bao giờ tới (đúng spec, review P11b).
- **Activity là notice.** "Đã chụp" (3 giây) và kết quả OCR (3 giây) có hạn nên chiếm notch vài giây kể cả khi nhạc đang phát, rồi nhạc quay lại (ghi chú nền tảng, mục 8). "Đang nhận chữ…" không có hạn nên không phải notice.

## 7. Từ `156f02d` đến hết 2026-10-15: đánh số bước, kính lúp, thước đo, xoá thông minh và canvas tự mở rộng (R3e)

Commit `00cb437`, vòng sửa quyền riêng tư `d6e83ef`. Test: Screenshot **326 test trong 28 suite** (218 trước R3e, 311 sau commit đầu), ba lần chạy sạch, 0 cảnh báo; review R3e: Approved, rồi **review quyền riêng tư r1: Approved** (các dò thử thấy 52 trên 83 chỗ rò trên bản cha, 0 sau sửa). Tất cả mở rộng trình sửa ảnh có sẵn: cùng `UndoStack` (ảnh chụp cả tài liệu), cùng đường xuất `MarkupRenderer.flatten` mà Lưu và Chép dùng. **Chưa ai nhìn bằng mắt** (không ảnh thật, không cửa sổ, không sự kiện thật; mọi test dùng `CGImage` tổng hợp và pasteboard giả).

### 7.1 Năm thứ mới trong trình sửa

| Công cụ | Tên trên thanh công cụ | Làm gì |
|---|---|---|
| Đánh số bước | **Đánh số bước** | Bấm thả một huy hiệu đánh số 1, 2, 3 theo màu hiện tại (cỡ theo độ dày đã chọn); kéo trước khi nhả thì di chuyển nó; **⌥-bấm** vào một huy hiệu thì xoá và đánh số lại. Chữ số đen hay trắng theo độ sáng của màu. |
| Kính lúp | **Kính lúp** | Kéo từ tâm ra ngoài. Hiện **chính các điểm ảnh đã vẽ bên dưới** phóng 1,5 đến 4 lần (mặc định 2; một hàng thanh trượt hiện dưới thanh công cụ), có viền theo màu hiện tại đúng ở mép vòng tròn. Lấy mẫu lúc **flatten**, nên xuất ra điểm ảnh và gồm cả chú thích vẽ trước. |
| Thước đo | **Thước đo** | Kéo giữa hai điểm: đường, vạch hai đầu và một viên chữ "240 px", hay trên ảnh Retina "240 px (120 pt)". **⇧** giữ theo trục mà cú kéo đi nhiều hơn. Tỉ lệ điểm ảnh trên point của ảnh được lưu trong chú thích. Số point tính từ số điểm ảnh đã làm tròn nên hai số luôn khớp. |
| Xoá thông minh | **Xoá thông minh** | Kéo một hình chữ nhật. Vòng 2 px **ngay ngoài** nó được lấy mẫu; nếu gần đồng nhất thì tô bằng màu chủ đạo của vòng, nếu không thì làm pixel (cùng kiểu làm pixel không đảo ngược như "Che vùng"). Tooltip nói rõ điều này. |
| Canvas tự mở rộng | (không có công cụ) | Một hình, chữ, huy hiệu, kính lúp hay thước vươn ra ngoài mép ảnh thì canvas lớn ra. Màu phần đệm là cài đặt (Settings → Ảnh chụp): **Trong suốt / Trắng / Đen / Màu viền ảnh** (mặc định: màu viền ảnh). Undo (hay xoá chú thích) co lại. |

- **Canvas được suy ra, không lưu:** chú thích giữ toạ độ tương đối với góc trên trái ảnh chụp (có thể âm); canvas là ảnh chụp cộng các khoảng đệm nguyên điểm nhỏ nhất chứa mọi chú thích thò ra (`MarkupDocument.canvas`). Undo, redo và xoá một huy hiệu co hay mở lại canvas mà không cần sổ sách thêm; JSON không có trường canvas nên file markup cũ vẫn mở được. Màu đệm cũng không lưu trong JSON: theo cài đặt lúc mở trình sửa.
- **Tăng trưởng:** bỏ qua nửa ngoài của nét khi đường viền nằm trên hay trong mép (một hình chữ nhật kéo đúng tới mép không thêm một dải đệm 2 điểm ảnh); khi đường viền đã vượt mép thì toàn bộ mực (độ dày nét, đầu mũi tên, viên nhãn) nằm trong. Che vùng và xoá thông minh **không bao giờ** mở rộng canvas (điểm bị kẹp vào canvas hiện có). Mọi thứ khác có thể mở, tối đa nửa cạnh dài của ảnh chụp (ít nhất 256 điểm ảnh) mỗi phía, nên kéo ra khỏi cửa sổ không đòi một bitmap khổng lồ.
- **Xoá thông minh:** "đồng nhất" nghĩa là phương sai của các điểm ảnh ở vòng, lấy trung bình trên R, G, B, alpha ở thang 0 đến 255, tối đa 64 (độ lệch chuẩn 8): chịu được nhiễu nén hay dải chuyển nhạt, không chịu chữ, đường nối hay hai nền (`EdgeColorSampler.uniformVarianceLimit`). Vòng ở **ngoài** vì một hình chữ nhật vẽ sát chữ nếu lấy bên trong sẽ lấy mẫu chính chữ và luôn rơi về làm pixel. "Chủ đạo" là trung bình của ô màu 16 mức đầy nhất. Hình chạm mép ảnh lấy mẫu các cạnh còn có; hình phủ cả canvas không có vòng nên làm pixel.
- **Thay đổi bố cục:** bề rộng tối thiểu của thanh công cụ 780 lên **900 pt** và cửa sổ trình sửa mở ở **1040 × 680** (chín nút công cụ không còn vừa chỗ cũ).
- **Quirk đã biết:** ⌥ được đọc lúc nhả nút chuột, nên nhấn ⌥ giữa cú kéo của công cụ đánh số thì xoá ở điểm nhả thay vì đặt (M2 hoãn).

### 7.2 Ruling (review R3e M1, quyền riêng tư, "phải sửa"): vùng đã che không được lộ trong kính lúp

`flatten` áp các chú thích đúng thứ tự và kính lúp lấy mẫu bitmap ngay lúc đó, nên một **Che vùng** hay **Xoá thông minh** vẽ **sau** kính lúp để lại một bản phóng to của các điểm ảnh bị che bên trong kính (người review đo được khoảng 10.500 điểm ảnh đọc được cho một vùng che 40 × 40 dưới kính 4×). **Sửa:** mỗi kính lúp lấy mẫu bức ảnh **như nó kết thúc**: bitmap tại điểm đó của quá trình vẽ cùng **mọi lần che và xoá đứng sau nó, bất kể thứ tự** (`snapshot(of:applying:)` sao chép bitmap, áp các `PixelEffect` đứng sau lên bản sao, và `magnify` vẽ từ bản sao đó; bitmap đang chạy không bị đụng). Không sao chép được thì **bỏ kính** chứ không vẽ từ điểm ảnh chưa che. **Lệch so với đề xuất ("dựng bản che và xoá trước, rồi kính lúp, rồi chú thích khác"):** không làm đúng nghĩa đen vì nó đổi hai hành vi đã ghim: một lần che vẽ sau một mũi tên, hộp hay chữ gõ phải tiếp tục che chúng (một bí mật gõ thành chữ rồi bị che sẽ lộ ra), và kính lúp tiếp tục phóng to các chú thích vẽ trước nó. Yêu cầu cốt lõi (không kính lúp nào hiện điểm ảnh mà một lần che hay xoá giấu đi) đúng ở cả hai thứ tự và được ghim bằng test (so điểm ảnh chính xác với bản che-trước ở mọi nơi ngoài vùng bị giấu). Giá: một lần sao chép bitmap cho mỗi kính có che hay xoá sau nó (vài mili giây trên ảnh 5K).
- **Mọi lối ra đi qua cùng đường:** Chép từ trình sửa (`copyMarkup`) và Lưu (`saveMarkup` qua `keepSidecars`) gọi `MarkupRenderer.flatten`; Chép, OCR, "Lưu vào" (`CaptureStore.export`), "Lưu thành…" (`export(_:to:)`), thumbnail và kéo thẻ ra ngoài (`dragFileURL`, liên kết cứng tới PNG đã lưu) đều đọc PNG hiển thị đã lưu (là đầu ra flatten), không cái nào đọc `originalURL`. **Cần biết:** bản gốc chưa che và JSON markup **vẫn nằm trên đĩa** cạnh ảnh chụp để sửa lại được (thiết kế có sẵn, không đổi ở đây); chúng không bao giờ bị chép, kéo hay xuất. Nếu "đã che" còn phải nghĩa là "không còn trên đĩa" thì đó là việc khác.
- **M5 và M6 (cùng đường vẽ):** toạ độ khổng lồ không còn làm sập `Int(...)` (`CanvasInsets.growing` kẹp ở dấu phẩy động trước khi đổi; `flatten` kẹp phần đệm theo cỡ ảnh thật; `Ruler.label` kẹp khoảng cách ở 10^9 px); một lần vẽ hỏng giữ bản xem trước tốt cuối cùng cùng canvas khớp với nó (tài liệu không vẽ được lúc mở thì mở như ảnh chụp trơn).
- **Minor hoãn của R3e** (đều không nằm trên đường che): M2 (chốt ⌥ lúc nhấn nút), M3 (giới hạn tổng điểm ảnh của canvas), M4 (chốt bề rộng thanh công cụ), M7, M8; và từ review quyền riêng tư: một `imageSize` vô lý có thể sập, màu đệm lấy trước khi che, bỏ kính im lặng, chi phí sao chép mỗi kính trên main với canvas rất lớn, thiếu test kính lồng và canvas đã mở rộng.

## 8. Cần kiểm thử tay (phần mới)

Xem [mục Ảnh chụp trong checklist gộp](../../manual-test-checklist-all.html#screenshot): bố cục thanh công cụ chín nút ở bề rộng 900 pt và hàng thanh trượt kính lúp; kéo ra ngoài mép ảnh (canvas lớn ra khi nhả, view khớp lại); huy hiệu bước (viền, căn số ở cả ba độ dày, ⌥-bấm xoá); viền kính lúp và vòng đứt nét khi kéo; thước trên ảnh Retina ("… px (… pt)", ⇧); xoá thông minh trên ảnh giao diện thật (nền phẳng so với ảnh chụp ảnh); cài đặt màu đệm; **che vùng rồi kiểm kính lúp không lộ chữ bị che (Chép, Lưu, kéo thẻ ra)**.
