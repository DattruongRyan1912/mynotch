# Ghi chú triển khai: Việc cần làm (Todo)

- **Ngày:** 2026-10-15
- **Spec:** không có spec thiết kế riêng; yêu cầu nằm trong brief T1 (danh sách việc trong ngày trên notch, lưu trong Apple Reminders, có chuyển việc quá hạn sang hôm sau). Người dùng chọn "Apple Reminders cộng chuyển việc tồn". Tài liệu này là nguồn mô tả kiến trúc.
- **Package:** `Packages/Modules/Todo`, product `TodoModule`. Module id `todo` ("Việc cần làm", **order 650**, tab cùng tên, icon `checklist`), **bật mặc định**, quyền **tuỳ chọn** Lời nhắc (`Permission.reminders`). Chỉ phụ thuộc MyNotchCore và NotchUI (không import Calendar). Ghép vào `project.yml` và `App/ModuleList.swift`.
- **Commit:** `463ba0a` (module), `943d82c` (quyền Lời nhắc thành tuỳ chọn, tab hiện trước khi có quyền), `b33834b` (sửa review: việc lặp, focus, hai lỗi đọc tiếng Việt).
- **Test tự động:** 172 test trong 11 suite ở `b33834b` (142 sau `943d82c`, 138 ở `463ba0a`), ba lần chạy sạch, 0 cảnh báo. Mọi test dùng nguồn dữ liệu giả; **đường đọc và ghi EventKit thật chưa được test tự động nào chạm tới**, và cơ sở dữ liệu Lời nhắc thật không bị đụng.
- **Kiểm thử tay:** [nhóm Việc cần làm trong checklist gộp](../../manual-test-checklist-all.html#todo). Quyền: Lời nhắc (đặt lại bằng `tccutil reset Reminders io.lucasvu.mynotch`).

## 1. Đã xây gì

- **Danh sách hôm nay** (`TodoToday`, thuần): các việc **chưa xong** đến hạn hôm nay hoặc **quá hạn** từ mọi danh sách không bị ẩn, cộng việc **không có ngày** của danh sách mặc định (công tắc "Cả việc không có ngày", mặc định bật). Thứ tự: quá hạn trước (cũ nhất trước), rồi hôm nay theo giờ (có giờ, rồi chỉ có ngày, rồi không ngày), ưu tiên cao trước khi hoà. Mỗi hàng: ô tích theo màu danh sách, tiêu đề (tối đa 2 dòng), nhãn "hôm qua" hay "quá hạn N ngày", giờ, dấu ưu tiên (!, !!, !!!), chấm màu danh sách, và glyph lặp (`repeat`, nhãn trợ năng "Lặp lại") cho việc có quy tắc lặp. Đầu tab ghi "Hôm nay" cùng tiến độ "Xong 4/7" (xong hôm nay trên tổng danh sách).
- **Tích xong:** hàng bị gạch ngay (lạc quan, trước khi EventKit trả lời); việc lưu chạy ở nguồn dữ liệu; hàng ở lại 2 giây (`lingerDuration`) với nút "Hoàn tác" rồi biến mất; hoàn tác bỏ trạng thái xong. Lưu hỏng thì hàng quay lại cùng dòng 3 giây "Không cập nhật được việc này."; hoàn tác hỏng thì hàng vẫn gạch, "Hoàn tác" ở lại thêm 2 giây và hiện cùng dòng đó (không biến mất).
- **Thêm nhanh:** ô "Thêm việc…" ở đầu tab. Return tạo việc ở danh sách mặc định, đến hạn hôm nay cả ngày. Bộ phân tích `TodoQuickAddParser` (tiếng Việt và tiếng Anh, dấu tuỳ chọn): đầu dòng `!`, `!!`, `!!!` là ưu tiên thấp, vừa, cao; giờ `15h`, `15h30`, `15:30`, `3 giờ chiều`, `3pm`, `3:30 pm`, có thể có `lúc`, `at` hay `@` trước; ngày `mai`, `ngày mai`, `tomorrow`, `hôm nay`, `today`, `chiều mai`, `tối nay`. Những gì đã đọc được hiện ở mép phải ô ("Ngày mai · 15:00 · !!") để thấy trước khi nhấn Return. Esc xoá chữ; **Esc trên ô trống đóng notch**. Thêm việc cho ngày khác hiện dòng 3 giây "Đã thêm cho ngày mai." (nếu không việc sẽ biến khỏi danh sách hôm nay); lưu hỏng hiện "Không thêm được việc. Nhấn Return để thử lại.".
- **Chuyển việc tồn:** không lưu gì ở MyNotch. Lời nhắc giữ việc quá hạn và danh sách đặt chúng lên đầu. Danh sách được đọc lại khi nhận `NSCalendarDayChanged`, khi máy thức dậy (đệm 1 giây, `refreshDebounce`), và khi tab mở sau một nửa đêm bị lỡ.
- **Phím tắt** (đổi được ở trang Shortcuts của app; không trùng mặc định nào đã có): **⌃⌥D** mở tab, **⌃⌥⇧D** mở tab và đưa con trỏ vào ô thêm nhanh. Chú ý: ⌃⌥ cũng là tổ hợp phím sửa của VoiceOver, chỉ liên quan khi VoiceOver bật.
- **Activity trên notch:** cài đặt "Hiện số việc còn lại" (mặc định **tắt**). Ưu tiên thấp, `summary` "Còn 3 việc", `minimal` là vòng tiến độ (xong trên tổng). Chỉ hiện khi còn việc và đã có quyền; activity ưu tiên thường (nhạc) giữ vị trí chính.
- **Đồng bộ:** `TodoService.changes` nghe `EKEventStoreChanged`, gộp (yên lặng 1 giây, chờ tối đa 5 giây). Mọi việc EventKit nằm trong một actor (`TodoService`), ngoài main actor. Việc sửa trên iPhone hay trong app Lời nhắc hiện ra trong vài giây.
- **Cài đặt:** hàng quyền (nút "Cho phép…"), "Cả việc không có ngày", "Danh sách cho việc mới" (mặc định "Danh sách mặc định của hệ thống"), "Hiện số việc còn lại", "Danh sách hiển thị" (một công tắc mỗi danh sách).

## 2. Quyền Lời nhắc là tuỳ chọn (T1 follow-up `943d82c`)

Bản đầu khai báo quyền bắt buộc, nên module (và tab) không khởi động cho tới khi cấp quyền ở Settings. Theo yêu cầu của người điều phối, quyền thành **tuỳ chọn**: module chạy khi chưa có quyền, tab có từ lần chạy đầu và hiện một gợi ý cùng nút **"Cho phép truy cập Lời nhắc"**; **chỉ cú bấm đó mới xin quyền** (không có hộp thoại nào lúc khởi động). Người đã từ chối thấy nút "Mở Cài đặt hệ thống" (như Calendar). Sau khi cấp (bằng nút hay ở System Settings) danh sách tự tải không cần chạy lại: quyền được kiểm lại khi tab mở và khi app thành active (`NSApplication.didBecomeActiveNotification`), và chỉ đọc lại khi danh sách đang hiện sai so với quyền hay ngày. Lý do hiện cho hàng quyền: "Đọc, thêm và đánh dấu xong các việc trong Lời nhắc." Mô tả quyền trong `Info.plist` (`NSRemindersFullAccessUsageDescription`): "MyNotch hiển thị, thêm và đánh dấu xong lời nhắc trong notch."

## 3. Việc lặp: EventKit đưa ra lần xuất hiện kế tiếp (review T1 I1)

Tài liệu EventKit của Apple ("Creating a recurring event") nói: với việc lặp, chỉ việc chưa xong đầu tiên của chuỗi lấy được; khi nó xong, việc kế tiếp trong chuỗi hiện ra. Nên đặt `isCompleted` rồi lưu là đủ và **MyNotch không tự tính lần lặp kế**; hành vi này được ghim trong nguồn dữ liệu giả (tích việc lặp thì nó xong và có thêm lần xuất hiện kế; bỏ tích thì lần kế đó mất). Test: việc lặp được đánh dấu; tích nó giữ hàng (gạch, có hoàn tác) và tính vào "Xong n/m" trong khi lần kế (ngày mai) không lên danh sách hôm nay; việc lặp trễ quay lại thành lần kế vẫn trễ; **hoàn tác khôi phục kho và danh sách đúng như trước**. **Chưa kiểm với một việc lặp hằng ngày thật:** lần xuất hiện kế có cùng `calendarItemIdentifier` hay khác, và bỏ tích làm gì với lần đã thay chỗ. Module đọc lại sự thật sau mỗi lần lưu nên tự hồi phục dù thế nào, nhưng hoàn tác của việc lặp là phần không chứng minh được nếu không có kho thật. Câu thứ hai của tài liệu cũng có nghĩa việc xong ở client khác có thể có `isCompleted == true` mà không có `completionDate`; `TodoToday` bỏ chúng khỏi "Xong n/m" (khoảng trống đã biết, test `aCompletedReminderWithoutADateIsNotToday`).

## 4. Bộ phân tích thêm nhanh: các lựa chọn đã ghim bằng test

- **Giờ đã qua vẫn là hôm nay** (hiện màu đỏ); số trần không bao giờ là giờ; `3h` trần là 03:00 trừ khi có buổi trong ngày.
- **"mai" chỉ tính khi viết thường và ở đầu hay cuối dòng:** "gọi Mai" và "hoa mai đẹp" giữ nguyên. Dòng chỉ gồm ngày hay giờ giữ nó làm tiêu đề.
- **Buổi trong ngày + từ chỉ ngày (review I3):** "3h chiều nay", "8h sáng nay", "8h tối nay", "9h sáng mai" lấy cả từ chỉ ngày đứng sau, ở bất kỳ chỗ nào trong dòng ("họp 3h chiều mai với Lan" cho tiêu đề "họp với Lan"). Có cả thứ tự ngược ("họp chiều nay 3h").
- **"tôi" không phải "tối" (review I4):** buổi trong ngày khớp theo chữ **có dấu** như đã gõ ("sáng", "trưa", "chiều", "tối", "đêm", "khuya"); "tôi", "tới", "tội" không bao giờ là buổi. Không dấu ("toi", "chieu", "sang", "dem") chỉ tính ngay sau một giờ và chỉ khi dòng kết thúc ở đó hay từ kế là từ chỉ ngày ("9h toi", "9h toi nay", "3h chieu mai"); "9h toi can chuan bi", "9h sang nha Lan", "9h dem laptop" giữ nguyên chữ. Bảng test có 109 cụm.
- **Dấu câu:** "tomorrow.", "15h,", "3h chiều?" vẫn được đọc; nhập nhằng "mua hoa mai" giữ như đã ghi.
- **Lịch khác (Phật lịch, Nhật…):** hạn được đọc bằng lịch Gregorian cùng múi giờ (Apple: lịch của thuộc tính này phải là Gregorian, nếu không sẽ có ngoại lệ). Hạn chỉ có ngày không bao giờ mang múi giờ riêng.
- **Báo thức:** việc có giờ nhận một `EKAlarm(absoluteDate:)` đúng giờ đến hạn (`TodoAlarm.fireDate`); việc chỉ có ngày thì không. Tài liệu im lặng ở đây nên đây là theo cách công tắc "Time" của Lời nhắc hoạt động chứ không phải quy tắc có tài liệu; một dòng trong `TodoService.create` bỏ nó đi nếu không muốn. Chưa kiểm với kho thật.
- **Đọc hỏng:** `TodoServiceError.fetchFailed`; tab giữ danh sách đang có, hiện "Không đọc được Lời nhắc." cùng "Thử lại", không nói "chưa có việc nào" và giữ số trên notch. Lần đọc tốt kế tiếp, nút, hoặc mở lại tab xoá dòng đó.

## 5. Focus của ô thêm nhanh (review T1 I2)

Chỉ phím tắt thêm nhanh mới xin focus. Yêu cầu là trạng thái dùng một lần của module (`TodoState.pendingFocus`): ô nhận nó khi xuất hiện hay khi nó được nâng lên trong lúc đã gắn (`takeFocusRequest()` xoá nó), nên một lần mở sau, một cú bấm tab hay ⌃⌥D gắn ô và không thấy gì để phục vụ. Yêu cầu cũng hết hạn sau 2 giây nếu notch không bao giờ mở (`focusRequestLifetime`, ví dụ app fullscreen) và đi cùng module. Các chỗ gọi trong view (`onAppear`, `onChange`) **không có test tự động** (hosting ngoài màn hình không bắn `onAppear`): cần mắt xác nhận rằng một lần mở thường để con trỏ yên.

## 6. Quyết định và Ruling

- **Danh sách chỉ lưu cái bị ẩn, không lưu cái được chọn** (giống Calendar): mặc định "mọi danh sách" và danh sách mới tự hiện. Danh sách bị ẩn cũng ẩn việc không ngày của nó. "Việc không ngày của danh sách mặc định" nghĩa là danh sách mặc định chọn ở Settings, nếu không thì danh sách hệ thống dành cho việc mới, nếu không thì danh sách đầu tiên nhận được lời nhắc.
- **`ChangeCoalescer` chép từ Calendar** (module không được phụ thuộc nhau). Nên đưa vào MyNotchCore sau; chưa làm vì brief không cho đụng MyNotchCore. Chi phí nếu sai: hai bản có thể lệch nhau.
- **Tab chỉ đọc lại khi mở nếu quyền hay ngày đã đổi**, không đọc ở mỗi lần mở; mở tab chỉ cập nhật đồng hồ mà các hàng dùng để phán "trễ" (không đọc).
- **Không nhận biết việc đã xong ở client khác mà thiếu `completionDate`** (xem mục 3) và **không xử lý xung đột sửa đồng thời** (M4 của review: cần kho thật).
- **Không hoãn M10, M11, M14** (hằng cứng của danh sách đã kiểm tay; hiếm).

## 7. Cần kiểm thử tay

Xem [nhóm Việc cần làm trong checklist gộp](../../manual-test-checklist-all.html#todo): ⌃⌥D và ⌃⌥⇧D; lần chạy đầu và cấp quyền không cần chạy lại; bề rộng 480 pt; tích xong và hoàn tác; thêm "gọi khách 15h30 mai", "!!! nộp báo cáo", "mua sữa" rồi xem trong app Lời nhắc; sửa ở iPhone hay Lời nhắc; **việc lặp hằng ngày thật**; Esc trên ô trống; activity "Còn N việc"; con trỏ không bị cướp bởi một lần mở thường.
