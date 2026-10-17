# MyNotch: bộ chỉnh âm (EQ) cho cả máy

- **Ngày:** 2026-10-18
- **Trạng thái:** Thiết kế, chờ duyệt
- **Thay cho:** eqMac. Người dùng chỉ dùng phần EQ, không dùng App Mixer.

## 1. Ý định

Người dùng đang dùng eqMac. Mỗi lần chuyển giữa nghe nhạc, xem phim và họp, họ **tự bấm đổi** sang hồ sơ EQ hợp với việc đó. Thỉnh thoảng họ mới kéo lại từng thanh EQ.

Họ muốn làm việc này ngay trên notch của MyNotch để bỏ được eqMac. Phần chỉnh âm lượng riêng cho từng app thì họ ít dùng nên để sau.

Thành công nghĩa là người dùng tắt eqMac, mỗi ngày đổi hồ sơ trên notch mà không nghĩ tới nó, âm thanh không rè, không trễ thấy rõ, và máy không nặng hơn.

## 2. Mục tiêu

- Một EQ 10 băng (32, 64, 125, 250, 500 Hz, 1, 2, 4, 8, 16 kHz; mỗi băng ±12 dB) kèm preamp (±12 dB), áp lên **toàn bộ âm thanh phát ra của máy**.
- Mỗi **hồ sơ** gồm tên, 10 mức băng và preamp.
  - Lần đầu có sẵn ba hồ sơ: **Nhạc**, **Phim**, **Họp**.
  - Người dùng thêm, đổi tên và xoá được. Xoá hết cũng được, khi đó EQ phẳng.
- Một **công tắc EQ** dùng chung cho cả máy. Tắt là âm thanh đi thẳng, không qua MyNotch.
- **Đổi hồ sơ nhanh** trong tab Nhạc: một dòng dưới trình phát, gồm:
  - chữ "EQ";
  - danh sách hồ sơ dạng thả xuống;
  - công tắc EQ;
  - nút "Chỉnh…" để mở tab Âm thanh.
- **Tab "Âm thanh"**, mặc định nằm trong mục "Khác" như mọi module mới (theo TB1), gồm:
  - danh sách hồ sơ thả xuống, kèm các nút thêm (＋), đổi tên (✎) và xoá (－);
  - công tắc EQ;
  - thanh Preamp;
  - 10 thanh EQ;
  - nút "Về phẳng".
- Mọi âm thanh vẫn ra **đúng thiết bị nó vốn được gửi tới**, và EQ áp lên từng thiết bị đó. Có hai trường hợp:
  - thiết bị đầu ra hệ thống (loa trong, tai nghe, loa Bluetooth), đi theo khi người dùng đổi thiết bị;
  - **thiết bị riêng mà app tự chọn**. Người dùng xác nhận khi họp, Zoom, Meet hay Teams của họ chọn loa hoặc tai nghe riêng, khác thiết bị hệ thống. Hồ sơ "Họp" phải có tác dụng lên âm thanh đó.
- Cùng một hồ sơ đang chọn áp lên mọi thiết bị đang có tiếng (lựa chọn của người viết). Không có hồ sơ riêng cho từng thiết bị.
- Phím âm lượng của máy vẫn chỉnh thiết bị thật như bình thường.

## 3. Không làm (đợt này)

- App Mixer, tức âm lượng riêng cho từng app.
- Spatial Audio, Extra Effects.
- Boost và Balance. Ảnh eqMac của người dùng để Boost 0% và Balance 100/100. Làm sau nếu cần, vì dễ.
- Tự đổi hồ sơ theo app hay theo cuộc họp. Người dùng muốn bấm tay.
- Hồ sơ tự đổi theo thiết bị.
- Expert EQ (nhiều băng hơn, tham số tự chỉnh).
- Driver âm thanh ảo (HAL plug-in) hoặc bất cứ thứ gì cần mật khẩu admin.

## 4. Không được xảy ra (lựa chọn của người viết; người dùng chưa nêu điều gì)

- **Rè, lụp bụp hay ngắt tiếng** khi phát lâu, khi đổi thiết bị, khi máy ngủ rồi thức, khi đổi hồ sơ hay kéo thanh EQ.
- **Trễ thấy rõ**, nhất là khi họp hay xem phim. Mục tiêu là trễ thêm không quá khoảng 20 ms trên loa trong.
- **Mất tiếng.** MyNotch thoát, crash hay bị kill thì âm thanh phải tự trở lại bình thường: hệ điều hành huỷ tap riêng của tiến trình, và người làm chọn chế độ tắt tiếng sao cho tiếng gốc trở lại khi không còn ai đọc tap. Treo luồng chính không sao, vì luồng âm thanh thời gian thực vẫn chạy. Trường hợp cả tiến trình bị đóng băng hẳn (SIGSTOP, debugger) **không** cần một watchdog bên ngoài (lựa chọn của người viết). Tắt EQ thì không còn xử lý gì, không tốn gì.
- **Đưa âm thanh sang nhầm thiết bị**, ví dụ tiếng cuộc họp đáng lẽ ra tai nghe lại phát ra loa.
- **Nặng máy.** Người dùng hay theo dõi RAM và CPU. Khi EQ bật và đang có tiếng, CPU phải ở mức thấp. Khi im lặng hoặc EQ tắt, gần như bằng không.
- **Hai EQ chồng lên nhau mà không biết.** Khi eqMac đang chạy, nói cho người dùng biết.
- **Làm hỏng phổ âm thanh thật** của module Nhạc.

