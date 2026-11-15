# MyNotch — Media / Now Playing (dự án con 2)

- **Ngày:** 2026-10-13
- **Trạng thái:** Thiết kế. Cần người dùng đồng ý tải mã nguồn `ungive/mediaremote-adapter` (BSD-3) về vendor trước khi triển khai.
- **Nguồn:** nghiên cứu SDK macOS 26.5, README/mã nguồn mediaremote-adapter, tài liệu Core Audio taps và lrclib. Chỉ tham khảo kiến trúc boring.notch (GPL); không dùng mã OneNotch.

## 1. Mục tiêu

**Trong phạm vi:**

- Thông tin bài đang phát của bất kỳ app nào (Music, Spotify, YouTube trên Safari/Chrome…): tên bài, nghệ sĩ, album, ảnh bìa, thời lượng, vị trí đang phát.
- Điều khiển: phát/dừng, bài trước/sau, tua bằng thanh tiến trình.
- Live activity khi notch đóng: ảnh bìa bên trái, cột sóng nhạc bên phải. Hiện khi đang phát; ẩn sau 5 giây tạm dừng.
- Tab "Media": ảnh bìa lớn, thông tin bài, thanh tiến trình, nút điều khiển, tên app đang phát.
- Phổ âm thanh thật từ âm thanh hệ thống (tuỳ chọn, mặc định tắt). Khi tắt, cột sóng chạy hiệu ứng giả, không cần quyền.
- Lời bài hát đồng bộ từ lrclib.net (tuỳ chọn, mặc định tắt vì phải gửi tên bài ra ngoài).

**Ngoài phạm vi:**

- Fallback AppleScript cho Music/Spotify: chỉ làm khi adapter bị Apple chặn.
- Xáo trộn/lặp, tốc độ phát.
- Lời bài hát theo từng chữ.

## 2. Cơ chế lấy Now Playing

macOS 15.4+ chặn app thường đọc MediaRemote. Cách còn hoạt động: `mediaremote-adapter`.

- `/usr/bin/perl` có chữ ký Apple (`com.apple.perl`). Nó nạp `MediaRemoteAdapter.framework` và in thông tin dạng JSON từng dòng.
- `stream --micros --debounce=100` in mỗi thay đổi một dòng `{"type":"data","diff":true,"payload":{…}}`.
  - Khoá có giá trị `null` nghĩa là bị xoá.
  - Payload rỗng nghĩa là không có gì đang phát.
  - Ảnh bìa đi kèm dạng base64.
- Lệnh điều khiển: `send <id>` (0 phát, 1 dừng, 2 bật/tắt, 4 bài sau, 5 bài trước), `seek <micro giây>`.
- `test` kiểm tra adapter còn hoạt động không. Nếu Apple vá lỗ hổng này, module báo `unavailable` với lý do rõ ràng.

### 2.1 Tích hợp build (XcodeGen)

- Vendor mã nguồn upstream tag `v0.7.7` vào `Vendor/mediaremote-adapter/`, giữ nguyên `LICENSE` (BSD-3). Thêm vào trang About.
- Target `framework` `MediaRemoteAdapter`:
  - nguồn `src/adapter`, `src/private`, `src/utility`; header `include/`;
  - ARC; `OTHER_CFLAGS: -fvisibility=default`;
  - bundle ID `io.lucasvu.mynotch.MediaRemoteAdapter`.
- Target MyNotch phụ thuộc framework đó với `embed: true`, `link: false` (chỉ nhúng vào `Contents/Frameworks` để perl nạp, app không link). Script `.pl` là resource.
- Package `MediaModule` không biết đường dẫn thật: app truyền URL của script và framework vào module qua init.

## 3. Thiết kế

Package `Packages/Modules/Media`, product `MediaModule`.

| Thành phần | Vai trò |
|---|---|
| `NowPlayingSource` (protocol) | `lines: AsyncStream<String>`, `send(_ command:)`, `seek(to:)`. Cho phép thay adapter bằng nguồn giả trong test hoặc bằng AppleScript sau này. |
| `AdapterProcess` | Chạy `perl … stream`, tách stdout theo dòng, SIGTERM khi dừng. Thoát bất thường thì khởi động lại với backoff (1, 2, 4, … tối đa 30 giây); lỗi chết (exit khác 0 ngay từ đầu) thì dừng hẳn và báo `unavailable`. Lệnh `send`/`seek` chạy tiến trình perl ngắn. |
| `NowPlayingReducer` | Thuần. Gộp các payload diff vào `NowPlayingState` (title, artist, album, duration, elapsed anchor, rate, playing, bundleID, artwork data + id). Chỉ giải mã ảnh bìa khi dữ liệu ảnh đổi. |
| `PlaybackClock` | Thuần. `vị trí = elapsed + (now − timestamp) × rate`, kẹp trong [0, duration]. |
| `NowPlayingStore` | `@Observable`. Trạng thái cho UI, ảnh bìa `NSImage`, tên/icon app phát. |
| `ActivityPolicy` | Thuần. Máy trạng thái hidden → playing → paused → hidden: ẩn sau `pauseGrace` (5 giây); payload rỗng thì ẩn ngay; chống nháy khi đổi bài bằng độ trễ 300 ms trước khi ẩn. Thời gian dùng `context.scheduler`. |
| `SpectrumAnalyzer` | Thuần (Accelerate vDSP): khung 1024 mẫu, cửa sổ Hann, FFT, công suất → dB, gộp thành N dải log, làm mượt attack/decay. |
| `SystemAudioTap` | Core Audio process tap toàn hệ thống (trừ chính MyNotch) → aggregate device riêng → IOProc → ring buffer → analyzer ~30 Hz. Chỉ chạy khi đang phát **và** có view phổ đang hiện. |
| `LyricsService` | Tuỳ chọn. `GET https://lrclib.net/api/get` với User-Agent `MyNotch/<version>`. Tôn trọng 429/`Retry-After`, mỗi lượt cách nhau ≥ 300 ms. Cache trên đĩa, kể cả kết quả "không có". `LRCParser` thuần. |
| `MediaModule` | Vòng đời, live activity, tab, cài đặt, phím tắt. |

