# Quay màn hình để gửi demo: Kế hoạch triển khai

> **Trạng thái (2026-10-18):** đã làm hết REC1 đến REC4 (`8ef594e`, `323c4ce`, `52223c7`, `ed609c9`, `2d8d2d3`, `c7553d1`) và việc dung lượng ST3 (`55a3560`, `41dba8a`). Kế hoạch giữ nguyên như lúc viết; chỗ khác và kết quả: [ghi chú Ảnh chụp, mục 11 và 12](../notes/2026-10-14-screenshot-implementation.html).

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Quay màn hình từ notch, có micro. Chỉnh sửa gồm cắt và zoom tự động theo hoạt động. Xuất MP4 rồi chép vào clipboard.

**Architecture:**
- Tất cả nằm trong gói `Packages/Modules/Screenshot`, thư mục `Recording/`. Nếu tách target thì: `RecordingKit` cho engine và zoom (không mặc định MainActor), phần còn lại ở `ScreenshotModule`.
- **Lúc quay:** ScreenCaptureKit ghi hình, micro và (tuỳ chọn) âm thanh hệ thống ra file gốc. Song song là một bản ghi hoạt động: vị trí con trỏ, cú bấm, và các lần có phím được nhấn.
- **Zoom, cắt và hiệu ứng bấm** chỉ áp khi xem trước và khi xuất, qua `AVComposition` và `AVVideoComposition`. File gốc không bị đổi.

**Spec:** `docs/superpowers/specs/2026-10-18-screen-recording-design.md`

## Global Constraints

- Thư mục mỗi bản quay là `<ModuleStorage.directory>/Recordings/<uuid>/`, gồm:
  - các đoạn file gốc (mỗi lần tạm dừng sinh một đoạn mới);
  - `activity.json`;
  - `project.json`, chứa các đoạn bị cắt, các chỉnh sửa zoom, hiệu ứng bấm và mức xuất.
- **Quy tắc zoom mặc định:**
  - phóng to 2×, chuyển vào trong 0,5 s;
  - hoạt động là cú bấm, di chuyển con trỏ và có phím được nhấn;
  - hết đoạn khi đã 1,5 s không có hoạt động, thu về trong 0,6 s;
  - một cú bấm lúc đang thu về thì phóng lại từ mức hiện tại;
  - hai đoạn cách nhau dưới 2,5 s thì nối thành một;
  - không giới hạn độ dài một đoạn.
- **"Một cửa sổ"** là vùng màn hình bằng khung cửa sổ lúc bắt đầu, giữ cố định.
- **Mức xuất:**
  - **"Gửi chat":** tối đa 1080p, 30 fps, H.264 khoảng 4–6 Mbit/s, kèm AAC 128 kbit/s.
  - **"Chất lượng cao":** độ phân giải gốc, chiều rộng tối đa 4096 px, H.264, fps như lúc quay.
  - Lưu ở `~/Movies/MyNotch/`. Xuất xong chép URL file vào clipboard, có marker `OwnPasteboardWrite`.
- **Không bao giờ tự xoá bản quay**, trừ khi người dùng bật tuỳ chọn trong ST3.
- Cửa sổ MyNotch không được lọt vào video: lọc chính app ra bằng `SCContentFilter`.
- Không ghi phím nào được nhấn, chỉ ghi thời điểm.
- Test không quay màn hình thật và không mở micro thật. Dùng nguồn khung hình giả, nguồn sự kiện giả, và video mẫu tạo ra trong test.
- `xcrun swift test` ×3 trong gói Screenshot, không cảnh báo.

## Review Focus

1. **Quay vài phút rồi xuất:** hình và tiếng không lệch, kể cả sau khi cắt đoạn giữa và qua các lần tạm dừng. Test ở REC2 và REC3.
2. **App crash giữa lúc quay:** phần đã quay vẫn mở được. Test ở REC1.
3. **Bấm liên tục hoặc vừa bấm vừa gõ:** zoom không giật, đường đi của khung liên tục, không nhảy quá ngưỡng mỗi khung hình. Test ở REC2.
4. **Màn hình hoặc vùng chọn rộng hơn 4096 px:** bản xuất "Chất lượng cao" bị thu về 4096. Test ở REC3.
5. **Thiếu quyền micro hoặc quyền ghi màn hình:** báo rõ, không treo, không quay ra file rỗng. Test ở REC1 và REC4.

---

### REC1: Engine quay và bản ghi hoạt động

- **Ghi hình:**
  - `RecordingSession` ghi bằng `SCStream`: độ phân giải gốc của vùng, 60 fps, `showsCursor = true`, `captureMicrophone` với micro đã chọn, và âm thanh hệ thống nếu bật (`excludesCurrentProcessAudio = true`).
  - Bộ lọc bỏ cửa sổ của chính MyNotch. Vùng là `sourceRect` của màn hình.
  - Ghi ra file bằng bộ mã hoá phần cứng. Người làm chọn `SCRecordingOutput` hay `AVAssetWriter`, với điều kiện **cứu được bản quay dở** (ví dụ `movieFragmentInterval` khoảng 2 s). Ghi lý do chọn vào báo cáo.
  - Tạm dừng thì đóng đoạn hiện tại và mở đoạn mới khi tiếp tục.
