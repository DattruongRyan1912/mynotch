# Checklist kiểm thử tay — Nền tảng

Điền **Đạt / Không đạt / Không kiểm được (lý do)** và ngày kiểm. Thoát OneNotch trước khi kiểm (hai app cùng chiếm vùng notch).

## Khởi động và menu bar

| # | Kịch bản | Kết quả | Ghi chú |
|---|---|---|---|
| 1 | Chạy app: không có icon Dock, có icon menu bar, menu hiện đủ các mục | | |
| 2 | Menu bar → Hide Notch / Show Notch; Pause All Modules có dấu tích và dừng Battery | | |
| 3 | Settings: ⌘W đóng cửa sổ, ⌘, mở lại, ⌘Q thoát app | | |
| 4 | Settings → General → Hiện icon trên menu bar: tắt thì icon biến mất; mở lại MyNotch từ Finder thì Settings hiện | | |
| 5 | Khởi động cùng máy: dùng bản **Release copy vào /Applications** (bản Debug trong DerivedData đổi chữ ký mỗi lần build). Bật → app có trong Login Items, tự chạy sau khi đăng nhập lại; nếu macOS cần duyệt thì hiện nút "Mở Login Items" | | |

## Notch và chuột

| # | Kịch bản | Kết quả | Ghi chú |
|---|---|---|---|
| 6 | Notch thật trên MacBook: notch đen trùng khít notch phần cứng, không lệch | | |
| 7 | Màn ngoài: notch ảo ở giữa cạnh trên; đổi chiều rộng/chiều cao trong Interface thì cập nhật ngay | | |
| 8 | Interface → Màn hình = Màn hình chính / Có con trỏ / Tất cả: notch hiện đúng màn | | |
| 9 | Rê chuột vào notch ~150ms thì mở; rời ra ~300ms thì đóng | | |
| 10 | Rê chuột ở mép dưới màn 4K (đặt phía trên MacBook) **không** làm notch MacBook mở | | |
| 11 | Click vào notch thì mở ngay; ⌃⌥N mở/đóng notch trên màn đang có con trỏ | | |
| 12 | Khi notch đóng: click menu bar và cửa sổ ngay dưới vùng notch vẫn hoạt động | | |
| 13 | Từ notch đang mở, kéo chuột thẳng xuống vùng trong suốt bên dưới: notch đóng, click ở đó tới được cửa sổ bên dưới | | |
| 14 | Cửa sổ phóng to (zoom/Fill) trên màn MacBook: thanh tab/tiêu đề ngay dưới notch vẫn click được (vùng đệm 8pt quanh notch nhận chuột — chấp nhận nếu chỉ mất vài pt) | | |
| 15 | Control Center, Wi-Fi, Spotlight và menu hệ thống không bị notch che | | |
| 16 | Hover activity: một activity xuất hiện ngay dưới con trỏ đang đứng yên thì notch mở sau ~150ms (đúng thiết kế) — ghi lại cảm nhận | | |

## Fullscreen và màn hình

| # | Kịch bản | Kết quả | Ghi chú |
|---|---|---|---|
| 17 | Video fullscreen Safari **trên màn MacBook**: notch ẩn; thoát fullscreen: hiện lại | | |
| 18 | Video fullscreen trên **màn 4K**, rồi click sang một app ở màn MacBook: notch màn 4K vẫn ẩn | | |
| 19 | Cửa sổ phóng to (zoom/Fill, không phải fullscreen) trên màn MacBook: notch **không** ẩn | | |
| 20 | Keynote khi trình chiếu: ghi lại notch có ẩn không (layer khác 0 — rủi ro đã biết) | | |
| 21 | Chuyển sang Space fullscreen của app khác: notch vẫn hiện/ẩn đúng theo cài đặt | | |
| 22 | Cho máy ngủ rồi đánh thức: notch vẫn đúng vị trí | | |
| 23 | Rút rồi cắm lại màn ngoài: notch biến mất rồi xuất hiện lại đúng chỗ | | |
| 24 | Màn ngoài với menu bar tự ẩn: notch ảo không che nội dung bất thường | | |

## Battery và Settings

| # | Kịch bản | Kết quả | Ghi chú |
|---|---|---|---|
| 25 | Tab Battery hiển thị %, trạng thái, nguồn điện; ở giới hạn sạc 80% hiện "Đã cắm sạc · không sạc" | | |
| 26 | Cắm sạc: activity tia sét + % hiện khoảng 4 giây; rút sạc trong 4 giây thì activity tắt ngay | | |
| 27 | Settings → Battery: các dòng cài đặt không bị lồng hộp trong hộp; hạ ngưỡng pin yếu thì cảnh báo cập nhật ngay | | |
| 28 | Settings → Battery: tắt thì tab/activity biến mất; bật lại thì xuất hiện | | |
| 29 | Activity Monitor: CPU của MyNotch khi rê chuột liên tục 30 giây | | |