### 3.1 Giao diện

- **Live activity** (`id: "nowPlaying"`, ưu tiên `.normal`):
  - bên trái: ảnh bìa bo góc 16 pt;
  - bên phải: 4 cột sóng (phổ thật nếu bật, không thì hiệu ứng);
  - nội dung đổi liên tục do `NowPlayingStore` điều khiển trong view (quy ước B1), không gọi `set` mỗi khung hình.
- **Tab "Media"** (cao 150 pt):
  - ảnh bìa 96 pt;
  - tên bài, nghệ sĩ; thanh tiến trình kéo được;
  - ⏮ ⏯ ⏭; icon app phát.
  - Có lời thì một dòng lời hiện tại nằm dưới thanh tiến trình.
  - Không có gì phát: "Không có gì đang phát".

### 3.2 Phím tắt

Không đặt mặc định (phím media của bàn phím đã có sẵn). Có thể gán: phát/dừng, bài sau, bài trước.

### 3.3 Cài đặt (`module.media.*`)

| Khoá | Mặc định | Ghi chú |
|---|---|---|
| `showActivity` | true | |
| `pauseGraceSeconds` | 5 | 0…60 |
| `realSpectrum` | false | Bật thì xin quyền ghi âm thanh hệ thống |
| `lyrics` | false | Settings ghi rõ: tên bài, nghệ sĩ, album, thời lượng gửi tới lrclib.net |
| `hiddenApps` | [] | Bundle ID không hiện activity |

### 3.4 Quyền

| Tính năng | Info.plist | Quyền TCC |
|---|---|---|
| Now Playing qua adapter | — | không |
| Phổ âm thật | `NSAudioCaptureUsageDescription` | "Chỉ ghi âm thanh hệ thống" |
| Lời bài hát | — | không (cần mạng) |

Quyền ghi âm thanh hệ thống không có API kiểm tra. Khi bị từ chối, bộ đệm toàn số 0. Module coi "im lặng > 10 giây trong lúc đang phát" là bị từ chối, rồi hiện hướng dẫn mở System Settings › Quyền riêng tư & Bảo mật › Ghi màn hình & âm thanh hệ thống.

## 4. Rủi ro

- Apple vá lỗ hổng perl, hoặc bỏ perl khỏi macOS. Có `test` lúc khởi động và protocol `NowPlayingSource` để thay nguồn.
- Upstream đổi định dạng CLI giữa các bản. Ghim tag, có test hợp đồng dùng các dòng JSON mẫu.
- Process tap: đổi thiết bị ra hoặc đổi sample rate thì dựng lại; tốn CPU nên chỉ chạy khi cần.
- Ký ad-hoc làm mất quyền mỗi lần build: nên chuyển sang Apple Development.

## 5. Kiểm thử

| Phần | Test tự động |
|---|---|
| Reducer | Payload đầy đủ, diff, `null` xoá khoá, payload rỗng, ảnh bìa chỉ giải mã khi đổi (dùng dòng JSON mẫu) |
| `PlaybackClock` | Đang phát/tạm dừng/rate ≠ 1, kẹp biên |
| `ActivityPolicy` | Chuỗi sự kiện với ManualScheduler: phát → dừng → hết grace; đổi bài không nháy; payload rỗng |
| `SpectrumAnalyzer` | Sóng sin tổng hợp rơi đúng dải; im lặng → toàn 0 |
| `LRCParser` | Nhiều mốc trên một dòng, offset, dòng hỏng, tìm dòng hiện tại |
| `LyricsService` | URLProtocol giả: 200/404/429 + `Retry-After`; cache |
| `AdapterProcess` | Chạy script giả bằng `/bin/sh` in vài dòng JSON; backoff; SIGTERM khi dừng |
| Module | Nguồn giả → activity hiện/ẩn; lệnh điều khiển gửi đúng id |

**Kiểm thử tay:** Music, Spotify (nếu có), YouTube trên Safari và Chrome; ảnh bìa; tua; activity; phổ âm khi bật (hộp thoại quyền); lời bài hát khi bật.
