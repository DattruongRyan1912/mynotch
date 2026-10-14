# MyNotch

Ứng dụng notch cá nhân cho macOS 26+, viết mới từ đầu, chia thành các module bật/tắt độc lập.

> **Clean-room:** MyNotch lấy hành vi của OneNotch làm tham chiếu nhưng **không chứa mã nguồn của OneNotch**. boring.notch (GPL) chỉ được đọc để hiểu kiến trúc, không chép mã. Bên thứ ba: KeyboardShortcuts (MIT) và `mediaremote-adapter` v0.7.7 (BSD-3, trong `Vendor/`); cả hai có trong trang About của app.

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

Mỗi tính năng là một package trong `Packages/Modules/`, bật/tắt trong Settings → Modules. Cột "Mặc định" là giá trị `defaultEnabled`.

| Module | Id | Mặc định | Làm gì |
|---|---|---|---|
| Clipboard | `clipboard` | Bật | Lịch sử clipboard (text, ảnh, file, màu), tìm kiếm, board, cửa sổ Thư viện (lưới và danh sách, thanh bên theo board, loại, app). Bấm một mục là **dán** vào app đang dùng (mặc định; cần Accessibility, tab hiện gợi ý kèm nút cấp quyền nếu thiếu). ⌃⌥V (tab), ⌃⌥⇧V (thư viện), mục "Thư viện Clipboard…" ở menu bar |
| Media | `media` | Bật | Bài đang phát của mọi app, điều khiển, cột sóng. Tắt sẵn: phổ âm thật; lời bài hát theo thứ tự phụ đề YouTube từ extension Chrome, Apple Music (bài của app Music, cần đăng nhập tài khoản của bạn), lrclib.net; dòng lời nằm giữa tab dưới các nút điều khiển, và tuỳ chọn hiện lời 2 dòng (đang hát, sắp tới) dưới notch thu gọn |
| Dịch | `translation` | Bật | Dịch trên máy bằng framework Translation: tab, mục Services, ⌃⌥T |
| Ảnh chụp | `screenshot` | Bật, cần Screen Recording | Chụp vùng, cửa sổ, màn hình, OCR, sửa ảnh. ⌃⌥S, ⌃⌥O |
| AI agents | `aiagents` | Bật | Trạng thái, token và chi phí của Claude Code và Codex; hook "trạng thái chính xác" tuỳ chọn. Đang làm việc chỉ là bubble khi có nhạc đang phát; chờ duyệt ("!") chiếm notch tới khi bạn trả lời, xong (✓) chiếm vài giây |
| Lịch | `calendar` | Bật, cần quyền Lịch | Sự kiện hôm nay, thông báo họp kèm nút Tham gia, lời nhắc |
| Hệ thống | `system` | Bật | Activity Bluetooth, mạng, Caps Lock, tải xong, âm lượng |
| Battery | `battery` | Bật | Pin và sạc (module mẫu): cục pin ngang chiếm cả tab (xanh khi sạc, vàng khi Nguồn điện thấp, đỏ khi pin yếu), thời gian, nguồn, công suất, dung lượng tối đa, chu kỳ sạc |
| Shortcuts | `shortcuts` | Bật | Chạy Apple Shortcuts ưa thích từ notch |
| Hẹn giờ | `timer` | Bật | Đếm ngược và bấm giờ |
| Khay | `shelf` | Bật | Thả file, link, văn bản lên notch; AirDrop, chia sẻ |
| Màn hình khoá | `lockscreen` | **Tắt**, thử nghiệm | Widget media, hẹn giờ, pin trên màn hình khoá (API riêng SkyLight, chưa kiểm chứng) |

Phím tắt chung: ⌃⌥N mở/đóng notch.

**Nhiều activity cùng lúc.** Notch thu gọn vẽ một activity **chính** (cao nhất theo ưu tiên; thông báo ngắn như âm lượng, "đã chép", ảnh chụp, ✓ của AI chiếm notch vài giây rồi trả lại) và tối đa hai **bubble** tròn bên phải cho các activity còn lại, "+N" khi nhiều hơn ba. Rê vào một bubble mở danh sách mọi activity; bấm một hàng mở tab của module đó. Dải lời dưới notch thuộc activity chính.

**Quyền.** Settings → **Quyền** (mục đầu thanh bên) liệt kê quyền của các module đang bật (cần thiết và tuỳ chọn), nhãn trạng thái, lý do, nút "Cấp quyền" hoặc "Mở Cài đặt", và "Cấp lần lượt" đi qua từng quyền còn thiếu. Thiếu quyền bắt buộc thì icon menu bar có chấm đỏ và menu có "Thiếu N quyền…". Trang tự mở một lần ở lần chạy đầu và khi chứng chỉ ký đổi (macOS khi đó quên mọi quyền).

Dữ liệu của module nằm ở `~/Library/Application Support/io.lucasvu.mynotch/Modules/<id>/`. Mặc định app không gửi dữ liệu ra ngoài. Chỉ lời bài hát (đang tắt) gửi tên bài tới lrclib.net; khi bạn kết nối Apple Music thì id bài của app Music cùng token của bạn đi tới Apple; phụ đề YouTube (đang tắt) chỉ đi trong máy, không gửi gì cho YouTube.

## Cấu trúc và cách ghép module

