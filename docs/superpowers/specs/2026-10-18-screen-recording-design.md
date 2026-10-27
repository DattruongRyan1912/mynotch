# MyNotch: quay màn hình để gửi demo

- **Ngày:** 2026-10-18
- **Trạng thái:** Đã duyệt (2026-10-18) và đã triển khai (REC1 đến REC4): xem [ghi chú Ảnh chụp, mục 11](../notes/2026-10-14-screenshot-implementation.html). Chỗ khác với spec: file gốc là HEVC, fragmented, trong các file `segment-00N.mov` (spec để người làm chọn định dạng file gốc, mục 7); "Chất lượng cao" bị giới hạn bởi H.264 level 5.2 (một màn 5K ở 60 fps ra 3946 × 2218); file MP4 xuất chép vào clipboard với dấu "của MyNotch" nên không vào lịch sử Clipboard.
- **Tham khảo tính năng:** OpenScreen (getopenscreen.com, giấy phép MIT). Chỉ tham khảo tính năng. Tự viết, không chép mã, giống mọi module của MyNotch.

## 1. Ý định

Người dùng quay demo tính năng để gửi đồng nghiệp qua Messenger, Zalo, Tanka và các kênh khác. Họ nói qua micro khi quay, không cần webcam. Quay xong họ cắt bớt, rồi **zoom theo con trỏ chuột** để người xem dễ theo dõi.

OneNotch có tính năng quay màn hình, và người dùng muốn MyNotch có tính năng tương đương. Họ muốn gọn hơn một ứng dụng riêng, nhưng vẫn có cắt và zoom.

Thành công nghĩa là quay một đoạn demo, cắt, có zoom tự động, xuất ra và dán vào Zalo, tất cả trong vài phút, không cần app khác.

## 2. Mục tiêu

- **Bắt đầu quay:** từ tab Chụp màn hình trên notch, hoặc bằng phím tắt.
  - Chọn **cả màn hình**, **một cửa sổ**, hoặc **một vùng**, dùng lại lớp chọn vùng và cửa sổ mà module Chụp màn hình đã có.
  - Có đếm ngược 3 giây (tắt được).
- **Đang quay:**
  - Notch hiện chấm đỏ, thời gian đã quay, nút **Dừng** và nút **Tạm dừng** (tạm dừng thì video không có đoạn đó).
  - Phím tắt dừng.
  - Cửa sổ của MyNotch, kể cả notch, không lọt vào video.
- **Âm thanh:**
  - Micro **mặc định bật**, chọn được micro nào.
  - Âm thanh hệ thống là tuỳ chọn, **mặc định tắt**.
  - Hình và tiếng không bị lệch.
- **Con trỏ và cú bấm:**
  - Con trỏ có trong video.
  - Vị trí con trỏ và các cú bấm được ghi riêng thành dữ liệu kèm theo, để làm zoom và hiệu ứng bấm khi xuất.
- **Cửa sổ chỉnh sửa** mở ra khi dừng quay:
  - xem lại, phát và tua;
  - **cắt** đầu và cuối, cắt bỏ đoạn giữa;
  - **zoom tự động theo cú bấm**: một quy tắc cố định, không dùng AI. Phóng to quanh chỗ bấm, đi theo con trỏ khi đang phóng to, thu về khi con trỏ ngừng hoạt động;
  - mỗi đoạn zoom hiện trên timeline. **Bỏ** được, chỉnh **mức phóng to** và **thời gian** của từng đoạn, và **thêm** một đoạn zoom bằng tay;
  - hiệu ứng vòng tròn nhỏ khi bấm chuột, bật hoặc tắt được;
  - xem trước có zoom ngay khi phát.
