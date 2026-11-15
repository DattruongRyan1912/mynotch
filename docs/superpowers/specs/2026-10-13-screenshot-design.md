# MyNotch — Chụp màn hình + OCR (dự án con 3)

- **Ngày:** 2026-10-13
- **Trạng thái:** Đã triển khai (xem [ghi chú triển khai](../notes/2026-10-14-screenshot-implementation.html)). Chỗ đã đổi sau khi viết, kể cả activity "Đã chụp" ở bước 6: xem "Cập nhật 2026-10-18" ở cuối.
- **Nguồn:** nghiên cứu SDK macOS 26.5 (ScreenCaptureKit, Vision) và tài liệu Apple. Không dùng mã OneNotch.

## 1. Mục tiêu

**Trong phạm vi:**

- Chụp vùng (kéo chọn), cửa sổ (rê để tô sáng rồi click) hoặc toàn màn hình, trên mọi màn, đúng độ phân giải Retina.
- Khay ảnh gần đây trong notch với các thao tác: copy, lưu, kéo ra ngoài, xoá, OCR, sửa.
- Trình sửa ảnh đơn giản: mũi tên, hình chữ nhật, chữ, bút dạ quang, che vùng (pixelate), hoàn tác/làm lại.
- OCR: nhận chữ từ ảnh đã chụp, hoặc từ một vùng chọn nhanh, rồi copy văn bản. Hỗ trợ tiếng Việt và tiếng Anh.

**Ngoài phạm vi (để sau):**

- Chụp cuộn.
- Kính lúp khi chọn.
- Vùng chọn trải qua nhiều màn hình.
- HDR, quay video, ghim ảnh lên màn hình.

## 2. Thiết kế

Package `Packages/Modules/Screenshot`, product `ScreenshotModule`, quyền bắt buộc `.screenRecording`.

| Thành phần | Vai trò |
|---|---|
| `CaptureService` | Nơi duy nhất gọi ScreenCaptureKit. `freezeDisplays()` chụp mỗi màn bằng `SCScreenshotManager.captureScreenshot(contentFilter:configuration:)` với filter loại trừ MyNotch (`SCContentFilter(display:excludingApplications:exceptingWindows:)`), SDR, không con trỏ, kích thước pixel = point × `pointPixelScale`. `captureWindow(id:)` dùng `SCContentFilter(desktopIndependentWindow:)`. |
| `GeometryMapper` | Thuần, có test. Đổi toạ độ AppKit (gốc dưới-trái) ↔ CG (gốc trên-trái), point → pixel theo từng màn, kẹp vùng chọn trong một màn. |
| `WindowHitTester` | Thuần trên danh sách `CGWindowListCopyWindowInfo(.optionOnScreenOnly)` (thứ tự trước-sau): cửa sổ đầu tiên chứa điểm, `layer == 0`, bỏ PID của MyNotch. |
| `SelectionOverlayController` | Mỗi màn một panel `.borderless` + `.nonactivatingPanel`, `level = .screenSaver`, nhận bàn phím. Hiện khung hình đã đóng băng, làm tối phần ngoài vùng chọn, có con trỏ chữ thập và nhãn kích thước. Esc huỷ, Space đổi chế độ vùng ↔ cửa sổ, Return chụp cả màn đang có con trỏ. Trả `CaptureResult`. |
| `CaptureStore` | PNG (ImageIO) trong `storage.directory/captures/` + `captures.json`. Giữ N ảnh gần nhất (mặc định 30); ảnh thu nhỏ trong caches. |
| `OCRService` | `RecognizeTextRequest`, `.accurate`, `usesLanguageCorrection`, ngôn ngữ mặc định `[vi-VN, en-US]` (so khớp theo `languageCode`). Ảnh nhỏ được phóng 2× trước khi nhận. Kết quả xếp từ trên xuống. Chạy ngoài main actor. |
| `MarkupEditor` | Cửa sổ thường (app chuyển `.regular` khi mở, như Settings). Mô hình chú thích dạng value type, gộp nét ở đúng độ phân giải pixel bằng `CGContext`. Che vùng bằng pixelate thô hoặc tô kín, không dùng blur nhẹ. Lưu bản gốc + file JSON chú thích để sửa lại. |
| Tab "Ảnh chụp" | Lưới ảnh thu nhỏ. Menu ngữ cảnh: Copy, Lưu vào Desktop/Downloads, Lưu thành…, OCR, Sửa, Xoá. Kéo ra ngoài trả file URL (`setDragging`). |
| `ScreenshotModule` | Phím tắt, **chip nổi "Sửa/Chép"** sau khi chụp (ảnh thu nhỏ, 6 giây; bản đầu của spec là activity "Đã chụp" 3 giây, đã thay: xem cuối), cài đặt. |

### 2.1 Luồng chụp

1. Phím tắt → kiểm tra quyền (`CGPreflightScreenCaptureAccess`). Thiếu quyền thì hiện hướng dẫn (toast) thay cho overlay.
2. `freezeDisplays()` → hiện overlay trên mọi màn.
3. Người dùng chọn vùng, cửa sổ hoặc cả màn.
   - Vùng và cả màn: cắt từ khung đã đóng băng theo pixel.
   - Cửa sổ: chụp lại riêng cửa sổ đó, có tuỳ chọn bỏ bóng.
