# Ghi chú triển khai: Media (Now Playing, phổ âm, lời bài hát)

- **Ngày:** 2026-10-14
- **Spec:** [Media (dự án con 2)](../specs/2026-10-13-media-design.html). Spec không bị sửa; chỗ đã lỗi thời nằm ở mục "Sửa lại spec".
- **Package:** `Packages/Modules/Media`, product `MediaModule`. Module id `media`, tab "Media" (order 200, cao 150 pt), live activity `nowPlaying`, bật mặc định, không có quyền bắt buộc.
- **Commit chính:** `0fe9b1c` nhúng adapter, `6851842` model và reducer, `595cccc` tiến trình adapter, `6446581` module, `21b983f` phổ âm, `70d95cb` sửa phổ âm, `21d81e6` lời bài hát, `cac1e37` chuỗi tra lời (M7), `e8a9b20`, `ba6695c`, `ff26aae` ba vòng sửa M7.
- **Test tự động:** 300 test theo báo cáo L1 (`verify.sh` qua ở `8a2b842`); riêng chuỗi lời đã review hai vòng, vòng cuối "Approved" (293/293 trước khi thêm 7 test màn hình khoá). Chưa chạy lại khi viết tài liệu này.
- **Kiểm thử tay:** [mục Media trong checklist gộp](../../manual-test-checklist-all.html#media)

## 1. Đã xây gì so với spec

- **Now Playing qua `mediaremote-adapter` v0.7.7** (BSD-3, `Vendor/`): framework nhúng vào `Contents/Frameworks`, script `.pl` ở `Contents/Resources`, `/usr/bin/perl` chạy `stream --micros --debounce=100`. App truyền đường dẫn vào module qua `App/MediaAdapterLocation.swift`.
- **Lõi thuần:** `NowPlayingReducer`, `PlaybackClock`, `ActivityPolicy`. `AdapterProcess` khởi động lại có backoff, dừng hẳn và báo "Không đọc được thông tin phát nhạc (macOS đã chặn adapter)" khi lỗi chết.
- **Giao diện:** live activity (ảnh bìa trái, bốn cột sóng phải), tab Media (ảnh bìa 96 pt, thanh tiến trình kéo được, ⏮ ⏯ ⏭, tên app). Ba phím tắt `mediaPlayPause`, `mediaNext`, `mediaPrevious`, không đặt mặc định. Cài đặt: `showActivity`, `pauseGraceSeconds` (0 đến 60), `hiddenApps`, `realSpectrum` (tắt), `lyrics` (tắt).
- **Phổ âm thật (tuỳ chọn):** `SpectrumAnalyzer` (vDSP), `SystemAudioTap` (Core Audio process tap), `SpectrumFeed`, `SilenceDetector`; chỉ chạy khi đang phát và có view phổ đang hiện. Thêm `NSAudioCaptureUsageDescription` (`7cccd10`).
- **Lời bài hát (tuỳ chọn):** `LRCParser`, `LyricsService`, `LyricsCache`, `VideoTitleParser`, `TrackKey`. Chi tiết ở mục 2.
- **Màn hình khoá:** Media đăng ký view `NowPlayingLockScreenView` (ảnh bìa, tên bài, nghệ sĩ, biểu tượng phát/dừng), xem [ghi chú Màn hình khoá](2026-10-14-lock-screen-implementation.html).

## 2. Chuỗi tra lời bài hát (sau M7 và ba vòng sửa)

Bài đủ điều kiện được tra tối đa bốn bước, mỗi bước cách bước trước ít nhất 300 ms tính từ lúc nhận câu trả lời:

1. `/api/get` kèm album, chỉ khi album không rỗng.
2. `/api/get` không album.
3. `/api/search?track_name=&artist_name=`.
4. `/api/search?q=<nghệ sĩ> <tên bài>`.

Quy tắc chọn kết quả:

- **Quy tắc stub:** kết quả đồng bộ chỉ dùng được khi có ít nhất 4 dòng (`minSyncedLines = 4`), hoặc là bài không lời (instrumental). Bản ghi 1 đến 3 dòng, hay chỉ có lời không đồng bộ, không kết thúc chuỗi: nó được giữ làm phương án dự phòng và chuỗi đi tiếp.
- Ở bước search: chọn bản đồng bộ dùng được có chênh lệch thời lượng nhỏ nhất, nhưng không quá 3 giây; bằng nhau thì chọn bản nhiều dòng hơn. Bản không có `duration` hoặc `instrumental` bị bỏ qua.
- Hết chuỗi: trả phương án dự phòng (ưu tiên nhiều dòng đồng bộ hơn, rồi lời thuần), không có thì `.notFound`. Kết quả cuối được cache.
- 429 hoặc 503 ở bất kỳ bước nào kết thúc chuỗi bằng `.unavailable` kèm thời gian chờ (`Retry-After`, kẹp 1 đến 3600 s, mặc định 60 s). Không cache. Module thử lại bài đang phát đúng một lần khi hết thời gian chờ. Phương án dự phòng không bao giờ được trả sau 429/503.
- Hàng đợi yêu cầu tuần tự. Huỷ hoặc tắt module giữa các bước thì rời hàng ngay, không đợi nốt 300 ms. Sửa vòng 2 chặn một lần huỷ trễ làm đứng hàng đợi (guard nằm trong `endStepWait()`).

**Quy tắc bỏ qua (không gọi lrclib, không cache, không chiếm lượt):**

- Bài dài hơn 15 phút.
- Tiêu đề có `playlist`, `1 hour`, `1 giờ`, `non stop` (kể cả `nonstop`, `non-stop`), `tuyển tập`.
- **Quy tắc "mix":** từ `mix` (cả `megamix`, `mixes`) chỉ bị bỏ qua khi bài dài hơn 360 giây. "Little Mix - Black Magic" 210 s, "(Original Mix)" 180 s hay "Mix It Up" vẫn được tra.
- Tiêu đề rỗng sau khi làm sạch ("-", "|"): trả `.notFound` ngay, không gửi yêu cầu.

**Làm sạch tiêu đề video (`VideoTitleParser`):** áp dụng khi nguồn là trình duyệt (Chrome, Safari, Arc, Edge, Firefox, Brave, Opera, Vivaldi, kể cả tiến trình helper và bản beta/canary theo tiền tố bundle id), hoặc khi album rỗng và tiêu đề có " - ", " – " hay " — ".

- **Quy tắc tách dấu gạch của trình duyệt:** chỉ tách "Nghệ sĩ - Bài hát" khi album rỗng (trình duyệt hay không). Có album nghĩa là player đã gắn thẻ thật (Spotify Web, YouTube Music, Bandcamp): giữ nguyên nghệ sĩ như player báo, chỉ bỏ nhiễu trong ngoặc và đuôi. "Bohemian Rhapsody - Remastered 2011" của "Queen" vẫn tra đúng như vậy.
- Nhiễu được bỏ: nhóm ngoặc hoặc đoạn sau `|` chỉ gồm từ nhiễu (official, music, video, mv, lyrics, audio, visualizer, live, 4k, hd, vietsub, `\d{3,4}p`...), hoặc bắt đầu bằng "Official" hay "Prod.". Ngoặc có từ thật ("Remastered 2011", "Can't Live Without You") được giữ. Tách `ft.`/`feat.`; bỏ " - Topic", "VEVO", "Official", "Music" khỏi tên kênh khi dùng kênh làm nghệ sĩ.
- Chuẩn hoá Unicode NFC (tiếng Việt dạng tổ hợp), gộp khoảng trắng; giữ dấu tiếng Việt.

**Cache (`storage.cachesDirectory/lyrics/<sha256>.json`):**

- Khoá = SHA-256 của (nghệ sĩ, tên bài, album, thời lượng làm tròn giây, phiên bản), phiên bản hiện là `v3`. Khoá dùng trường gốc player báo, không dùng kết quả làm sạch.
- Kết quả `notFound` hết hạn sau 7 ngày (tính theo ngày sửa file; ngày sửa ở tương lai coi như hết hạn). Kết quả tìm thấy không hết hạn. `.unavailable` không bao giờ được cache.
- File cache cũ không có phiên bản hoặc `v2` bị bỏ qua, không bị xoá.
- Phiên HTTP riêng, ephemeral, không cache, không cookie. User-Agent `MyNotch/<phiên bản> (personal)`.

**Giao diện:** kết quả chỉ có lời không đồng bộ thì tab hiện một dòng mờ "Chỉ có lời không đồng bộ" dưới thanh tiến trình, chiều cao player không đổi. Dòng giải thích trong Settings: "Khi bật, tên bài, nghệ sĩ, album và thời lượng của mỗi bài mới (kể cả video phát trong trình duyệt) được gửi tới lrclib.net để lấy lời."

## 3. Sai khác so với spec và lý do

- Payload rỗng hoặc không hoạt động làm ẩn activity sau 300 ms (chống nháy khi đổi bài), không ẩn ngay. App nằm trong `hiddenApps` thì ẩn ngay.
- Danh tính bài (`TrackIdentity`: bundle, tiêu đề, nghệ sĩ, album và các id) dùng để giữ ảnh bìa và phát lại activity đúng một lần mỗi bài.
- Chuỗi tra lời, cache `v3`, hết hạn 7 ngày: spec chỉ mô tả một lần gọi `/api/get`. Lý do: bằng chứng ngày 2026-10-14, lrclib trả 404 khi album lệch ("- Single", "Deluxe"), và mọi mục trong cache là `notFound`.
- `AdapterProcess` tuần tự hoá lệnh `send`/`seek` (seek cuối thắng). Thanh tiến trình chỉ seek một lần khi thả chuột hoặc click, vì mỗi lệnh là một tiến trình perl.
- Sửa M5 (`70d95cb`): cờ "bị từ chối quyền" được xoá khi tap khởi động lại, và `SampleRing.write` không cấp phát bộ nhớ trong Debug.

## 4. Giới hạn đã chấp nhận (Ruling)

- **Stub từ `/api/get`.** Quyết định: bản đồng bộ chỉ dùng được khi có từ 4 dòng; stub hoặc chỉ-lời-thuần từ `/api/get` thành phương án dự phòng và chuỗi tiếp tục tìm; search chọn bản đồng bộ dùng được có chênh lệch thời lượng nhỏ nhất (hoà thì nhiều dòng hơn); 429/503 giữa chuỗi vẫn là `.unavailable`. **Chi phí nếu sai:** thêm tối đa 4 yêu cầu lrclib cho mỗi bài chưa cache, và một stub 1 dòng vẫn có thể hiện nếu lrclib không có gì tốt hơn.
- **"mix" chỉ bỏ qua khi bài dài hơn 360 giây** (khuyến nghị của reviewer; brief gốc "chứa mix" bỏ qua cả bài thật như "Little Mix", "(Original Mix)"). Các từ bỏ qua khác và trần 15 phút giữ nguyên. **Chi phí nếu sai:** một video remix ngắn trong 6 phút có thể gọi lrclib (vô hại, tối đa 4 yêu cầu).
- **Tách dấu gạch chỉ khi album rỗng** (trình duyệt hay không), tin metadata thật của Spotify Web, YouTube Music, Bandcamp; nâng cache lên `v3`; thêm NFC. **Chi phí nếu sai:** một video YouTube báo album không rỗng mà tiêu đề bẩn sẽ không được làm sạch.
- **Bài từ trình duyệt có album giữ nguyên nghệ sĩ player báo** ("AdeleVEVO" vẫn là "AdeleVEVO"). Chấp nhận vì album thật nghĩa là thẻ thật.
- **Bỏ qua:** Minor 9 (kiểm tra tên bài chứa trong kết quả search) vì rủi ro âm tính giả với tiêu đề tiếng Việt và phiên âm; Minor 5 phần tách camel-case của VEVO và tách bài hợp tác ("A x B", "A & B"). Minor 10 (sửa spec) chuyển vào mục 6 của tài liệu này.
- **Ruling (L1 bắt đầu trước khi sửa review M7 vào main):** chỉnh sửa Media của màn hình khoá giới hạn ở việc đăng ký view (`NowPlayingLockScreenView`, `refreshLockScreen`), để cherry-pick các sửa lời bài hát sau đó không xung đột. **Chi phí nếu sai:** một xung đột merge nhỏ ở `MediaModule.swift`. Các commit lời bài hát (`e8a9b20`, `ba6695c`, `ff26aae`) đã được cherry-pick lên trên L1.
- **Quan sát:** `1421c16` (commit M7 đầu) được cherry-pick vào main thành `cac1e37` trước khi review; chấp nhận vì cục bộ, đảo ngược được và cùng nội dung.

## 5. Khoảng trống đã biết

- Stub 1 đến 3 dòng vẫn hiện (một dòng lạc) khi đó là thứ tốt nhất lrclib có, và được cache vĩnh viễn như mọi kết quả tìm thấy.
- 503 ở `/api/get` kết thúc chuỗi (chờ 60 s rồi thử lại một lần), không rơi sang bước search.
- Tiêu đề không có dấu gạch trên kênh không phải nghệ sĩ ("BTS (방탄소년단) 'Dynamite' Official MV" trên "HYBE LABELS") ra nghệ sĩ là tên kênh; lrclib không biết. Đây là dự phòng theo thiết kế.
- Chưa quan sát: `Upgrade | Beyoncé` mất "Upgrade"; `(1080p` không đóng vẫn còn sau khi bỏ nhiễu khác; "Sad :(" mất dấu "("; nghệ sĩ rỗng chưa được chặn như tiêu đề rỗng.
- Các bước 2 đến 4 của chuỗi mới chỉ kiểm bằng client giả, chưa chạm dữ liệu thật ngoài hai lần chạy một lần (Rick Astley 213 s: stub 1 dòng từ `/api/get`, search tìm được 59 dòng; Queen 355 s: 56 dòng ở bước 1).
- Giao diện lời chưa được agent nào nhìn thấy bằng mắt, cần người kiểm: dòng lời đồng bộ và dòng mờ "Chỉ có lời không đồng bộ".
- Video YouTube dài khoảng 33 phút (mix) sẽ không bao giờ có lời, đúng thiết kế. Thử bằng một bài đơn.

## 6. Sửa lại spec (Spec corrections)

- **§3, hàng `LyricsService`**: chỉ mô tả `GET https://lrclib.net/api/get`. Thực tế là chuỗi bốn bước, quy tắc stub, quy tắc bỏ qua, cache `v3`, hết hạn 7 ngày và dòng mờ "không đồng bộ" như mục 2 ở trên.
- **§3.3, hàng `lyrics`**: câu giải thích đã đổi thành "Khi bật, tên bài, nghệ sĩ, album và thời lượng của mỗi bài mới (kể cả video phát trong trình duyệt) được gửi tới lrclib.net để lấy lời."
- **§3, hàng `ActivityPolicy`**: payload rỗng ẩn sau 300 ms, không "ngay".
- **Dòng trạng thái**: spec ghi "Thiết kế. Cần người dùng đồng ý tải mã nguồn `ungive/mediaremote-adapter`". Adapter v0.7.7 đã nằm trong `Vendor/` và đã nhúng vào app.
- **§3.4**: `NSAudioCaptureUsageDescription` có sẵn trong `project.yml`: "MyNotch hiển thị phổ âm thanh của nhạc đang phát."; entitlement `com.apple.security.device.audio-input` có từ dự án con 0.5.
- **§3 và §1**: thêm hàng "view màn hình khoá" (Media là một contributor của `LockScreenContentCenter`).

## 7. Cần kiểm thử tay

Xem [mục Media trong checklist gộp](../../manual-test-checklist-all.html#media). Các mục đụng quyền hoặc API riêng: Now Playing qua adapter (MediaRemote riêng, chạy qua perl), phổ âm thật (quyền ghi âm thanh hệ thống, reset TCC trước khi thử), lời bài hát (gửi tên bài ra mạng).
