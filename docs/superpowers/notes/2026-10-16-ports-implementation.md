# Ghi chú triển khai: Cổng (xem app nào giữ cổng và giải phóng nó)

- **Ngày:** 2026-10-16
- **Spec:** không có spec thiết kế riêng; yêu cầu của người dùng (2026-10-16): thay một tiện ích quản lý cổng mở (một extension Raycast). Báo cáo PORT1 là nguồn.
- **Package:** `Packages/Modules/Ports`, product `PortsModule`. Module id `ports`, tên **"Cổng"**, icon `network`, **order 920**, **bật mặc định**, không có quyền macOS nào. Mặc định nằm trong mục **Khác** của thanh trang. Ghép vào `project.yml` và `App/ModuleList.swift` ở `4fb61f2` (cùng module Hiệu năng).
- **Commit:** `dc11fc9` (module), `e675072` (che bí mật trong dòng lệnh).
- **Test tự động:** 133 test trong 17 suite ở `e675072`, ba lần chạy sạch, 0 cảnh báo (118 ở `dc11fc9`). Test dùng nguồn cổng giả; lớp đọc thật (`libproc`) có vài test chỉ-đọc trên chính máy, và test tiến trình con thật cho việc dừng.
- **Cổng:** cổng `verify.sh` xanh ở `e675072` và ở `41dba8a` (HEAD khi viết).
- **Chưa ai thấy trên màn hình thật** (PORT1 chưa bao giờ thấy notch thật).

## 1. Đã xây gì

Một tab **"Cổng"** cao 230 pt với hai ô chữ và một danh sách. Chỉ đọc (mỗi 2 giây: khởi động hay dừng một máy chủ không gửi thông báo nào cho app) khi tab đang hiện; không làm gì khi chọn tab khác.

- **Danh sách:** mỗi hàng là một cổng đang lắng nghe, kèm tên và icon của tiến trình (Docker, VS Code… hiện icon app), chủ sở hữu, "PID N", dòng lệnh, một gợi ý cho một số khung (Django, Vite…), và nhãn **"Chỉ máy này"** (127.0.0.1 và ::1) hay **"Cả mạng"** (cái máy khác tới được). Mặc định chỉ TCP đang lắng nghe; **"Hiện cả cổng UDP"** trong Settings → Cổng (tắt; "Mặc định chỉ hiện cổng TCP đang lắng nghe. UDP thường có nhiều cổng của trình duyệt và dịch vụ hệ thống.").
- Ô **"Lọc theo cổng hoặc tên"**, và ô kiểm nhanh **"Cổng nào đang bị chiếm?"**: gõ một cổng thì nói cổng đó trống hay ai đang giữ. Kết quả là một trong: "Cổng N: <tiến trình> · PID M" (kèm "và K nữa"), "Cổng N trống", "Cổng N đang bị chiếm, nhưng không đọc được tiến trình (của hệ thống hoặc người dùng khác)" hay "Nhập số cổng từ 1 đến 65535". Một cổng bị người dùng khác hay root giữ thì **không bao giờ nói "trống"**: "trống" chỉ được nói khi hệ thống đồng ý (một lần thử bind trên loopback, và một cổng ở wildcard của người khác nhờ kernel từ chối bind chéo người dùng). Chân trang: "Cổng của hệ thống cần quyền quản trị". Rỗng thì "Không có cổng nào đang mở" hay "Không có cổng nào khớp".
- Mỗi hàng có **"Mở"** (cổng TCP: mở `localhost:cổng` bằng trình duyệt), **"Chép"** (chép `localhost:cổng`) và **"Dừng"**.
- **Dừng** chỉ cho **tiến trình của chính bạn** (không bao giờ root hay của người khác; ControlCenter giữ cổng AirPlay 5000 và 7000 nên có hàng nhưng không có "Dừng"). Bấm "Dừng" hỏi ngay trong hàng (câu hỏi nêu tên tiến trình, ví dụ "com.docker.backend của Docker") với **"Dừng"** (xác nhận) và **"Huỷ"**; xác nhận gửi **SIGTERM** (kiểm lại pid trước khi gửi để không dừng nhầm tiến trình đã thay); nếu sau khoảng 3 giây tiến trình chưa thoát thì hàng nói "… chưa thoát." với **"Buộc dừng"** (SIGKILL) và **"Để yên"**; xong thì "Đã dừng …" trong khoảng 4 giây và hàng biến mất. Trong lúc một câu hỏi đang hiện, notch được ghim.