- **Xuất MP4** (H.264 kèm AAC), mở được ở mọi nơi.
  - Hai mức: **"Gửi chat"**, mặc định, tối đa 1080p, 30 fps, dung lượng vừa phải; và **"Chất lượng cao"**, độ phân giải gốc, 60 fps nếu quay ở 60 fps.
  - Xuất xong: file được **chép vào clipboard**, dán thẳng vào Zalo hay Messenger được. Có thể kéo file từ cửa sổ chỉnh sửa, và có nút "Hiện trong Finder".
- **Danh sách bản quay gần đây** trong tab Chụp màn hình: mở lại để chỉnh, hoặc xoá.

## 3. Không làm (đợt này)

- Webcam và xoá phông webcam.
- Làm mờ vùng nhạy cảm, phụ đề hoặc chép lời, dịch.
- Khung nền, viền thiết bị, bo góc.
- Zoom 3D.
- Bộ con trỏ thay thế, đổi kiểu con trỏ sau khi quay.
- Chỉnh tốc độ (speed ramp), chỉnh sửa theo lời nói, AI agent, MCP.
- Xuất GIF. Dễ thêm sau nếu cần.

## 4. Không được xảy ra (lựa chọn của người viết)

- **Giật, rơi khung hoặc lệch tiếng** khi quay một đoạn dài vài phút.
- **Notch hay cửa sổ MyNotch lọt vào video.**
- **Nặng máy khi quay:** dùng bộ mã hoá phần cứng, không xử lý hiệu ứng trong lúc quay. Hiệu ứng chỉ áp khi xuất.
- **Mất bản quay** nếu MyNotch thoát hoặc crash giữa chừng: phần đã quay phải cứu được.
- **File quá nặng để gửi chat:** mức "Gửi chat" nhắm khoảng 4–6 Mbit/s ở 1080p30.
- **Zoom gây chóng mặt:** chuyển động phải mượt, không giật theo từng cú bấm liên tiếp.

## 5. Ràng buộc

- macOS 26.5, Swift 6, SwiftUI kết hợp AppKit, một gói SwiftPM cho mỗi module. Module không import nhau.
- Quyền "Ghi màn hình" đã có cho module Chụp màn hình. Quyền Trợ năng đã có (dùng để biết lúc có phím được nhấn khi zoom). Quyền **Micro** là mới:
  - thêm `NSMicrophoneUsageDescription` trong `project.yml`;
  - entitlement `device.audio-input` đã có.
- Không cài gì cần quyền admin.
- Giao diện tiếng Việt, viết hoa đầu câu.
- `CaptureHiding` của NotchUI đã có, dùng để giấu cửa sổ MyNotch khỏi bản quay.

## 6. Cách làm (đã chọn)

- **Chỗ đặt:** nằm trong **module Chụp màn hình** (gói `Screenshot`), để dùng chung lớp chọn vùng và cửa sổ, quyền ghi màn hình và chỗ lưu. Tab Chụp màn hình có thêm nút "Quay" và danh sách bản quay gần đây.
- **Ghi hình:** ScreenCaptureKit (`SCStream`) ghi hình, micro (`captureMicrophone`) và, nếu bật, âm thanh hệ thống ra file bằng bộ mã hoá phần cứng.
  - Ghi ở độ phân giải gốc của vùng chọn, 60 fps.
  - Ghi kèm một file dữ liệu: vị trí con trỏ khoảng 60 lần mỗi giây, các cú bấm và thời điểm, theo cùng đồng hồ với video.
