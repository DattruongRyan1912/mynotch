# Ghi chú triển khai: Dịch

- **Ngày:** 2026-10-14
- **Spec:** [Dịch (dự án con 4)](../specs/2026-10-13-translation-design.html). Spec không bị sửa; chỗ đã lỗi thời nằm ở mục "Sửa lại spec".
- **Package:** `Packages/Modules/Translation`, product `TranslationModule`. Module id `translation`, tab "Dịch" (order 400, cao 220 pt, nhận bàn phím), bật mặc định. Không có quyền bắt buộc; `optionalPermissions: [.accessibility]`.
- **Điểm nối Core và app:** `ServiceRegistry` và `ModuleServices` trong MyNotchCore, `App/ServicesProvider.swift`, mục `NSServices` trong `project.yml` ("Dịch bằng MyNotch").
- **Commit chính:** `41a6f5d` và `a75ea22` engine, detector, selection reader; `af75ff2` Services trong Core và app; `57d1a85` và `2bd557a` module; `3fc9482` hàng đợi Services 10 giây; `2655167` gắn vào app (cùng Media).
- **Test tự động:** 82 test theo báo cáo L1 (`verify.sh` qua ở `8a2b842`). Test không gọi framework Translation thật. Chưa chạy lại khi viết tài liệu này.
- **Kiểm thử tay:** [mục Dịch trong checklist gộp](../../manual-test-checklist-all.html#translation)

## 1. Đã xây gì so với spec

- Chỉ dùng framework Translation của Apple, dịch trên máy. `AppleTranslationEngine` giữ một `TranslationSession(installedSource:target:)` cho mỗi cặp đã cài, trên main actor; lỗi có kiểu `notInstalled`, `unsupported`, `failed`, không nuốt lỗi.
- `LanguageDetector` dùng `NLLanguageRecognizer` giới hạn trong các ngôn ngữ hỗ trợ; độ tin cậy từ 0,5 trở lên mới ghi đè ngôn ngữ nguồn đã chọn gần nhất; quy tắc đảo: nếu nguồn trùng đích thì đích đổi sang ngôn ngữ còn lại của cặp ưa thích (mặc định vi và en).
- `SelectionReader` đọc vùng chọn qua Accessibility (timeout 0,25 s), và với app Chromium/Electron đã biết (Chrome, Edge, Brave, Arc, Vivaldi, Opera, Slack, Discord, VS Code, Cursor, Notion, Obsidian, Figma...) bật `AXManualAccessibility` hoặc `AXEnhancedUserInterface` rồi thử lại tối đa 600 ms khi `useChromiumAccessibility` bật.
- Tab: ô nhập nhiều dòng (Return dịch, ⇧Return xuống dòng), menu ngôn ngữ nguồn (kèm "Tự nhận diện") và đích, nút đảo, kết quả có nút copy, băng rôn trạng thái gói ngôn ngữ. Phím tắt ⌃⌥T (`translateSelection`).
- `LanguageInstallerWindow`: cửa sổ nhỏ chứa `.translationTask { try await $0.prepareTranslation() }`; app chuyển `.regular` khi mở và về `.accessory` chỉ khi không còn cửa sổ titled nào khác; có nút mở System Settings và kiểm lại trạng thái mỗi 2 giây.
- Cài đặt `module.translation.*`: `preferredPair` (vi và en), `targetLanguage` (vi), `autoTranslateOnOpen` (true), `useChromiumAccessibility` (true); danh sách trạng thái từng cặp kèm nút cài.
- Services: module đăng ký handler dịch vụ `translate` qua `context.services`; app là `NSApp.servicesProvider` và chuyển tiếp. Handler tự huỷ khi module dừng.

## 2. Sai khác so với spec và lý do

- **Dịch khi gõ:** ngoài Return, tab còn dịch sau 600 ms ngừng gõ (`typingDelay`, qua `context.scheduler`). Spec chỉ nêu Return. Thêm theo brief T3.
- **Hàng đợi Services (P9, `3fc9482`):** chọn dịch vụ làm MyNotch khởi động, hệ thống gửi yêu cầu trong lúc module chưa chạy. `ServiceRegistry` giữ yêu cầu mới nhất của mỗi tên trong 10 giây và giao cho handler đầu tiên đăng ký. Spec §2.1 không có hàng đợi.
- Dịch tuần tự và báo huỷ rõ ràng (`a75ea22`); nhận diện ngôn ngữ trên toàn bộ danh sách hỗ trợ, cặp ưa thích luôn đứng đầu danh sách ứng viên để "en" không thành "en-AU".

## 3. Giới hạn đã chấp nhận (Ruling)

Ledger không có dòng `Ruling:` nào riêng cho Dịch. Điểm đã biết từ `HANDOFF.md` mục 5:

- Ở commit `8a2b842`, khi module Dịch đang tắt, yêu cầu từ menu Services bị giữ 10 giây rồi bỏ im lặng, người dùng không thấy lỗi. Chi phí: bấm "Dịch bằng MyNotch" khi module tắt thì không có phản hồi nào. Một bản sửa đang được làm riêng và **chưa commit** khi viết tài liệu này: `ServiceRegistry.finishStartup()` kết thúc giai đoạn khởi động, sau đó yêu cầu không ai xử lý bị từ chối và menu Services hiện "Mô-đun Dịch của MyNotch chưa chạy. Hãy bật mô-đun Dịch trong Cài đặt MyNotch." Nếu bản sửa đó vào, mục này và mục 5 cần cập nhật.

## 4. Khoảng trống đã biết

- Ở `8a2b842`, `App/ServicesProvider.swift` có nhánh báo lỗi "Mô-đun Dịch của MyNotch chưa chạy." khi `registry.handle` trả `false`, nhưng `ServiceRegistry.handle` luôn trả `true` (đưa vào hàng đợi), nên nhánh này không bao giờ chạy: mâu thuẫn giữa code app và Core. Bản sửa chưa commit ở mục 3 làm nhánh này chạy được sau giai đoạn khởi động.
- Fallback ⌘C để đọc vùng chọn không làm, vì nó phải sửa clipboard của người dùng và cần cổng chặn trong Core để Clipboard bỏ qua lần copy giả.
- Chromium: bật AX có thể thất bại với `kAXErrorAttributeUnsupported`, và editor kiểu Monaco vẫn thường không trả gì (research). Bật AX cho Chromium có tác dụng phụ (Chrome chuyển chế độ trình đọc màn hình); có tuỳ chọn tắt.
- Sheet tải gói ngôn ngữ có thể không hiện khi app ở dạng accessory; lối dự phòng là System Settings.
- Chưa có kết quả kiểm thử tay được ghi lại cho: gói vi và en, Services trong Safari, Notes và Chrome, phím tắt có Accessibility, thiếu gói ngôn ngữ.

## 5. Sửa lại spec (Spec corrections)

- **§2, hàng "Tab"**: thêm dịch khi gõ sau 600 ms ngừng gõ.
- **§2.1, `ServiceRegistry`**: thêm hàng đợi một yêu cầu mới nhất cho mỗi tên trong 10 giây; ở `8a2b842` `handle` luôn trả `true` (bản sửa chưa commit: chỉ trả `true` trong giai đoạn khởi động, sau `finishStartup()` trả `false` cho yêu cầu không ai xử lý).
- **§2, hàng `LanguageInstaller`**: là cửa sổ regular chứa `.translationTask`; trả về `.accessory` chỉ khi không còn cửa sổ titled nào khác.
- **§2.2**: cài đặt có thêm danh sách trạng thái gói theo cặp trong Settings.
- **Dòng trạng thái** "Thiết kế, triển khai sau Screenshot" đã lỗi thời: module đã triển khai và gắn vào app.

## 6. Cần kiểm thử tay

Xem [mục Dịch trong checklist gộp](../../manual-test-checklist-all.html#translation). Các mục đụng quyền: phím tắt ⌃⌥T cần Accessibility; Services không cần quyền.