| Thư mục | Vai trò |
|---|---|
| `App/` | Target app: khởi động, menu bar, Settings. `ModuleList.swift` là nơi **duy nhất** ghép module vào app. Icon app là `App/Icon/MyNotch.icon` (Icon Composer, hướng "Notch glow"; xem mục "Icon") |
| `Packages/MyNotchCore` | Hợp đồng module, registry, settings, quyền, phím tắt, live activity, Services |
| `Packages/NotchUI` | Cửa sổ notch, hình học, state machine, đa màn hình, thả file, SkyLight shim |
| `Packages/DebugTools` | Chỉ có trong bản Debug (ở Release biên dịch thành rỗng): kích hoạt live activity giả qua distributed notification để thử notch mà không cần app thật (mục "Gỡ lỗi" bên dưới) |
| `Packages/Modules/*` | Mỗi tính năng một package; chỉ phụ thuộc MyNotchCore và NotchUI, không module nào import module khác |
| `Tools/mynotch-hook` | Helper CLI của AI agents, được nhúng vào `Contents/MacOS` |
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

Module dùng được: `context.storage`, `context.scheduler` (việc đã hẹn tự huỷ khi module dừng), `context.hotkeys` (đăng ký và `unregister` theo tên), `context.presenter` (`open()` mở tab của chính module, `showToast`, `close`), `context.activities` (live activity cập nhật tại chỗ, `raise`; `LiveActivity` có `bottom` và `bottomHeight` cho dải dưới notch, `minimal` và `summary` cho bubble và danh sách, `expiresAfter` biến nó thành thông báo ngắn thắng hoà ưu tiên), `context.services` (macOS Services: cần thêm một mục `NSServices` trong `project.yml` và một phương thức trong `App/ServicesProvider.swift`, nếu không hệ thống không bao giờ gọi), `context.lockScreen` (view nhỏ không nhạy cảm cho màn hình khoá), `FeatureModule.menuItems` (mục thêm vào menu của icon menu bar, chỉ hiện khi module chạy), `NotchTab(acceptsKeyboard:dropTypes:onDrop:)`, `@Environment(\.notch)` (ghim, báo đang kéo, đóng notch), `optionalPermissions` trong `ModuleDescriptor`. Sau khi module dừng, `scheduler`, `hotkeys`, `presenter`, `activities`, `services` và `lockScreen` không làm gì nữa. Test cần thư mục tạm thì dùng `ScratchFolders.shared.reserve("<nhãn>")` của `MyNotchTestSupport` (tự xoá khi tiến trình test thoát).

## Tài liệu

- **Spec:** `docs/superpowers/specs/2026-10-13-*-design.html` (bản `.md` đi kèm). Kế hoạch nền tảng: `docs/superpowers/plans/`.
- **Ghi chú triển khai** (sai khác so với spec, giới hạn đã chấp nhận, mục sửa lại spec): `docs/superpowers/notes/2026-10-14-<module>-implementation.html`, mỗi module một file cùng một file cho nền tảng (bubble, bàn phím, quyền, hiệu năng, Battery, trigger Debug nằm ở đó), và `2026-10-15-app-icon-implementation.html` cho icon.
- **Kiểm thử tay:** `docs/manual-test-checklist-all.html` (gộp theo module, chọn kết quả và copy ra văn bản). `docs/manual-test-checklist.html` là checklist cũ, chỉ phần nền tảng.
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
| `youtube-bridge` | mọi bản | Host `mynotch-youtube-host`, app, các mã `diag` của extension, khớp bài, độ lệch lời |

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

App, các helper `mynotch-hook` và `mynotch-youtube-host`, và framework MediaRemoteAdapter được ký bằng chứng chỉ **Apple Development** (`CODE_SIGN_IDENTITY: "Apple Development"`, `DEVELOPMENT_TEAM: B394MAY4QN` trong `project.yml`, có hardened runtime). Nhờ vậy macOS nhớ các quyền đã cấp (Accessibility, Screen Recording, Lịch…) qua các lần build lại.

Chứng chỉ này cần chứng chỉ trung gian **Apple WWDR G3** (`AppleWWDRCAG3.cer`) trong keychain **login** (cài bằng `security add-certificates -k ~/Library/Keychains/login.keychain-db AppleWWDRCAG3.cer`; keychain iCloud không nhận chứng chỉ, báo lỗi `-25294`). Kiểm tra: `security find-identity -v -p codesigning` phải báo `1 valid identities found`. Máy không có chứng chỉ thì đổi lại `CODE_SIGN_IDENTITY: "-"` (ad-hoc), khi đó macOS quên quyền sau mỗi lần build.

Chứng chỉ Apple Development của Apple ID miễn phí có hạn (thường 1 năm); hết hạn thì macOS không mở app nữa: tạo chứng chỉ mới trong Xcode rồi build lại.

## Xử lý sự cố

- `cannot find '<Tên>' in scope` cho symbol nằm ở một package local khác: xoá thư mục `.build` của package đang build rồi chạy lại.
- Notch chồng nhau hoặc không nhận chuột: thoát các app notch khác (OneNotch, boring.notch…) đang chạy, và chỉ chạy một bản MyNotch.
- Quyền bị quên sau khi build: xem mục "Ký app". Cấp lại bằng Settings → Quyền → “Cấp lần lượt” (trang này tự mở khi app lần đầu chạy hoặc khi chứng chỉ ký đổi). Muốn thử lại hộp thoại quyền từ đầu: `tccutil reset All io.lucasvu.mynotch`; với cùng chứng chỉ ký trang Quyền **không** tự mở lại sau lệnh này (chấm đỏ và "Thiếu N quyền…" trên menu bar là lời nhắc), muốn thấy nó tự mở: `defaults delete io.lucasvu.mynotch app.permissionIdentity` rồi mở lại app.
- Sau khi chạy `./scripts/verify.sh` hay build lại, bản `MyNotch.app` dưới `.build/xcode` bị thay ngay dưới tiến trình đang chạy: thoát **mọi** bản MyNotch (kể cả bản đã chạy từ đường dẫn khác, và adapter `mediaremote-adapter.pl` mồ côi nếu có) rồi mới mở bản mới; để lại hai bản là hai notch chồng nhau.
