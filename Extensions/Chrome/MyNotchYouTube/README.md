# MyNotch YouTube Bridge

Extension Chrome nhỏ (Manifest V3) chuyển phụ đề mà YouTube đã tải sẵn trong trang sang ứng dụng MyNotch trên cùng máy, để notch hiển thị làm lời bài hát đồng bộ.

## Cách hoạt động

- Khi bạn bật phụ đề (CC) trên một video YouTube, trình phát tự tải phụ đề. Extension chỉ đọc bản sao của phản hồi đó trong trang, không tự gọi mạng và không liên lạc với YouTube.
- Dữ liệu đi qua Native Messaging tới `mynotch-youtube-host` rồi tới MyNotch, toàn bộ nằm trong máy bạn.

**Được gửi cho MyNotch:** mã video, tiêu đề video, vị trí phát hiện tại, trạng thái phát/tạm dừng, tốc độ phát và nội dung phụ đề (thời điểm, độ dài, chữ).

**Không bao giờ gửi:** URL (kể cả URL phụ đề có token), cookie, thông tin tài khoản hay bất cứ thứ gì ngoài các trường trên.

## Cài đặt

1. Trong MyNotch, mở Cài đặt của module Media, bật "Phụ đề YouTube làm lời" rồi bấm **Cài cầu nối cho Chrome**. MyNotch cài host, ghi manifest cho Chrome và sao chép extension vào `~/Library/Application Support/io.lucasvu.mynotch/ChromeExtension`.
2. Mở `chrome://extensions`, bật **Developer mode**.
3. Bấm **Load unpacked** và chọn thư mục `~/Library/Application Support/io.lucasvu.mynotch/ChromeExtension`.
4. Mở một video trên `www.youtube.com` và **bật phụ đề (CC)**. Không có CC thì không có gì được chuyển sang MyNotch.

Mã extension (id) cố định nhờ khoá công khai trong `manifest.json`, id nằm trong file `EXTENSION_ID`. Cầu nối của MyNotch chỉ cho phép đúng id này kết nối.

## Gỡ bỏ

- Trong `chrome://extensions`, bấm **Remove** ở "MyNotch YouTube Bridge".
- Trong MyNotch, bấm **Gỡ cầu nối** để xoá host và manifest Native Messaging.

## Phát triển

Chạy test (Node 24, không cần cài gói nào):

```sh
node --test Extensions/Chrome/MyNotchYouTube/tests/
```
