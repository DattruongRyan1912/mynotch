# MyNotch — Dịch (dự án con 4)

- **Ngày:** 2026-10-13
- **Trạng thái:** Thiết kế, triển khai sau Screenshot
- **Nguồn:** nghiên cứu framework Translation trong SDK macOS 26.5. Đã thử thật: tạo session ngoài SwiftUI được; cặp vi↔en có sẵn để tải.

## 1. Mục tiêu

**Trong phạm vi:**

- Tab "Dịch" trong notch:
  - ô nhập văn bản;
  - tự nhận ngôn ngữ nguồn, chọn ngôn ngữ đích, nút đảo chiều;
  - kết quả copy được.
- Dịch đoạn chữ đang chọn trong app khác:
  - qua mục Services "Dịch bằng MyNotch": không cần quyền;
  - qua phím tắt ⌃⌥T: đọc vùng chọn bằng Accessibility.
- Chỉ dùng framework Translation của Apple. Dịch trên máy, không gửi dữ liệu ra ngoài.
- Quản lý gói ngôn ngữ: hiện trạng thái đã cài hay chưa và hướng dẫn cài.

**Ngoài phạm vi (để sau):**

- Dịch ảnh: OCR rồi dịch (ghép với dự án con 3 sau này).
- Popover gắn tại vị trí vùng chọn.
- Thay thế văn bản tại chỗ.
- Nhà cung cấp dịch trực tuyến.
- Fallback ⌘C để đọc vùng chọn. Nó phải sửa clipboard của người dùng và cần một cổng chặn trong MyNotchCore để Clipboard bỏ qua lần copy giả. Chỉ làm nếu thật sự cần.

## 2. Thiết kế

Package `Packages/Modules/Translation`, product `TranslationModule`. Không có quyền bắt buộc; `optionalPermissions: [.accessibility]`.

| Thành phần | Vai trò |
|---|---|
| `TranslationEngine` | MainActor. Mỗi cặp ngôn ngữ đã cài có một `TranslationSession(installedSource:target:)`, được cache. `translate(text, from:to:)` trả kết quả hoặc lỗi có kiểu: `notInstalled`, `unsupported`, `failed`. Không nuốt lỗi. |
| `LanguageDetector` | `NLLanguageRecognizer` giới hạn trong các ngôn ngữ được hỗ trợ. Độ tin cậy thấp thì dùng ngôn ngữ nguồn người dùng chọn gần nhất. Quy tắc đảo: nếu ngôn ngữ phát hiện trùng ngôn ngữ đích thì đổi đích sang ngôn ngữ còn lại của cặp ưa thích (mặc định vi⇄en). |
| `LanguageInstaller` | Nút "Cài gói ngôn ngữ" mở một cửa sổ nhỏ dạng activating (app chuyển `.regular`). Cửa sổ chứa view SwiftUI có `.translationTask(config) { try await $0.prepareTranslation() }`. Nếu sheet hệ thống không hiện, mở System Settings › Chung › Ngôn ngữ & Vùng › Ngôn ngữ dịch và kiểm tra lại trạng thái mỗi 2 giây. |
| `SelectionReader` | Đọc chữ đang chọn qua AX: system-wide → app đang focus → element đang focus → `kAXSelectedTextAttribute`, timeout 0,25 giây. Với app Chromium/Electron đã biết, bật `AXManualAccessibility` hoặc `AXEnhancedUserInterface` trước rồi thử lại trong tối đa 600 ms. Không đọc được thì mở tab trống. |
| `ServicesProvider` | `NSServices` trong Info.plist (`NSSendTypes = public.utf8-plain-text`, tên menu "Dịch bằng MyNotch"). App đặt `NSApp.servicesProvider` (thông qua MyNotchCore: module đăng ký handler dịch vụ theo tên). Mở tab với đoạn chữ nhận được. |
| Tab "Dịch" | `acceptsKeyboard: true`, cao 220 pt. Ô nhập (Return để dịch, ⇧Return xuống dòng), hai menu ngôn ngữ, nút đảo, kết quả có nút copy, băng rôn trạng thái gói ngôn ngữ. |

### 2.1 Điểm nối nền tảng cần thêm

`ServiceRegistry` trong MyNotchCore:
- module đăng ký handler `(String) -> Void` cho một tên dịch vụ;
- app là `servicesProvider` và chuyển tiếp lời gọi tới handler;
- tên dịch vụ phải khớp khai báo `NSServices` trong `project.yml`.

### 2.2 Cài đặt (`module.translation.*`)

| Khoá | Mặc định |
|---|---|
| `preferredPair` | `vi` ⇄ `en` |
| `targetLanguage` | `vi` |
| `autoTranslateOnOpen` | true (dịch ngay chữ nhận được qua Services hoặc phím tắt) |
| `useChromiumAccessibility` | true |

## 3. Rủi ro

- Sheet tải gói ngôn ngữ có thể không hiện khi app ở dạng accessory. Đã có lối dự phòng là System Settings.
- `TranslationSession` không `Sendable`: giữ trên main actor.
- Bật accessibility cho Chromium có tác dụng phụ (Chrome chuyển chế độ trình đọc màn hình). Có tuỳ chọn tắt.
- AX có thể treo: luôn đặt timeout.

## 4. Kiểm thử

| Phần | Test tự động |
|---|---|
| `LanguageDetector` | vi/en rõ ràng, độ tin cậy thấp, quy tắc đảo |
| `TranslationEngine` | Qua protocol giả: cache session, ánh xạ lỗi `notInstalled` → trạng thái UI |
| Module | Start/stop, phím tắt, nhận chữ từ handler Services → tab mở với chữ đó |

Không gọi Translation thật trong unit test (phụ thuộc gói đã cài).

**Kiểm thử tay:** cài gói vi↔en; dịch trong tab; Services trong Safari, Notes và Chrome; phím tắt khi đã có quyền Accessibility; thiếu gói ngôn ngữ.
