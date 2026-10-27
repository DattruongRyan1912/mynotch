# Sổ Tay Tri Thức Dự Án MyNotch (Project Knowledge Base)

> Tài liệu tổng hợp kiến trúc hệ thống, danh mục module nghiệp vụ, cơ chế bảo mật TCC, cấu hình ký chứng chỉ và quy trình phát triển.
> 
> *Khuyến nghị: Mở file [PROJECT_KNOWLEDGE_BASE.html](PROJECT_KNOWLEDGE_BASE.html) trên trình duyệt để có trải nghiệm đọc tối ưu nhất với tính năng tìm kiếm nhanh và copy code 1-click.*

---

## 1. Tổng Quan & Triết Lý Thiết Kế

**MyNotch** là ứng dụng thanh trạng thái và tiện ích mở rộng vùng Notch phần cứng (hoặc Notch ảo trên màn hình ngoài) dành cho macOS 26 trở lên, được xây dựng hoàn toàn mới từ đầu với nguyên tắc **Clean-room Design**:

- **Clean-Room Principle**: Lấy trải nghiệm Notch hiện đại làm tham chiếu nhưng hoàn toàn không sao chép mã nguồn của bất kỳ ứng dụng bên thứ ba nào. Mã nguồn tách biệt thành 18 package độc lập trong `Packages/Modules/`.
- **Swift 6 Strict Concurrency**: Toàn bộ codebase áp dụng `SWIFT_STRICT_CONCURRENCY: complete` và `SWIFT_DEFAULT_ACTOR_ISOLATION: MainActor`. Các luồng I/O ngầm, đọc kernel Mach ticks, Audio DSP, SMC đều chạy trên các isolated Actor hoặc utility queues an toàn dữ liệu 100%.
- **Kích thước Notch chuẩn 192pt**: Chiều cao mở rộng của Notch được giới hạn nghiêm ngặt ở mức 192pt nhằm bảo đảm tỷ lệ vàng hiển thị, không che lấp cửa sổ làm việc và được kiểm thử tự động qua `PerformanceTabLayoutTests`.
- **Tiết kiệm năng lượng (On-Demand Demand-Driven Polling)**: Ứng dụng không bao giờ thăm dò dữ liệu ngầm liên tục nếu người dùng không mở tab tương ứng (trừ các background daemon cần thiết như điều khiển đường cong quạt).

---

## 2. Kiến Trúc Hệ Thống & Nền Tảng Cốt Lõi

```text
+---------------------------------------------------------------------------------+
|                                App (MyNotch)                                    |
|   AppDelegate.swift  |  Menu Bar Controller  |  Settings Window  |  Info.plist  |
+---------------------------------------------------------------------------------+
                                      |
       +------------------------------+------------------------------+
       v                                                             v
+-------------------------------+                     +-------------------------------+
|            NotchUI            |                     |          MyNotchCore          |
|  ScreenManager (Notch Detect) |                     |  FeatureModule Protocol       |
|  NotchWindowController        | <------------------ |  Registry & ActivityCenter    |
|  ActivitySlots & Strip Engine |                     |  LiveActivity & SettingKey    |
+-------------------------------+                     +-------------------------------+
       ^                                                             ^
       |                                                             |
+---------------------------------------------------------------------------------+
|                    18 Feature Modules (Packages/Modules/*)                      |
|  Media  |  Performance  |  Clipboard  |  Screenshot  |  Equalizer  |  Pet  ...  |
+---------------------------------------------------------------------------------+
       |                                                             |
       v                                                             v
+---------------------------------+                 +---------------------------------+
|         External Daemons        |                 |       System Kernel & APIs      |
|  mynotch-fan-helper (root daemon)|                 |  Mach Host Stats (HOST_CPU)     |
|  mediaremote-adapter (Perl/ObjC)|                 |  AppleSMC Sensors & Fan RPM     |
|  mynotch-clipboard-mcp          |                 |  ScreenCaptureKit & CoreAudio   |
|  Chrome Extension Bridge        |                 |  TCC & AppleEvents Automation   |
+---------------------------------+                 +---------------------------------+
```