## 5. Ràng buộc

- macOS 26.5, Swift 6, SwiftUI kết hợp AppKit, một gói SwiftPM cho mỗi module. Module không phụ thuộc lẫn nhau, như mọi module khác của MyNotch.
- Ứng dụng không chạy trong sandbox, ký bằng Apple Development (team B394MAY4QN), không cần entitlement riêng.
- Quyền "Ghi âm thanh hệ thống" (System Audio Recording) đã được xin cho phổ âm thanh thật của module Nhạc. EQ cần cùng quyền đó.
- Không cài gì cần quyền admin.
- Giao diện tiếng Việt, viết hoa đầu câu. Theo glass và màu chữ hiện có của notch, đọc rõ trên cả nền sáng và nền tối.

## 6. Cách làm (đã chọn)

- **Đường ống:** dùng Core Audio process tap, cùng họ API với `SystemAudioTap` của module Nhạc. EQ cần thêm ba việc:
  - tắt tiếng bản gốc trong lúc tap (`muteBehavior` khác `.unmuted`);
  - loại chính MyNotch ra khỏi tap;
  - phát lại bản đã qua EQ ra **đúng thiết bị đó**.

  Vì app có thể chọn thiết bị riêng, đường ống phải **gắn với từng thiết bị đầu ra** (tap theo stream của thiết bị), mỗi thiết bị đang có tiếng một đường ống. Một tap toàn cục phát lại về một thiết bị thì không được. Thường chỉ có một hoặc hai thiết bị cùng lúc. Thiết bị nào im lặng hay biến mất thì đường ống của nó được dỡ đi.
- **Chọn hồ sơ:** danh sách thả xuống, không dùng nút chip, vì danh sách hồ sơ do người dùng tự thêm bớt.
- **Lưu hồ sơ:** kéo thanh nào là lưu ngay vào hồ sơ đang chọn, không có nút Lưu và không có trạng thái "Manual" riêng. Đây là lựa chọn của người viết, người dùng không phản đối.
- **Đường cong mặc định** (lựa chọn của người viết, người dùng chỉnh được):
  - Nhạc: hình chữ V nhẹ;
  - Phim: thêm bass và vùng thoại;
  - Họp: hạ bass, nâng vùng giọng nói khoảng 1–4 kHz.
- **Dùng chung trạng thái giữa hai module:** dòng EQ trong tab Nhạc và module Âm thanh dùng chung trạng thái (danh sách hồ sơ, hồ sơ đang chọn, công tắc) qua MyNotchCore, không để module này import module kia. Công tắc ở hai nơi là một.

## 7. Để người làm tự quyết

- Kiến trúc đường ống chi tiết, miễn là gắn theo từng thiết bị như mục 6:
  - dùng aggregate device hay một IOProc riêng;
  - cách phát hiện thiết bị nào đang có tiếng;
  - cách bù lệch nhịp giữa tap và thiết bị ra;
  - kích thước buffer và cách đạt độ trễ mục tiêu.
- Bộ lọc: biquad của vDSP, `AVAudioUnitEQ`, hay tự viết. Điều kiện là luồng âm thanh thời gian thực không cấp phát bộ nhớ và không khoá.
- Cách chuyển êm khi đổi hồ sơ hay kéo thanh, để không nghe tiếng "tách".
- Xử lý khi đổi thiết bị, khi đổi tần số lấy mẫu, khi ngủ hoặc thức, và khi chưa có quyền.
- Cách phát hiện eqMac đang chạy và câu chữ thông báo.
- Tên module, mã định danh, biểu tượng, và cách lưu hồ sơ (settings hay file trong ModuleStorage).
- Thứ tự các phần và cách chia việc.

## 8. Kiểm chứng

- **Test:**
  - Toán của bộ lọc: đáp ứng tần số của từng băng ở ±12 dB; preamp; hồ sơ phẳng thì tín hiệu đi qua không đổi.
  - Hồ sơ: thêm, đổi tên, xoá, xoá hết, lưu rồi đọc lại.
  - Trạng thái dùng chung giữa tab Nhạc và tab Âm thanh.
  - Luồng âm thanh thời gian thực không cấp phát (dùng bộ đếm cấp phát trong test).
  - Các trường hợp đổi thiết bị, dùng thiết bị giả.
- **Kiểm tra trên máy thật** (người điều phối làm sau khi cài):
  - phát nhạc trên YouTube và Music qua loa trong và qua loa Bluetooth;
  - đặt app họp (hoặc một app phát thử) ra một thiết bị khác thiết bị hệ thống: tiếng vẫn ra đúng thiết bị đó và có EQ;
  - đổi hồ sơ trong lúc phát;
  - cắm và rút tai nghe;
  - cho máy ngủ rồi thức;
  - thoát MyNotch giữa chừng: tiếng phải trở lại ngay;
  - đo CPU và RAM bằng `perf/measure.sh`;
  - nghe xem có rè không.
