# Ghi chú triển khai: Shortcuts

- **Ngày:** 2026-10-14
- **Spec:** [Khay file, Shortcuts, Hẹn giờ (dự án con 8), §3](../specs/2026-10-13-shelf-shortcuts-timer-design.html). Spec không bị sửa; chỗ đã lỗi thời nằm ở mục "Sửa lại spec".
- **Package:** `Packages/Modules/Shortcuts`, product `ShortcutsModule`. Module id `shortcuts` ("Shortcuts", order 850), tab "Shortcuts" (cao 150 pt), bật mặc định, không có quyền.
- **Commit chính:** `3376513` module, `45e4419` giới hạn output, `e2b0586` gắn vào app.
- **Test tự động:** 44 test theo báo cáo L1 (`verify.sh` qua ở `8a2b842`). Test không bao giờ chạy `/usr/bin/shortcuts` thật (bộ chạy thật chỉ được thử với `/bin/echo`, `/usr/bin/false`, `/bin/sleep`, `/usr/bin/head` và một đường dẫn không tồn tại). Chưa chạy lại khi viết tài liệu này.
- **Kiểm thử tay:** [mục Shortcuts trong checklist gộp](../../manual-test-checklist-all.html#shortcuts)

## 1. Đã xây gì so với spec

- `ShortcutsCLI` đứng sau protocol: `list()` chạy `/usr/bin/shortcuts list --show-identifiers` (parser chịu được tên có ngoặc, Unicode, CRLF), `run(id:)` chạy `shortcuts run <id> -o <file tạm> --output-type public.plain-text`. Dùng `Process` với mảng đối số, đường dẫn tuyệt đối, không qua shell, ngoài main actor, huỷ được, timeout 60 giây.
- Người dùng chọn shortcut ưa thích trong Settings (danh sách có ô chọn và nút làm mới), lưu theo identifier trong `module.shortcuts.favorites`. Tab hiện chúng dạng nút có vòng xoay khi đang chạy.
- Kết quả: activity "Đã chạy X" hoặc lỗi kèm thông điệp ngắn; nếu có output dạng văn bản thì hiện toast có nút chép.
- Mỗi shortcut ưa thích gán được phím tắt toàn cục, đăng ký động qua `ModuleHotkeys` với tên `run_<id đã làm sạch>`; không có phím mặc định.

## 2. Sai khác so với spec và lý do

- **Giới hạn output 64 KB (`45e4419`):** `SystemProcessRunner` vẫn đọc hết ống nhưng chỉ giữ 64 KB đầu mỗi luồng; file `-o` đọc bằng `FileHandle.read(upToCount:)`; giải mã lossy nên cắt giữa ký tự nhiều byte vẫn ra văn bản. Toast chỉ hiện 600 ký tự đầu (kèm "…"), nút chép chép tối đa 64 KB. Lý do: review thấy output lớn có thể ăn bộ nhớ không giới hạn và làm khựng main thread khi vẽ văn bản.
- **SIGKILL sau SIGTERM:** huỷ hoặc quá 60 giây thì gửi SIGTERM, sau 2 giây (`killGrace`) nếu tiến trình còn sống thì `kill(SIGKILL)`. Trước đây một con bỏ qua SIGTERM làm hạn 60 giây không được đảm bảo.
- **Chỉ nhận identifier là UUID:** `run(id:)` ném lỗi "Mã shortcut không hợp lệ" nếu `UUID(uuidString:)` thất bại, để một id bắt đầu bằng `-` không bị hiểu thành tuỳ chọn dòng lệnh.
- **Ít việc hơn lúc khởi động:** `start()` chỉ liệt kê shortcut khi đã có mục ưa thích (cần tên cho tiêu đề phím tắt và "Đã chạy X"). Tab nạp lại danh sách mỗi lần hiện; Settings nạp khi hiện nếu danh sách rỗng.
- **Đăng ký phím tắt theo thay đổi:** module nhớ tiêu đề phím tắt của từng mục và chỉ đăng ký lại khi tiêu đề đổi, để mỗi lần làm mới không xáo thứ tự `HotkeyRegistry.registrations`.

## 3. Giới hạn đã chấp nhận (Ruling)

Ledger ghi vòng sửa H1/H3/H4 là "DONE_WITH_CONCERNS", 9 trong 12 mục Minor đã sửa. Phần Shortcuts đã bỏ qua:

- **Phím tắt của shortcut đã bỏ ưa thích vẫn bị giữ.** Cần `ModuleHotkeys.unregister` theo tên trong MyNotchCore, ngoài phạm vi vòng sửa; handler của mục đã bỏ không làm gì (có comment trong code), và phím được thả khi module dừng. **Chi phí nếu sai:** tổ hợp phím đó vẫn bị app chiếm toàn cục cho tới khi tắt module hoặc thoát app.
- **Hạn cứng của bộ chạy chưa được tái cấu trúc** (`terminationHandler` và đọc byte bất đồng bộ): mỗi lượt chạy vẫn chặn ba thread của pool. Chi phí thực tế là ba thread chặn mỗi lượt chạy hiếm.

## 4. Khoảng trống đã biết

- Brief `H3-fix.md` ghi mục `ModuleHotkeys.unregister` là bắt buộc, nhưng báo cáo vòng sửa xếp nó vào mục bỏ qua và mã nguồn không có hàm huỷ phím theo tên (`HotkeyRegistry.unregister` vẫn là `private`).
- Các mục Minor của brief `H3-fix.md` mà code chưa có: `standardInput` chưa đặt là `/dev/null`, chưa có `Mutex` bảo vệ tiến trình giữa `onCancel` và `run()`, tab chưa hạn chế nạp lại danh sách (nạp mỗi lần hiện).
- Chưa có kết quả kiểm thử tay: chạy shortcut thật, output trên 64 KB, tiến trình bỏ qua SIGTERM tới hạn 60 giây.
- Shortcut điều khiển app khác có thể làm macOS hỏi quyền Automation (Apple Events); `NSAppleEventsUsageDescription` có sẵn trong `project.yml`, nhưng module này không tự xin quyền nào.

## 5. Sửa lại spec (Spec corrections)

- **§3, chạy**: thêm SIGKILL sau 2 giây sau SIGTERM, giới hạn 64 KB mỗi luồng và file output, toast 600 ký tự, id phải là UUID.
- **§3, danh sách**: thêm một lần liệt kê lúc khởi động, chỉ khi có mục ưa thích.
- **§3, phím tắt**: bỏ ưa thích không gỡ phím tắt cho tới khi module dừng.
- **Dòng trạng thái** "Thiết kế" đã lỗi thời: module đã triển khai và gắn vào app.

## 6. Cần kiểm thử tay

Xem [mục Shortcuts trong checklist gộp](../../manual-test-checklist-all.html#shortcuts). Mục chạy shortcut thật có thể gây hộp thoại quyền Automation tuỳ shortcut.