- **Bản ghi hoạt động:**
  - `ActivityRecorder` lấy vị trí con trỏ khoảng 60 lần mỗi giây, các cú bấm (trái và phải), và thời điểm có phím được nhấn qua global monitor (cần quyền Trợ năng; thiếu quyền thì chỉ ghi chuột).
  - Thời gian theo cùng đồng hồ với khung hình. Toạ độ quy về hệ toạ độ của vùng quay.
  - Lưu thành `activity.json`.
- **`RecordingProject`:** đọc và ghi `project.json`. Danh sách bản quay gồm ngày, thời lượng, dung lượng và trạng thái "quay dở".
- **Test:** nguồn khung hình giả và nguồn sự kiện giả với đồng hồ tiêm vào; quy đổi toạ độ; hai đoạn khi tạm dừng; cứu một file bị cắt cụt do test tự tạo; báo lỗi khi thiếu quyền.
- **Commit:** `feat(screenshot): record the screen with the microphone, and what the pointer did`

### REC2: Lập kế hoạch zoom, đường đi của khung, và composition

- **`ZoomPlanner.plan(activity:rules:) -> [ZoomSegment]`** là hàm thuần. `ZoomSegment` có `start`, `end`, `scale` và các điểm focus.
- **`CameraPath.rect(at:)`** trả khung cắt đã làm mượt, bằng lò xo tắt tới hạn hoặc đường ease. Khung không bao giờ ra ngoài khung hình.
- **`RecordingComposition`:**
  - Ghép các đoạn file và áp các khoảng bị cắt thành `AVMutableComposition`.
  - `AVVideoComposition` có compositor riêng, cắt và phóng theo `CameraPath`, rồi vẽ vòng tròn khi bấm nếu bật.
  - Dùng cho cả xem trước lẫn xuất.
- **Test:**
  - Bảng quy tắc zoom: gộp, hết đoạn khi không có hoạt động, gõ phím giữ zoom, phóng lại từ mức hiện tại.
  - Đường đi liên tục: bước nhảy mỗi khung dưới ngưỡng.
  - Thời gian sau khi cắt, với video mẫu do test tạo bằng `AVAssetWriter`.
  - Vòng tròn hiện đúng lúc bấm.
  - Tiếng khớp hình sau khi cắt.
- **Commit:** `feat(screenshot): zoom that follows the pointer, applied when previewing and exporting`

### REC3: Cửa sổ chỉnh sửa và xuất

- **Cửa sổ:**
  - AppKit window, nội dung SwiftUI, mở khi dừng quay hoặc mở lại từ danh sách.
  - Xem trước bằng `AVPlayer` với composition.
  - Timeline gồm dải ảnh thu nhỏ, tay kéo cắt đầu và cuối, chọn một khoảng rồi bấm "Cắt" để bỏ.
  - Dải zoom: các đoạn zoom hiện thành khối. Chọn thì bỏ được, kéo mép đổi thời gian, thanh trượt đổi mức phóng to (1,25×–3×), và nút "Thêm zoom tại đây".
  - Công tắc hiệu ứng bấm và chọn mức xuất.
  - Hoàn tác và làm lại. Mọi chỉnh sửa lưu vào `project.json`.
- **Xuất:**
  - Đọc qua composition và ghi bằng `AVAssetWriter` với bitrate đã chốt, hiện tiến độ, huỷ được.
  - Xuất xong chép URL file vào clipboard, có nút "Hiện trong Finder", và kéo file ra ngoài được.
- **Test:**
  - Các mức xuất cho ra đúng kích thước, fps và khoảng bitrate trên video mẫu.
  - Thu về 4096 px.
  - Clipboard giả nhận URL kèm marker.
  - Chỉnh sửa được lưu.
  - Huỷ xuất dọn file dở.
- **Commit:** `feat(screenshot): edit a recording, and export it ready to paste`

### REC4: Nối vào module

- **Tab Chụp màn hình:**
  - Nút "Quay" với ba cách chọn: màn hình, cửa sổ, vùng. Dùng lại lớp chọn có sẵn.
  - Đếm ngược 3 giây, tắt được.
  - Danh sách "Bản quay gần đây" hiện dung lượng, có Mở và Xoá (hỏi lại trước khi xoá).
- **Lúc đang quay:**
  - Live activity trên notch: chấm đỏ, thời gian, Tạm dừng, Dừng.
  - Mục trên menu bar (`menuItems`) khi notch bị ẩn.
  - Phím tắt cho Bắt đầu/Dừng và cho Tạm dừng, đặt lại được.
- **Cài đặt:** chọn micro, âm thanh hệ thống (mặc định tắt), đếm ngược, mức và thời gian zoom mặc định, hiệu ứng bấm mặc định, mức xuất mặc định.
- **Quyền micro:** xin quyền lần đầu. Thiếu quyền ghi màn hình thì hướng dẫn mở System Settings.
- **Người điều phối:** thêm `NSMicrophoneUsageDescription` vào `project.yml`.
- **Test:** chạy qua `RegistryHarness` với engine giả: bắt đầu, tạm dừng và dừng sinh ra activity đúng, menu bar đúng, phím tắt đúng; xoá bản quay chỉ xoá thư mục của nó, không xoá file đã xuất.
- **Commit:** `feat(screenshot): record from the notch`

## Thứ tự

- REC1 → REC2 → REC3 → REC4, cùng gói nên làm lần lượt.
- Bắt đầu sau SHOT1.
- Nhóm "Bản quay" cho trang Dung lượng thuộc ST3, làm sau REC4.
