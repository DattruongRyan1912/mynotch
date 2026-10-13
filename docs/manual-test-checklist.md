# Checklist kiểm thử tay — Nền tảng

- **Ngày kiểm:**
- **Commit / bản build:** (`git log -1 --format=%h`; Debug hay Release)
- **Máy:** MacBook có notch + màn ngoài (ghi model và độ phân giải)

Điền **Đạt / Không đạt / Không kiểm được (lý do)** vào cột Kết quả.

Trước khi kiểm:
- Thoát OneNotch và các app notch khác (hai app cùng chiếm vùng notch).
- Chỉ chạy **một** bản MyNotch. Bản Debug (DerivedData) và bản Release (`/Applications`) nằm ở hai đường dẫn khác nhau; mở cả hai sẽ thành hai notch chồng nhau. Thoát bản cũ (menu bar → Quit MyNotch) trước khi mở bản kia.

## Khởi động và menu bar

| # | Kịch bản | Kết quả | Ghi chú |
|---|---|---|---|
| 1 | Chạy app: không có icon Dock; có icon menu bar; menu có Open Settings…, Hide Notch, Pause All Modules, Quit MyNotch | | |
| 2 | Menu bar → Hide Notch: notch biến mất, mục đổi thành Show Notch; bấm lại thì hiện. Pause All Modules: có dấu tích, tab Battery biến mất; bấm lại thì bỏ tích và Battery chạy lại | | |
| 3 | Khi cửa sổ Settings đang focus: ⌘W đóng cửa sổ; mở lại bằng menu bar → Open Settings…; ⌘, (khi MyNotch đang là app active) mở Settings; ⌘Q thoát app | | |
| 4 | Settings → General → Hiện icon trên menu bar: tắt thì icon biến mất; mở lại MyNotch từ Finder (cùng bản đang chạy) thì Settings hiện; bật lại thì icon quay về | | |
| 5 | Khởi động cùng máy: dùng bản **Release cài vào /Applications** theo README (bản Debug đổi chữ ký mỗi lần build). Bật → app có trong System Settings → General → Login Items và tự chạy sau khi đăng xuất/đăng nhập lại; nếu macOS cần duyệt thì Settings hiện nút "Mở Login Items" | | |
| 6 | Thoát app rồi mở lại: mọi cài đặt đã đổi (Interface, Battery, phím tắt) vẫn giữ nguyên | | |

## Notch và chuột

| # | Kịch bản | Kết quả | Ghi chú |
|---|---|---|---|
| 7 | Notch thật trên MacBook: notch đen trùng khít notch phần cứng, không lệch | | |
| 8 | Màn ngoài: notch ảo ở giữa cạnh trên. Interface → Notch ảo: đổi Chiều rộng thì cập nhật ngay; tắt "Cao bằng menu bar" rồi kéo Chiều cao thì cập nhật ngay (slider bị khoá khi toggle đang bật) | | |
| 9 | Interface → Màn hình: "Tất cả" → notch ở mọi màn; "Màn hình có con trỏ" → notch theo màn có con trỏ; "Màn hình chính" → chỉ màn được đặt làm màn chính trong System Settings → Displays (nếu màn 4K là màn chính thì notch MacBook biến mất — đúng thiết kế) | | |
| 10 | Rê chuột vào notch ~150ms thì mở; rời ra ~300ms thì đóng. Đổi "Trễ khi mở/đóng" trong Interface thì độ trễ đổi theo; đổi Chiều rộng khi mở rộng thì notch mở rộng theo | | |
| 11 | Rê chuột ở mép dưới màn 4K (đặt phía trên MacBook) **không** làm notch MacBook mở | | |
| 12 | Click vào notch thì mở ngay; ⌃⌥N mở/đóng notch trên màn đang có con trỏ | | |
| 13 | Settings → General → đổi phím tắt "Mở/đóng notch" bằng ô ghi phím: phím mới hoạt động, ⌃⌥N cũ thôi hoạt động | | |
| 14 | Khi notch đóng: click menu bar và cửa sổ ngay dưới vùng notch (ngoài vùng đệm 8pt quanh notch) vẫn hoạt động | | |
| 15 | Từ notch đang mở, rê chuột thẳng xuống vùng trong suốt bên dưới: notch đóng, click ở đó tới được cửa sổ bên dưới | | |
| 16 | Cửa sổ phóng to (zoom/Fill) trên màn MacBook: thanh tab/tiêu đề ngay dưới notch vẫn click được, trừ vùng đệm 8pt quanh notch (chấp nhận) | | |
| 17 | Control Center, Wi-Fi, Spotlight và menu hệ thống không bị notch che | | |
| 18 | Để con trỏ đứng yên cạnh notch, cách mép notch khoảng 20–60pt (ngoài vùng đệm 8pt nhưng trong vùng activity), cắm sạc: activity hiện dưới con trỏ và notch mở sau ~150ms (đúng thiết kế) — ghi lại cảm nhận | | |

