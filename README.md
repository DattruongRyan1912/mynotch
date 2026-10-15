# MyNotch

Ứng dụng notch cá nhân cho macOS 26+, viết mới từ đầu, chia thành các module bật/tắt độc lập.

> **Clean-room:** MyNotch lấy hành vi của OneNotch làm tham chiếu nhưng **không chứa mã nguồn của OneNotch**. boring.notch (GPL) chỉ được đọc để hiểu kiến trúc, không chép mã. Bên thứ ba: KeyboardShortcuts (MIT) và `mediaremote-adapter` v0.7.7 (BSD-3, trong `Vendor/`); cả hai có trong trang Giới thiệu của app.

## Yêu cầu

- macOS 26.0 trở lên
- Xcode 26.6 (`xcode-select -p` phải trỏ vào Xcode, không phải Command Line Tools)
- XcodeGen: `brew install xcodegen`

## Build, chạy và kiểm tra

```bash
xcodegen generate
open MyNotch.xcodeproj
```

Chọn scheme **MyNotch** rồi Run (⌘R). App chạy trên menu bar; icon Dock chỉ hiện khi một cửa sổ của MyNotch đang mở (Settings, trình sửa ảnh, trình cài gói ngôn ngữ).

```bash
./scripts/verify.sh                     # xcodegen, test mọi package, build Debug; phải kết thúc bằng "All checks passed."
cd Packages/Modules/Clipboard && swift test   # test riêng một package
```

Đừng chạy `verify.sh` song song trong cùng một thư mục làm việc: nó xoá `.build` của lần chạy kia.

## Module

Mỗi tính năng là một package trong `Packages/Modules/`, bật/tắt trong Settings → Modules. Cột "Mặc định" là giá trị `defaultEnabled`; cột "Quyền" là quyền macOS của module (bắt buộc thì module không chạy khi thiếu; còn lại là tuỳ chọn, module vẫn chạy và trang Quyền nhắc).

