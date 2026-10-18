# MyNotch: dọn dẹp dữ liệu

- **Ngày:** 2026-10-18
- **Trạng thái:** Đã duyệt trong chat ("chuẩn")
- **Hiện trạng:** khoảng 69 MB, gồm clipboard 58 MB, ảnh chụp 10 MB, còn lại khoảng 1 MB. Bản quay màn hình sắp có sẽ làm con số này tăng nhanh.

## 1. Ý định

Dùng lâu, MyNotch tích nhiều dữ liệu. Người dùng muốn **cả hai**: MyNotch **tự dọn theo quy tắc**, và có **nút dọn tay**.

## 2. Mục tiêu

- **Trang "Dung lượng" trong Cài đặt:**
  - Tổng dung lượng MyNotch đang dùng.
  - Danh sách theo module và theo nhóm, mỗi nhóm có dung lượng và nút **"Dọn"**.
  - Cuối trang có nút **"Dọn tất cả những thứ có thể dọn"**.
  - Trước khi xoá luôn hỏi lại và ghi rõ số MB sẽ giải phóng.
  - Dung lượng được đo lại khi mở trang và sau mỗi lần dọn.
- **Các nhóm:**
  - **Clipboard:** ảnh và file trong lịch sử, chỉ những mục **không ghim, không thuộc bảng nào, không khoá**; ảnh xem trước link; file tạm khi kéo thả.
  - **Chụp màn hình:** ảnh chụp, và sau này là bản quay màn hình.
  - **Nhạc:** bộ nhớ tạm lời bài hát, ảnh bìa và những thứ tương tự.
  - **Mọi module:** thư mục cache (`ModuleStorage.cachesDirectory`) của module đó. Theo định nghĩa thì cache dọn được, kể cả với module chưa khai báo nhóm riêng.
- **Tự dọn**, mặc định như sau và chỉnh được:
  - **Bộ nhớ tạm:** xoá thứ cũ hơn **30 ngày**, hoặc khi tổng vượt **200 MB** thì xoá từ cũ nhất.
  - **Lịch sử clipboard:** giữ quy tắc đang có (1 tháng, tối đa 500 mục). Trang Dung lượng hiện quy tắc đó và có link tới cài đặt Clipboard.
  - **Ảnh chụp màn hình:** giữ quy tắc đang có (30 ảnh gần nhất), hiện ra và có link như trên.
  - **Bản quay màn hình:** mặc định **không tự xoá**. Có tuỳ chọn "Xoá bản gốc đã xuất sau N ngày".
  - Tự dọn chạy khi app mở và sau đó mỗi 24 giờ, không bao giờ trong lúc đang quay hay đang xuất.
- **Không bao giờ dọn:**
  - mục đã ghim, các bảng và mục đã khoá trong clipboard;
  - hồ sơ EQ;
  - mọi cài đặt;
  - file người dùng đã xuất ra ngoài thư mục của MyNotch (video, ảnh đã lưu ở Desktop hay `~/Movies/MyNotch`).

## 3. Cách làm

- **Trong MyNotchCore:** protocol `StorageCleaning`, mà module nào có dữ liệu riêng thì tuân theo.
  - Nó khai báo các nhóm (id, tên, dung lượng, mô tả những gì được giữ lại).
  - Nó dọn một nhóm và trả về số byte đã giải phóng.
  - Nó dọn theo quy tắc.
- **Trong `ModuleRegistry`:** gom các provider lại.
- **Phần chung:** đo và dọn thư mục cache của mọi module.
- **Lịch tự dọn:** dùng `Scheduler` đã có.
- **Phải chạy cả khi module đang tắt:** dữ liệu của module tắt vẫn đo và dọn được. Chỉ dùng `ModuleStorage` và các file, không cần module đang chạy.
- **Trang Cài đặt:** một `SettingsPage` mới là `.storage`, nhãn "Dung lượng".

## 4. Thứ tự

1. **ST1:** Core (protocol, gom provider, phần cache chung, lịch tự dọn) và trang Cài đặt.
2. **ST2:** Clipboard.
3. **ST3:** Chụp màn hình và Nhạc. Bản quay màn hình sẽ thêm nhóm của nó khi có.