### Các Thành Phần Nền Tảng

1. **`MyNotchCore`**: Định nghĩa protocol `FeatureModule`, vòng đời khởi tạo, đăng ký phím tắt (KeyboardShortcuts), lưu trữ thiết lập (`SettingKey`), và quản lý thanh trạng thái `LiveActivity` / `ActivityCenter`.
2. **`NotchUI`**: Điều phối cửa sổ Notch nổi (`NSPanel` không chiếm focus), phát hiện tai thỏ phần cứng MacBook và render tai thỏ ảo trên màn hình ngoài; quản lý Animation 120fps mở rộng / thu gọn.
3. **`DebugTools`**: Cung cấp logger, tracer hiệu năng, và công cụ debug trạng thái module phục vụ chế độ phát triển mà không ảnh hưởng tới bản Release.
4. **Helper Daemons**: Bao gồm `mynotch-fan-helper` (chạy quyền root qua `SMAppService.daemon`) và `mynotch-youtube-host` kết nối Native Messaging Chrome Extension.

### Cơ Chế Vòng Đời & On-Demand Polling

Nhằm tối ưu pin trên MacBook, MyNotch sử dụng cơ chế cấu trúc nhu cầu (`Demand`):
- `visibleTabs > 0`: Khi notch được người dùng mở ra và tab của module đang hiển thị, module mới bắt đầu kích hoạt timer đọc dữ liệu (ví dụ đọc CPU mỗi 2 giây).
- `dropWhatNobodyShows()`: Khi tab đóng lại, toàn bộ bộ nhớ đệm và dữ liệu thời gian thực được huỷ bỏ ngay lập tức (`state.cpuUsage = nil`, `state.cpuProcesses = []`).
- Riêng chức năng điều khiển quạt (Fan Curve) có thể chạy ngầm độc lập khi được kích hoạt với mức tiêu thụ tài nguyên tối thiểu.

---

## 3. Danh Mục 18 Module Nghiệp Vụ