4. Giải phóng khung đóng băng ngay sau đó.
5. Lưu vào khay. Nếu `copyToClipboard` bật thì ghi PNG lên clipboard, không gắn đánh dấu của Clipboard: lịch sử clipboard ghi nhận ảnh chụp như mọi ảnh khác.
6. Hiện chip nổi ở góc trên bên phải (ảnh thu nhỏ, chữ "Đã chụp", nút "Sửa" và "Chép", 6 giây; nút "Sửa" mở trình sửa). *(Bản đầu của spec: activity "Đã chụp" 3 giây cạnh notch, click activity mở tab. Đã bỏ: không có cách bắt cú click một activity, vì rê vào notch thu gọn mở notch trước khi cú bấm tới.)*

Chế độ **OCR nhanh** dùng cùng overlay, nhưng chỉ ở chế độ vùng. Ảnh không được lưu: nhận chữ xong thì copy văn bản và hiện activity "Đã chép N ký tự".

### 2.2 Phím tắt mặc định

| Hành động | Phím |
|---|---|
| Chụp (overlay, chế độ vùng) | ⌃⌥S |
| OCR nhanh | ⌃⌥O |

### 2.3 Cài đặt (`module.screenshot.*`)

| Khoá | Mặc định | Ghi chú |
|---|---|---|
| `copyToClipboard` | true | |
| `keepCount` | 30 | 5…200 |
| `saveLocation` | `desktop` | `desktop`, `downloads`, `pictures`; dùng khi chọn "Lưu" |
| `windowShadow` | true | |
| `ocrLanguages` | `["vi-VN","en-US"]` | |
| `showCapturedActivity` | true | |

Lưu thẳng vào Desktop/Downloads cần usage description `NSDesktopFolderUsageDescription` và `NSDownloadsFolderUsageDescription` (thêm vào `project.yml`). "Lưu thành…" dùng `NSSavePanel`.

## 3. Rủi ro

- macOS 15+ hỏi lại quyền Screen Recording định kỳ (khoảng hàng tháng) với app chụp không qua system picker. Không tránh được; Settings giải thích điều này.
- Ký ad-hoc: macOS quên quyền sau mỗi lần build lại. Nên chuyển sang ký Apple Development (xem README).
- Khung đóng băng của màn 6K tốn khoảng 80 MB: chỉ giữ trong lúc overlay mở.
- Space fullscreen và Stage Manager: kiểm thử tay.

## 4. Kiểm thử

| Phần | Test tự động |
|---|---|
| `GeometryMapper` | Đổi toạ độ trên bố cục nhiều màn, scale khác nhau; kẹp vùng; làm tròn pixel |
| `WindowHitTester` | Thứ tự trước-sau, bỏ layer ≠ 0, bỏ PID của mình |
| `CaptureStore` | Lưu/đọc chỉ mục, giới hạn N, xoá file |
| `OCRService` | Ảnh tiếng Việt và tiếng Anh dựng bằng CoreText được nhận đúng, giữ dấu |
| Markup | Gộp nét: kích thước ảnh giữ nguyên; vùng che không còn pixel gốc; undo/redo |
| Module | Start/stop, phím tắt, activity (dùng `CaptureService` giả) |

**Kiểm thử tay:** chụp vùng, cửa sổ và cả màn trên MacBook và màn 4K; ảnh đúng độ phân giải; notch không lọt vào ảnh; OCR tiếng Việt; trình sửa; kéo ảnh ra ngoài; khi thiếu quyền.

## Cập nhật 2026-10-18

Spec này viết ngày 2026-10-13; những chỗ sau đã đổi khi làm và khi bổ sung (chi tiết ở [ghi chú triển khai](../notes/2026-10-14-screenshot-implementation.html), các mục 10 đến 12):

- **Bước 6 và dòng `ScreenshotModule`:** activity "Đã chụp" (3 giây, bấm mở tab) **không còn**. Thay bằng một chip nổi ở góc trên bên phải có "Sửa" và "Chép", sống 6 giây (SHOT1 `3f9f255`). Cài đặt "Hiện ảnh vừa chụp kèm nút Sửa" giữ khoá lưu cũ `showCapturedActivity`. Activity "Đã chép N ký tự" của OCR nhanh vẫn như trên.
- **Trình sửa** có thêm công cụ **Cắt** (Tự do, 1:1, 4:3, 16:9, "Như ảnh gốc"), và **"Chép ảnh vào clipboard khi sửa xong"** (mặc định bật; lần chép này là một lần chép bình thường nên nằm trong lịch sử Clipboard); đóng cửa sổ khi còn thay đổi hỏi "Lưu", "Bỏ thay đổi" hay "Tiếp tục sửa".
- **Quay màn hình** (⌃⌥R, ⌃⌥⇧R, trình sửa bản quay, xuất MP4) nằm trong cùng module: xem [spec quay màn hình](2026-10-18-screen-recording-design.html). **Dung lượng:** ảnh chụp và bản quay có mặt trên trang Dung lượng của Settings: xem [spec dọn dung lượng](2026-10-18-storage-cleanup-design.html).
