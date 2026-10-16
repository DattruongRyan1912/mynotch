# MyNotch YouTube Bridge

Extension Chrome nhỏ (Manifest V3) làm hai việc cho ứng dụng MyNotch trên cùng máy:

1. Chuyển phụ đề mà YouTube đã tải sẵn trong trang sang MyNotch, để notch hiển thị làm lời bài hát đồng bộ.
2. Báo cho MyNotch biết tab nào đang phát hoặc đang tạm dừng âm thanh/video (trên mọi trang web), để tab Media của notch cho bạn chuyển giữa các nguồn đang phát (Music, Spotify, các tab Chrome) và điều khiển từng nguồn.

## Cách hoạt động

- Khi bạn bật phụ đề (CC) trên một video YouTube, trình phát tự tải phụ đề. Extension chỉ đọc bản sao của phản hồi đó trong trang, không tự gọi mạng và không liên lạc với YouTube.
- Dữ liệu đi qua Native Messaging tới `mynotch-youtube-host` rồi tới MyNotch, toàn bộ nằm trong máy bạn.

**Được gửi cho MyNotch (YouTube):** mã video, tiêu đề video, vị trí phát hiện tại, trạng thái phát/tạm dừng, tốc độ phát và nội dung phụ đề (thời điểm, độ dài, chữ).

**Được gửi cho MyNotch (mọi trang có media):** tên miền của trang (chỉ tên miền, ví dụ `music.example.com`, không có đường dẫn), tiêu đề, nghệ sĩ và album mà trang tự khai trong Media Session (nếu không có thì tiêu đề tài liệu), trạng thái phát/tạm dừng, vị trí, độ dài, tốc độ phát, có phải phát trực tiếp hay không, nguồn của nó là một phần tử `<video>`/`<audio>` hay chỉ là lời khai trong Media Session (`element`), và Chrome có đang nghe thấy tab này phát âm thanh hay không (`audible`: service worker hỏi Chrome, trang không tự khai được; không cần thêm quyền nào).

**Chẩn đoán:** extension cũng gửi vài mã chẩn đoán rất ngắn (extension đã khởi động, Chrome có cho extension đọc YouTube hay không, số tab YouTube đang mở đã được nạp script, kết nối với host thế nào, số sự kiện phụ đề đã đọc, lỗi gửi tin, lệnh Bài sau/Bài trước đã làm được hay không). Chúng chỉ gồm mã cố định và con số, không chứa tiêu đề, URL, mã video hay chữ của phụ đề, và MyNotch chỉ ghi chúng vào nhật ký hệ thống của máy.

**Nhận từ MyNotch:** hai loại lệnh cố định, đều là bộ đóng (không có trường nào chứa chữ tự do). Một là "Bài sau" (`next`) và "Bài trước" (`previous`) cho YouTube, khi bạn bấm nút trên notch hoặc dùng phím tắt: extension kiểm tra lại rồi chuyển cho tab YouTube vừa báo trạng thái phát gần nhất. Hai là lệnh cho một tab cụ thể mà notch đang hiển thị: `play`, `pause`, `toggle`, `next`, `previous` hoặc `seek` (kèm số giây). Mỗi bước (MyNotch, host, service worker, script trong trang) kiểm tra lại và chỉ chuyển tiếp lệnh mình đã kiểm tra.

**Không bao giờ gửi:** URL (kể cả URL phụ đề có token và địa chỉ trang), đường dẫn, cookie, thông tin tài khoản, ảnh bìa, biểu tượng trang hay bất cứ thứ gì ngoài các trường trên. Extension không tự gọi mạng: nó không tải ảnh bìa hay favicon, nên tab Chrome mà macOS không coi là "đang phát" sẽ hiện biểu tượng Chrome và tên miền thay cho ảnh bìa.

## Cài đặt

1. Trong MyNotch, mở Cài đặt của module Media, bật "Phụ đề YouTube làm lời" rồi bấm **Cài cầu nối cho Chrome**. MyNotch cài host, ghi manifest cho Chrome và sao chép extension vào `~/Library/Application Support/io.lucasvu.mynotch/ChromeExtension`.
2. Mở `chrome://extensions`, bật **Developer mode**.
3. Bấm **Load unpacked** và chọn thư mục `~/Library/Application Support/io.lucasvu.mynotch/ChromeExtension`.
4. Mở một video trên `www.youtube.com` và **bật phụ đề (CC)**. Không bật CC thì không có phụ đề nào được gửi; khi xem video, extension vẫn gửi các trường phát lại đã nêu ở trên (mã video, tiêu đề, vị trí, trạng thái phát, tốc độ), và chỉ những trường đó.

