# Ghi chú triển khai: Trạng thái AI agent (Claude Code, Codex)

- **Ngày:** 2026-10-14
- **Spec:** [Trạng thái AI agent (dự án con 5)](../specs/2026-10-13-ai-agents-design.html). Spec không bị sửa; chỗ đã lỗi thời nằm ở mục "Sửa lại spec".
- **Package:** `Packages/Modules/AIAgents`, product `AIAgentsModule` và `AgentHookKit`. Module id `aiagents` ("AI agents", order 500), tab "AI" (cao 200 pt), live activity `agent`, bật mặc định, không có quyền. Helper CLI: target `mynotch-hook` (`Tools/mynotch-hook/main.swift`) trong `project.yml`.
- **Commit chính:** `67ccc84` parser, `1b007f1` store và theo dõi file, `60c5a5a` module, `46eab02` hook kit, server, installer, `fc1443e` nối trạng thái chính xác, `33bbe96` gắn vào app, `e2b0586` nhúng helper, `806d2c3` sửa sau review (đếm usage Codex một lần, công tắc hook, helper ổn định), `2a8be48` đồng bộ đường dẫn socket với thư mục lưu trữ cùng dòng lỗi trong Settings.
- **Test tự động:** 374 test theo báo cáo `A6-fix2-report` (360 sau `806d2c3`; đã chạy `rm -rf .build` rồi `swift test` ba lần, 0 cảnh báo). Mọi fixture tự viết theo hình dạng record, không có hội thoại thật; test không bao giờ đọc hay ghi `~/.claude` hoặc `~/.codex` thật. Chưa chạy lại khi viết tài liệu này.
- **Kiểm thử tay:** [mục AI agents trong checklist gộp](../../manual-test-checklist-all.html#ai-agents)

## 1. Đã xây gì so với spec

- **Mức 0 (mặc định, không sửa cấu hình):** `JSONLTailer` đọc tiếp theo offset; `ClaudeTranscriptParser` và `CodexRolloutParser` thuần; `ClaudeSessionRegistry` đọc `~/.claude/sessions/*.json` và kiểm tra PID; `AgentWatcher` dùng FSEvents qua protocol `AgentFileSystem`. Mỗi agent một watcher. Khi khởi động, đọc 64 KB cuối file để dựng lại lượt hiện tại.
- **`AgentSessionStore`:** phiên theo (nguồn, sessionId), máy trạng thái working, waitingForInput, finished (5 giây rồi idle), idle, error; xoá phiên khi `SessionEnd`, khi PID chết hoặc sau 2 giờ không sự kiện; usage trong ngày khử trùng theo `message.id` (Claude) và theo tổng cộng dồn (Codex); chi phí lấy từ `cost-state` nếu có, không thì ước tính theo bảng giá đi kèm và ghi "ước tính".
- **Giao diện:** activity `agent` cập nhật tại chỗ (đang làm: glyph xoay kèm thời gian chạy; chờ người dùng: "!" cam, ưu tiên `.high`; xong: ✓ trong `finishedSeconds`). Tab "AI": mỗi phiên một dòng (dự án, nhánh, trạng thái, tool, thời gian), cuối tab là token và chi phí hôm nay mỗi agent cùng rate limit của Codex. Click một phiên mở thư mục trong Terminal; menu ngữ cảnh "Mở thư mục" và "Copy đường dẫn".
- **Mức 1 (tuỳ chọn):** `AgentHookKit` (allow-list trường, datagram tối đa 2 KB, luôn thoát mã 0, không in gì), `AgentEventServer` (socket datagram Unix, thư mục 0700, `SO_RCVBUF` 256 KB), `HookInstaller` (plugin cục bộ cho Claude Code, gộp và gỡ hook trong `settings.json` và `~/.codex/hooks.json` kèm sao lưu), nút cài trong Settings có hộp xác nhận xem trước.
- **Lỗi mở socket hiện trong Settings:** `HookListenStatus` (`@Observable`, do module giữ) được đặt khi `server.start()` ném lỗi, xoá khi thành công, khi tắt công tắc và khi `stopWatching`; `AIAgentsSettingsView` hiện nó bằng chữ đỏ dưới công tắc "Trạng thái chính xác" ("Không mở được socket nhận hook nên trạng thái chính xác chưa hoạt động. Tắt rồi bật lại để thử lại.", không có đường dẫn; chi tiết nằm trong log). Một socket không mở được cũng chỉ bị thử lại sau khi tắt rồi bật (`listenFailed`), không thử lại ở mỗi lần đổi cài đặt.
- **Cài đặt `module.aiagents.*`:** `claudeEnabled` (true), `codexEnabled` (true), `showWorkingActivity` (true), `finishedSeconds` (5, từ 2 đến 30), `preciseStatus` (false).
- **Helper:** target `mynotch-hook` được nhúng vào `Contents/MacOS/mynotch-hook` và ký cùng app. Khi cài hook, nó được chép sang bản ổn định (mục 2).

## 2. Sai khác so với spec và lý do

- **`preciseStatus` là công tắc của người dùng, không phải cờ chỉ đọc `preciseStatusInstalled`.** Các nút cài bật công tắc này sau khi ghi thành công (kể cả khi "đã cài từ trước"), nhưng nút gỡ không tắt nó: gỡ hook Claude không được làm app thôi nghe Codex, và đường plugin được gỡ bằng `claude plugin uninstall` mà app không thấy.
- **Đường dẫn helper trong lệnh hook là bản chép ổn định** `~/Library/Application Support/io.lucasvu.mynotch/Modules/aiagents/bin/mynotch-hook`, không phải `<bundle id>/bin/` như spec §2 (module chỉ biết thư mục lưu trữ của chính nó, cùng nơi đặt socket). Bản trong app (`Contents/MacOS/mynotch-hook`) chỉ là nguồn để chép; nút cài từ chối ghi gì nếu bản nhúng thiếu hoặc không chạy được.
- **Lệnh hook có guard và timeout:** `P='<đường dẫn>'; [ -x "$P" ] && exec "$P" --source <nguồn>; exit 0`, `"timeout": 5` ở mọi mục (settings.json, hooks.json, hooks.json của plugin). Helper thiếu hoặc bị xoá thì thoát mã 0 im lặng, không sinh "hook error" trong Claude Code hay Codex. Nút "Gỡ" vẫn nhận ra cả dạng lệnh cũ không guard.
- **Hook của nguồn đã tắt bị bỏ:** `claudeEnabled` và `codexEnabled` chặn cả sự kiện hook, đọc ngay khi datagram đến (tắt agent sau khi socket đã mở cũng có tác dụng).
- **Hook thắng suy luận từ transcript và từ registry** trong 60 giây sau một sự kiện hook của cùng phiên (`hooksDecideState`, dùng chung cho transcript và registry: một mục registry `busy` không còn đặt `.working` đè lên điều hook vừa báo; phiên khác không bị ảnh hưởng).
- **Usage Codex đếm một lần:** `DayUsageLedger` lấy tổng cao nhất đã thấy làm đường cơ sở và cộng 0 cho tổng thấp hơn, nên bật tắt agent nhiều lần (đọc lại rollout từ dòng 1) không đếm lại.
- **Thư mục socket dự phòng `/tmp/mynotch-<uid>` được kiểm chủ sở hữu:** thư mục đã có mà chủ không phải người dùng hiện tại thì `AgentEventServer.start()` ném `StartError.directoryNotOwned` trước khi tạo hay đổi quyền gì (`stat` theo cả liên kết). Module ghi log và dòng lỗi Settings áp dụng.
- **Ngắt lượt không có `Stop`:** quy tắc 90 giây của spec nay cũng áp cho `waitingForInput` của Claude khi registry báo idle (xem Ruling).
- **Bảng giá:** khớp tiền tố tên model, ký tự sau tiền tố không được là chữ số, sau dấu gạch chỉ không có chữ số hoặc đúng 8 chữ số (ngày); model có đuôi lạ như `claude-opus-5-9` hay `claude-opus-4-11` không có ước tính. Giá Claude lấy từ skill claude-api (cache 2026-10-06). **Giá Codex/OpenAI chưa được xác minh** (có comment trong code). Haiku 5.5 với prompt trên 100K token tính 0,50 và 2,50 USD; code bỏ qua điều này.
- **Không yêu cầu nhưng có:** nhãn "≥" khi chi phí chỉ một phần (ngày lẫn model có giá và không có giá); đường cơ sở qua nửa đêm trong `DayUsageLedger`; bấm một dòng phiên thì đóng notch.
- **Quyền riêng tư:** chỉ giữ tên tool và tóm tắt tối đa 120 ký tự (đầu lệnh Bash hoặc tên file), không bao giờ lưu hay hiện nội dung prompt hoặc câu trả lời.

## 3. Giới hạn đã chấp nhận (Ruling)

- **Ruling: dấu "!" chờ duyệt hết hạn sau 90 giây khi registry của Claude báo idle.** Agent không kiểm chứng được (không được đọc `~/.claude`). Giữ nguyên, và **người dùng phải kiểm tra** (để một prompt xin quyền của Claude Code mở hơn 90 giây rồi xem "!" còn không). **Chi phí nếu sai:** "!" biến mất với prompt để quá 90 giây; cách sửa là bỏ hạn hoặc gắn vào sự kiện hook (hoặc `statusUpdatedAt`).
- Các giới hạn khác đã chấp nhận: "waiting" của Codex không bao giờ hết hạn; nút gỡ không tắt `preciseStatus`; bản chép helper chỉ được làm mới ở lần bấm cài kế tiếp (không tự làm mới sau khi cập nhật app).
- Tổng usage của Codex dùng mức cao nhất đã thấy làm đường cơ sở và cộng 0 cho tổng thấp hơn (sửa lỗi đếm trùng Critical). Đánh đổi: bộ đếm thật sự khởi động lại trong cùng một phiên sẽ không được đếm cho tới khi vượt mức cũ.
- Phiên Codex chạy một tool im lặng hơn 90 giây hiện là idle cho tới khi có output (chấp nhận từ brief A3, có comment trong code).
- **Bỏ qua trong vòng sửa `806d2c3`:** Minor 4 (`cwd` trong payload hook bị bỏ, nên phiên chỉ có hook chưa hiện dự án), Minor 5 (installer ghi lại cả file qua `JSONSerialization`: khoá sắp xếp lại, số thực đổi dạng, mảng rỗng `"Stop": []` biến mất; chỉ tương đương về ngữ nghĩa), Minor 7 (lịch sử commit), và một phần Minor 6 (test cho `callbacksQueuedBeforeStopAreDropped` và các kiểm tra âm dùng `Task.sleep`, test "CLI không in gì"). Vòng `2a8be48` làm nốt dòng lỗi Settings, ba Minor khác của A6-fix và test đồng bộ đường dẫn socket.

## 4. Khoảng trống đã biết

- Định dạng transcript và rollout không được công bố và có thể đổi; parser chịu lỗi theo từng trường.
- "!" của một tool đã duyệt chạy lâu giữ tới `PostToolUse` (không có tín hiệu duyệt, chỉ có hạn giờ mà hạn giờ cũng ẩn các lần chờ thật).
- Codex nhấn Esc ở prompt duyệt trong vòng 60 giây sau hook `PermissionRequest`: `turn_aborted` bị bỏ qua do ưu tiên hook, "!" ở lại tới lần dọn 2 giờ.
- `AgentSocket` ghi cứng bundle id `io.lucasvu.mynotch` (helper không có bundle riêng). Từ `2a8be48` có `AgentSocketSyncTests`: so `defaultPath` với `StorageRoot` thật của app, so bundle id với `PRODUCT_BUNDLE_IDENTIFIER` của target `MyNotch` trong `project.yml` (test tìm file từ `#filePath` và báo lỗi nếu không thấy), so id module với `AIAgentsModule.descriptor.id`; mỗi so sánh đã được kiểm đột biến. Chưa có test cho việc `AIAgentsModule.listen` truyền `context.storage.directory` (thư mục tạm của harness dài hơn 103 byte nên sẽ rơi về `/tmp` thật).
- Dòng lỗi đỏ `HookListenStatus` trong Settings chưa ai thấy trên màn hình và không có test view.
- Chưa có test ghim việc "CLI không in gì" (cần chạy target CLI, không nằm trong dự án test).
- Bản Debug ký ad-hoc không có cờ `runtime` (Hardened Runtime) cho cả app lẫn helper; cần kiểm bản Release.
- Mở thư mục bằng app khác (spec §4.1 nói "có tuỳ chọn") chưa làm; chỉ có Terminal.
- Chưa có kết quả kiểm thử tay được ghi lại cho: phiên Claude Code và Codex thật, hiệu ứng pulse, cài hook thật, chờ duyệt quyền.

## 5. Sửa lại spec (Spec corrections)

- **§2 Mức 1, vị trí helper**: bản chép nằm ở `~/Library/Application Support/io.lucasvu.mynotch/Modules/aiagents/bin/mynotch-hook`; bản trong app ở `Contents/MacOS/mynotch-hook`.
- **§2 Mức 1, lệnh hook**: dạng có guard `[ -x ... ] && exec ...; exit 0` và `timeout` 5 giây; socket ở `.../Modules/aiagents/agent.sock` (dự phòng `/tmp/mynotch-<uid>/agent.sock` khi đường dẫn dài hơn 103 byte).
- **§3**: quy tắc 90 giây cũng áp cho `waitingForInput` của Claude khi registry idle; không áp cho Codex.
- **§4.2**: `preciseStatusInstalled` chỉ đọc không tồn tại; thay bằng `preciseStatus` (công tắc, mặc định false). `finishedSeconds` nằm trong khoảng 2 đến 30.
- **§4, bảng thành phần**: thêm `AgentHookKit` (library và product), `AgentSocket`, `HookHelper`, `HookSetup`, `DayUsageLedger`.
- **§4.1**: click phiên chỉ mở Terminal; chưa có tuỳ chọn app khác.
- **§4, thành phần**: thêm `HookListenStatus` (lỗi mở socket hiện trong Settings) và kiểm chủ sở hữu thư mục socket dự phòng (`directoryNotOwned`).

## 6. Cần kiểm thử tay

Xem [mục AI agents trong checklist gộp](../../manual-test-checklist-all.html#ai-agents). Cài hook thật **sửa file cấu hình của bạn** (`~/.claude/settings.json`, `~/.codex/hooks.json`, hoặc cài plugin Claude Code); app tạo bản sao lưu trước, nhưng hãy xem hộp xác nhận.