| Module | Id | Mặc định | Quyền | Làm gì |
|---|---|---|---|---|
| Clipboard | `clipboard` | Bật | Accessibility và "Dán từ app khác" (tuỳ chọn) | Lịch sử clipboard (text, ảnh, file, màu `#hex`, `rgb()`, `hsl()`; mã nguồn được nhận ra và tô màu theo ngôn ngữ), tìm kiếm có bộ lọc `@loại` và `@app` (`@code`, `@link`, `@chrome`…), board có icon, màu và thứ tự, cửa sổ Thư viện (lưới và danh sách, thanh bên theo board, loại, app), bảng nổi ở con trỏ (⇧⌘C, dán bằng ⌘1 đến ⌘9, có thể ghim), ngăn xếp copy (⌃⌥C bật, ⌃⌥⌘V dán lần lượt), sao lưu và khôi phục `.mynotchclip` (Settings → Clipboard), **board khoá** bằng mật khẩu (nội dung mã hoá; quên mật khẩu thì không có cách lấy lại; Touch ID chỉ khi bản app có hồ sơ ký, hiện chưa có), nhấn **Space** hay ⌘Y để xem một mục thật lớn như Quick Look (trong thư viện và bảng nổi). **Tuỳ chọn, tắt sẵn:** cho AI agent (Claude Code, Cursor, Codex) tìm trong lịch sử qua MCP, chỉ trong máy (Settings → Clipboard). Bấm một mục là **dán** vào app đang dùng (mặc định; thiếu quyền thì chỉ chép và hiện gợi ý). ⌃⌥V (tab), ⌃⌥⇧V (thư viện), mục "Thư viện Clipboard…" ở menu bar |
| Media | `media` | Bật | Ghi âm thanh hệ thống (tuỳ chọn) | Bài đang phát của mọi app, điều khiển (bốn ô nút chọn trong Settings: bài trước và sau, tua 15 giây, ngẫu nhiên, lặp lại, âm lượng, lời), cột sóng, **màu theo ảnh bìa** (bật), karaoke theo từng chữ (bật, khi lời có thời gian chữ), Bài sau và Bài trước cho YouTube trong Chrome qua cầu nối. Tắt sẵn: phổ âm thật; lời bài hát theo thứ tự phụ đề YouTube từ extension Chrome, Apple Music (bài của app Music, cần đăng nhập tài khoản của bạn), lrclib.net; dòng lời nằm giữa tab dưới các nút điều khiển, tuỳ chọn hiện lời 2 dòng (đang hát, sắp tới) dưới notch thu gọn, và bảng lời nổi trên mọi cửa sổ |
| Dịch | `translation` | Bật | Accessibility (tuỳ chọn) | Dịch trên máy bằng framework Translation: tab, mục Services, ⌃⌥T. Đọc to bản gốc và bản dịch; thay vào chỗ đang chọn; tự quy đổi đơn vị, giờ có múi giờ, phép tính và (tắt sẵn) tiền tệ; thẻ từ điển (cần tải từ điển trong Dictionary.app); bộ máy dịch riêng tuỳ chọn (Google, Microsoft, LLM tương thích OpenAI, cần khoá của bạn trong Keychain). **"Bôi đen là hiểu"** (bật; cần Accessibility): bôi đen ở app nào cũng được, một nút nhỏ cạnh vùng chọn hiện kết quả quy đổi hay bản dịch xem trước trên máy |
| Ảnh chụp | `screenshot` | Bật | Screen Recording (bắt buộc), thư mục Desktop và Downloads (tuỳ chọn) | Chụp vùng, cửa sổ, màn hình, OCR, sửa ảnh (mũi tên, hình, chữ, che vùng, đánh số bước, kính lúp, thước đo, xoá thông minh, canvas tự mở rộng). ⌃⌥S, ⌃⌥O |
| AI agents | `aiagents` | Bật | Không bắt buộc quyền nào (macOS hỏi Automation lần đầu khi nhảy tới Terminal hay iTerm) | Trạng thái, token và chi phí của Claude Code và Codex; hook "trạng thái chính xác" tuỳ chọn (cần cài, và cài lại sau khi nâng cấp): **duyệt hay từ chối yêu cầu quyền ngay trên notch** (chỉ trả lời khi bạn bấm), đếm agent con, nhảy tới đúng tab Terminal.app hay iTerm2. Đang làm việc chỉ là bubble khi có nhạc đang phát; chờ duyệt ("!") chiếm notch tới khi bạn trả lời, xong (✓) chiếm vài giây |
| Lịch | `calendar` | Bật | Lịch (bắt buộc), Lời nhắc (tuỳ chọn) | Sự kiện hôm nay, dòng tóm tắt trong ngày (số sự kiện, khoảng rảnh, giờ kết thúc), thông báo họp kèm Tham gia (Meet, Zoom, Whereby, Jitsi), Báo lại 5 phút và Bỏ qua, thêm sự kiện một dòng (nút "+": `họp nhóm 3h chiều mai`), lời nhắc |
| Việc cần làm | `todo` | Bật | Lời nhắc (tuỳ chọn; tab hiện nút xin quyền) | Danh sách việc trong ngày lưu ở Apple Reminders: việc quá hạn lên đầu, tích xong có Hoàn tác, thêm nhanh bằng một dòng (`gọi khách 15h30 mai`, `!!! nộp báo cáo`). ⌃⌥D mở tab, ⌃⌥⇧D thêm nhanh. Tuỳ chọn tắt sẵn: số việc còn lại cạnh notch |
| Hệ thống | `system` | Bật | Bluetooth, thư mục Downloads, Accessibility (đều tuỳ chọn) | Activity Bluetooth, mạng, Caps Lock, tải xong, âm lượng; tuỳ chọn tắt sẵn **thay HUD âm lượng, độ sáng và đèn bàn phím của macOS** bằng thanh của MyNotch (cần Accessibility) |
| Battery | `battery` | Bật | Không | Pin và sạc (module mẫu): cục pin ngang chiếm cả tab (xanh khi sạc, vàng khi Nguồn điện thấp, đỏ khi pin yếu), thời gian, nguồn, công suất, dung lượng tối đa, chu kỳ sạc |
| Shortcuts | `shortcuts` | Bật | Không | Chạy Apple Shortcuts ưa thích từ notch; mỗi shortcut ưa thích có một phím tắt (không có mặc định) |
| Hẹn giờ | `timer` | Bật | Không | Đếm ngược theo ba loại (**Tập trung**, **Nhắc việc**, **Nghỉ**) đặt bằng mặt số phút, gợi ý nghỉ sau khi tập trung xong, và bấm giờ |
| Khay | `shelf` | Bật | Không | Thả file, link, văn bản lên notch; AirDrop, chia sẻ; **hành động với file**: đổi định dạng, đổi kích thước, nén (ảnh hay zip), tách nền, nhận chữ (OCR), gộp và tách PDF, kết quả cạnh nguồn |
| Chia cửa sổ | `windows` | **Tắt** | Accessibility (tuỳ chọn, nhưng module không làm gì nếu thiếu) | Kéo một cửa sổ lên notch rồi thả vào một ô (nửa trái, nửa phải, toàn màn hình, chia bốn, chia ba, giữa) để xếp; không để cửa sổ đè nhau, thông báo khi một cửa sổ không thu nhỏ được; khoảng cách 0, 8 hay 16 pt |
| Màn hình khoá | `lockscreen` | **Tắt**, thử nghiệm | Không | Widget media (kèm nút trước, phát dừng, sau; có công tắc riêng), hẹn giờ, pin trên màn hình khoá (API riêng SkyLight, chưa kiểm chứng) |

### Phím tắt mặc định

Bảng này lấy từ các lần đăng ký phím trong mã (`App/AppDelegate.swift` và mỗi module). Đổi hay gỡ ở Settings → Chung → "Phím tắt" (trang đó cũng báo "Trùng phím" khi hai phím cùng tổ hợp). Phím của một module chỉ có khi module đang chạy; phím của App thì có luôn. Nếu hai nơi đăng ký cùng một tổ hợp **mặc định**, app không dừng mà ghi một lỗi vào log (category `hotkeys`).