### Cập nhật tự động

Khi MyNotch khởi động, nếu bạn đã cài cầu nối trước đó (thư mục `ChromeExtension` và manifest của host trong thư mục của Chrome đều có), và extension trong app có phiên bản mới hơn bản đã cài (so từng số, `0.10` mới hơn `0.9`), hoặc host đã cài khác host trong app, MyNotch thay bản đã cài bằng bản trong app (chép sang một thư mục tạm cạnh đó rồi đổi chỗ, nên chép lỗi thì bản cũ còn nguyên). MyNotch không bao giờ cài khi bạn chưa cài, không bao giờ hạ phiên bản, không ghi vào thư mục của Chrome và không đụng tới Chrome. Sau đó MyNotch hiện một thông báo ngắn (và một dòng trong Cài đặt của Media) nhắc **tải lại extension trong `chrome://extensions`**, vì Chrome vẫn chạy file cũ cho tới khi extension được tải lại.

### Quyền đọc mọi trang web

Để biết tab nào đang phát media, extension cần chạy một script nhỏ trên mọi trang `https` (khung chính), nên manifest xin quyền trang web `https://*/*`. Trang `http` thường (không mã hoá) không được báo; ngoại lệ duy nhất là `http://localhost/*`, để thử một trang phát nhạc tự viết. (Từ phiên bản 0.2.1, `http://*/*` đã bỏ: gần như mọi trang phát media thật đều dùng https, và một trang không mã hoá có thể bị bất kỳ ai trên đường truyền sửa nội dung nên không nên là nguồn mà notch tin.) Script này không làm gì trên trang không có media: chỉ có vài trình nghe sự kiện media, và nó chỉ bắt đầu báo khi một phần tử `<video>` hoặc `<audio>` bắt đầu phát. Video tắt tiếng, âm thanh giao diện và clip dưới 5 giây bị bỏ qua, trừ khi trang tự đặt tiêu đề trong Media Session (nghĩa là nó là trình phát). Video/audio nằm trong iframe không được báo.

Cuộc gọi và phát trực tiếp từ camera/micro không phải là nhạc: một phần tử mà nguồn của nó là luồng trực tiếp (`srcObject` là `MediaStream`, cách trang họp nhận tiếng của người khác) và mọi phần tử trên các trang họp quen thuộc (Google Meet, Zoom, Teams, Whereby, Webex, Jitsi, GoToMeeting, Skype, Chime) đều bị bỏ qua, trừ khi trang đặt tiêu đề trong Media Session.

Một script thứ hai chạy trong chính trang (MAIN world) chỉ để ghi nhận những gì trang tự khai trong Media Session: tiêu đề/nghệ sĩ/album, trạng thái phát/tạm dừng (`playbackState`), vị trí (`setPositionState`) và những hàm xử lý mà trang đã đăng ký (phát, tạm dừng, tua, bài sau, bài trước). Nhờ vậy nhận ra cả trang phát bằng một `Audio` không nằm trong tài liệu (nhiều trình phát web làm vậy, và sự kiện media của tài liệu không bao giờ thấy nó), và khi bạn bấm nút trong MyNotch, nó gọi đúng hàm xử lý đó của trang, như nút media của Chrome. Khi trang có phần tử `<video>`/`<audio>` trong tài liệu thì phần tử đó là nguồn chính (vị trí chính xác hơn) và Media Session chỉ bổ sung. Script gọi hàm gốc trước và trả kết quả nguyên vẹn, không đọc gì khác của trang.

Extension chỉ chạy ở cửa sổ thường: manifest không khai `incognito`, nên Chrome để **Cho phép ở chế độ ẩn danh** (Allow in Incognito) tắt, và nên để nguyên như vậy. Thư mục extension đã cài nằm trong Application Support của bạn, nên chương trình nào chạy dưới tài khoản của bạn và ghi được vào đó cũng đổi được extension: quyền đọc mọi trang https làm việc đó đáng kể hơn khi extension chỉ đọc YouTube.

Script của YouTube (`content.js`) vẫn nằm cùng mục với script này (Chrome chỉ nạp một file một lần cho mỗi tài liệu, và hai script cần cùng `captions.js` trong cùng một world) nhưng tự kiểm tra địa chỉ và không làm gì ngoài `www.youtube.com`.

### Quyền truy cập trang web