| Module | Mã Định Danh | Mặc Định | Quyền Yêu Cầu | Chức Năng & Điểm Nổi Bật |
|---|---|---|---|---|
| **Media** | `media` | Bật | Automation (AppleEvents) | Phát nhạc từ mọi app, sóng nhạc, karaoke theo chữ, click chuyển thẳng tới Tab YouTube/App phát. |
| **Performance** | `performance` | Bật | Root Helper (quạt) | % CPU tổng (Mach kernel), Top CPU process, nhiệt độ SoC, RAM, điều khiển quạt (Fan Curve). |
| **Screenshot** | `screenshot` | Bật | Screen Recording | Chụp màn hình, OCR, sửa ảnh, quay màn hình, zoom tự động theo click chuột, xuất MP4. |
| **Equalizer** | `equalizer` | Bật | Audio Capture | Bộ chỉnh âm 10 băng tần toàn hệ thống thay thế eqMac, không cần driver âm thanh, lưu profile. |
| **Clipboard** | `clipboard` | Bật | Accessibility (tuỳ chọn) | Lịch sử clipboard, tô màu mã nguồn, bảo mật board bằng mật khẩu, MCP server cho Claude/Codex. |
| **AI Agents** | `aiagents` | Bật | Automation | Giám sát trạng thái Claude Code & Codex, đếm token, duyệt yêu cầu quyền trực tiếp trên Notch. |
| **Pet (Thú cưng)** | `pet` | Bật | Không | 6 nhân vật pixel (mèo, capybara, hamster, chim cánh cụt, corgi, ếch) vui nhộn quanh camera. |
| **Dịch (Translation)** | `translation` | Bật | Accessibility (tuỳ chọn) | Dịch thuật trực tiếp trên máy bằng Apple Translation, bôi đen là hiểu, quy đổi đơn vị/múi giờ. |
| **Lịch (Calendar)** | `calendar` | Bật | Calendars, Reminders | Lịch trình trong ngày, thông báo cuộc họp trực tuyến kèm nút bấm Tham gia (Meet, Zoom, Teams). |
| **Việc cần làm (Todo)** | `todo` | Bật | Reminders | Quản lý công việc lưu trữ Apple Reminders, thêm nhanh 1 dòng, việc quá hạn tự đưa lên đầu. |
| **Cổng (Ports)** | `ports` | Bật | Không | Quét tiến trình đang lắng nghe cổng TCP/UDP, mở trình duyệt nhanh, kill process chiếm port. |
| **Battery** | `battery` | Bật | Không | Hiển thị trạng thái pin thanh ngang trực quan, công suất sạc watt, chu kỳ sạc, dung lượng tối đa. |
| **Hệ thống (System)** | `system` | Bật | Accessibility (tuỳ chọn) | Thay thế thanh HUD âm lượng, độ sáng macOS; thông báo pin Bluetooth, Caps Lock. |
| **Khay (Shelf)** | `shelf` | Bật | Không | Kéo thả file lên Notch; chuyển đổi định dạng ảnh/tài liệu, nén zip, tách nền, nhận dạng chữ OCR. |
| **Hẹn giờ (Timer)** | `timer` | Bật | Không | Đồng hồ đếm ngược Tập trung (Pomodoro), Nhắc việc, Nghỉ giải lao, bấm giờ trực tiếp. |
| **Shortcuts** | `shortcuts` | Bật | Không | Kích hoạt nhanh các phím tắt Apple Shortcuts trực tiếp từ danh sách trên Notch. |
| **Chia cửa sổ** | `windows` | Tắt | Accessibility | Kéo cửa sổ lên notch để chia nửa màn hình, chia tư, chia ba hoặc phóng to màn hình. |
| **Màn hình khoá** | `lockscreen` | Tắt | Không | Thử nghiệm widget phát nhạc và lời bài hát hiển thị ngay trên Lock Screen qua SkyLight. |

### Module Media & Smart Browser Tab Focus
- Theo dõi bài hát đang phát thông qua `mediaremote-adapter`.
- **Smart Browser Tab Activation**: Kết hợp `NSRunningApplication.activate` và AppleScript 4 tầng bất đồng bộ trong `Task.detached`:
  1. Tab có URL YouTube (`youtube.com`/`youtu.be`) và tiêu đề khớp `title`.
  2. Tab YouTube đầu tiên đang mở.
  3. Tab có tiêu đề khớp với bài hát (SoundCloud, Bandcamp...).
  4. Cửa sổ chính của trình duyệt.

### Module Hiệu Năng (Performance)
- **Đo % CPU Tổng**: Đọc từ Mach kernel API `host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, ...)`.
- **Top Tiến Trình CPU**: Sử dụng `proc_pid_rusage(pid, RUSAGE_INFO_V4, &info)` đo chính xác nano giây CPU tiêu thụ của từng PID. Bộ chọn `[CPU | RAM]` cho phép chuyển đổi nhanh.
- **Nhiệt độ SoC**: Đọc qua AppleSMC.
- **Quạt**: XPC daemon `mynotch-fan-helper` chạy quyền root qua `SMAppService.daemon`.

---

## 4. Cơ Chế Bảo Mật, Quyền TCC & Ký Mã (Code Signing)

### Bản Chất Hiện Tượng Mất Quyền Khi Build Mới

Khi build với cờ `CODE_SIGN_IDENTITY="-"` (Ad-hoc signing), macOS không thể neo quyền vào một Developer Certificate cố định. Thay vào đó, TCC lưu quyền theo **mã băm nhị phân (CDHash)** của ứng dụng. Mỗi lần sửa code và compile lại, CDHash thay đổi khiến macOS coi ứng dụng là một phần mềm lạ bị sửa đổi và tự động vô hiệu hoá toàn bộ quyền Trợ năng / Ghi màn hình đã cấp.

### Cấu Hình Ký Mã Chuẩn