## Fullscreen và màn hình

| # | Kịch bản | Kết quả | Ghi chú |
|---|---|---|---|
| 19 | Video fullscreen Safari **trên màn MacBook**: notch ẩn; thoát fullscreen: hiện lại | | |
| 20 | Video fullscreen trên **màn 4K**, rồi click sang một app ở màn MacBook: notch màn 4K vẫn ẩn | | |
| 21 | Cửa sổ phóng to (zoom/Fill, không phải fullscreen) trên màn MacBook: notch **không** ẩn | | |
| 22 | Tắt "Ẩn khi app đang fullscreen" rồi vào fullscreen: notch vẫn hiện; bật lại: notch ẩn | | |
| 23 | Keynote khi trình chiếu: ghi lại notch có ẩn không (layer cửa sổ khác 0 — rủi ro đã biết) | | |
| 24 | Vuốt sang Space fullscreen của app khác rồi quay lại desktop: notch ẩn/hiện đúng theo cài đặt | | |
| 25 | Cho máy ngủ rồi đánh thức: notch vẫn đúng vị trí | | |
| 26 | Rút rồi cắm lại màn ngoài: notch biến mất rồi xuất hiện lại đúng chỗ | | |
| 27 | Màn ngoài với menu bar tự ẩn (System Settings → Thanh menu → "Tự động ẩn và hiển thị thanh menu"): notch ảo vẫn ở cạnh trên, không lệch xuống, không chặn click ngoài vùng notch | | |

## Battery và Settings

| # | Kịch bản | Kết quả | Ghi chú |
|---|---|---|---|
| 28 | Tab Battery hiển thị %, trạng thái, nguồn điện; khi đã cắm sạc mà máy đang giữ giới hạn sạc (ví dụ 80%) thì hiện "Đã cắm sạc · không sạc" | | |
| 29 | Cắm sạc: activity tia sét + % hiện khoảng 4 giây; rút sạc trong 4 giây thì activity tắt ngay | | |
| 30 | Settings → Battery → tắt "Thông báo khi cắm sạc": cắm sạc thì không còn activity tia sét | | |
| 31 | Pin yếu (rút sạc, pin ≤ 50%): Settings → Battery tăng ngưỡng lên trên % hiện tại → activity pin yếu (đỏ) hiện; hạ ngưỡng xuống dưới % hiện tại → tắt ngay. Các dòng cài đặt không bị lồng hộp trong hộp | | |
| 32 | Settings → Modules → Battery: tắt thì tab và activity biến mất; bật lại thì tab quay lại (activity sạc chỉ hiện ở lần cắm sạc tiếp theo; activity pin yếu chỉ hiện nếu pin vẫn dưới ngưỡng) | | |
| 33 | Trang About: Phiên bản `0.1.0 (1)`, Bundle ID `io.lucasvu.mynotch`, mục Thư viện bên thứ ba có KeyboardShortcuts (MIT, link mở được) | | |
| 34 | Activity Monitor: CPU của MyNotch khi rê chuột liên tục 30 giây — đạt nếu trung bình dưới ~5% (ghi con số) | | |