| Phím | Làm gì | Module |
|---|---|---|
| ⌃⌥N | Mở hoặc đóng notch | App |
| ⌃⌥V | Mở tab Clipboard (lịch sử) | Clipboard |
| ⌃⌥⇧V | Mở cửa sổ Thư viện Clipboard | Clipboard |
| ⇧⌘C | Mở hoặc đóng bảng clipboard nổi (phím toàn cục: trình duyệt dùng nó cho công cụ nhà phát triển) | Clipboard |
| ⌃⌥C | Bật hoặc tắt ngăn xếp clipboard | Clipboard |
| ⌃⌥⌘V | Dán mục kế tiếp trong ngăn xếp | Clipboard |
| ⌃⌥T | Dịch đoạn chữ đang chọn | Dịch |
| ⌃⌥S | Chụp màn hình | Ảnh chụp |
| ⌃⌥O | OCR vùng chọn | Ảnh chụp |
| ⌃⌥D | Mở danh sách việc cần làm | Việc cần làm |
| ⌃⌥⇧D | Thêm việc nhanh (mở tab và đưa con trỏ vào ô nhập) | Việc cần làm |
| (không có mặc định) | Phát/dừng nhạc, Bài sau, Bài trước, Bật/tắt bảng lời nổi | Media |
| (không có mặc định) | Chạy từng Shortcut ưa thích ("Chạy <tên shortcut>") | Shortcuts |
| (không có mặc định) | "Hiện/ẩn icon menu bar": hiện hay giấu lại các icon đã kéo sang trái dấu ‹ (chỉ có tác dụng khi "Ẩn bớt icon trên menu bar" đang bật) | App |

Chia cửa sổ, Hẹn giờ, Khay, Lịch, Hệ thống, AI agents, Battery và Màn hình khoá không đăng ký phím nào.

Space và ⌘Y (xem lớn một mục) là phím của chính cửa sổ thư viện và bảng clipboard nổi, không phải phím tắt toàn cục: không có trong bảng trên và không đổi được. Space mở hay đóng bản xem lớn khi ô tìm trống, hay ngay sau khi bạn bấm ↑ hoặc ↓; ⌘Y luôn mở hay đóng; khi đang mở: ↑↓ đổi mục, Return dán, Esc (hay Tab) chỉ đóng bản xem lớn.

### Giao diện và cử chỉ

Settings → Giao diện (cùng hai trang cạnh nó, Chung và "Trang trên notch"; tên các trang ở thanh bên là Quyền, Chung, Giao diện, "Trang trên notch", nhóm Modules và Giới thiệu):

- **Màn hình:** "Tất cả màn hình" (mặc định), "Màn hình chính" hay "Màn hình đang dùng" (notch theo màn bạn đang làm việc: đổi sau khi con trỏ ở lại màn khác khoảng 0,3 giây, hay ngay khi bạn chuyển sang app có cửa sổ ở màn khác). Chiều rộng khi mở 480 đến 900 pt (mặc định 600), độ trễ mở và đóng, notch ảo cho màn không có notch phần cứng.
- **Giao diện notch:** "Cổ điển (đen)" (mặc định) hay **Liquid Glass** (macOS 26: notch, bubble và thông báo là kính trong suốt, kể cả notch thu gọn; có thể nhuộm theo màu nhấn); "Kính mờ khi notch mở rộng" (tắt sẵn, chỉ ở Cổ điển).
- **Màu nhấn:** "Hệ thống" (mặc định, theo macOS), tám màu có sẵn hay màu tuỳ chọn; mọi module theo màu này.
- **Cử chỉ:** vuốt hai ngón ngang để chuyển tab (bật), vuốt dọc để mở và đóng (bật, độ nhạy Thấp, Vừa, Cao), rung nhẹ (bật; cần trackpad Force Touch). Settings → "Trang trên notch" đổi thứ tự tab.
- **Chung → "Ẩn MyNotch khi quay hoặc chia sẻ màn hình":** "Không ẩn" (mặc định), "Chỉ khi notch đóng" hay "Luôn ẩn" cho notch, bảng và thư viện Clipboard (cả cửa sổ xem lớn bằng Space), bảng lời nổi, màn hình khoá, khung xếp cửa sổ và nút của "Bôi đen là hiểu" (Cài đặt và trình chú thích ảnh chụp vẫn hiện).
- **Chung → "Ẩn bớt icon trên menu bar"** (tắt sẵn; cần "Hiện icon trên menu bar" bật vì icon MyNotch là nút bấm): thêm dấu ‹ ngay bên trái icon MyNotch. Giữ ⌘ rồi kéo icon của app khác sang **trái** dấu ‹ để chọn cái cần ẩn; bấm icon MyNotch để ẩn hay hiện chúng (bấm chuột phải, hay control-click, mở menu; bàn phím và VoiceOver mở menu). "Tự thu gọn": 10 giây (mặc định; chọn không, 3, 5, 15, 30 giây, 1 hay 2 phút), và trong phút đầu sau khi bật không tự thu gọn để bạn sắp xếp. "Hiện khi rê chuột lên thanh menu" (tắt sẵn). Phím "Hiện/ẩn icon menu bar" không có mặc định. Chỉ dùng API công khai (kéo dài dấu ‹ để đẩy icon bên trái ra khỏi màn hình): nếu dấu ‹ không còn ở bên trái icon MyNotch thì không thu gọn (kêu bíp), nếu icon MyNotch bị che hay bị gỡ thì mọi thứ tự hiện lại, và gỡ dấu ‹ khỏi menu bar thì tính năng tự tắt. Máy có notch: kéo các icon cần dùng sang phải dấu ‹.