Chrome cho đặt quyền truy cập trang web của từng extension. Nếu để **Khi nhấp** (On click), Chrome không nạp extension vào YouTube nên không có gì được gửi sang MyNotch, và extension không thể tự sửa việc đó. Hãy mở `chrome://extensions`, bấm **Details** ở "MyNotch YouTube Bridge", chọn **Quyền truy cập trang web** (Site access) là **Trên tất cả trang web** (hoặc **Trên các trang web cụ thể** rồi thêm `www.youtube.com`). Extension báo trạng thái này cho MyNotch, và MyNotch hiện lời nhắc trong Cài đặt khi Chrome đang chặn.

### Tab YouTube đã mở sẵn

Chrome chỉ nạp script của extension vào trang mở sau khi extension có mặt. Vì vậy sau khi cài, cập nhật hoặc tải lại extension, và khi bạn vừa cho phép truy cập YouTube, extension tự nạp lại script vào các tab đang mở (quyền `scripting`; mỗi script chỉ vào những tab mà phạm vi của nó nêu: script YouTube chỉ vào tab `www.youtube.com`, script media vào mọi trang web) để không phải tải lại từng tab. Lời nhắc "Chrome đang chặn" trong MyNotch chỉ nói về quyền đọc YouTube. Phụ đề mà trang đã tải trước đó không đọc lại được: chúng xuất hiện khi trình phát tải phụ đề lần nữa (tắt rồi bật lại CC, đổi ngôn ngữ phụ đề hoặc chuyển video).

### Bài sau và Bài trước

YouTube tự gỡ các nút "bài sau/bài trước" khỏi điều khiển media của Chrome, nên phím media của macOS không chuyển được bài trong YouTube (kể cả danh sách Mix). Khi nhận lệnh từ MyNotch, script của extension làm đúng như người dùng: bấm nút **Next** của trình phát (nút chỉ được bấm khi đang hiện và đang bật). Với **Previous**, nó bấm nút Previous của trình phát nếu có; nếu trình phát không có nút đó (video lẻ, không nằm trong danh sách) thì tua về 0 giây khi video đã chạy quá 3 giây, đúng như nút Previous của YouTube. Nút Previous của YouTube cũng tự quay về đầu video khi đã quá 3 giây, nên muốn về video trước hãy bấm hai lần.

Một video lẻ, không nằm trong danh sách phát, thường không có nút Next đang hiện (YouTube ẩn nó khi tự phát tiếp đang tắt), nên từ phiên bản 0.2.2 **Next** thử lần lượt: (1) nút Next của trình phát khi nó dùng được; (2) nếu nút đó là một liên kết tới video khác của YouTube thì bấm vào liên kết đó, kể cả khi nút đang ẩn (trừ khi trình phát đánh dấu nó bị tắt); (3) mục đầu tiên của "Tiếp theo" (Up next) ở cột bên; (4) liên kết của màn hình kết thúc. Mỗi bước chỉ là một cú bấm vào một liên kết tới video khác trên chính `www.youtube.com` (đường dẫn `/watch` có mã video hợp lệ, không phải video đang phát, không mở cửa sổ mới); mọi địa chỉ khác bị từ chối, và trang thường tự đi tiếp trong cùng tab mà không tải lại. **Previous**: nút Previous nếu có, nếu không thì tua về 0 giây khi video đã chạy quá 3 giây, nếu không (video mới bắt đầu) thì quay lại một trang trong lịch sử, nhưng chỉ khi trang trước đó là trang xem của một video khác (extension biết điều này qua Navigation API, chỉ cho cùng nguồn gốc); không biết được thì không làm gì. Khi quảng cáo đang chạy, không bước nào được thực hiện.

Script không tạo sự kiện bàn phím nào và không làm gì khi quảng cáo đang chạy. Mỗi lệnh để lại một mã chẩn đoán (`content-command next ok via=<button|href|upnext|endscreen>` cho Next, `via=<button|restart|history>` cho Previous, hoặc `unavailable reason=<ad|none|refused|error>`: quảng cáo đang chạy, không có chỗ nào để đi, mọi địa chỉ đều bị từ chối, hoặc trang gây lỗi; chỉ là các từ cố định, không có địa chỉ hay tiêu đề); nếu tab đã đóng, service worker báo `sw-command-no-tab` và bỏ lệnh. Các mã trả lời này không bị giới hạn tần suất vì MyNotch chờ mỗi lệnh một câu trả lời: không thấy gì sau 1 giây (host hoặc extension là bản cũ chưa biết lệnh) thì MyNotch dùng phím media của macOS cho lần bấm đó. Khi extension đã trả lời, kể cả `unavailable`, MyNotch không thử cách nào khác.

Mã extension (id) cố định nhờ khoá công khai trong `manifest.json`, id nằm trong file `EXTENSION_ID`. Cầu nối của MyNotch chỉ cho phép đúng id này kết nối.

