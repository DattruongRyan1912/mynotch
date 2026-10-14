# MyNotch YouTube Bridge

Extension Chrome nhỏ (Manifest V3) chuyển phụ đề mà YouTube đã tải sẵn trong trang sang ứng dụng MyNotch trên cùng máy, để notch hiển thị làm lời bài hát đồng bộ.

## Cách hoạt động

- Khi bạn bật phụ đề (CC) trên một video YouTube, trình phát tự tải phụ đề. Extension chỉ đọc bản sao của phản hồi đó trong trang, không tự gọi mạng và không liên lạc với YouTube.
- Dữ liệu đi qua Native Messaging tới `mynotch-youtube-host` rồi tới MyNotch, toàn bộ nằm trong máy bạn.

**Được gửi cho MyNotch:** mã video, tiêu đề video, vị trí phát hiện tại, trạng thái phát/tạm dừng, tốc độ phát và nội dung phụ đề (thời điểm, độ dài, chữ).

**Chẩn đoán:** extension cũng gửi vài mã chẩn đoán rất ngắn (extension đã khởi động, Chrome có cho extension đọc YouTube hay không, số tab YouTube đang mở đã được nạp script, kết nối với host thế nào, số sự kiện phụ đề đã đọc, lỗi gửi tin, lệnh Bài sau/Bài trước đã làm được hay không). Chúng chỉ gồm mã cố định và con số, không chứa tiêu đề, URL, mã video hay chữ của phụ đề, và MyNotch chỉ ghi chúng vào nhật ký hệ thống của máy.

**Nhận từ MyNotch:** đúng hai lệnh cố định, "Bài sau" (`next`) và "Bài trước" (`previous`), khi bạn bấm nút trên notch hoặc dùng phím tắt. Lệnh đi từ MyNotch qua host tới extension; extension kiểm tra lại, rồi chuyển cho tab YouTube vừa báo trạng thái phát gần nhất. Không có lệnh nào khác và không có trường nào chứa chữ tự do.

**Không bao giờ gửi:** URL (kể cả URL phụ đề có token), cookie, thông tin tài khoản hay bất cứ thứ gì ngoài các trường trên.

## Cài đặt

1. Trong MyNotch, mở Cài đặt của module Media, bật "Phụ đề YouTube làm lời" rồi bấm **Cài cầu nối cho Chrome**. MyNotch cài host, ghi manifest cho Chrome và sao chép extension vào `~/Library/Application Support/io.lucasvu.mynotch/ChromeExtension`.
2. Mở `chrome://extensions`, bật **Developer mode**.
3. Bấm **Load unpacked** và chọn thư mục `~/Library/Application Support/io.lucasvu.mynotch/ChromeExtension`.
4. Mở một video trên `www.youtube.com` và **bật phụ đề (CC)**. Không bật CC thì không có phụ đề nào được gửi; khi xem video, extension vẫn gửi các trường phát lại đã nêu ở trên (mã video, tiêu đề, vị trí, trạng thái phát, tốc độ), và chỉ những trường đó.

### Quyền truy cập trang web

Chrome cho đặt quyền truy cập trang web của từng extension. Nếu để **Khi nhấp** (On click), Chrome không nạp extension vào YouTube nên không có gì được gửi sang MyNotch, và extension không thể tự sửa việc đó. Hãy mở `chrome://extensions`, bấm **Details** ở "MyNotch YouTube Bridge", chọn **Quyền truy cập trang web** (Site access) là **Trên tất cả trang web** (hoặc **Trên các trang web cụ thể** rồi thêm `www.youtube.com`). Extension báo trạng thái này cho MyNotch, và MyNotch hiện lời nhắc trong Cài đặt khi Chrome đang chặn.

### Tab YouTube đã mở sẵn

Chrome chỉ nạp script của extension vào trang mở sau khi extension có mặt. Vì vậy sau khi cài, cập nhật hoặc tải lại extension, và khi bạn vừa cho phép truy cập YouTube, extension tự nạp lại script vào các tab `www.youtube.com` đang mở (quyền `scripting`, chỉ trên YouTube) để không phải tải lại từng tab. Phụ đề mà trang đã tải trước đó không đọc lại được: chúng xuất hiện khi trình phát tải phụ đề lần nữa (tắt rồi bật lại CC, đổi ngôn ngữ phụ đề hoặc chuyển video).

### Bài sau và Bài trước

YouTube tự gỡ các nút "bài sau/bài trước" khỏi điều khiển media của Chrome, nên phím media của macOS không chuyển được bài trong YouTube (kể cả danh sách Mix). Khi nhận lệnh từ MyNotch, script của extension làm đúng như người dùng: bấm nút **Next** của trình phát (nút chỉ được bấm khi đang hiện và đang bật). Với **Previous**, nó bấm nút Previous của trình phát nếu có; nếu trình phát không có nút đó (video lẻ, không nằm trong danh sách) thì tua về 0 giây khi video đã chạy quá 3 giây, đúng như nút Previous của YouTube. Nút Previous của YouTube cũng tự quay về đầu video khi đã quá 3 giây, nên muốn về video trước hãy bấm hai lần.

Script không tạo sự kiện bàn phím nào và không làm gì khi quảng cáo đang chạy. Mỗi lệnh để lại một mã chẩn đoán (`content-command next ok` hoặc `unavailable`); nếu tab đã đóng, service worker báo `sw-command-no-tab` và bỏ lệnh. MyNotch không thử cách nào khác khi lệnh không làm được.

Mã extension (id) cố định nhờ khoá công khai trong `manifest.json`, id nằm trong file `EXTENSION_ID`. Cầu nối của MyNotch chỉ cho phép đúng id này kết nối.

## Gỡ bỏ

- Trong `chrome://extensions`, bấm **Remove** ở "MyNotch YouTube Bridge".
- Trong MyNotch, bấm **Gỡ cầu nối** để xoá host và manifest Native Messaging.

## Phát triển

Chạy test (Node 24, không cần cài gói nào):

```sh
node --test Extensions/Chrome/MyNotchYouTube/tests/
```

`captions-page.js` là bản sao y hệt của `captions.js` dành cho MAIN world: Chrome chỉ nạp một file một lần cho mỗi tài liệu dù nó nằm trong nhiều mục `content_scripts`, nên cùng một file không thể có mặt ở cả hai world. Sau mỗi lần sửa `captions.js`, chạy `cp captions.js captions-page.js` (test báo lỗi nếu hai file khác nhau, và nếu một file xuất hiện ở hai mục).
