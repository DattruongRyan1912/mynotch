# Ghi chú triển khai: Icon ứng dụng

- **Ngày:** 2026-10-14 tối (commit), ghi chú 2026-10-15
- **Spec:** không có spec riêng; đây là yêu cầu của người dùng trong phiên ("làm icon cho app"). Mục "Sửa lại spec" không áp dụng.
- **Commit:** `e99b26d` `feat(app): give MyNotch its own icon` (file `App/Icon/MyNotch.icon/`, hai dòng trong `project.yml`, một dòng trong `README.md`).
- **Test tự động:** không có. Kiểm bằng một bản dựng riêng (copy sạch của cây, không phải cây làm việc): `Assets.car` và `MyNotch.icns` có trong bundle, `CFBundleIconName` và `CFBundleIconFile` đều là `MyNotch`, và ảnh kết xuất từ bản dựng khớp hướng A với hiệu ứng Liquid Glass. `verify.sh` không kiểm icon.
- **Kiểm thử tay:** [Icon ứng dụng trong checklist gộp](../../manual-test-checklist-all.html#app-icon)

## 1. Đã làm gì

- Một **tài liệu Icon Composer** `App/Icon/MyNotch.icon` (định dạng icon nhiều lớp của macOS 26) thay cho `AppIcon.appiconset`. Không có `.appiconset` song song: `.icon` thay thế nó, mục tiêu tối thiểu của app là macOS 26.0, và công cụ biên dịch (`actool`) tự sinh `Assets.car` cùng bản dự phòng `MyNotch.icns`.
- Nối vào dự án bằng **một dòng** `ASSETCATALOG_COMPILER_APPICON_NAME: MyNotch` trong `settings.base` của **target app `MyNotch`** (không áp cho các helper `mynotch-hook`, `mynotch-youtube-host` hay framework). XcodeGen (2.46.0) tự thêm `.icon` vào Resources vì `project.yml` đã có `sources: - path: App`; không cần khai báo file.

## 2. Quyết định: hướng A "Notch glow"

Ba hướng được vẽ và đặt cạnh nhau trong một trang xem trước (`~/Project/MyNotch-handoff/icon-concepts/index.html`, **ngoài repo**): A "Notch glow", B "Notch + sound" (notch cộng năm thanh tím như phổ nhạc) và C "Notch + bubbles" (viên thuốc cộng hai bong bóng, một sáng một đen). **Người dùng chọn A.** Chưa có thay đổi trong repo cho tới khi người dùng chọn.

Hướng A: thân squircle than chì ba tông (sáng ở trên, tối dần xuống dưới), một notch đen cắt ở giữa mép trên với tỉ lệ thật (rộng, thấp, góc dưới bo tròn, hai "tai" lõm ở trên) và một luồng sáng tím `#7D5CFF` (màu nhấn của app, `NotchTokens.accent`) tràn xuống từ dưới notch như đang mở ra. Chỉ một nguồn sáng, không thêm ký hiệu nào. Lý do chọn trong trang xem trước: ít chi tiết nhất nên đọc được nhất khi nhỏ (ở 16 px vẫn thấy khe đen và vệt sáng tím), và hợp Liquid Glass vì lớp ánh sáng nằm riêng. MyNotch là app `LSUIElement` (không có ô trong Dock), nên icon chủ yếu hiện ở Finder, Login Items, System Settings và Spotlight, tức cỡ 16 đến 64 pt: khả năng đọc khi nhỏ quan trọng hơn Dock.

## 3. Nằm ở đâu

| Thứ | Vị trí |
|---|---|
| Tài liệu icon | `App/Icon/MyNotch.icon/icon.json` |
| Ba lớp (SVG 1024 × 1024 phủ kín khung, không bo góc, không bóng; hệ thống tự cắt squircle và thêm hiệu ứng kính) | `App/Icon/MyNotch.icon/Assets/` |
| Tên icon cho bộ biên dịch | `ASSETCATALOG_COMPILER_APPICON_NAME: MyNotch` trong `project.yml`, target `MyNotch` |
| Kết quả dựng | `MyNotch.app/Contents/Resources/Assets.car` và `MyNotch.icns`; `CFBundleIconName` và `CFBundleIconFile` trong `Info.plist` của bản dựng |
| Nguồn của ba hướng (ngoài repo) | `~/Project/MyNotch-handoff/icon-concepts/`: `generate_icons.py` (vẽ SVG bằng Python, không dùng ảnh có sẵn hay biểu tượng của app khác), `build_preview.py` (trang xem trước), `render_liquid_glass.sh` (kết xuất bằng `ictool` và kiểm `actool`), thư mục `A`, `B`, `C` |

Các lớp của `icon.json` (từ sau ra trước), đều tắt `glass`, không bóng, không trong suốt, `lighting` là `individual`:

| Lớp | Vai trò |
|---|---|
| `layer0-background.svg` | nền toàn khung, đục |
| `layer1-glow.svg` | ánh sáng tím tràn xuống từ dưới notch |
| `layer2-notch.svg` | notch đen |

Màu nền của tài liệu (`fill`) là than chì `srgb:0.094,0.098,0.114`.

## 4. Cách đổi icon

1. **Chỉnh bằng Icon Composer:** mở `App/Icon/MyNotch.icon` bằng Icon Composer (đi cùng Xcode 26; bản đã dùng là Icon Composer 1.6 với Xcode 26.6), chỉnh lớp, kính, và các dạng tối, nhuộm màu, trong suốt, rồi lưu đè tại chỗ. Không cần sửa `project.yml`.
2. **Hoặc đổi file SVG** trong `App/Icon/MyNotch.icon/Assets/` (giữ 1024 × 1024, phủ kín khung, không bo góc, không bóng). Nếu thêm hay bớt lớp thì sửa tên trong `icon.json`.
3. **Dựng lại:** `xcodegen generate` chỉ cần khi thêm hay bớt file ngoài `.icon`; build bình thường. Kiểm `Contents/Resources/Assets.car` và `MyNotch.icns` có mặt, và `plutil -p MyNotch.app/Contents/Info.plist` có `CFBundleIconName` là `MyNotch`.
4. **Xem trước các dạng của Tahoe** (mặc định, tối, nhuộm màu, trong suốt) không cần chạy app: `render_liquid_glass.sh` trong thư mục concept kết xuất từng bản nháp bằng `ictool` và kiểm `actool` biên dịch được.
5. macOS lưu đệm icon: nếu Finder vẫn hiện icon cũ sau khi dựng lại, `touch` bundle rồi mở lại cửa sổ Finder (chưa kiểm cách này trên máy này). Muốn đổi sang hướng B hay C: chép bản nháp `B/icon-draft/MyNotchB.icon` hay `C/icon-draft/MyNotchC.icon` thành `App/Icon/MyNotch.icon`.

## 5. Giới hạn và chưa kiểm

- Chưa ai nhìn icon thật ở Finder, System Settings (Login Items, Quyền riêng tư), Spotlight, và ở các chế độ sáng, tối, nhuộm màu, trong suốt của macOS 26; ảnh kết xuất của người điều phối khớp hướng A nhưng chỉ là ảnh, không phải Finder thật.
- Cỡ nhỏ (16 và 32 px) chỉ được xem qua ảnh phóng của trang xem trước, không qua Finder.
- `project.yml` dùng mặc định Debug và Release; icon áp cho cả hai. Bản Release chưa được dựng lại để kiểm riêng icon.
- Hướng B và C còn trong thư mục ngoài repo; không được dùng ở đâu trong dự án.

## 6. Cần kiểm thử tay

Xem [Icon ứng dụng trong checklist gộp](../../manual-test-checklist-all.html#app-icon): Finder (cỡ khác nhau), Settings và Login Items, trang Giới thiệu, dạng tối, nhuộm màu và trong suốt.
