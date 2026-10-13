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

Chọn scheme **MyNotch** rồi Run (⌘R). App không có icon Dock; tìm icon trên menu bar.

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

1. Tạo package trong `Packages/Modules/<Tên>/`, viết một class theo `FeatureModule`.
2. Khai báo package trong `project.yml` (mục `packages` và `dependencies` của target MyNotch).
3. Thêm một dòng vào `App/ModuleList.swift`.
4. `xcodegen generate`.

## Bản Release

Khởi động cùng máy cần một bản app ổn định (bản Debug đổi chữ ký mỗi lần build):

```bash
xcodebuild -project MyNotch.xcodeproj -scheme MyNotch -configuration Release \
    -destination 'platform=macOS' -derivedDataPath .build/xcode build -quiet
cp -R .build/xcode/Build/Products/Release/MyNotch.app /Applications/
```

## Ký app

Mặc định app được ký ad-hoc ("Sign to Run Locally"), đủ cho các module không cần quyền hệ thống.
Khi làm module cần quyền (Accessibility, Screen Recording…), trong `project.yml` đặt `DEVELOPMENT_TEAM`
bằng Team ID của Apple ID (Xcode → Settings → Accounts) và đổi `CODE_SIGN_IDENTITY` từ `"-"` thành
`"Apple Development"` để macOS nhớ quyền giữa các lần build.

## Xử lý sự cố

- `cannot find '<Tên>' in scope` cho symbol nằm ở một package local khác: xoá thư mục `.build` của package đang build rồi chạy lại.
- Notch chồng nhau hoặc không nhận chuột: thoát các app notch khác (OneNotch, boring.notch…) đang chạy.