**Nhiều activity cùng lúc.** Notch thu gọn vẽ một activity **chính** (cao nhất theo ưu tiên; thông báo ngắn như âm lượng, "đã chép", ảnh chụp, ✓ của AI chiếm notch vài giây rồi trả lại) và tối đa hai **bubble** tròn bên phải cho các activity còn lại, "+N" khi nhiều hơn ba. Rê vào một bubble mở danh sách mọi activity; bấm một hàng mở tab của module đó. Dải lời dưới notch thuộc activity chính.

**Quyền.** Settings → **Quyền** (mục đầu thanh bên) liệt kê quyền của các module đang bật (cần thiết và tuỳ chọn), nhãn trạng thái, lý do, nút "Cấp quyền" hoặc "Mở Cài đặt", và "Cấp lần lượt" đi qua từng quyền còn thiếu. Thiếu quyền bắt buộc thì icon menu bar có chấm đỏ và menu có "Thiếu N quyền…" (chấm đỏ và huy hiệu chỉ đếm quyền bắt buộc). Khi còn quyền tuỳ chọn chưa cấp và cửa sổ Settings hay notch đang mở, app đọc lại trạng thái mỗi 3 giây, và ngay khi bạn quay về từ System Settings; hết thiếu, hay không có gì đang mở, thì không thăm dò gì. Trang tự mở một lần ở lần chạy đầu và khi chứng chỉ ký đổi (macOS khi đó quên mọi quyền). Quyền tuỳ chọn mới: Lời nhắc (Việc cần làm), Accessibility (Chia cửa sổ, Bôi đen là hiểu và thay vào chỗ đang chọn của Dịch, thay HUD của macOS), thư mục Desktop và Downloads (Ảnh chụp; Khay lưu kết quả của một mục kéo vào ở `~/Downloads/MyNotch`). Nhảy tới đúng tab Terminal hay iTerm của một phiên AI làm macOS hỏi quyền Automation lần đầu.

Dữ liệu của module nằm ở `~/Library/Application Support/io.lucasvu.mynotch/Modules/<id>/`.

### Quyền riêng tư

Mặc định app không gửi dữ liệu ra ngoài. Cái gì có thể ra mạng, và chỉ khi bạn bật nó:

- **Lời bài hát** (tắt sẵn): tên bài tới lrclib.net; khi bạn kết nối Apple Music thì id bài của app Music cùng token của bạn đi tới Apple.
- **Quy đổi tiền tệ** (tắt sẵn): chỉ khi văn bản có một số tiền, app lấy tỷ giá hằng ngày từ `open.er-api.com`; yêu cầu **không chứa chữ nào của bạn**.
- **Bộ máy dịch riêng** (mặc định là Apple trên máy): chỉ đoạn chữ cần dịch được gửi tới Google, Microsoft hay máy chủ OpenAI-tương thích mà bạn chọn, kèm khoá của bạn (lưu ở Keychain, không bao giờ trong cài đặt hay log). Không bao giờ đi theo chuyển hướng khi có khoá. **"Bôi đen là hiểu" luôn xem trước bằng Apple trên máy**, không bao giờ qua bộ máy từ xa.

Những thứ khác ở lại trong máy:

- **Bôi đen là hiểu** đọc vùng chọn qua Accessibility ngay trong máy; không bao giờ đọc trường mật khẩu hay trình quản lý mật khẩu; không ghi chữ đã chọn vào log; bộ theo dõi phím chỉ giữ mã phím và cờ shift, command (không bao giờ chữ gõ).
- **Cầu nối YouTube** (tắt sẵn) chỉ đi trong máy: extension, helper, rồi ổ cắm Unix 0600 tới app; phụ đề giữ trong bộ nhớ và không gửi gì cho YouTube.
- **Sao lưu clipboard** (`.mynotchclip`) là tệp 0600 **không mã hoá**; app nói rõ nếu có văn bản cũ có thể là bí mật mà nó không nhận ra, và mục bí mật mặc định bị bỏ qua. Board khoá mặc định không nằm trong tệp (kể cả tên); bật "Gồm cả N board đã khoá" thì mỗi board đi vào dưới dạng tệp mã hoá và cần mật khẩu của chính nó (board dùng Touch ID không bao giờ vào tệp). Khôi phục không ghi gì trước khi bạn chọn.
- **MCP cho AI agent** (Clipboard, tắt sẵn) không đi qua mạng: helper `mynotch-clipboard-mcp` hỏi app qua một ổ cắm Unix 0600 trong thư mục 0700 của module, app chỉ nhận kết nối từ chính tài khoản của bạn (`getpeereid`), và helper chỉ nói chuyện khi thư mục, tệp ổ cắm và tiến trình ở đầu kia đều là của bạn. Tắt công tắc, "Tắt ngay" hay dừng module thì ổ cắm đóng ngay. Agent chỉ nhận chữ, liên kết, màu và mã (tối đa 8 KB mỗi mục); ảnh chỉ có kích thước và dung lượng, tệp chỉ có tên (không đường dẫn). Mục đánh dấu nhạy cảm và mục của board khoá (kể cả khi đang mở) không bao giờ được trả về; mục trông giống mật khẩu hay khoá (mẫu khoá API, khối PEM, chuỗi kết nối có mật khẩu, dòng `password:`, chuỗi ngẫu nhiên dài…) cũng bị giấu, nhưng đó là **đoán theo hình dạng chữ, không phải bảo đảm**: đừng bật nếu clipboard của bạn chứa bí mật quan trọng. Nhật ký truy cập (50 lần gần nhất, chỉ trong bộ nhớ) ghi giờ, công cụ và số kết quả, không ghi nội dung tìm. Tối đa 10 lệnh gọi mỗi giây. MyNotch không tự sửa file cấu hình của agent: bạn dán đoạn cấu hình.
- **Board khoá** (Clipboard): mục của board được mã hoá AES-GCM bằng một khoá ngẫu nhiên 256 bit, khoá này được bọc bằng khoá dẫn xuất từ mật khẩu (PBKDF2-HMAC-SHA256, 600.000 vòng; mật khẩu tối thiểu 10 ký tự) và nằm trong tệp 0600 ở `vault/` (thư mục 0700). Khi khoá chỉ thấy tên, icon, màu và số mục. **Quên mật khẩu thì không có cách khôi phục** (chỉ xoá được board); nhập sai năm lần liên tiếp thì phải chờ 30 giây, mỗi lần sai sau gấp đôi, tối đa 10 phút. Khi mở, mục (kể cả ảnh) nằm trong bộ nhớ, chỉ có một tệp tạm 0600 vài giây khi bạn kéo một ảnh ra app khác; board tự khoá sau 5 phút không dùng (chỉnh được), khi máy ngủ hay khoá màn hình và khi MyNotch thoát, và luôn khoá được cả khi lần lưu cuối hỏng (thay đổi chưa lưu bị mất, có báo). Bản chép cũ của nội dung có thể còn trong Time Machine hay ảnh chụp ổ đĩa tạo trước khi khoá.
- **Hook của AI agents chỉ trả lời khi bạn bấm**: yêu cầu quyền đi từ helper tới app qua ổ cắm trong máy; chỉ nút "Cho phép" hay "Từ chối" của bạn mới thành câu trả lời; hết 60 giây, không có MyNotch, hay bạn chọn "Hỏi trong terminal" thì agent tự hỏi trong terminal như thường. Helper không đọc prompt hay transcript, và app chỉ nói chuyện với ổ cắm thuộc chính bạn (thư mục 0700, `getpeereid`).
- **Ẩn khỏi quay màn hình** (Chung) tắt sẵn; `sharingType = .none` chưa được xác minh với QuickTime, Meet hay Zoom.

## Cấu trúc và cách ghép module

| Thư mục | Vai trò |
|---|---|
| `App/` | Target app: khởi động, menu bar, Settings. `ModuleList.swift` là nơi **duy nhất** ghép module vào app. Icon app là `App/Icon/MyNotch.icon` (Icon Composer, hướng "Notch glow"; xem mục "Icon") |
| `Packages/MyNotchCore` | Hợp đồng module, registry, settings, quyền, phím tắt, live activity, Services |
| `Packages/NotchUI` | Cửa sổ notch, hình học, state machine, đa màn hình, thả file, SkyLight shim |
| `Packages/DebugTools` | Chỉ có trong bản Debug (ở Release biên dịch thành rỗng): kích hoạt live activity giả qua distributed notification để thử notch mà không cần app thật (mục "Gỡ lỗi" bên dưới) |
| `Packages/Modules/*` | Mỗi tính năng một package; chỉ phụ thuộc MyNotchCore và NotchUI, không module nào import module khác |
| `Tools/mynotch-hook` | Helper CLI của AI agents, được nhúng vào `Contents/MacOS`: gửi trạng thái và, cho một yêu cầu quyền, đợi câu trả lời của bạn tối đa 60 giây (chỉ in ra khi bạn bấm Cho phép hay Từ chối) |
| `Tools/mynotch-clipboard-mcp` | Helper MCP (stdio) cho Clipboard, nhúng vào `Contents/MacOS` (mã nằm ở thư viện `ClipboardMCPKit` của package Clipboard). Khi bạn bật MCP, app chép nó vào `bin/` trong thư mục dữ liệu của module để cấu hình của agent trỏ tới một đường dẫn không đổi qua các lần nâng cấp app |
| `Tools/mynotch-youtube-host` | Helper Native Messaging cho extension Chrome (mã nằm ở thư viện `YouTubeBridgeKit` của package Media), nhúng vào `Contents/MacOS` |
| `Extensions/Chrome/MyNotchYouTube` | Extension Chrome (Manifest V3) chuyển phụ đề YouTube cho module Media; được nhúng vào `Contents/Resources/ChromeExtension`, và nút "Cài cầu nối cho Chrome" chép nó ra `~/Library/Application Support/io.lucasvu.mynotch/ChromeExtension` để nạp bằng Load unpacked. Test: `node --test Extensions/Chrome/MyNotchYouTube/tests/` (`verify.sh` không chạy test này) |
| `Vendor/` | `mediaremote-adapter` (không sửa file vendor) |
| `docs/` | Spec, ghi chú triển khai, checklist kiểm thử tay |

Ghép một module cần hai chỗ: `project.yml` (mục `packages` và `dependencies` của target MyNotch) và một dòng trong `App/ModuleList.swift`.

