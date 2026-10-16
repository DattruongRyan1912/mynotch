# Ghi chú triển khai: Hẹn giờ và bấm giờ

- **Ngày:** 2026-10-14
- **Spec:** [Khay file, Shortcuts, Hẹn giờ (dự án con 8), §4](../specs/2026-10-13-shelf-shortcuts-timer-design.html). Spec không bị sửa; chỗ đã lỗi thời nằm ở mục "Sửa lại spec".
- **Package:** `Packages/Modules/Timer`, product `TimerModule`. Module id `timer` ("Hẹn giờ", **order 880**, để Battery giữ order 900), tab "Hẹn giờ" (cao 150 pt ở bản đầu, khoảng 188 pt từ R3i), live activity `timer`, bật mặc định, không có quyền, không có khoá cài đặt riêng.
- **Commit chính:** `bec55d9` module, `f994113` sửa sau review, `5a1362a` (màn hình khoá, kèm các sửa Timer của review H4), `e2b0586` gắn vào app.
- **Test tự động:** 36 test theo báo cáo L1 (`verify.sh` qua ở `8a2b842`). Test chỉ dùng đồng hồ giả, `ManualScheduler` và bộ phát âm thanh giả. Chưa chạy lại khi viết tài liệu này.
- **Kiểm thử tay:** [mục Hẹn giờ trong checklist gộp](../../manual-test-checklist-all.html#timer)
- **Cập nhật sau `034e40d` (2026-10-16):** đọc được trên kính sáng và tối: mặt số và núm không còn trắng cứng (S2 `37d02c8`, `a944673`; mục 9). Timer 128 test. Cổ điển giữ nguyên từng điểm ảnh; các commit này nằm trong cổng `verify.sh` xanh ở `6077497` (17 package cộng app). Chưa ai thấy trên kính thật.
- **Cập nhật sau `156f02d` (2026-10-15):** ba loại hẹn giờ và mặt số phút (`30830cf`, `23f4ff1`) (mục 7 và 8). Timer 125 test. Mục 1 và 4 ở trên nói về tab bản đầu (các mẫu 1, 5, 10, 25 phút), đã được thay.

## 1. Đã xây gì so với spec

- `TimerModel` thuần, `Codable`: đếm ngược theo `endDate` (giờ thực, nên không lệch khi máy ngủ) và bấm giờ (thời gian tích luỹ cộng mốc bắt đầu); chuyển trạng thái bắt đầu, tạm dừng, tiếp tục, huỷ, thêm 1 phút. Lưu vào `storage.directory/timer.json` (ghi nguyên tử), nên mở lại app vẫn còn.
- Live activity khi đang chạy: đồng hồ cát bên trái, thời gian còn lại bên phải bằng `Text(timerInterval:)`, không gọi `set` mỗi giây.
- Hết giờ: activity `.high` "Hết giờ" kèm âm thanh `NSSound(named: "Glass")` đúng một lần, giữ tới khi người dùng bấm hoặc sau 30 giây (`finishedLifetime`).
- Tab (bản đầu; đã thay bằng loại và mặt số ở mục 7): các mẫu 1, 5, 10, 25 phút cùng ô tuỳ chỉnh, thời gian lớn, nút Tạm dừng, Tiếp tục, Huỷ, "+1 phút" (nút "Đóng" khi đã hết giờ), và công tắc "Bấm giờ". Không có phím tắt mặc định.
- Màn hình khoá: Timer đăng ký view đếm ngược (ưu tiên `.high`), xem [ghi chú Màn hình khoá](2026-10-14-lock-screen-implementation.html).

## 2. Sai khác so với spec và lý do

- **Bấm giờ dùng giờ thực `Date`, không dùng mốc `ContinuousClock`** như spec §4. Cần để lưu và khôi phục được qua lần mở lại; có comment trong kiểu `TimerModel`. `elapsed` và `pause` đều kẹp về không khi đồng hồ chạy lùi.
- **Mở lại app không thông báo lại "Hết giờ" đã qua:** `start()` chỉ phát activity khi mô hình lưu chưa ở trạng thái `.finished`. Đếm ngược kết thúc lúc app đóng vẫn được thông báo khi mở lại, và tab vẫn hiện trạng thái đã xong cho tới khi bấm "Đóng". Không thêm ngày "xong lúc" thật vì nó đổi định dạng lưu.
- **Mọi thay đổi làm mới mô hình trước** (`mutate` gọi `refresh(now:)` rồi phát âm nếu vừa xong), nên tạm dừng một đếm ngược vừa đến giờ thì kết thúc nó thay vì dừng ở 0.
- **`timer.json` hỏng được ghi log** (`Logger.error`); thiếu file thì im lặng như lần chạy đầu.
- Số lớn của tab dùng `Text(timerInterval: .distantPast...endDate, countsDown: true)` (cận dưới ổn định) thay cho `Date.now...endDate` tính trong `body`.
- Màn hình khoá chỉ nhận **đếm ngược**; bấm giờ không được đưa lên màn hình khoá (live activity thì giữ nguyên).

## 3. Giới hạn đã chấp nhận (Ruling)

Ledger không có dòng `Ruling:` riêng cho Timer; vòng sửa H1/H3/H4 là "DONE_WITH_CONCERNS". Liên quan đến Timer:

- **Timer phát âm khi `mutate` chạm một đếm ngược đã quá giờ,** kể cả khi thay đổi đó là `cancel` hay `startCountdown` (đồng hồ đã vượt `endDate`). Ghi nhận trong báo cáo L1 như một hệ quả của việc làm mới trước.
- **Ruling L1 (một dòng chung cho cả vòng sửa màn hình khoá):** quy tắc hiện, một shim và một space SkyLight cho mỗi module, đối chiếu `isScreenLocked()` khi thức dậy, id space 64 bit, và "view Timer trên màn hình khoá chỉ hiện đếm ngược" (brief ghi "thời gian còn lại"). Chi phí nếu sai ghi trong [ghi chú Màn hình khoá](2026-10-14-lock-screen-implementation.html).

## 4. Khoảng trống đã biết

- Chuỗi đếm ngược thật sự hiển thị (`Text(timerInterval:)`) không đọc được khi chạy không giao diện; mới đo bằng `NSHostingView` rằng kích thước vừa khớp giống nhau (84 x 45 ở cỡ chữ 38) cho ba dạng cận dưới. Chuỗi thật chỉ "được kỳ vọng đúng".
- Thư mục tạm của test: `RegistryHarness` từng để lại 25 thư mục `MyNotchTests-<uuid>` mỗi lần chạy test Timer. Đã sửa ở `2bb5fc1` (`ScratchFolders` trong `MyNotchTestSupport`, xoá khi tiến trình test thoát); `verify.sh` vẫn quét phần còn lại của một lần chạy bị crash.
- Chưa có kết quả kiểm thử tay được ghi lại cho: mẫu 1, 5, 10, 25 phút, hết giờ và âm Glass, hẹn giờ qua lúc máy ngủ, thoát và mở lại.

## 5. Sửa lại spec (Spec corrections)

- **§4, bấm giờ**: dùng giờ thực `Date`, không phải mốc `ContinuousClock`.
- **§4, hết giờ**: thêm quy tắc không thông báo lại trạng thái đã xong khi mở lại app, và trạng thái xong vẫn thấy trong tab tới khi bấm "Đóng".
- **Order**: 880 (spec không ghi, brief cố định để Battery giữ 900).
- **Dòng trạng thái** "Thiết kế" đã lỗi thời: module đã triển khai và gắn vào app.

## 6. Cần kiểm thử tay

Xem [mục Hẹn giờ trong checklist gộp](../../manual-test-checklist-all.html#timer). Không có quyền hệ thống.

## 7. Từ `156f02d` đến hết 2026-10-15: loại hẹn giờ và mặt số phút (R3i)

Commit `30830cf`, vòng sửa `23f4ff1`. Test: Timer **125 test trong 7 suite** ở `23f4ff1` (36 trước, 102 sau commit đầu), ba lần chạy sạch, 0 cảnh báo. **Mục 1 ở trên ("Tab: các mẫu 1, 5, 10, 25 phút cùng ô tuỳ chỉnh…") đã lỗi thời:** các mẫu và ô tuỳ chỉnh 1 đến 180 phút đã được thay bằng loại và mặt số (dưới đây). **Chưa ai nhìn bằng mắt** (bộ chọn, ô chữ và lớp bắt cuộn là AppKit và không vẽ được offscreen).

### 7.1 Ba loại, một mặt số

- **Loại** (`TimerKind`): **Tập trung** (`task`, 25 phút mặc định, `brain.head.profile`, cam), **Nhắc việc** (`reminder`, 10 phút, `bell.fill`, lục lam), **Nghỉ** (`rest`, 5 phút, `cup.and.saucer.fill`, bạc hà; `break` là từ khoá Swift nên dùng `rest`), cộng chế độ **Bấm giờ**. Mỗi mặc định là một khoá cài đặt (`taskMinutes`, `reminderMinutes`, `breakMinutes`, kẹp 1 đến 60), sửa bằng ba stepper (dạng "Tập trung: 25 phút") trong hàng cài đặt của module. Số phút bạn xoay trên mặt số **không được lưu**: nó chỉ ảnh hưởng lần bắt đầu kế, rồi mặt số về mặc định của loại.
- **Mặt số phút** (`MinuteDial`, `MinuteDialView`): toán thuần: 6 độ mỗi phút từ 12 giờ theo chiều kim đồng hồ, dính vào phút nguyên gần nhất, mọi góc quấn theo vòng. Đỉnh mặt số là 0 hay 60 tuỳ con trỏ đến từ đâu (giá trị trước từ 30 trở lên cho 60), nên kéo theo chiều kim qua 12 giờ thì kết thúc ở vòng đầy 60 rồi quấn về 1, 2, …. Bàn phím ←/→ là ±1, ⇧ là ±5, kẹp ở 0 và 60 (không quấn). Con lăn và vuốt dùng cùng các bước kẹp qua `DialScroll` (trackpad 12 point cho mỗi phút sau vòng sửa; một nấc con lăn là 1 phút). Khi đang đếm ngược hay tạm dừng, cùng vòng đó hiện **thời gian còn lại** (số phút còn trên 60, vòng đầy nếu quá một giờ) với đồng hồ ở giữa, cập nhật mỗi 5 giây (`NotchTimeline(every: 5)`, nên đứng yên khi notch ngoài màn hình). VoiceOver: khi đặt thì đọc "25 phút" (có hành động tăng, giảm); khi chạy đọc "còn 12 phút" (làm tròn lên), "còn dưới 1 phút", "hết giờ".
- **Tab:** bộ chọn phân đoạn (Tập trung / Nhắc việc / Nghỉ / Bấm giờ), mặt số bên trái, tên loại, ô chữ nhắc việc và nút **"Bắt đầu"** bên phải (bị mờ ở 0 phút; module cũng từ chối 0). Tab nhận bàn phím (`acceptsKeyboard`) để phím mũi tên và ô chữ dùng được. Chiều cao tab tính từ các hằng (bộ chọn 22 pt, mặt số 112 pt, khoảng cách 10, đệm, thanh tab 30; khoảng 188 pt theo báo cáo, trước là 150).
- **Luồng:** `TimerKind.next` (Tập trung sang Nghỉ, Nghỉ sang Tập trung, Nhắc việc không có). Khi hẹn giờ vừa xong (`.finished`), `module.suggestion` đề nghị loại kế với độ dài mặc định của loại đó: bảng "xong" hiện nút lớn một cú bấm **"Nghỉ 5 phút"** sau Tập trung hay **"Bắt đầu tập trung"** sau Nghỉ (`module.startNext()`) cạnh "+1 phút" và "Đóng". Một Nhắc việc đã xong hiện nhãn của nó làm tiêu đề và không đề nghị gì.
- **Activity trên notch** (`TimerActivity`): bên trái và `minimal` là glyph của loại với màu của nó, bên phải là thời gian chạy (công bố một lần, hệ thống tự đếm), `summary` là "Tập trung" / "Nghỉ" / "Nhắc việc" / "Nhắc việc: <nhãn>" / "Bấm giờ". Phía bên của notch thu gọn chỉ 64 pt nên nhãn của một nhắc việc nằm trong **một dải một dòng dưới notch** (`bottom`, 22 pt). Khi xong: ưu tiên cao, 30 giây như cũ, glyph loại màu đỏ, "Hết giờ" cạnh notch, summary "Hết giờ: <nhãn>", "Hết giờ tập trung", "Hết giờ nghỉ". Widget màn hình khoá (vẫn chỉ có thời gian) dùng glyph và màu của loại.
- **Lưu:** `timer.json` giờ chứa `StoredTimer { model, session }` (session là loại và nhãn); một file của bản trước (chỉ `TimerModel`) vẫn nạp được như một hẹn giờ trơn, nên một đếm ngược đang chạy qua lần cập nhật vẫn sống. Một `session` không đọc được trong một file khác còn tốt chỉ làm mất loại (hẹn giờ vẫn chạy), một `label` không đọc được giữ loại; `model` hỏng vẫn bị từ chối. `TimerModel` không đổi.

### 7.2 Vòng sửa (review R3i `23f4ff1`)

- **I1, độ dài trên một giờ:** nút **"Dài hơn"** cạnh "Bắt đầu" (menu **1 giờ, 90 phút, 2 giờ, 3 giờ**, bắt đầu ngay qua `startCountdown(minutes:kind:label:)`). Lệch so với lời đề nghị của review: **không phải `Menu` của SwiftUI mà là một `NSMenu` pop-up** (`TimerLengthMenu`) **ghim notch trong lúc mở**, như menu ngôn ngữ của Dịch, vì menu là cửa sổ ngoài notch và notch đóng khi con trỏ rời hay bấm vào nó. Các mẫu nhanh cũ (`TimerLength.quick`: **5, 10, 25 phút**) quay lại thành chip nhỏ trong cùng hàng với "Bắt đầu", trong một `ViewThatFits` nên hàng giữ nguyên 112 pt chiều cao và chip rơi ra khi notch mở quá hẹp (cần khoảng 500 pt của notch; mặc định 600).
- **I2 và M3, định tuyến cuộn:** `DialScrollGate` (thuần) quyết định một lần cho mỗi cử chỉ như `TabSwipeRecognizer` (ngưỡng khoá 8 point): một cử chỉ bắt đầu lên xuống là của mặt số tới khi hết; một cử chỉ ngang hay chéo thì không bao giờ là của mặt số, và cho tới khi hướng rõ thì sự kiện được chuyển tiếp, nên bộ nhận diện của notch vẫn thấy `began` (vuốt ngang bắt đầu trên mặt số **đổi tab** như R1a). Quán tính không bao giờ là của mặt số; một nấc con lăn không có pha được xét riêng. Mọi thứ không phải của mặt số đi tới `super.scrollWheel(with:)`. **Hướng cuộn theo thiết lập "cuộn tự nhiên" của hệ thống** (dấu của cuộn như được chuyển giao).
- **M2:** logic bắt đầu nằm ở `module.startFromTab(_:minutes:)`: 0 phút thì không bắt đầu và giữ nhãn đã gõ; ngược lại một nhắc việc lấy nhãn rồi xoá ô. "Bắt đầu", chip, menu và Return trong ô đều đi qua đây.
- **Hoãn (không được đòi):** M4 (bấm vào giữa mặt số), M5 (ký tự điều khiển trong nhãn), M7 (test nối phím và view), M8.

### 7.3 Ruling và quyết định (kèm chi phí nếu sai)

- **Hẹn giờ nhanh cũ chính là loại Nhắc việc.** Một đếm ngược bắt đầu không có loại (`startCountdown(minutes:)`, một `timer.json` cũ) là Nhắc việc "trơn" nhãn trống nên vẫn chạy; dài hơn một giờ với được bằng "+1 phút" hay "Dài hơn". Chi phí: nếu muốn các mẫu nhanh làm chế độ thứ năm thì thêm (chúng hiện là chip khi đủ chỗ).
- **Không có thông báo hệ thống.** Nền tảng chưa có mặt tiền thông báo và không nơi nào trong repo dùng `UserNotifications` (xin quyền là một hộp thoại xin quyền mà quy tắc COMMON cấm gây ra); "thông báo" là activity xong ưu tiên cao mang nhãn cộng âm thanh có sẵn.
- **Không có cài đặt âm thanh** (âm là `"Glass"` cố định): giữ nguyên, phát một lần khi kết thúc một đếm ngược đang chạy, không bao giờ khi khởi động lại.
- **"Bắn ngay nếu đã quá giờ"** là hành vi có sẵn có test: một đếm ngược đã hết lúc app đóng bắt đầu ở `.finished` với activity ưu tiên cao (kể cả nhãn nhắc việc) và màn hình khoá bị xoá, **không có âm thanh** (một tiếng chuông lúc khởi động vài giờ sau có vẻ sai; một dòng trong `start` nếu muốn nhắc việc kêu khi mở).

## 8. Cần kiểm thử tay (phần mới)

Xem [mục Hẹn giờ trong checklist gộp](../../manual-test-checklist-all.html#timer): kéo vòng quanh mặt số (bám con trỏ, dính phút nguyên, qua 12 giờ từ phía cao thì ra 60); con lăn và vuốt trên mặt số đổi phút mà **không** đổi tab, vuốt ngang bắt đầu trên mặt số thì đổi tab; ←/→ và ⇧←/⇧→; ô nhắc việc; VoiceOver; notch thu gọn với từng loại (glyph và thời gian, dải nhãn, trạng thái xong màu đỏ); bộ chọn bốn đoạn ở notch mở thật; "Dài hơn" mở menu mà notch không đóng; chip nhanh ở bề rộng mặc định; đóng và mở lại app với hẹn giờ đang chạy hay đã hết lúc app đóng.

## 9. Đọc được trên kính sáng và tối (S2 `37d02c8`, test `a944673`, 2026-10-16)

Quy tắc chung và hai thứ S2 thêm vào NotchUI (`NotchTokens.fill(_:)` và `View.notchColorScheme()`): ghi chú Nền tảng, mục 16.5.

- **Thay:** 2 chỗ `.white` (rãnh của mặt số và núm) thành `NotchTokens.fill(_:)`. Không còn gì trắng cứng trong package.
- **Test:** `TimerGlassTests` (kính sáng, kính tối, Cổ điển trên fixture mặt số và bấm giờ). Commit `a944673` đo nền kính từ một ảnh trống cùng cỡ thay vì trung vị của ảnh (một view phủ gần hết khung làm trung vị sai). Timer **128 test** (S2). Cổ điển **giống từng điểm ảnh** (băm toàn bộ bitmap trước và sau, hai appearance, bốn lần chạy). Kính do WindowServer vẽ nên không test nào thấy nó: test dựng view trên nền sáng hay tối và đọc màu của chính view. Bộ vẽ ngoài màn hình có hai "tâm trạng" ổn định (mặt số và đồng hồ bấm giờ cũng vậy ở mã chưa sửa), nên băm được so theo tập.
- **Cần người kiểm:** hàng "Chữ trên kính" cuối nhóm [Hẹn giờ](../../manual-test-checklist-all.html#timer) của checklist (hình nền sáng, giao diện sáng của macOS, Liquid Glass).
