# MyNotch Sync (Android)

Đồng bộ clipboard giữa Android và MyNotch trên Mac qua relay WebSocket mã hoá đầu–cuối (AES-256-GCM,
`Tools/mynotch-cloud-relay`). Ghép đôi bằng mã QR trong MyNotch → Cài đặt → Clipboard.

## Mac → Android

App nhận clip qua WebSocket và ghi vào clipboard Android. Socket chỉ sống khi tiến trình app còn sống: khi app mở,
hoặc khi bật "Tự gửi mỗi lần copy" (foreground service giữ tiến trình).

## Android → Mac

Từ Android 10, app nền không đọc được clipboard. Có bốn đường gửi, đều mã hoá trong Kotlin (`ClipSender`, gửi một lần
rồi đóng socket, không cần Flutter engine):

| Đường | Cách dùng |
|---|---|
| Menu bôi đen text | Bôi đen → "Gửi sang Mac" (`PROCESS_TEXT`) |
| Share | Chia sẻ text → "Gửi sang Mac" (`SEND`) |
| Quick Settings tile | Thêm ô "Gửi sang Mac" vào Quick Settings; bấm để gửi clipboard hiện tại |
| Tự gửi mỗi lần copy | Bật trong app; cần cấp quyền một lần qua adb (dưới đây) |

### Tự gửi mỗi lần copy

`ClipWatchService` đăng ký listener clipboard; Android từ chối báo cho app nền nhưng ghi log
`ClipboardService: Denying clipboard access to <package>`. Service đọc log đó (cần `READ_LOGS`), rồi đọc clipboard qua
một cửa sổ overlay 1px nhận focus; app nào ẩn overlay (Danh bạ, Cài đặt, app ngân hàng…) thì đọc qua activity trong
suốt (mở từ nền nhờ quyền overlay).

Cấp một lần (điện thoại bật USB debugging):

```bash
adb shell pm grant io.lucasvu.mynotch.mynotch_android android.permission.READ_LOGS
adb shell appops set io.lucasvu.mynotch.mynotch_android SYSTEM_ALERT_WINDOW allow
```

Giới hạn đã biết:
- Android 13+ hỏi "Allow one-time access" (quyền đọc log) mỗi lần service khởi động lại (mở lại app sau khi bị tắt,
  khởi động lại máy, cài bản mới).
- Android 12+ hiện thông báo hệ thống "đã dán từ clipboard" mỗi lần app đọc clipboard.
- Mỗi lần copy, app lấy focus trong tích tắc. Với overlay, bàn phím vẫn mở (đã thử trên Chrome); với activity
  (app ẩn overlay), bàn phím có thể bị đóng.
- Clip được app nguồn đánh dấu nhạy cảm (`EXTRA_IS_SENSITIVE`, Android 13+, ví dụ trình quản lý mật khẩu) không tự
  gửi; gửi tay qua tile/menu vẫn được.
- Chưa có boot receiver: sau khi khởi động lại máy phải mở app một lần thì mới tự gửi tiếp.
- ROM của hãng có thể đổi nội dung dòng log; khi đó dùng tile hoặc menu bôi đen.

## Phát triển

```bash
flutter build apk --debug
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

Bản debug nhận link ghép đôi để khỏi quét QR trên emulator (bản release bỏ qua link này):

```bash
adb shell am start -a android.intent.action.VIEW -d "'mynotch://pair?c=…&k=…&e=…&s=…'" io.lucasvu.mynotch.mynotch_android
```
