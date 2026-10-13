# MyNotch

Ứng dụng notch cá nhân cho macOS 26+, viết mới từ đầu, chia thành các module bật/tắt độc lập.

## Yêu cầu

- macOS 26.0 trở lên
- Xcode 26.6 (`xcode-select -p` phải trỏ vào Xcode, không phải Command Line Tools)
- XcodeGen: `brew install xcodegen`

## Build và chạy

```bash
xcodegen generate
open MyNotch.xcodeproj
```

Chọn scheme **MyNotch** rồi Run (⌘R). App chạy trên menu bar; icon Dock chỉ hiện khi cửa sổ Settings đang mở.

Kiểm tra toàn bộ (test mọi package rồi build app):

```bash
./scripts/verify.sh
```

## Cấu trúc

| Thư mục | Vai trò |
|---|---|
| `App/` | Target app: khởi động, ghép module (`ModuleList.swift`), menu bar, Settings |
| `Packages/MyNotchCore` | Hợp đồng module, registry, settings, quyền, phím tắt, live activity |
| `Packages/NotchUI` | Cửa sổ notch, hình học, state machine, đa màn hình |
| `Packages/Modules/*` | Mỗi tính năng một package; chỉ phụ thuộc MyNotchCore + NotchUI |
| `docs/superpowers/` | Spec và kế hoạch triển khai |

## Thêm một module

1. Tạo package trong `Packages/Modules/<Tên>/`; chép `Packages/Modules/Battery/Package.swift` làm mẫu (macOS 26, phụ thuộc đường dẫn tới MyNotchCore/NotchUI, `.defaultIsolation(MainActor.self)`, test dùng `MyNotchTestSupport`). Viết một class theo `FeatureModule`.
2. Khai báo package trong `project.yml` (mục `packages` và `dependencies` của target MyNotch).
3. Module cần quyền mới: thêm usage description và entitlement tương ứng vào `project.yml`.
4. Thêm một dòng vào `App/ModuleList.swift`.
5. `xcodegen generate`. `scripts/verify.sh` tự chạy test của mọi package trong `Packages/Modules/`.

Module dùng được: `context.storage` (thư mục dữ liệu riêng), `context.scheduler` (việc đã hẹn tự huỷ khi module dừng), `NotchTab(acceptsKeyboard:)` (tab nhận bàn phím),
`@Environment(\.notch)` (ghim/đóng notch từ view), `optionalPermissions` trong `ModuleDescriptor` (quyền không bắt buộc)
và `context.lockScreen` (view nhỏ, không nhạy cảm, hiện trên màn hình khoá khi module Màn hình khoá được bật).

## Bản Release

Khởi động cùng máy cần một bản app ổn định (bản Debug đổi chữ ký mỗi lần build). Thoát MyNotch đang chạy
(menu bar → Quit MyNotch) rồi:

```bash
xcodebuild -project MyNotch.xcodeproj -scheme MyNotch -configuration Release \
    -destination "platform=macOS,arch=$(uname -m)" -derivedDataPath .build/xcode build -quiet
rm -rf /Applications/MyNotch.app
ditto .build/xcode/Build/Products/Release/MyNotch.app /Applications/MyNotch.app
```

Không dùng `cp -R` đè lên bản cũ: macOS sẽ giết app khi mở vì chữ ký không còn khớp.

## Ký app

Mặc định app được ký ad-hoc ("Sign to Run Locally"), đủ cho các module không cần quyền hệ thống.
Với ký ad-hoc, macOS quên các quyền đã cấp (Accessibility, Screen Recording…) mỗi lần build lại.
Để macOS nhớ quyền giữa các lần build:

1. Xcode → Settings → Accounts: thêm Apple ID, rồi Manage Certificates → tạo chứng chỉ **Apple Development**.
2. Trong `project.yml` đặt `DEVELOPMENT_TEAM` bằng Team ID của Apple ID và đổi `CODE_SIGN_IDENTITY` từ `"-"` thành `"Apple Development"`.
3. Chạy lại `xcodegen generate`.

Chứng chỉ Apple Development của Apple ID miễn phí có hạn (thường 1 năm); hết hạn thì macOS không mở app nữa —
tạo chứng chỉ mới trong Xcode rồi build lại.

## Xử lý sự cố

- `cannot find '<Tên>' in scope` cho symbol nằm ở một package local khác: xoá thư mục `.build` của package đang build rồi chạy lại.
- Notch chồng nhau hoặc không nhận chuột: thoát các app notch khác (OneNotch, boring.notch…) đang chạy.
