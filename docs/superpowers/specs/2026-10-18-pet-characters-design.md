# MyNotch: nhiều nhân vật, chọn riêng cho từng màn hình

- **Ngày:** 2026-10-18
- **Trạng thái:** Đã duyệt. Người dùng nói "làm hết đi", nên các lựa chọn không được hỏi đều là của người viết và có đánh dấu.
- **Nền:** module Pet hiện có, gồm mèo pixel, cổng dịch chuyển qua camera, mèo trong viên thuốc, và mỗi loại notch một stage (PET4).

## 1. Ý định

Người dùng thích con mèo nhưng muốn **nhiều nhân vật hơn**. Họ muốn **chọn riêng cho từng màn hình**: mỗi màn một con, hoặc nhiều con chung một màn, cả hai cách đều phải có. Nhân vật tiếp theo là **capybara**: ngâm mình trong nước, ăn cam, ngủ gật.

Người dùng đồng ý làm cả bốn con người viết đề xuất: hamster, chim cánh cụt, corgi, ếch.

## 2. Nhân vật

Tất cả là pixel art vẽ bằng code như con mèo, cùng tỉ lệ, đọc rõ trên nền sáng và nền tối. Con nào cũng đi qua cổng dịch chuyển ở màn có tai thỏ và chơi được trong viên thuốc.

| Nhân vật | Tính cách | Hoạt động riêng (tối thiểu) |
|---|---|---|
| Mèo (đã có) | Hiếu động | Giữ nguyên |
| **Capybara** | Thư thái, chậm | Ngâm mình trong chậu hoặc suối nước nóng, đôi khi có quả cam trên đầu; ăn cam (bóc, nhai); ngủ gật (gật gù, bong bóng ngủ); đi chậm. **Không bao giờ hoảng** khi máy bận: chỉ đổ mồ hôi hoặc ngâm nước lâu hơn (lựa chọn của người viết). |
| **Hamster** | Chăm chỉ | Chạy bánh xe, **máy càng bận thì bánh xe càng quay nhanh** (theo tải CPU đã đo sẵn); nhét hạt đầy má; cuộn tròn ngủ; đi lon ton. |
| **Chim cánh cụt** | Vụng về | Lạch bạch đi; **nằm sấp trượt** một mạch, kể cả qua cổng; câu cá; trượt ngã rồi đứng dậy. |
| **Corgi** | Tăng động | Đuổi bóng; chạy vòng vòng như điên; vẫy mông; ngồi xin ăn khi con trỏ lại gần. |
| **Ếch** | Lười, thích rình | Nhảy cóc; nằm trên lá sen; **thè lưỡi bắt bướm đêm** (bướm đêm đã có sẵn). |

**Chơi chung với capybara** (khi capybara ở chung màn với con khác; tần suất do người làm chọn, vừa phải):
- mèo leo lên ngồi trên lưng capybara;
- ếch ngồi trên đầu capybara khi nó ngâm nước;
- hamster trốn sau lưng capybara;
- chim cánh cụt trượt tới đứng cạnh;
- corgi nằm xuống bên cạnh.

## 3. Chọn theo màn hình

- Cài đặt có danh sách **các màn hình đang cắm** (tên màn hình, kèm "màn có tai thỏ" hoặc "màn rời"). Mỗi màn chọn **một hoặc nhiều** nhân vật, hoặc **không con nào**.
- Mặc định: mỗi màn có một con mèo, giữ đúng hành vi hiện tại. Màn cắm vào lần đầu cũng nhận mặc định này.
- Lựa chọn được nhớ theo **mã ổn định của màn hình** (UUID của display), nên rút ra cắm lại vẫn giữ.
- **Tối đa 3 nhân vật mỗi màn** (lựa chọn của người viết), vì chỗ chơi hẹp: hai cánh 100 pt bên camera, viên thuốc 280 pt.
- Nhiều nhân vật chung một làn:
  - mỗi con có bộ não riêng;
  - được đi ngang qua nhau, nhưng **không dừng lại chồng lên nhau**;
  - không cùng lúc đứng trong vùng cổng.
- Mỗi màn hình một stage (đổi từ "mỗi loại notch một stage" của PET4), vì lựa chọn giờ là theo màn. Hai cánh của một notch vẫn chung một stage và một đồng hồ.
- Tên module hiển thị đổi từ "Mèo" thành **"Thú cưng"** (lựa chọn của người viết). Id vẫn là `pet`, nên cài đặt cũ giữ nguyên.

## 4. Không làm

- Nhân vật do người dùng tự vẽ hoặc tải về.
- Âm thanh riêng cho từng con. Riêng tiếng meo của mèo giữ như cũ.
- Đồng bộ một con chạy từ màn này sang màn khác.

## 5. Không được xảy ra

- Nhân vật nằm dưới camera, hoặc nháy hình khi quay đầu. Đây là các lỗi đã sửa ở PET3 và PET4.
- Nặng máy: thêm nhân vật không được làm CPU khi rảnh tăng đáng kể. Màn không có nhân vật nào thì không chạy gì.
- Mất lựa chọn của người dùng khi cắm hoặc rút màn hình.

## 6. Thứ tự làm

1. **PET5 (khung):**
   - tách "loài" ra khỏi con mèo: bộ não, cảnh và bộ hình riêng cho từng loài;
   - mỗi màn một stage;
   - cài đặt theo từng màn hình, chọn nhiều con;
   - làn chung cho nhiều con;
   - đổi tên module.

   Chỉ có mèo, chưa thêm loài mới. Hành vi của mèo không đổi.
2. **PET6:** capybara, kèm nước, cam và các kiểu chơi chung (khung cho các kiểu chơi chung với loài khác).
3. **PET7:** hamster. **PET8:** chim cánh cụt. **PET9:** corgi. **PET10:** ếch.
4. **PET11:** đủ các kiểu chơi chung giữa capybara và từng loài.

Mỗi bước có test đầy đủ, chạy kiểm tra toàn bộ, cài lên máy, rồi quay màn hình kiểm tra.