Để macOS ghi nhớ quyền vĩnh viễn xuyên suốt các lần build, dự án bắt buộc phải được ký bằng chứng chỉ Apple Development với Team Identifier hợp lệ:

```yaml
# Trong project.yml:
settingGroups:
  signing:
    CODE_SIGN_STYLE: Automatic
    CODE_SIGN_IDENTITY: "Apple Development"
    DEVELOPMENT_TEAM: B394MAY4QN
```

Lệnh build giữ nguyên quyền TCC:
```bash
xcodebuild -scheme MyNotch -destination 'platform=macOS' \
  DEVELOPMENT_TEAM="B394MAY4QN" \
  CODE_SIGN_IDENTITY="Apple Development" build
```

Designated Requirement của app:
```text
designated => identifier "io.lucasvu.mynotch" and anchor apple generic and certificate leaf[subject.CN] = "Apple Development: dattruong19122003@gmail.com (3CHN565YD5)"
```

---

## 5. Hướng Dẫn Phát Triển, Kiểm Thử & Triển Khai

### Yêu Cầu Môi Trường
- macOS 26.0 trở lên.
- Xcode 26.6 (`xcode-select -p` trỏ đúng vào Xcode app).
- XcodeGen: `brew install xcodegen`.

### Lệnh Xây Dựng & Kiểm Thử Thường Dùng
```bash
# 1. Sinh lại file project Xcode từ project.yml:
xcodegen generate

# 2. Chạy test cho một package cụ thể:
swift test --package-path Packages/Modules/Performance
swift test --package-path Packages/Modules/Media

# 3. Chạy toàn bộ test gate kiểm tra toàn diện:
./scripts/verify.sh

# 4. Build và triển khai bản vào /Applications:
xcodebuild -scheme MyNotch -destination 'platform=macOS' \
  DEVELOPMENT_TEAM="B394MAY4QN" CODE_SIGN_IDENTITY="Apple Development" build

# Cập nhật nhị phân và khởi chạy:
killall MyNotch || true
rm -rf /Applications/MyNotch.app
cp -R ~/Library/Developer/Xcode/DerivedData/MyNotch-*/Build/Products/Debug/MyNotch.app /Applications/
open /Applications/MyNotch.app
```

### Triết Lý Kiểm Thử
- Sử dụng Swift Testing framework (`@Suite`, `@Test`).
- Áp dụng mô hình **Fakes** thay vì dynamic mocks để bảo đảm hiệu năng và tính an toàn luồng dữ liệu.

---

## 6. Sổ Tay Bảo Trì & Xử Lý Sự Cố Thường Gặp (FAQ)

1. **Click vào bài hát không mở YouTube tab mà chỉ mở cửa sổ chung?**  
   *Khắc phục:* macOS yêu cầu cấp quyền Automation (AppleEvents). Khi click lần đầu, hãy bấm **Cho phép (Allow)** trên popup hệ thống.
2. **App bị mất quyền Trợ năng / Ghi màn hình sau khi cập nhật?**  
   *Khắc phục:* Build với cờ `CODE_SIGN_IDENTITY="Apple Development"` và `DEVELOPMENT_TEAM="B394MAY4QN"`. Sau đó vào **System Settings > Privacy & Security > Accessibility**, gạt Tắt rồi gạt Bật lại mục MyNotch 1 lần duy nhất để macOS cập nhật Designated Requirement.
3. **Kiểm tra hai bản MyNotch chạy đè nhau?**  
   *Khắc phục:* Luôn kiểm tra `pgrep -fl MyNotch` trước khi mở bản mới. Tránh chạy đồng thời bản trong DerivedData và bản trong `/Applications`.
4. **Các phím tắt mặc định toàn hệ thống:**  
   `⌃⌥N` (Mở / đóng Notch), `⇧⌘C` (Bảng nổi Clipboard), `⌃⌥S` (Chụp màn hình), `⌃⌥R` (Bắt đầu / dừng quay màn hình), `⌃⌥T` (Mở dịch thuật), `⌃⌥D` (Mở danh sách Todo).
