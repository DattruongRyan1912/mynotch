# Ghi chú triển khai: Shortcuts

- **Ngày:** 2026-10-14
- **Spec:** [Khay file, Shortcuts, Hẹn giờ (dự án con 8), §3](../specs/2026-10-13-shelf-shortcuts-timer-design.html). Spec không bị sửa; chỗ đã lỗi thời nằm ở mục "Sửa lại spec".
- **Package:** `Packages/Modules/Shortcuts`, product `ShortcutsModule`. Module id `shortcuts` ("Shortcuts", order 850), tab "Shortcuts" (cao 150 pt), bật mặc định, không có quyền. Thêm vào MyNotchCore: `ModuleHotkeys.unregister(_:)`.
- **Commit chính:** `3376513` module, `45e4419` giới hạn output, `e2b0586` gắn vào app, `9f2d14b` Core: huỷ phím tắt theo tên, `a8025b2` bộ chạy `posix_spawn` và huỷ phím tắt của mục bỏ ưa thích.
- **Test tự động:** Shortcuts 52 test và MyNotchCore 119 (báo cáo `H3-fix2-report`, `verify.sh` qua); review lại vòng H3-fix2 (`re-review-H3-fix2.md`) **Approved**, không có Critical hay Important, đã chạy lại hai package (52 và 119, ba lần, 0 cảnh báo) cùng thí nghiệm riêng cho bộ chạy (fd, process group, 300 vòng huỷ đua, trạng thái thoát). Test không bao giờ chạy `/usr/bin/shortcuts` thật (bộ chạy thật chỉ được thử với `/bin/echo`, `/usr/bin/false`, `/bin/sleep`, `/usr/bin/head`, `/bin/sh` và một đường dẫn không tồn tại). Chưa chạy lại khi viết tài liệu này.
- **Kiểm thử tay:** [mục Shortcuts trong checklist gộp](../../manual-test-checklist-all.html#shortcuts)

## 1. Đã xây gì so với spec

- `ShortcutsCLI` đứng sau protocol: `list()` chạy `/usr/bin/shortcuts list --show-identifiers` (parser chịu được tên có ngoặc, Unicode, CRLF), `run(id:)` chạy `shortcuts run <id> -o <file tạm> --output-type public.plain-text`. Đường dẫn tuyệt đối, mảng đối số, không qua shell, ngoài main actor, huỷ được, timeout 60 giây.
- **Bộ chạy tiến trình `SystemProcessRunner`** (file riêng, `posix_spawn`): tiến trình con đứng đầu một process group riêng (`POSIX_SPAWN_SETPGROUP`), nhận `/dev/null` làm stdin, chỉ giữ fd 0 đến 2 (`POSIX_SPAWN_CLOEXEC_DEFAULT`). Huỷ hoặc quá 60 giây thì `killpg(SIGTERM)`, sau `killGrace` (2 giây) nếu còn chạy thì `killpg(SIGKILL)`. Trạng thái `idle`, `running(pid)`, `cancelled`, `finished` nằm sau một `Mutex`, nên huỷ trước lúc chạy nghĩa là không chạy, huỷ lúc đang chạy thì gửi tín hiệu cho cả nhóm, và sau khi xong thì không gửi gì (một pid đã được cấp lại không bao giờ bị trúng). Đọc ống và `waitpid` chạy trên thread dispatch, hẹn giờ giết dùng `asyncAfter`, không dùng thread của pool Swift.
- Người dùng chọn shortcut ưa thích trong Settings (danh sách có ô chọn và nút làm mới), lưu theo identifier trong `module.shortcuts.favorites`. Tab hiện chúng dạng nút có vòng xoay khi đang chạy.
- Kết quả: activity "Đã chạy X" hoặc lỗi kèm thông điệp ngắn; nếu có output dạng văn bản thì hiện toast có nút chép.
- Mỗi shortcut ưa thích gán được phím tắt toàn cục, đăng ký động qua `ModuleHotkeys` với tên `run_<id đã làm sạch>`; không có phím mặc định. Bỏ ưa thích thì phím tắt được huỷ đăng ký (`context.hotkeys.unregister`): hàng biến khỏi danh sách phím tắt và handler gỡ ngay; tổ hợp phím người dùng đã ghi vẫn được lưu, nên ưa thích lại thì phím cũ chạy lại.

## 2. Sai khác so với spec và lý do

- **Giới hạn output 64 KB (`45e4419`):** `SystemProcessRunner` vẫn đọc hết ống nhưng chỉ giữ 64 KB đầu mỗi luồng; file `-o` đọc bằng `FileHandle.read(upToCount:)`; giải mã lossy nên cắt giữa ký tự nhiều byte vẫn ra văn bản. Toast chỉ hiện 600 ký tự đầu (kèm "…"), nút chép chép tối đa 64 KB. Lý do: output lớn có thể ăn bộ nhớ không giới hạn và làm khựng main thread khi vẽ văn bản.
- **Kill cả process group, không chỉ tiến trình con (`a8025b2`):** vòng sửa đầu chỉ có SIGKILL cho tiến trình con, nhưng với `sh -c 'trap "" TERM; sleep 30'` cái `sleep` còn sống và giữ ống mở nên lượt chạy treo tới khi `sleep` xong. `Process` không cho tạo nhóm tiến trình mới, nên bộ chạy được viết lại bằng `posix_spawn` và `killpg`.
- **Chỉ nhận identifier là UUID:** `run(id:)` ném lỗi "Mã shortcut không hợp lệ" nếu `UUID(uuidString:)` thất bại, để một id bắt đầu bằng `-` không bị hiểu thành tuỳ chọn dòng lệnh.
- **Ít việc hơn lúc khởi động và khi mở tab:** `start()` chỉ liệt kê shortcut khi đã có mục ưa thích (cần tên cho tiêu đề phím tắt và "Đã chạy X"). Tab gọi `refreshIfStale(maxAge: 60 giây)`: chỉ liệt kê lại khi danh sách rỗng hoặc đã quá 60 giây. Settings nạp khi hiện nếu danh sách rỗng, và nút "Làm mới" luôn nạp.
- **Đăng ký phím tắt theo thay đổi:** module nhớ tiêu đề phím tắt của từng mục (`hotkeyTitles`, khoá chính là tên đã đăng ký) và chỉ đăng ký lại khi tên mới hoặc tiêu đề đổi, để mỗi lần làm mới không xáo thứ tự `HotkeyRegistry.registrations`.
- **MyNotchCore:** `HotkeyRegistry.unregister(_:owner:)` và `ModuleHotkeys.unregister(_:)` (không làm gì nếu tên chưa đăng ký; không làm gì sau khi module dừng, để facade đã dừng không gỡ phím của module khởi động lại).

## 3. Giới hạn đã chấp nhận (Ruling)

Ledger không có dòng `Ruling:` riêng cho Shortcuts. Vòng sửa H1/H3/H4 (`45e4419`) bỏ qua hai mục mà vòng H3-fix2 (`9f2d14b`, `a8025b2`) đã làm sau đó: `ModuleHotkeys.unregister` và SIGKILL cho cả nhóm tiến trình, cùng stdin `/dev/null`, `Mutex` quanh tiến trình, hạn 60 giây cho lần nạp danh sách ở tab và bộ chạy không còn chặn ba thread của pool. Còn lại:

- **Không huỷ chuỗi quan sát cài đặt khi `stop()`.** Sau `stop()` kiểm tra `self.context === context` kết thúc chuỗi ở lần đổi cài đặt kế tiếp; tới lúc đó một `withObservationTracking` còn treo, chỉ giữ context đã dừng và tham chiếu yếu tới module (có comment trong code). Không thêm token để huỷ vì không được gì.
- Không có tập `registeredNames` riêng: khoá của `hotkeyTitles` đã là tập đó.
- Hai Minor của re-review, chưa sửa: `waitpid` thu hồi tiến trình đứng đầu ngoài khoá và `finish()` chỉ chạy sau đó trong `defer` của `run`, nên trong khoảng đó một lần huỷ hay hẹn giờ giết có thể `killpg` một pid đã được cấp lại (cần pid xoay vòng trong vài micro giây, thực tế không xảy ra; cách sửa: gọi `finish()` trong closure ngay sau `waitpid`); và comment ở `ShortcutsCLI.swift` còn ghi tham số đi "tới `Process`".
- Một tiến trình con cháu rời nhóm bằng `setsid` mà vẫn giữ ống mở thì làm lượt chạy treo quá lúc huỷ tới khi nó thoát (đo được 5,7 giây với `sleep` 6 giây). Mã `Process` cũ cũng vậy, không phải hồi quy.

## 4. Khoảng trống đã biết

- Chưa có kết quả kiểm thử tay: chạy shortcut thật (kiểm chính của việc đổi sang `posix_spawn`: có hộp thoại quyền hay lỗi nào mới mà `Process` không gây ra không), output trên 64 KB, tiến trình bỏ qua SIGTERM tới hạn 60 giây (nay kể cả tiến trình con của nó), bỏ ưa thích rồi xem hàng phím tắt biến mất.
- `shortcuts` thật chưa bao giờ được chạy bởi agent nào; con của bộ chạy giờ có process group riêng, `/dev/null` làm input và chỉ ba fd.
- Shortcut điều khiển app khác có thể làm macOS hỏi quyền Automation (Apple Events); `NSAppleEventsUsageDescription` có sẵn trong `project.yml`, nhưng module này không tự xin quyền nào.

## 5. Sửa lại spec (Spec corrections)

- **§3, chạy**: tiến trình con chạy bằng `posix_spawn` trong process group riêng, stdin `/dev/null`; SIGTERM cho cả nhóm, SIGKILL sau 2 giây; giới hạn 64 KB mỗi luồng và file output; toast 600 ký tự; id phải là UUID.
- **§3, danh sách**: thêm một lần liệt kê lúc khởi động, chỉ khi có mục ưa thích; tab chỉ liệt kê lại khi danh sách rỗng hoặc quá 60 giây.
- **§3, phím tắt**: bỏ ưa thích thì phím tắt được huỷ đăng ký ngay (cần `ModuleHotkeys.unregister` ở Core); ưa thích lại thì khôi phục phím đã ghi.
- **Dòng trạng thái** "Thiết kế" đã lỗi thời: module đã triển khai và gắn vào app.

## 6. Cần kiểm thử tay

Xem [mục Shortcuts trong checklist gộp](../../manual-test-checklist-all.html#shortcuts). Mục chạy shortcut thật có thể gây hộp thoại quyền Automation tuỳ shortcut.