## 2. Che bí mật trong dòng lệnh (`e675072`)

Dòng lệnh có thể chứa bí mật (`--password=…`, token trong tham số) và hàng hiện nó trên notch, kể cả khi đang chia sẻ màn hình. **Che xảy ra trước khi dòng được giữ** (`SecretMask`, trong `ProcArguments.display`, trước khi cắt ở 200 ký tự), nên bí mật nguyên bản không có ở `PortProcess.commandLine`, bộ lọc hay đâu khác trong module. Giá trị thành `••••`, tên cờ hay biến ở lại. Năm quy tắc: (1) `tên=giá trị` với tên bí mật, ở đầu một tham số, sau một dấu `=` khác (`-e DB_PASSWORD=x`, `--env=DB_PASSWORD=x`) hay trong query của URL (`?x=1&token=abc&y=2`); (2) cờ bí mật không có `=` che tham số kế tiếp trừ khi đó cũng là một cờ (`--token abc`; `--password --verbose` giữ); (3) `scheme://user:pass@host`; (4) từ sau `Bearer`; (5) `-pBÍMẬT` dính liền, **chỉ** cho họ mysql và mariadb (`mysql -p mydb` và `psql -p 5432` giữ, vì với psql `-p` là cổng). Một tên là bí mật theo các từ của nó (tách ở `-`, `_`, `.` và camelCase): password, passwd, pwd, pass, passphrase, token, secret, bearer, requirepass, apikey hay `api` kèm `key`; tên có thêm file, path, dir, stdin, prompt, through hay env là một con trỏ tới bí mật nên giữ (`--password-file /run/secrets/db`). Bảng 42 trường hợp (24 phải che, 18 phải giữ).

**Khi MyNotch được giữ ngoài ảnh quay** (Settings → Chung → "Ẩn MyNotch khi quay hoặc chia sẻ màn hình" khác "Không ẩn"), hàng **chỉ có tên, cổng, chủ sở hữu và nút, không có tham số**, và bộ lọc cũng không tìm trong chúng (một phỏng đoán không được nói ra dòng đã ẩn nói gì). **Diễn giải cần xác nhận:** macOS không có lời gọi công khai nào cho biết "đang bị quay", nên cài đặt đứng thay cho nó; với "Không ẩn" thì dòng được hiện, đã che.

## 3. Quyết định, giới hạn

- **Ruling (PORT1):** mô-đun chỉ làm việc với tiến trình của chính bạn. Chi phí nếu sai: không dừng được một dịch vụ của người dùng khác (cố ý).
- Che là một **danh sách mẫu, không phải bảo đảm**: một bí mật truyền theo vị trí (`app hunter2`) hay dưới một tên cờ không có từ nào ở trên (`--key`, `--auth`) không được nhận ra, và `Authorization: Basic …` không được che.
- Một tiến trình được giữ sống bởi launchd, `brew services`, một bộ giám sát hay chính sách khởi động lại của Docker sẽ hiện "Đã dừng …" rồi xuất hiện lại dưới pid mới một lát sau.
- Test thăm dò chỉ trên loopback: một listener wildcard của người khác dựa vào kiểm tra bind chéo người dùng của kernel mà test không chứng minh (bind wildcard trong test có thể làm hiện hộp thoại tường lửa).
- Một test dùng tiến trình con thật (`anExitedChildIsGoneEvenBeforeItIsReaped`) từng chờ 5 giây rồi thất bại một lần khi máy tải 28 đến 48; thời gian chờ nay là 20 giây.

## 4. Cần kiểm thử tay

Xem [nhóm Cổng trong checklist gộp](../../manual-test-checklist-all.html#ports): `python3 -m http.server 8000` cùng một máy chủ Vite, rồi hàng, gợi ý và nhãn; Docker và VS Code; cổng AirPlay không có "Dừng"; luồng dừng trên `sh -c "trap '' TERM; nc -l 9999"`; ô chữ và Esc, notch ở lại mở trong lúc có câu hỏi; kiểm nhanh một cổng bị giữ, một cổng trống và một cổng của người khác; "Mở" và "Chép"; CPU khi tab mở (gần bằng không) và không gì khi chọn tab khác; "Hiện cả cổng UDP"; một dòng lệnh có `--password=…` bị che, và với ẩn khỏi quay màn hình bật thì hàng không có tham số.
