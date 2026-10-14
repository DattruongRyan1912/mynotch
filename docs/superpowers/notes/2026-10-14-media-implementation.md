# Ghi chú triển khai: Media (Now Playing, phổ âm, lời bài hát)

- **Ngày:** 2026-10-14
- **Spec:** [Media (dự án con 2)](../specs/2026-10-13-media-design.html). Spec không bị sửa; chỗ đã lỗi thời nằm ở mục "Sửa lại spec".
- **Package:** `Packages/Modules/Media`, product `MediaModule`, cộng product `YouTubeBridgeKit` (thư viện chỉ dùng Foundation, dùng chung với helper `Tools/mynotch-youtube-host`) và extension Chrome ở `Extensions/Chrome/MyNotchYouTube/`. Module id `media`, tab "Media" (order 200, cao 150 pt), live activity `nowPlaying`, bật mặc định, không có quyền bắt buộc.
- **Commit chính:** `0fe9b1c` nhúng adapter, `6851842` model và reducer, `595cccc` tiến trình adapter, `6446581` module, `21b983f` phổ âm, `70d95cb` sửa phổ âm, `21d81e6` lời bài hát, `cac1e37` chuỗi tra lời (M7), `e8a9b20`, `ba6695c`, `ff26aae` ba vòng sửa M7.
- **Commit sau phiên thử nghiệm:** Apple Music (M8) `f341b31`, sửa `ecc4697`; extension Chrome (M9b) `71321ad`, sửa `f650805`, `898cc12`; cầu nối phía Swift (M9a) `31c7395`, sửa `1264317` (test SIGPIPE) và `55fc6ad` (dọn adapter mồ côi).
- **Test tự động:** package Media 622 test (`swift test`, hai target `MediaModuleTests` và `YouTubeBridgeKitTests`; số của báo cáo vòng sửa M9a ở `55fc6ad`, `verify.sh` qua ở lần đó) và 95 test node cho extension (`node --test Extensions/Chrome/MyNotchYouTube/tests/`). Chuỗi lrclib (M7) đã review hai vòng; M8 và M9a, M9b mỗi phần review một vòng cộng re-review, đều kết thúc "Approved" hoặc "ADDRESSED", không còn Critical hay Important. Chưa chạy lại khi viết tài liệu này. **Chưa có test nào chạm Keychain thật, Apple thật, Chrome thật hay YouTube thật**; phần đó nằm ở checklist.
- **Kiểm thử tay:** [mục Media trong checklist gộp](../../manual-test-checklist-all.html#media)

## 1. Đã xây gì so với spec

- **Now Playing qua `mediaremote-adapter` v0.7.7** (BSD-3, `Vendor/`): framework nhúng vào `Contents/Frameworks`, script `.pl` ở `Contents/Resources`, `/usr/bin/perl` chạy `stream --micros --debounce=100`. App truyền đường dẫn vào module qua `App/MediaAdapterLocation.swift`.
- **Lõi thuần:** `NowPlayingReducer`, `PlaybackClock`, `ActivityPolicy`. `AdapterProcess` khởi động lại có backoff, dừng hẳn và báo "Không đọc được thông tin phát nhạc (macOS đã chặn adapter)" khi lỗi chết.
- **Giao diện:** live activity (ảnh bìa trái, bốn cột sóng phải), tab Media (ảnh bìa 96 pt, thanh tiến trình kéo được, ⏮ ⏯ ⏭, tên app). Ba phím tắt `mediaPlayPause`, `mediaNext`, `mediaPrevious`, không đặt mặc định. Cài đặt: `showActivity`, `pauseGraceSeconds` (0 đến 60), `hiddenApps`, `realSpectrum` (tắt), `lyrics` (tắt), `youtubeCaptions` (tắt, độc lập với `lyrics`).
- **Phổ âm thật (tuỳ chọn):** `SpectrumAnalyzer` (vDSP), `SystemAudioTap` (Core Audio process tap), `SpectrumFeed`, `SilenceDetector`; chỉ chạy khi đang phát và có view phổ đang hiện. Thêm `NSAudioCaptureUsageDescription` (`7cccd10`).
- **Lời bài hát (tuỳ chọn):** `LRCParser`, `LyricsService`, `LyricsCache`, `VideoTitleParser`, `TrackKey`. Ba nguồn và thứ tự ở mục 2, chuỗi lrclib ở mục 3.
- **Lời từ Apple Music (M8, tuỳ chọn):** `AppleMusicLyricsClient`, `TTMLLyricsParser`, `AppleMusicAccount`, `TokenStore` (Keychain), cửa sổ đăng nhập `AppleMusicLoginWindow`, hàng Settings `AppleMusicRows`. Mục 4.
- **Phụ đề YouTube từ extension Chrome (M9, tuỳ chọn):** extension `Extensions/Chrome/MyNotchYouTube/`, helper `mynotch-youtube-host` (`Tools/`, nhúng vào `Contents/MacOS`), thư viện `YouTubeBridgeKit`, và trong module: `YouTubeBridgeServer`, `YouTubeCaptionStore`, `YouTubeCaptionMatcher`, `YouTubeCaptionLyrics`, `YouTubeBridgeInstaller`, hàng Settings `YouTubeBridgeRows`. Mục 5.
- **Dọn adapter mồ côi:** `OrphanedAdapterReaper` và `SystemProcessTable`, chạy ở mỗi lần `AdapterProcess.start`. Mục 6.
- **Màn hình khoá:** Media đăng ký view `NowPlayingLockScreenView` (ảnh bìa, tên bài, nghệ sĩ, biểu tượng phát/dừng), xem [ghi chú Màn hình khoá](2026-10-14-lock-screen-implementation.html).

## 2. Nguồn lời bài hát và thứ tự (từ M8, M9)

Lời có ba nguồn. Với mỗi bài, nguồn đầu tiên có câu trả lời thì dừng:

| # | Nguồn | Dùng cho | Điều kiện | Gì rời khỏi máy |
|---|---|---|---|---|
| 1 | Phụ đề YouTube từ extension Chrome | bài từ trình duyệt mà extension báo đúng video đang phát | `youtubeCaptions` bật, người dùng đã bật CC trên video, khớp theo mục 5 | không gì cả: dữ liệu chỉ đi trong máy |
| 2 | Apple Music | bài phát trong app Music, có catalog id số | `lyrics` bật, tài khoản "Đã kết nối" | id bài (nằm trong URL), developer token và user token của chính người dùng, gửi tới `amp-api.music.apple.com` |
| 3 | lrclib.net | mọi bài còn lại, và bài của Music mà Apple không có | `lyrics` bật | tên bài, nghệ sĩ, album, thời lượng |

- **Phụ đề thắng.** Khi khớp, bài đó không gọi Apple lẫn lrclib; lượt tra đang chạy bị huỷ. Khi phụ đề mất (`clear`, đổi video, tắt cài đặt) lượt tra chạy lại, lấy từ cache nếu đã có. Phụ đề độc lập với `lyrics`: bật `youtubeCaptions` và tắt `lyrics` vẫn hiện phụ đề.
- **Apple chỉ cho app Music.** Nguồn phải đúng `com.apple.Music` và `uniqueIdentifier` của adapter toàn chữ số (đã đối chiếu bằng tra cứu iTunes công khai: đó là catalog song id của bài đang phát; `contentItemIdentifier` dạng `1219::1227` không phải). Bài từ Spotify hoặc YouTube không bao giờ gửi tên bài tới Apple. Apple trả lời đồng bộ hoặc lời thuần thì đó là câu trả lời; mọi trường hợp khác chuỗi lrclib chạy nguyên như cũ. Bộ lọc "bài dài hoặc mix" vẫn chạy trước Apple.
- **Cache.** Khoá bump lên `v4`; bài đã hỏi Apple có khoá `v4+am` (chỉ khi tài khoản "Đã kết nối"), nên kết nối tài khoản làm các câu "không có" cũ của bài Music hết liên quan ngay. Lời tìm thấy ở Apple nằm trong cùng thư mục cache như lrclib, kể cả sau khi ngắt kết nối (chỉ dùng lại sau khi kết nối lại). Phụ đề YouTube không bao giờ vào cache hay đĩa.
- **Apple lỗi.** Apple không trả lời được (429, 408, 5xx, mạng) mà lrclib cũng không có gì thì kết quả là `.unavailable("Apple Music: …")`, không cache; nếu không, bài bị coi là "không có" cả tuần dù Apple chưa từng trả lời. Lrclib có lời thì đó là câu trả lời và được cache.
- **Hàng đợi chung.** Mọi yêu cầu của một lượt tra (hai endpoint Apple, làm mới token, bốn bước lrclib) đi tuần tự, cách nhau ít nhất 300 ms, huỷ được giữa hai bước.

**Quyền riêng tư, nói thẳng:**

- Tới **Apple** (chỉ khi người dùng bấm kết nối): id bài của app Music, hai token, storefront; việc làm mới developer token chỉ tải trang `music.apple.com` và script của nó, không kèm thông tin đăng nhập. Mật khẩu và mã 2FA chỉ gõ vào trang của Apple trong cửa sổ đăng nhập; app không thấy.
- Tới **YouTube**: không có gì. Extension chỉ đọc bản sao phản hồi phụ đề mà chính trình phát của trang đã tải; MyNotch không liên lạc với YouTube.
- Extension chuyển cho MyNotch (trong máy, qua Native Messaging và socket Unix): mã video, tiêu đề, vị trí phát, trạng thái phát, tốc độ và nội dung phụ đề. Không bao giờ có URL (kể cả URL phụ đề mang token), cookie hay thông tin tài khoản.
- Lrclib như cũ: tên bài, nghệ sĩ, album, thời lượng. Mặc định (cả ba tính năng tắt) app không gửi gì ra ngoài.

## 3. Chuỗi tra lời lrclib (sau M7 và ba vòng sửa)

Bài đủ điều kiện được tra tối đa bốn bước, mỗi bước cách bước trước ít nhất 300 ms tính từ lúc nhận câu trả lời:

1. `/api/get` kèm album, chỉ khi album không rỗng.
2. `/api/get` không album.
3. `/api/search?track_name=&artist_name=`.
4. `/api/search?q=<nghệ sĩ> <tên bài>`.

Quy tắc chọn kết quả:

- **Quy tắc stub:** kết quả đồng bộ chỉ dùng được khi có ít nhất 4 dòng (`minSyncedLines = 4`), hoặc là bài không lời (instrumental). Bản ghi 1 đến 3 dòng, hay chỉ có lời không đồng bộ, không kết thúc chuỗi: nó được giữ làm phương án dự phòng và chuỗi đi tiếp.
- Ở bước search: chọn bản đồng bộ dùng được có chênh lệch thời lượng nhỏ nhất, nhưng không quá 3 giây; bằng nhau thì chọn bản nhiều dòng hơn. Bản không có `duration` hoặc `instrumental` bị bỏ qua.
- Hết chuỗi: trả phương án dự phòng, không có thì `.notFound`. Dự phòng xếp hạng theo số dòng đồng bộ trước rồi số từ của lời thuần, hoà thì giữ bản đến trước (nên một stub đồng bộ thắng một bản lời thuần); một stub đồng bộ tìm thấy ở bước search cũng là ứng viên dự phòng, như stub của `/api/get`. Kết quả cuối được cache.
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

- Khoá = SHA-256 của (nghệ sĩ, tên bài, album, thời lượng làm tròn giây, phiên bản), phiên bản hiện là `v4` (`v4+am` cho bài đã hỏi Apple, mục 2; M8 nâng từ `v3`). Khoá dùng trường gốc player báo, không dùng kết quả làm sạch.
- Kết quả `notFound` hết hạn sau 7 ngày (tính theo ngày sửa file; ngày sửa ở tương lai coi như hết hạn). Kết quả tìm thấy không hết hạn. `.unavailable` không bao giờ được cache.
- File cache của phiên bản cũ (không phiên bản, `v2`, `v3`) không bao giờ được tra vì phiên bản nằm trong khoá, và không bị xoá.
- Phiên HTTP riêng, ephemeral, không cache, không cookie. User-Agent `MyNotch/<phiên bản> (personal)`.

**Giao diện:** kết quả chỉ có lời không đồng bộ thì tab hiện một dòng mờ "Chỉ có lời không đồng bộ" dưới thanh tiến trình, chiều cao player không đổi. Dòng giải thích trong Settings: "Khi bật, tên bài, nghệ sĩ, album và thời lượng của mỗi bài mới (kể cả video phát trong trình duyệt) được gửi tới lrclib.net để lấy lời."

## 4. Đăng nhập và lời từ Apple Music (M8)

Lý do: lrclib không có lời cho nhiều bài người dùng nghe trong app Music (remix TikTok tiếng Việt như "Hoa Tàn Tình Tan (Remix)" và "Mật Ngọt (X2X Remix)": đã kiểm lrclib không có bản ghi nào trong ±3 giây, chỉ có bản gốc và remix khác), trong khi app Music hiện lời của Apple. Người dùng chọn lấy lời của Apple bằng **tài khoản của chính mình** (không dùng proxy bên thứ ba). Đây là API **không chính thức**, viết từ mô tả cộng đồng, có thể ngừng hoạt động khi Apple đổi.

- **Settings → Media** (hàng chỉ hiện khi `lyrics` bật): hàng tiêu đề "Lời từ Apple Music" (không phải `Section` lồng), câu giải thích, "Trạng thái" (`Chưa kết nối`, `Đã kết nối (<storefront>)`, `Cần đăng nhập lại` màu cam), nút "Kết nối Apple Music…" và "Ngắt kết nối" (chỉ khi trạng thái khác "Chưa kết nối"), và một dòng đỏ khi Keychain từ chối ghi hoặc không lấy được storefront.
- **Cửa sổ đăng nhập** "Đăng nhập Apple Music" (480×680): `WKWebView` với kho dữ liệu web riêng `WKWebsiteDataStore(forIdentifier:)` (UUID cố định), tải `https://music.apple.com/`, giả danh Safari trong user agent (đoán, chưa kiểm). Người dùng tự đăng nhập. Mỗi giây app đọc `MusicKit.getInstance()` (`developerToken`, `musicUserToken`, `storefrontId`, JS tĩnh bọc try/catch, trả JSON), dự phòng cookie `media-user-token` của `music.apple.com` (kiểm miền: `evil-music.apple.com` và `.apple.com` bị từ chối). Đủ hai token thì lấy storefront nếu thiếu (`GET /v1/me/storefront`), lưu cả ba hoặc không lưu gì, rồi đóng cửa sổ.
- **Kho dữ liệu web chỉ sống bằng cửa sổ.** Mỗi khi cửa sổ mất (đăng nhập xong, Keychain từ chối, không lấy được storefront, người dùng tự đóng, module dừng), module xoá sạch kho; mỗi lần đăng nhập cũng bắt đầu bằng một lần xoá. Hệ quả: sau khi kết nối, Keychain là bản sao duy nhất của user token, và mỗi lần kết nối bắt đầu từ trang chưa đăng nhập. "Ngắt kết nối" xoá ba mục Keychain và dữ liệu web.
- **Token ở Keychain:** generic password, service `io.lucasvu.mynotch.applemusic`, accounts `developer-token`, `media-user-token`, `storefront`; `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, không đồng bộ iCloud; dùng keychain login dạng file (không dùng data protection keychain vì nó cần entitlement và provisioning profile mà app không có). Token không vào `UserDefaults`, log, thông báo lỗi hay output test; `AppleMusicCredentials` không in token kể cả qua `dump`. Test chỉ dùng kho giả, không bao giờ chạm Keychain thật.
- **Yêu cầu tới Apple:** `GET https://amp-api.music.apple.com/v1/catalog/{storefront}/songs/{id}/syllable-lyrics`; 404 hoặc không có TTML thì `…/lyrics`. Header `Authorization: Bearer <developer token>`, `Media-User-Token`, `Origin`, `Referer`. Storefront phải là hai chữ cái, id chỉ chữ số (cả hai đi vào đường dẫn).
- **401 hoặc 403:** làm mới developer token **một lần** mỗi lượt tra, không cần người dùng (GET `https://music.apple.com/`, tìm script `/assets/index*.js`, lấy JWT đầu tiên; luôn tải script từ `music.apple.com`, không kèm thông tin đăng nhập), rồi thử lại một lần. Vẫn 401 hoặc 403: trạng thái "Cần đăng nhập lại", app ngừng gọi Apple tới khi người dùng kết nối lại, lời lấy từ lrclib. Trạng thái này **chỉ nằm trong bộ nhớ**: mở lại app thì Apple được hỏi thêm một lần.
- **Mã trạng thái khác:** 404, rỗng, TTML hỏng, và mọi 4xx trừ 408 và 429 là "không có" (được nhớ, không hỏi lại mỗi lần phát lại); 408, 429, 5xx, lỗi mạng là `.unavailable` (không cache, lrclib vẫn chạy). Apple không có cooldown riêng cho `Retry-After`.
- **TTML (`TTMLLyricsParser`, thuần):** `itunes:timing="Line"` một dòng mỗi `<p>`; `"Word"` (từng chữ) cũng một dòng mỗi `<p>`, ghép các span đúng như hiển thị, bỏ span nền (`x-bg`), dịch và phiên âm (nên **không có tô sáng từng chữ**); `"None"` là lời thuần (dòng mờ "Chỉ có lời không đồng bộ"). Đọc được bốn dạng thời gian (`12.345`, `1:02.345`, `01:02:03.456`, `12.3s`); bỏ `<head>`; hỏng thì coi như không có.
- **Khi kết nối lúc đang phát** bài của Music, bài đó được tra lại ngay; mất đăng nhập thì lời đang hiện được giữ.

## 5. Cầu nối phụ đề YouTube qua extension Chrome (M9)

**Vì sao không tự tải phụ đề từ YouTube.** Spike ngày 2026-10-14 chỉ đo được 2 trong khoảng 60 yêu cầu dự kiến: yêu cầu thứ hai tới YouTube đã bị chặn bằng bot check ("Sign in to confirm you're not a bot"). Theo tài liệu cộng đồng (chưa tự kiểm), phụ đề của client WEB cần PO token; tự tạo PO token là vượt cơ chế chống lạm dụng của YouTube nên bị từ chối, và truy cập tự động ngoài trình phát bị điều khoản cấm (theo trí nhớ của người làm spike, chưa đọc lại điều khoản). Tỷ lệ tìm đúng video và tải được phụ đề chưa từng đo. Người dùng chọn đường extension: chính trình phát của trang đã tải phụ đề bằng token hợp lệ của nó, nên MyNotch không gửi gì cho YouTube.

**Đường đi của dữ liệu:** trang YouTube → extension (`page.js` ở MAIN world, `content.js`, `background.js`) → Native Messaging → `mynotch-youtube-host` → socket Unix → `MediaModule`. Giao thức (ba tin `captions`, `playback`, `clear`, trường `v: 1`) nằm trong `mntasks/media/M9-protocol.md`.

- **Extension** "MyNotch YouTube Bridge" (Manifest V3, `minimum_chrome_version` 111): quyền `nativeMessaging` và `host_permissions` `https://www.youtube.com/*`. Id **`cccjddkmjjmnnccbgokidgbkpblogbnp`** cố định nhờ khoá công khai trong `manifest.json` (khoá riêng đã xoá, không nằm trong repo; test tính lại id từ `key` và so với file `EXTENSION_ID`). `page.js` bọc `fetch` và `XMLHttpRequest` bằng Proxy, chỉ quan sát phản hồi của đường dẫn `/api/timedtext` (json3, srv3), luôn trả nguyên bản cho trang, nuốt mọi lỗi, không bao giờ chuyển URL. `content.js` theo dõi video, mã video và nút CC, gửi `playback` (khi phát, dừng, tua, đổi tốc độ, đổi video, và mỗi 5 giây khi đang phát), `captions`, `clear` (CC tắt, đổi video, rời trang xem, `pagehide`). `background.js` nối lười tới host, nối lại với backoff 2 đến 60 giây, giữ `captions` mới nhất của mỗi video để gửi lại sau khi nối lại. Khi phát có quảng cáo, `playing` là `false`.
- **Chỉ phụ đề của video đang xem.** Một `captions` có `videoId` khác với id trong URL hiện tại không được chuyển đi mà giữ tối đa 10 giây (một ô); nếu trang chuyển đúng sang video đó trong 10 giây thì gửi (thứ tự `clear` cũ, `playback` mới, `captions` mới), không thì bỏ. Cách này chịu được cả hai thứ tự "YouTube tải phụ đề trước hay đổi URL trước", điều chưa ai quan sát được.
- **Helper `mynotch-youtube-host`** (host Native Messaging `io.lucasvu.mynotch.youtube`; target `tool` trong `project.yml`, nhúng ở `Contents/MacOS`, ký như `mynotch-hook`): đọc khung Native Messaging từ stdin, kiểm hợp lệ, chuyển nguyên byte qua socket cho app. Không bao giờ ghi stdout hay stderr, thoát 0 khi stdin kết thúc, nối lại mỗi 2 giây khi app vắng (tin gửi trong lúc đó bị bỏ). **Phát lại:** host giữ trong bộ nhớ `captions` mới nhất của tối đa 3 video và `playback` mới nhất; sau mỗi lần nối lại, gửi `captions` trước rồi `playback` (chỉ khi `playback` chưa quá 10 giây). Nên chỉ khởi động lại MyNotch khi Chrome vẫn phát thì phụ đề quay lại sau khoảng 2 đến 4 giây, không cần chạm CC.
- **Socket:** `<Application Support>/io.lucasvu.mynotch/Modules/media/youtube.sock` (dự phòng `/tmp/mynotch-<uid>/youtube.sock` khi đường dẫn dài hơn 103 byte); mode 0600, thư mục 0700, mở **chỉ khi `youtubeCaptions` bật**, gỡ khi tắt hoặc dừng module. App kiểm uid của đầu bên kia bằng `getpeereid`, host kiểm chủ socket sau khi nối (trước khi gửi gì), tối đa 8 kết nối. Khung app là 4 byte big-endian cộng JSON, tối đa 4 MiB; tối đa 5000 sự kiện mỗi `captions`, mỗi sự kiện tối đa 500 ký tự.
- **Cài:** nút "Cài cầu nối cho Chrome" (và nó bật luôn `youtubeCaptions`) chép host ra `<storage>/bin/mynotch-youtube-host`, chép thư mục extension (không có `tests/`) ra `~/Library/Application Support/io.lucasvu.mynotch/ChromeExtension`, ghi manifest host vào `~/Library/Application Support/Google/Chrome/NativeMessagingHosts/io.lucasvu.mynotch.youtube.json` (`allowed_origins` chỉ có đúng id trên, ghi nguyên tử), rồi mở thư mục extension trong Finder. Người dùng tự bật Developer mode và Load unpacked trong `chrome://extensions`. **Chỉ Google Chrome**: không Chromium, Brave, Arc, Edge hay Safari. "Gỡ cầu nối" xoá manifest, host đã chép và thư mục extension đã chép; không đụng file nào khác trong thư mục của Chrome. Trạng thái: "Chưa cài", "Đã cài — chờ extension", "Extension đang kết nối" (có tin hợp lệ trong 30 giây gần nhất).
- **Khớp bài.** Phụ đề chỉ dùng cho bài đang phát khi: nguồn là trình duyệt (`NowPlayingState.isFromBrowser`), tin `playback` mới nhất không quá 10 giây tuổi và `playing`, tiêu đề của nó bằng tiêu đề now-playing sau chuẩn hoá (NFC, không phân biệt hoa thường, gộp khoảng trắng). **Đã khớp thì giữ** kể cả khi tạm dừng hay trang im lặng, tới khi `clear`, đổi video, đổi bài, tắt cài đặt hoặc dừng module.
- **Thành dòng lời:** mỗi sự kiện một dòng tại thời điểm `t`; sự kiện chỉ là dấu hiệu ("[Music]", "[Âm nhạc]", "♪") thành dòng trống; thêm dòng trống sau sự kiện nếu khoảng lặng sau nó lớn hơn 5 giây hoặc nó là sự kiện cuối. Phụ đề tự động (ASR) tự cuộn, nên các dòng có thể lặp chữ: không khử trùng lặp. `lang` chỉ để tham khảo (extension gửi `tlang` khi người dùng chọn dịch tự động trong trình phát). Phụ đề chỉ nằm trong RAM (tối đa 3 video), không ghi đĩa.

## 6. Dọn adapter mồ côi (sau M9a)

Lỗi thấy khi thử: tắt MyNotch bằng SIGTERM, SIGKILL hoặc để nó crash thì `AdapterProcess` không kịp chạy `stop()`/`deinit`, nên `/usr/bin/perl …/mediaremote-adapter.pl <framework> stream …` sống tiếp với cha là launchd (pid 1), giữ một kết nối MediaRemote mà không ai đọc.

Sửa (`55fc6ad`): **mỗi lần `AdapterProcess.start`, trước khi chạy stream mới**, `OrphanedAdapterReaper` hỏi `SystemProcessTable` (`proc_listallpids`, `proc_pidinfo`, `sysctl KERN_PROCARGS2`) các tiến trình của người dùng hiện tại có cha là pid 1 và gửi **SIGTERM** cho tiến trình có dòng lệnh đúng `<chương trình> <script của bundle này> <framework của bundle này> stream …` (so từng phần tử từ `argv[1]`, không so tiền tố chuỗi). Không bao giờ chạm: app khác, bundle khác (script hay framework khác đường dẫn), stream còn cha là một app (kể cả bản MyNotch khác đang chạy), lệnh `send` hay `seek`, tiến trình của người dùng khác, pid 1 và chính app. Không có SIGKILL dự phòng (tránh bắn nhầm pid tái dùng). Khi dọn được thì ghi một dòng log.

- 18 test dùng bảng tiến trình giả (không test nào gửi tín hiệu thật); một lần kiểm tay bằng ba tiến trình perl tạm (chỉ mồ côi đúng script bị dừng); và lúc 16:53 ngày 2026-10-14 trên app thật: SIGTERM bản cũ, adapter của nó thành mồ côi, bản mới khởi động thì mồ côi biến mất, chỉ còn adapter của chính nó.
- **Giới hạn:** mồ côi chỉ bị dọn ở lần khởi động **kế tiếp**, không ngay lúc app bị giết. Khớp cần đúng đường dẫn script, nên mồ côi của một lần mở qua App Translocation (đường dẫn ngẫu nhiên) sẽ không khớp; đây là bản cá nhân ở chỗ cố định.

## 7. Sai khác so với spec và lý do

- Payload rỗng hoặc không hoạt động làm ẩn activity sau 300 ms (chống nháy khi đổi bài), không ẩn ngay. App nằm trong `hiddenApps` thì ẩn ngay.
- Danh tính bài (`TrackIdentity`: bundle, tiêu đề, nghệ sĩ, album và các id) dùng để giữ ảnh bìa và phát lại activity đúng một lần mỗi bài.
- Chuỗi tra lời, cache `v3` (nay `v4`), hết hạn 7 ngày: spec chỉ mô tả một lần gọi `/api/get`. Lý do: bằng chứng ngày 2026-10-14, lrclib trả 404 khi album lệch ("- Single", "Deluxe"), và mọi mục trong cache là `notFound`.
- `AdapterProcess` tuần tự hoá lệnh `send`/`seek` (seek cuối thắng). Thanh tiến trình chỉ seek một lần khi thả chuột hoặc click, vì mỗi lệnh là một tiến trình perl.
- Sửa M5 (`70d95cb`): cờ "bị từ chối quyền" được xoá khi tap khởi động lại, và `SampleRing.write` không cấp phát bộ nhớ trong Debug.
- **Ba nguồn lời, không phải một** (M8, M9): spec chỉ có lrclib. Thứ tự và điều kiện ở mục 2. Cache nâng từ `v3` lên `v4`, thêm `v4+am`.
- **M8, hàng Settings Apple Music là hàng tiêu đề**, không phải `Section` lồng (chưa ai nhìn bố cục thật). Thêm dòng đỏ khi Keychain từ chối hoặc không lấy được storefront (brief không có). Storefront được lấy **trước** khi lưu, nên một lần lấy hỏng không để lại nửa đăng nhập trong Keychain.
- **M8, Apple lỗi mà lrclib không có gì là `.unavailable`**, không phải `.notFound` (không cache, xem mục 2). "Cần đăng nhập lại" chỉ trong bộ nhớ.
- **M8, phần ngoài brief:** tra lại bài đang phát ngay khi kết nối; mọi 4xx của Apple trừ 408 và 429 là "không có"; kho dữ liệu web bị xoá mỗi khi cửa sổ đăng nhập mất (vòng sửa 1, mục 4).
- **M9, khớp bài "dính"** (không chớp tắt ở mỗi lần tạm dừng), `playback` chỉ được host phát lại nếu chưa quá 10 giây, "Gỡ cầu nối" xoá cả thư mục extension đã chép, cài cầu nối bật luôn `youtubeCaptions` (cùng tiền lệ `preciseStatus` của AI agents), và đoạn phát hiện trình duyệt của `TrackKey` được chuyển nguyên vào `NowPlayingState.isFromBrowser` để lời và phụ đề dùng chung.
- **M9, extension** thêm `bridge.js` (logic nối lại tách khỏi `background.js` để test được), đường `/live/<id>` tính như trang xem, và `tests/index.js` (Node 24 coi đối số thư mục của `node --test` là một module).

## 8. Giới hạn đã chấp nhận (Ruling)

- **Stub từ `/api/get`.** Quyết định: bản đồng bộ chỉ dùng được khi có từ 4 dòng; stub hoặc chỉ-lời-thuần từ `/api/get` thành phương án dự phòng và chuỗi tiếp tục tìm; search chọn bản đồng bộ dùng được có chênh lệch thời lượng nhỏ nhất (hoà thì nhiều dòng hơn); 429/503 giữa chuỗi vẫn là `.unavailable`. **Chi phí nếu sai:** thêm tối đa 4 yêu cầu lrclib cho mỗi bài chưa cache, và một stub 1 dòng vẫn có thể hiện nếu lrclib không có gì tốt hơn.
- **"mix" chỉ bỏ qua khi bài dài hơn 360 giây** (khuyến nghị của reviewer; brief gốc "chứa mix" bỏ qua cả bài thật như "Little Mix", "(Original Mix)"). Các từ bỏ qua khác và trần 15 phút giữ nguyên. **Chi phí nếu sai:** một video remix ngắn trong 6 phút có thể gọi lrclib (vô hại, tối đa 4 yêu cầu).
- **Tách dấu gạch chỉ khi album rỗng** (trình duyệt hay không), tin metadata thật của Spotify Web, YouTube Music, Bandcamp; nâng cache lên `v3`; thêm NFC. **Chi phí nếu sai:** một video YouTube báo album không rỗng mà tiêu đề bẩn sẽ không được làm sạch.
- **Bài từ trình duyệt có album giữ nguyên nghệ sĩ player báo** ("AdeleVEVO" vẫn là "AdeleVEVO"). Chấp nhận vì album thật nghĩa là thẻ thật.
- **Bỏ qua:** Minor 9 (kiểm tra tên bài chứa trong kết quả search) vì rủi ro âm tính giả với tiêu đề tiếng Việt và phiên âm; Minor 5 phần tách camel-case của VEVO và tách bài hợp tác ("A x B", "A & B"). Minor 10 (sửa spec) chuyển vào mục 10 của tài liệu này.
- **Ruling (L1 bắt đầu trước khi sửa review M7 vào main):** chỉnh sửa Media của màn hình khoá giới hạn ở việc đăng ký view (`NowPlayingLockScreenView`, `refreshLockScreen`), để cherry-pick các sửa lời bài hát sau đó không xung đột. **Chi phí nếu sai:** một xung đột merge nhỏ ở `MediaModule.swift`. Các commit lời bài hát (`e8a9b20`, `ba6695c`, `ff26aae`) đã được cherry-pick lên trên L1.
- **Quan sát:** `1421c16` (commit M7 đầu) được cherry-pick vào main thành `cac1e37` trước khi review; chấp nhận vì cục bộ, đảo ngược được và cùng nội dung.
- **Ruling (M8): Apple chỉ dùng cho bài phát trong app Music** (catalog id số); tiêu đề YouTube hay Spotify không gửi tới Apple. **Chi phí nếu sai:** bài từ trình duyệt vẫn chỉ dựa vào lrclib (hoặc phụ đề YouTube khi đã cài cầu nối).
- **Ruling (M8): token chỉ ở Keychain**, test không bao giờ chạm Keychain thật; khoá cache mã hoá việc có hỏi Apple. **Chi phí nếu sai:** nếu Keychain từ chối ghi (ký, entitlement) thì không kết nối được và hàng Settings hiện dòng đỏ; phần này chưa chạy thật lần nào.
- **Ruling (M8 vòng sửa 1): xoá kho dữ liệu web mỗi khi cửa sổ đăng nhập mất**, và mỗi lần đăng nhập bắt đầu từ trang chưa đăng nhập, thay vì luôn hiện "Ngắt kết nối". **Chi phí nếu sai:** phải đăng nhập lại sau mỗi lần thử hỏng hoặc bị bỏ dở.
- **Ruling (M8): "Cần đăng nhập lại" chỉ trong bộ nhớ.** **Chi phí nếu sai:** sau mỗi lần mở lại app, Apple bị hỏi thêm một lượt (một 401, một lần làm mới, một 401) trước khi trạng thái lật lại.
- **Ruling (M9): phụ đề YouTube thắng lrclib và Apple** khi người dùng đã bật CC và extension báo đúng video đang phát; `youtubeCaptions` mặc định tắt và độc lập với `lyrics`; phụ đề chỉ ở RAM. **Chi phí nếu sai:** video có phụ đề tự động kém hiện phụ đề đó thay cho lời của lrclib (tắt CC là quay lại).
- **Ruling (M9): host phát lại `captions` và `playback` sau khi nối lại app.** **Chi phí nếu sai:** không đáng kể (bộ nhớ có giới hạn, tối đa 3 video).
- **Ruling (M9b vòng 2): ô giữ 10 giây** (không phải khoảng 2 giây) cho phụ đề đến trước khi trang đổi video. **Chi phí nếu sai:** phụ đề trễ của video trước được gửi nếu người dùng quay lại đúng video đó trong 10 giây; đó là phụ đề của chính video ấy nên chấp nhận.
- **Ruling (M9a): khớp dính qua tạm dừng**, host chỉ phát lại `playback` dưới 10 giây, "Gỡ cầu nối" xoá cả thư mục extension đã chép, bản host đã chép chỉ làm mới ở lần bấm cài kế tiếp. **Chi phí nếu sai:** phụ đề của video đang tạm dừng ở lại tới khi `clear` hoặc đổi video; sau khi cập nhật app phải bấm cài lại để host mới có hiệu lực (nhỏ, nhưng lệch giao thức sẽ im lặng).
- **Ruling (adapter mồ côi): dọn ở lần khởi động kế tiếp, chỉ SIGTERM**, chỉ tiến trình khớp đúng script và framework của bundle. **Chi phí nếu sai:** một adapter mồ côi sống tới lần mở app sau, hoặc không bị dọn nếu app từng chạy qua đường dẫn khác.

## 9. Khoảng trống đã biết

- Stub 1 đến 3 dòng vẫn hiện (một dòng lạc) khi đó là thứ tốt nhất lrclib có, và được cache vĩnh viễn như mọi kết quả tìm thấy.
- 503 ở `/api/get` kết thúc chuỗi (chờ 60 s rồi thử lại một lần), không rơi sang bước search.
- Tiêu đề không có dấu gạch trên kênh không phải nghệ sĩ ("BTS (방탄소년단) 'Dynamite' Official MV" trên "HYBE LABELS") ra nghệ sĩ là tên kênh; lrclib không biết. Đây là dự phòng theo thiết kế.
- Chưa quan sát: `Upgrade | Beyoncé` mất "Upgrade"; `(1080p` không đóng vẫn còn sau khi bỏ nhiễu khác; "Sad :(" mất dấu "("; nghệ sĩ rỗng chưa được chặn như tiêu đề rỗng.
- Các bước 2 đến 4 của chuỗi mới chỉ kiểm bằng client giả, chưa chạm dữ liệu thật ngoài hai lần chạy một lần (Rick Astley 213 s: stub 1 dòng từ `/api/get`, search tìm được 59 dòng; Queen 355 s: 56 dòng ở bước 1).
- Giao diện lời chưa được agent nào nhìn thấy bằng mắt, cần người kiểm: dòng lời đồng bộ và dòng mờ "Chỉ có lời không đồng bộ".
- Video YouTube dài khoảng 33 phút (mix) sẽ không bao giờ có lời từ lrclib hay Apple, đúng thiết kế. Thử bằng một bài đơn.
- **Chưa chạy thật lần nào (M8, M9):** Keychain, cửa sổ đăng nhập `WKWebView` (kể cả user agent giả Safari; cửa sổ `window.open` của luồng đăng nhập không được xử lý), lời Apple thật, Chrome nạp extension (`world: MAIN`, `key` và id), hình dạng thật của phản hồi `/api/timedtext`, các selector của YouTube (`.ytp-subtitles-button`, `video.html5-main-video`, Shorts), thứ tự YouTube tải phụ đề và đổi URL, và việc host chạy từ Application Support với chữ ký Apple Development. Mọi thứ ở checklist.
- **Minor đã hoãn (M8):** Apple trả 400 được cache "không có" một tuần (nên chỉ coi 404, 410, 422, 451 là "không có"); không có cooldown theo `Retry-After` của Apple; không giới hạn kích thước thân phản hồi (TTML, script); cửa sổ đăng nhập không hạn chế điều hướng hay popup; `TokenStore.remove` không báo lỗi xoá hỏng; làm mới token dùng user agent mặc định; bình luận cũ trong `AppleMusicLoginWindow.swift`.
- **Minor đã hoãn (M9):** `stat` của thư mục socket đi theo symlink (cùng mẫu với `AgentEventServer`, nên đổi cả hai cùng lúc); bản host đã chép là ảnh chụp và được thay bằng xoá rồi chép; chỉ một `playback` mới nhất nên hai tab hay hai profile phát video khác nhau làm khớp chớp; test "mồ côi đi trước" không thể fail; một `captions` cũ đang bị giữ có thể ghi đè `captions` mới cùng video (`content.js:204`); XHR parse đồng bộ; không phân tích srv1 và WebVTT; `all_frames` tắt (trình phát nhúng ở trang khác không được phủ).
- **Chỉ Google Chrome** nhận được phụ đề; không có cầu nối cho Safari, Arc, Brave hay Edge.
- Phụ đề đồng bộ theo từng sự kiện, và TTML theo từng chữ của Apple cũng hiện theo dòng: "lời theo từng chữ" của spec vẫn ngoài phạm vi.

## 10. Sửa lại spec (Spec corrections)

- **§3, hàng `LyricsService`**: chỉ mô tả `GET https://lrclib.net/api/get`. Thực tế là chuỗi bốn bước, quy tắc stub, quy tắc bỏ qua, cache `v3` (nay `v4`), hết hạn 7 ngày và dòng mờ "không đồng bộ" như mục 3 ở trên.
- **§1 (phạm vi) và §3, hàng `LyricsService`, về nguồn lời**: spec chỉ có lrclib. Thực tế có ba nguồn thử theo thứ tự phụ đề YouTube từ extension Chrome, Apple Music (bài của app Music, khi đã kết nối), lrclib (mục 2), kèm đăng nhập Apple Music (mục 4), cầu nối Chrome (mục 5) và `TTMLLyricsParser`.
- **§3.3, thêm khoá `youtubeCaptions`** (mặc định `false`, độc lập với `lyrics`) và hai khối Settings mới: "Lời từ Apple Music" (hiện khi `lyrics` bật) và "Phụ đề YouTube làm lời" cùng "Cầu nối Chrome" (luôn hiện). Chuỗi giải thích Apple: "Khi kết nối, MyNotch dùng phiên đăng nhập Apple Music của bạn để lấy lời của bài đang phát trong app Music từ máy chủ Apple (API không chính thức, có thể ngừng hoạt động). Token được cất trong Keychain của máy này." Chuỗi YouTube: "Phụ đề YouTube làm lời: khi bạn bật phụ đề (CC) trên YouTube trong Chrome, extension MyNotch chuyển phụ đề đó sang notch. Không có gì được gửi lên mạng."
- **§3.3, hàng `lyrics`**: câu giải thích đã đổi thành "Khi bật, tên bài, nghệ sĩ, album và thời lượng của mỗi bài mới (kể cả video phát trong trình duyệt) được gửi tới lrclib.net để lấy lời."
- **§3, hàng `ActivityPolicy`**: payload rỗng ẩn sau 300 ms, không "ngay".
- **Dòng trạng thái**: spec ghi "Thiết kế. Cần người dùng đồng ý tải mã nguồn `ungive/mediaremote-adapter`". Adapter v0.7.7 đã nằm trong `Vendor/` và đã nhúng vào app.
- **§3.4**: `NSAudioCaptureUsageDescription` có sẵn trong `project.yml`: "MyNotch hiển thị phổ âm thanh của nhạc đang phát."; entitlement `com.apple.security.device.audio-input` có từ dự án con 0.5.
- **§3 và §1**: thêm hàng "view màn hình khoá" (Media là một contributor của `LockScreenContentCenter`).
- **§3.4, bảng quyền**: dòng "Lời bài hát: không (cần mạng)" chỉ đúng cho lrclib. Lời Apple Music dùng Keychain của người dùng (không có hộp thoại TCC riêng, hệ thống có thể hỏi truy cập Keychain) và cần tài khoản Apple Music. Cầu nối YouTube không cần quyền TCC nhưng ghi một file manifest vào thư mục `NativeMessagingHosts` của Google Chrome và chép hai thứ ra `~/Library/Application Support/io.lucasvu.mynotch/` (xem mục 5).
- **§3, bảng thành phần**: thêm `AppleMusicLyricsClient`, `TTMLLyricsParser`, `AppleMusicAccount`/`TokenStore`, `YouTubeBridgeServer`/`YouTubeCaptionStore`/`YouTubeCaptionMatcher`/`YouTubeBridgeInstaller`, `OrphanedAdapterReaper`; thư viện `YouTubeBridgeKit`; helper `Tools/mynotch-youtube-host`; extension `Extensions/Chrome/MyNotchYouTube/`.

## 11. Cần kiểm thử tay

Xem [mục Media trong checklist gộp](../../manual-test-checklist-all.html#media). Các mục đụng quyền hoặc API riêng: Now Playing qua adapter (MediaRemote riêng, chạy qua perl), phổ âm thật (quyền ghi âm thanh hệ thống, reset TCC trước khi thử), lời bài hát (gửi tên bài ra mạng). Các mục mới chỉ người dùng làm được: **kết nối Apple Music** (tài khoản Apple Music và Keychain thật, đăng nhập trong cửa sổ web), **cầu nối YouTube** (Chrome ở Developer mode nạp extension chưa đóng gói, rồi bật CC trên video thật), và kiểm adapter mồ côi sau khi giết MyNotch.
