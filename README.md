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
| Clipboard | `clipboard` | Bật | Lịch sử clipboard (text, ảnh, file, màu), tìm kiếm, board, dán trực tiếp, cửa sổ Thư viện. ⌃⌥V (tab), ⌃⌥⇧V (thư viện) |
| Media | `media` | Bật | Bài đang phát của mọi app, điều khiển, cột sóng. Tắt sẵn: phổ âm thật; lời bài hát theo thứ tự phụ đề YouTube từ extension Chrome, Apple Music (bài của app Music, cần đăng nhập tài khoản của bạn), lrclib.net |
| Dịch | `translation` | Bật | Dịch trên máy bằng framework Translation: tab, mục Services, ⌃⌥T |
| Ảnh chụp | `screenshot` | Bật, cần Screen Recording | Chụp vùng, cửa sổ, màn hình, OCR, sửa ảnh. ⌃⌥S, ⌃⌥O |
| AI agents | `aiagents` | Bật | Trạng thái, token và chi phí của Claude Code và Codex; hook "trạng thái chính xác" tuỳ chọn |
| Lịch | `calendar` | Bật, cần quyền Lịch | Sự kiện hôm nay, thông báo họp kèm nút Tham gia, lời nhắc |
| Hệ thống | `system` | Bật | Activity Bluetooth, mạng, Caps Lock, tải xong, âm lượng |
| Battery | `battery` | Bật | Pin và sạc (module mẫu) |
| Shortcuts | `shortcuts` | Bật | Chạy Apple Shortcuts ưa thích từ notch |
| Hẹn giờ | `timer` | Bật | Đếm ngược và bấm giờ |
| Khay | `shelf` | Bật | Thả file, link, văn bản lên notch; AirDrop, chia sẻ |
| Màn hình khoá | `lockscreen` | **Tắt**, thử nghiệm | Widget media, hẹn giờ, pin trên màn hình khoá (API riêng SkyLight, chưa kiểm chứng) |

Phím tắt chung: ⌃⌥N mở/đóng notch. Dữ liệu của module nằm ở `~/Library/Application Support/io.lucasvu.mynotch/Modules/<id>/`. Mặc định app không gửi dữ liệu ra ngoài. Chỉ lời bài hát (đang tắt) gửi tên bài tới lrclib.net; khi bạn kết nối Apple Music thì id bài của app Music cùng token của bạn đi tới Apple; phụ đề YouTube (đang tắt) chỉ đi trong máy, không gửi gì cho YouTube.

## Cấu trúc và cách ghép module

| Thư mục | Vai trò |
|---|---|
| `App/` | Target app: khởi động, menu bar, Settings. `ModuleList.swift` là nơi **duy nhất** ghép module vào app |
| `Packages/MyNotchCore` | Hợp đồng module, registry, settings, quyền, phím tắt, live activity, Services |
| `Packages/NotchUI` | Cửa sổ notch, hình học, state machine, đa màn hình, thả file, SkyLight shim |
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
3. Module cần quyền mới: thêm usage description và entitlement tương ứng vào `project.yml`.
4. Thêm một dòng vào `App/ModuleList.swift`, rồi `xcodegen generate`. `verify.sh` tự test mọi package trong `Packages/Modules/`.

Module dùng được: `context.storage`, `context.scheduler` (việc đã hẹn tự huỷ khi module dừng), `context.hotkeys` (đăng ký và `unregister` theo tên), `context.presenter` (`open()` mở tab của chính module, `showToast`, `close`), `context.activities` (live activity cập nhật tại chỗ, `raise`), `context.services` (macOS Services: cần thêm một mục `NSServices` trong `project.yml` và một phương thức trong `App/ServicesProvider.swift`, nếu không hệ thống không bao giờ gọi), `context.lockScreen` (view nhỏ không nhạy cảm cho màn hình khoá), `FeatureModule.menuItems` (mục thêm vào menu của icon menu bar, chỉ hiện khi module chạy), `NotchTab(acceptsKeyboard:dropTypes:onDrop:)`, `@Environment(\.notch)` (ghim, báo đang kéo, đóng notch), `optionalPermissions` trong `ModuleDescriptor`. Sau khi module dừng, `scheduler`, `hotkeys`, `presenter`, `activities`, `services` và `lockScreen` không làm gì nữa. Test cần thư mục tạm thì dùng `ScratchFolders.shared.reserve("<nhãn>")` của `MyNotchTestSupport` (tự xoá khi tiến trình test thoát).

## Tài liệu

- **Spec:** `docs/superpowers/specs/2026-10-13-*-design.html` (bản `.md` đi kèm). Kế hoạch nền tảng: `docs/superpowers/plans/`.
- **Ghi chú triển khai** (sai khác so với spec, giới hạn đã chấp nhận, mục sửa lại spec): `docs/superpowers/notes/2026-10-14-<module>-implementation.html`, mỗi module một file cùng một file cho nền tảng.
- **Kiểm thử tay:** `docs/manual-test-checklist-all.html` (gộp theo module, chọn kết quả và copy ra văn bản). `docs/manual-test-checklist.html` là checklist cũ, chỉ phần nền tảng.
- Tạo HTML từ Markdown: `python3 scripts/md2html.py <file.md>`.

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
- Quyền bị quên sau khi build: xem mục "Ký app". Muốn thử lại hộp thoại quyền từ đầu: `tccutil reset All io.lucasvu.mynotch`.