## Thêm một module

1. Tạo package `Packages/Modules/<Tên>/`; chép `Packages/Modules/Battery/Package.swift` làm mẫu (macOS 26, phụ thuộc đường dẫn tới MyNotchCore và NotchUI, `.defaultIsolation(MainActor.self)`, test dùng `MyNotchTestSupport`). Viết một class theo `FeatureModule`.
2. Khai báo package trong `project.yml`.
3. Module cần quyền mới: thêm usage description và entitlement tương ứng vào `project.yml`, và khai báo quyền trong descriptor (`permissions` là bắt buộc, `optionalPermissions` là tuỳ chọn, `permissionReasons` là một dòng lý do cho mỗi quyền) để trang Quyền trong Settings hiện nó.
4. Thêm một dòng vào `App/ModuleList.swift`, rồi `xcodegen generate`. `verify.sh` tự test mọi package trong `Packages/Modules/`.

Module dùng được: `context.storage`, `context.scheduler` (việc đã hẹn tự huỷ khi module dừng), `context.hotkeys` (đăng ký và `unregister` theo tên), `context.presenter` (`open()` mở tab của chính module, `showToast`, `close`), `context.activities` (live activity cập nhật tại chỗ, `raise`; `LiveActivity` có `bottom` và `bottomHeight` cho dải dưới notch, `minimal` và `summary` cho bubble và danh sách, `expiresAfter` biến nó thành thông báo ngắn thắng hoà ưu tiên), `context.services` (macOS Services: cần thêm một mục `NSServices` trong `project.yml` và một phương thức trong `App/ServicesProvider.swift`, nếu không hệ thống không bao giờ gọi), `context.lockScreen` (view nhỏ không nhạy cảm cho màn hình khoá), `FeatureModule.menuItems` (mục thêm vào menu của icon menu bar, chỉ hiện khi module chạy), `NotchTab(acceptsKeyboard:dropTypes:onDrop:)`, `@Environment(\.notch)` (ghim, báo đang kéo, đóng notch), `optionalPermissions` trong `ModuleDescriptor`. Từ NotchUI (qua `NotchInterface.shared`): `@Environment(\.notchAccent)` cho màu nhấn (một cửa sổ riêng thì đưa `interface.accent` vào bằng `.environment` và `.tint`), `CaptureHidingFollower` để một cửa sổ của module theo cài đặt ẩn khỏi quay màn hình, `KeyboardHandBack` để trả bàn phím cho app phía trước trước khi gửi một phím, `interface.feel(.alignment)` cho một cú chạm trackpad. Một tab xin cao hơn 240 pt bị ghi lỗi vào log và kẹp về 240 (`NotchTab.heightRange`); hai phím tắt cùng tổ hợp mặc định chỉ ghi log, không dừng app. Sau khi module dừng, `scheduler`, `hotkeys`, `presenter`, `activities`, `services` và `lockScreen` không làm gì nữa. Test cần thư mục tạm thì dùng `ScratchFolders.shared.reserve("<nhãn>")` của `MyNotchTestSupport` (tự xoá khi tiến trình test thoát).

## Tài liệu

- **Spec:** `docs/superpowers/specs/2026-10-13-*-design.html` (bản `.md` đi kèm). Kế hoạch nền tảng: `docs/superpowers/plans/`.
- **Ghi chú triển khai** (sai khác so với spec, giới hạn đã chấp nhận, mục sửa lại spec): `docs/superpowers/notes/2026-10-14-<module>-implementation.html`, mỗi module một file cùng một file cho nền tảng (bubble, bàn phím, quyền, hiệu năng, Battery, trigger Debug, và từ mục 14 ẩn khỏi quay màn hình, tab và cử chỉ, màn hình đang dùng, màu nhấn, Liquid Glass nằm ở đó, và từ mục 15 ẩn icon menu bar, làm mới quyền, tên tiếng Việt của các trang Settings); ghi chú Clipboard có thêm MCP (mục 11), board khoá (mục 12) và xem lớn bằng Space (mục 13); `2026-10-15-app-icon-implementation.html` cho icon, `2026-10-15-window-layout-implementation.html` cho Chia cửa sổ và `2026-10-15-todo-implementation.html` cho Việc cần làm. Mỗi ghi chú có các mục Ruling (quyết định kèm chi phí nếu sai) và khoảng trống chưa kiểm.
- **Kiểm thử tay:** `docs/manual-test-checklist-all.html` (gộp theo module, chọn kết quả và copy ra văn bản; mục cần phần cứng như trackpad Force Touch, khoá màn hình thật, màn ngoài hay iTerm2 có nhãn riêng). `docs/manual-test-checklist.html` là checklist cũ, chỉ phần nền tảng.
- Tạo HTML từ Markdown: `python3 scripts/md2html.py <file.md>`.

## Gỡ lỗi (bản Debug)

Hai trigger chỉ có ở bản Debug (Release không chứa chuỗi của chúng; kiểm: `strings -a MyNotch.app/Contents/MacOS/MyNotch | grep -c io.lucasvu.mynotch.debug` ra `0`). Chúng nhận **distributed notification**, nên gửi được từ Terminal:

| Trigger | Object | Làm gì |
|---|---|---|
| `io.lucasvu.mynotch.debug.activities` | `add 1` đến `add 5`, `high`, `clear` | Phát activity giả (mỗi cái một symbol, ưu tiên xoay thấp, thường, cao) để thử chính, bubble, "+N" và danh sách mà không cần app thật; `high` thêm một activity ưu tiên cao 8 giây; `clear` gỡ hết. Tối đa một lệnh mỗi giây |
| `io.lucasvu.mynotch.debug.appleLyrics` | catalog id Apple (1 đến 20 chữ số) | Chạy một lượt tra lời Apple Music (cần đã kết nối; không đọc hay ghi cache, không chạm bài đang phát). Tối đa một lượt mỗi 5 giây |

```bash
xcrun swift -e 'import Foundation; DistributedNotificationCenter.default().postNotificationName(.init("io.lucasvu.mynotch.debug.activities"), object: "add 3", userInfo: nil, deliverImmediately: true)'
```

Đọc log bằng `/usr/bin/log` (trong zsh, `log` là lệnh dựng sẵn khác). Mọi dòng ở mức notice nên không cần `--info`, và **không có dòng nào chứa token, nội dung clipboard, tiêu đề hay lời bài hát**:

```bash
/usr/bin/log show --last 5m --style compact --predicate 'subsystem == "io.lucasvu.mynotch" AND category == "notch-ui"'
```

| `category` | Có ở | Nội dung |
|---|---|---|
| `notch-ui` | Debug | Trạng thái notch, đổi tab, cửa sổ (frame, alpha, key), trả bàn phím, dải, bubble, danh sách |
| `perf` | Debug | Mỗi 10 giây: `layouts/s`, `bodies/s`, `spectrumUpdates/s` (đo xem notch có bị vẽ lại liên tục không) |
| `activities` | Debug | Lệnh của trigger activity và mỗi lần activity chính hay bubble đổi |
| `media` | mọi bản | Các bước tra lời Apple Music (trạng thái, mã lỗi, storefront; thêm `AND eventMessage CONTAINS "Apple"`) |
| `youtube-bridge` | mọi bản | Host `mynotch-youtube-host`, app, các mã `diag` của extension (kể cả `sw-inject`, `sw-access`, `content-command`), khớp bài, độ lệch lời, lệnh Bài sau và Bài trước và đường rơi sang MediaRemote |
| `smart-selection` | mọi bản | "Bôi đen là hiểu": mỗi cử chỉ một dòng `gesture` rồi một dòng `skip reason=…` hay `hint kind=…`; chỉ mã, không bao giờ chữ đã chọn (`log stream --predicate 'subsystem == "io.lucasvu.mynotch" AND category == "smart-selection"' --level info`) |
| `window-layout` | mọi bản | Chia cửa sổ: `neighbours`, `placed`, `overlaps` cho mỗi lần thả; chỉ bundle id, id bố cục và số, không có tiêu đề cửa sổ |
| `translation` | mọi bản | Bộ máy dịch riêng hỏng: "<bộ máy> failed: <loại> (HTTP n)"; không bao giờ khoá, URL hay chữ |
| `todo` | mọi bản | Việc cần làm: mỗi lần làm mới (`refresh status=…`), đổi pha, câu trả lời của hộp thoại quyền Lời nhắc và lần chờ hệ thống đồng ý (`access request`, `access recheck`), làm mới kho (`store renewed…`), kết quả đọc (`read lists=… items=…`); chỉ mã và số, không bao giờ tiêu đề hay ghi chú của một việc |
| `app` | mọi bản | Menu bar: lần thu gọn bị từ chối vì dấu ‹ không nằm bên trái icon MyNotch, dấu ‹ hay icon MyNotch bị gỡ khỏi menu bar (kèm việc tự tắt công tắc tương ứng) |
| `hotkeys`, `modules` | mọi bản | Hai phím tắt cùng tổ hợp mặc định (hai id cố định); một tab xin cao quá 240 pt (id module và số) |

Thêm `AND process == "MyNotch"` (hoặc `"mynotch-youtube-host"`) để lọc theo tiến trình, và dùng `log stream` thay `log show` để xem trực tiếp. Bản Debug còn đọc user default `MyNotchKeyboardReturn` (`sinkPanel` mặc định, `sinkAndActivate`, `orderOutIn`) để so cách notch trả bàn phím cho app đang dùng: `defaults write <bundle id của bản Debug> MyNotchKeyboardReturn -string sinkAndActivate`, rồi mở lại app. Cách đọc từng log và các kết quả mong đợi: ghi chú nền tảng và ghi chú Media trong `docs/superpowers/notes/`.

## Icon

Icon app là một tài liệu Icon Composer nhiều lớp (hướng A, "Notch glow": nền than chì, notch đen cắt giữa mép trên, luồng sáng tím tràn xuống) ở `App/Icon/MyNotch.icon`, nối vào dự án bằng `ASSETCATALOG_COMPILER_APPICON_NAME: MyNotch` trong target app của `project.yml`; không có `AppIcon.appiconset`. Đổi icon: mở `App/Icon/MyNotch.icon` bằng Icon Composer (đi cùng Xcode 26) rồi lưu đè, hoặc sửa ba lớp SVG trong `Assets/` (1024 × 1024, phủ kín khung), rồi build lại. Chi tiết: `docs/superpowers/notes/2026-10-15-app-icon-implementation.html`.
## Bản Release