- **Zoom và hiệu ứng bấm chỉ áp khi xem trước và khi xuất**, bằng một video composition. File gốc không bị đổi, nên chỉnh lại bao nhiêu lần cũng được.
- **Quy tắc zoom tự động mặc định** (lựa chọn của người viết, chỉnh được trong cài đặt):
  - Bấm thì phóng to **2×** quanh chỗ bấm, chuyển trong 0,5 s.
  - **Hoạt động** gồm cú bấm, di chuyển con trỏ và **gõ phím**. Chỉ ghi lúc có phím được nhấn, không bao giờ ghi phím nào.
    - Lý do tính gõ phím: mẫu demo hay gặp nhất là bấm vào ô rồi gõ, và nếu không tính thì zoom sẽ thu về giữa câu.
    - Bắt sự kiện bằng global monitor sự kiện phím của AppKit, dựa trên quyền Trợ năng mà MyNotch đã có cho "Bôi đen là hiểu".
    - Chưa có quyền Trợ năng thì chỉ tính chuột.
  - Một đoạn zoom kết thúc khi đã **1,5 s không có hoạt động nào**, đếm từ hoạt động cuối cùng. Sau đó thu về trong 0,6 s.
  - Đang phóng to thì khung đi theo con trỏ một cách mượt.
  - Một cú bấm đến lúc đang thu về thì phóng to lại **từ mức hiện tại**, không thu hết rồi mới phóng.
  - Hai đoạn cách nhau dưới 2,5 s thì nối thành một.
  - Không giới hạn độ dài một đoạn.
- **"Một cửa sổ"** là **vùng màn hình đúng bằng khung cửa sổ lúc bắt đầu quay** (lựa chọn của người viết), không phải quay riêng cửa sổ đó.
  - Như vậy menu, popover và danh sách thả xuống vẫn hiện, mà demo tính năng thì cần những thứ này.
  - Vùng giữ cố định trong suốt bản quay, kéo cửa sổ đi chỗ khác thì vùng không đi theo.
  - Ảnh chụp màn hình vẫn giữ kiểu chụp riêng cửa sổ như cũ.
- **Lưu giữ** (lựa chọn của người viết):
  - **Không bao giờ tự xoá bản quay.** Bản gốc giữ cho tới khi người dùng xoá trong "Bản quay gần đây".
  - Danh sách hiện dung lượng từng bản và tổng cộng.
  - File xuất lưu ở `~/Movies/MyNotch/` và là file của người dùng. Xoá bản quay không xoá file đã xuất.
- **Khi notch bị ẩn** (ví dụ app toàn màn hình), lúc đang quay có thêm một mục trên menu bar: chấm đỏ, thời gian, Dừng, Tạm dừng. Có phím tắt cho cả **Dừng** và **Tạm dừng**. Không đổi cách notch ẩn.
- **Mức "Chất lượng cao"** dùng H.264 ở độ phân giải gốc, tối đa chiều rộng 4096 px. Màn rộng hơn thì thu nhỏ về 4096, vẫn là H.264 để mở được ở mọi nơi.

## 7. Để người làm tự quyết

- Định dạng file gốc (MOV hay MP4, fragmented hay không) và cách cứu bản quay dở.
- Cách đồng bộ dữ liệu con trỏ với khung hình.
- Kiến trúc cửa sổ chỉnh sửa, dạng timeline, thao tác kéo.
- Thuật toán làm mượt chuyển động zoom.
- Phím tắt mặc định (có thể đặt lại).
- Thư mục lưu (mặc định cạnh ảnh chụp, hoặc `~/Movies/MyNotch`).
- Cách chia việc.

## 8. Kiểm chứng

- **Test:**
  - quy tắc zoom: các cú bấm cho ra đoạn zoom, gộp và thu về đúng thời điểm;
  - cắt: các đoạn bị bỏ không có trong bản xuất, và tiếng khớp hình sau khi cắt;
  - dữ liệu con trỏ khớp thời gian video;
  - mức xuất: độ phân giải, fps, bitrate;
  - clipboard nhận file;
  - danh sách bản quay;
  - bản quay dở được cứu.

  Test không quay màn hình thật. Dùng nguồn khung hình giả và video mẫu tạo ra trong test.
- **Trên máy thật** (người điều phối làm, và người dùng xem):
  - quay 3 phút có nói;
  - cắt và zoom;
  - xuất "Gửi chat" rồi dán vào Zalo;
  - kiểm tra notch không lọt vào hình;
  - đo CPU khi quay.
