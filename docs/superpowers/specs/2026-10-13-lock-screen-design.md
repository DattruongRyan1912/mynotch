# MyNotch — Widget trên màn hình khoá (dự án con 9)

- **Ngày:** 2026-10-13
- **Trạng thái:** Thiết kế, thử nghiệm
- **Nguồn:** kiểm tra các symbol SkyLight trên macOS 26.5.2 (có đủ) và các báo cáo cộng đồng. Đọc boring.notch chỉ để biết symbol nào được dùng, không chép mã.

## 1. Mục tiêu và giới hạn

Hiện một widget nhỏ ở vùng notch khi màn hình khoá: bài đang phát, hẹn giờ, pin.

- **Không có API công khai.** Không level `NSWindow` nào vẽ trên lớp khoá.
- Cách duy nhất là API riêng của SkyLight: tạo một "space" có level tuyệt đối 400 (`NotificationCenterAtScreenLock`), hiện space đó, rồi chuyển cửa sổ vào khi màn hình khoá.
- Có báo cáo cách này hỏng trên bản beta macOS 27. Vì vậy:
  - module **tắt mặc định**, ghi rõ "Thử nghiệm (API riêng)";
  - mọi symbol được nạp bằng `dlsym`; thiếu symbol nào thì module báo `unavailable`;
  - không dựa vào giá trị trả về của các hàm SLS, vì chúng có thể trả rác dù vẫn chạy.
- Chỉ hiện nội dung không nhạy cảm. Tên lịch, nội dung AI và clipboard không bao giờ hiện trên màn hình khoá.

## 2. Thiết kế

| Thành phần | Vai trò |
|---|---|
| `SkyLightShim` (NotchUI) | Nạp `SLSMainConnectionID`, `SLSSpaceCreate`, `SLSSpaceSetAbsoluteLevel`, `SLSShowSpaces`, `SLSSpaceAddWindowsAndRemoveFromSpaces`, `SLSRemoveWindowsFromSpaces` qua `dlsym` từ `/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight`. API Swift nhỏ: `isAvailable`, `makeLockScreenSpace()`, `attach(windowNumber:)`, `detach(windowNumber:)`. |
| `LockStateObserver` | Lắng nghe distributed notification `com.apple.screenIsLocked`/`com.apple.screenIsUnlocked`. Trạng thái ban đầu từ `CGSessionCopyCurrentDictionary()` (`CGSSessionScreenIsLocked`). Thêm `screensDidSleep/DidWake` và `sessionDidResign/BecomeActive`. |
| `LockScreenPanel` | Panel không activating, không bao giờ key, không nhận sự kiện. Đặt giữa cạnh trên màn hình chính, ngay dưới notch. |
| `LockScreenModule` | Khi khoá: dựng nội dung, gắn panel vào space. Khi mở khoá hoặc trước khi máy ngủ: tách ra, có trễ ngắn để không nháy. |

**Nội dung lấy từ đâu:** module không phụ thuộc module khác. MyNotchCore thêm một kênh chia sẻ chỉ đọc: `LockScreenContentCenter`. Media, Timer và Battery mỗi module đăng ký một view nhỏ, không nhạy cảm. LockScreen hiện view có ưu tiên cao nhất.

### 2.1 Cài đặt (`module.lockscreen.*`)

`showMedia` (true), `showTimer` (true), `showBattery` (false).

## 3. Kiểm thử

| Phần | Test tự động |
|---|---|
| `LockStateObserver` | Chuỗi thông báo giả → trạng thái; trạng thái ban đầu |
| `LockScreenContentCenter` | Đăng ký/huỷ, chọn theo ưu tiên |
| Module | `SkyLightShim` giả: gắn khi khoá, tách khi mở khoá và trước khi ngủ, không gắn khi shim không khả dụng |

**Kiểm thử tay:** khoá máy (⌃⌘Q) khi đang phát nhạc; mở khoá không còn sót cửa sổ; ngủ/thức; màn ngoài.