Khởi động cùng máy cần một bản app ổn định (bản Debug đổi chữ ký mỗi lần build). Thoát MyNotch đang chạy (menu bar → Quit MyNotch) rồi:

```bash
xcodebuild -project MyNotch.xcodeproj -scheme MyNotch -configuration Release \
    -destination "platform=macOS,arch=$(uname -m)" -derivedDataPath .build/xcode build -quiet
rm -rf /Applications/MyNotch.app
ditto .build/xcode/Build/Products/Release/MyNotch.app /Applications/MyNotch.app
```

Không dùng `cp -R` đè lên bản cũ: macOS sẽ giết app khi mở vì chữ ký không còn khớp.

## Ký app

App, các helper `mynotch-hook`, `mynotch-clipboard-mcp` và `mynotch-youtube-host`, và framework MediaRemoteAdapter được ký bằng chứng chỉ **Apple Development** (`CODE_SIGN_IDENTITY: "Apple Development"`, `DEVELOPMENT_TEAM: B394MAY4QN` trong `project.yml`, có hardened runtime). Nhờ vậy macOS nhớ các quyền đã cấp (Accessibility, Screen Recording, Lịch…) qua các lần build lại.

Chứng chỉ này cần chứng chỉ trung gian **Apple WWDR G3** (`AppleWWDRCAG3.cer`) trong keychain **login** (cài bằng `security add-certificates -k ~/Library/Keychains/login.keychain-db AppleWWDRCAG3.cer`; keychain iCloud không nhận chứng chỉ, báo lỗi `-25294`). Kiểm tra: `security find-identity -v -p codesigning` phải báo `1 valid identities found`. Máy không có chứng chỉ thì đổi lại `CODE_SIGN_IDENTITY: "-"` (ad-hoc), khi đó macOS quên quyền sau mỗi lần build.

Chứng chỉ Apple Development của Apple ID miễn phí có hạn (thường 1 năm); hết hạn thì macOS không mở app nữa: tạo chứng chỉ mới trong Xcode rồi build lại.

## Xử lý sự cố

- `cannot find '<Tên>' in scope` cho symbol nằm ở một package local khác: xoá thư mục `.build` của package đang build rồi chạy lại.
- Notch chồng nhau hoặc không nhận chuột: thoát các app notch khác (OneNotch, boring.notch…) đang chạy, và chỉ chạy một bản MyNotch.
- Quyền bị quên sau khi build: xem mục "Ký app". Cấp lại bằng Settings → Quyền → “Cấp lần lượt” (trang này tự mở khi app lần đầu chạy hoặc khi chứng chỉ ký đổi). Muốn thử lại hộp thoại quyền từ đầu: `tccutil reset All io.lucasvu.mynotch`; với cùng chứng chỉ ký trang Quyền **không** tự mở lại sau lệnh này (chấm đỏ và "Thiếu N quyền…" trên menu bar là lời nhắc), muốn thấy nó tự mở: `defaults delete io.lucasvu.mynotch app.permissionIdentity` rồi mở lại app.
- Sau khi nâng cấp app, **cài lại hook AI** (Settings → AI agents) để có thẻ duyệt quyền, đếm agent con và nhảy đúng tab terminal, và bấm lại **"Cài cầu nối cho Chrome"** rồi nạp lại extension (0.1.3) trong `chrome://extensions`: bản chép cũ của helper và extension không biết các lệnh mới. Nếu cầu nối YouTube im lặng, đặt "Quyền truy cập trang web" của extension là "Trên tất cả trang web" (Settings → Media nói khi Chrome đang chặn).
- "Bôi đen là hiểu" không hiện gì: bật Accessibility; xem log `smart-selection` (mỗi lần bôi đen có một dòng nói vì sao không hiện); trong Chrome nhấn ⌃⌥T một lần hay để cài đặt "Đọc vùng chọn trong Chrome và app Electron" bật.
- "Ẩn bớt icon trên menu bar" bật mà bấm không ẩn gì và kêu bíp: dấu ‹ phải nằm bên **trái** icon MyNotch; giữ ⌘ rồi kéo nó sang trái. Icon của app khác chỉ ẩn khi nằm bên trái dấu ‹. Nếu mọi icon tự hiện lại, icon MyNotch đã bị che hay bị gỡ (kéo nó về lại menu bar, hay bật "Hiện icon trên menu bar").
- AI agent báo không kết nối được MyNotch: bật "Cho AI agent đọc lịch sử clipboard (MCP)" ở Settings → Clipboard (module Clipboard phải đang chạy), dán lại đoạn cấu hình đúng cho agent đó và khởi động lại agent. Sau khi nâng cấp MyNotch, tắt rồi bật lại công tắc để bản chép của helper được làm mới.
- Sau khi chạy `./scripts/verify.sh` hay build lại, bản `MyNotch.app` dưới `.build/xcode` bị thay ngay dưới tiến trình đang chạy: thoát **mọi** bản MyNotch (kể cả bản đã chạy từ đường dẫn khác, và adapter `mediaremote-adapter.pl` mồ côi nếu có) rồi mới mở bản mới; để lại hai bản là hai notch chồng nhau.