### Nguồn nhạc từ các tab

Mỗi tab có media là một nguồn trong tab Media của notch. Tiêu đề là của Media Session; nếu trang không đặt thì là tiêu đề tài liệu (trên YouTube bỏ số thông báo ở đầu và hậu tố " - YouTube", ở trang khác giữ nguyên để trùng với tiêu đề mà macOS báo, nhờ đó MyNotch nhận ra một tab đang phát là một nguồn chứ không hai). Khi trình phát bị làm trống (YouTube làm vậy ở mỗi video kế tiếp và mỗi quảng cáo), extension chờ 2,5 giây xem có phát lại không rồi mới báo tab hết media; rời trang hoặc phần tử bị gỡ khỏi tài liệu thì báo ngay. Khi trang phát, tạm dừng, tua hoặc đổi bài, script báo ngay; khi đang phát nó báo lại mỗi 5 giây, khi đang tạm dừng mỗi 30 giây (MyNotch giữ một tab một hai phút không có tin). Một trang không thể làm ngập MyNotch: mỗi trang chỉ được báo tối đa bốn lần mỗi giây (cách nhau ít nhất 250 ms; trong khoảng đó tin cuối cùng thắng và luôn được gửi khi trang yên), service worker lại giới hạn mỗi tab ở một tin mỗi 200 ms và 64 tab, và ứng dụng cũng giới hạn mỗi tab 0,2 giây và 64 tab mỗi Chrome. Bộ đếm thời gian của script chạy mỗi giây khi trang đang phát và mỗi 5 giây khi đang tạm dừng, và chỉ chạy khi trang có media để báo.

Một trang chỉ có Media Session (không có phần tử media của tài liệu) nói gì cũng được, nên lời khai đó một mình không đủ để giành notch: tab chỉ được tính là đang phát để giành vị trí chính khi Chrome báo tab đang phát tiếng (`tab.audible`, không cần quyền `tabs`; xem tài liệu `chrome.tabs`) hoặc khi trang có phần tử media. Tab vẫn hiện như một nguồn trong tab Media để bạn tự chọn. Các tên mà script trong trang dùng để trao đổi với script của extension (cờ đánh dấu, nhãn thông điệp) là chuỗi vô nghĩa, không nêu tên extension, để một trang không nhận ra nó mà đáp lại. Khi trang không còn media, khi bạn rời trang hoặc đóng tab, MyNotch được báo là tab đó đã hết. Service worker không giữ danh sách tab nào ngoài bộ nhớ.

Phát, tạm dừng và tua tác động thẳng lên phần tử media khi trang có, nếu không thì qua hàm xử lý Media Session của trang. Với YouTube, "Bài sau/Bài trước" cho một tab cụ thể vẫn là các cú bấm nút của trình phát (như phần trên); với trang khác là hàm xử lý Media Session của chính trang đó, nếu có. Khi trang không có, lệnh báo `unavailable` (mã chẩn đoán `content-tabcommand next unavailable`) và không làm gì thêm. Vị trí của một trang chỉ có Media Session là vị trí trang khai gần nhất, chạy tiếp theo tốc độ phát; trang không khai vị trí thì hiện 0 và không có độ dài.

## Gỡ bỏ

- Trong `chrome://extensions`, bấm **Remove** ở "MyNotch YouTube Bridge".
- Trong MyNotch, bấm **Gỡ cầu nối** để xoá host và manifest Native Messaging.

## Phát triển

Chạy test (Node 24, không cần cài gói nào):

```sh
node --test Extensions/Chrome/MyNotchYouTube/tests/
```

`captions-page.js` là bản sao y hệt của `captions.js` dành cho MAIN world: Chrome chỉ nạp một file một lần cho mỗi tài liệu dù nó nằm trong nhiều mục `content_scripts`, nên cùng một file không thể có mặt ở cả hai world. Sau mỗi lần sửa `captions.js`, chạy `cp captions.js captions-page.js` (test báo lỗi nếu hai file khác nhau, và nếu một file xuất hiện ở hai mục).

Các file: `tabmessages.js` (thông điệp về tab media, thuần hàm, dùng ở script trang và service worker), `tabs.js` (script báo media của tab, isolated world), `mediasession-page.js` (MAIN world, Media Session của trang), `content.js` (YouTube), `page.js` (YouTube MAIN), `bridge.js` và `background.js` (service worker). Khi đổi phiên bản trong `manifest.json`, đổi cả ghim trong `tests/manifest.test.mjs`. Không đổi `key` trong manifest: id extension nằm trong `allowed_origins` của host.
