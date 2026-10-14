# Ghi chú triển khai: Trạng thái AI agent (Claude Code, Codex)

- **Ngày:** 2026-10-14
- **Spec:** [Trạng thái AI agent (dự án con 5)](../specs/2026-10-13-ai-agents-design.html). Spec không bị sửa; chỗ đã lỗi thời nằm ở mục "Sửa lại spec".
- **Package:** `Packages/Modules/AIAgents`, product `AIAgentsModule` và `AgentHookKit`. Module id `aiagents` ("AI agents", order 500), tab "AI" (cao 200 pt), live activity `agent`, bật mặc định, không có quyền. Helper CLI: target `mynotch-hook` (`Tools/mynotch-hook/main.swift`) trong `project.yml`.
- **Commit chính:** `67ccc84` parser, `1b007f1` store và theo dõi file, `60c5a5a` module, `46eab02` hook kit, server, installer, `fc1443e` nối trạng thái chính xác, `33bbe96` gắn vào app, `e2b0586` nhúng helper, `806d2c3` sửa sau review (đếm usage Codex một lần, công tắc hook, helper ổn định), `2a8be48` đồng bộ đường dẫn socket với thư mục lưu trữ cùng dòng lỗi trong Settings. Sau đó (2026-10-14 tối đến 2026-10-15): `043560f` "đang làm" thành `.low`, `2ec7afb` và `94f5f64` kiểm tra "xong" có hạn, `44a2ace` và `d133d1e` glyph nhấp nháy trên render server.
- **Test tự động:** 383 test theo báo cáo PERF1 (374 ở `A6-fix2-report`; 377 sau `043560f`; 380 sau `94f5f64`; 383 sau PERF1). Mọi fixture tự viết theo hình dạng record, không có hội thoại thật; test không bao giờ đọc hay ghi `~/.claude` hay `~/.codex` thật. Chưa chạy lại khi viết tài liệu này. `AgentWatcherTests` nhạy thời gian: từng đỏ một lần trong `verify.sh` khi máy bận (4 kỳ vọng file-event), qua khi chạy lại; nếu lại chập chờn, nhìn `AgentActivityViewsTests` trước (PERF1 mục 5.6).
- **Kiểm thử tay:** [mục AI agents trong checklist gộp](../../manual-test-checklist-all.html#ai-agents)

## 1. Đã xây gì so với spec

- **Mức 0 (mặc định, không sửa cấu hình):** `JSONLTailer` đọc tiếp theo offset; `ClaudeTranscriptParser` và `CodexRolloutParser` thuần; `ClaudeSessionRegistry` đọc `~/.claude/sessions/*.json` và kiểm tra PID; `AgentWatcher` dùng FSEvents qua protocol `AgentFileSystem`. Mỗi agent một watcher. Khi khởi động, đọc 64 KB cuối file để dựng lại lượt hiện tại.
- **`AgentSessionStore`:** phiên theo (nguồn, sessionId), máy trạng thái working, waitingForInput, finished (5 giây rồi idle), idle, error; xoá phiên khi `SessionEnd`, khi PID chết hoặc sau 2 giờ không sự kiện; usage trong ngày khử trùng theo `message.id` (Claude) và theo tổng cộng dồn (Codex); chi phí lấy từ `cost-state` nếu có, không thì ước tính theo bảng giá đi kèm và ghi "ước tính".
- **Giao diện:** activity `agent` cập nhật tại chỗ (đang làm: glyph nhấp nháy kèm thời gian chạy, ưu tiên `.low`; chờ người dùng: "!" cam, ưu tiên `.high`; xong: ✓ trong `finishedSeconds`, là notice có hạn). Ba thay đổi từ 2026-10-14 tối ở mục 7. Tab "AI": mỗi phiên một dòng (dự án, nhánh, trạng thái, tool, thời gian), cuối tab là token và chi phí hôm nay mỗi agent cùng rate limit của Codex. Click một phiên mở thư mục trong Terminal; menu ngữ cảnh "Mở thư mục" và "Copy đường dẫn".
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
- **Glyph "đang làm" nhấp nháy bằng độ mờ, không phải `symbolEffect(.pulse)`** (PERF1, `44a2ace`): chi tiết ở mục 7. Spec và các câu trong mục này nói "glyph xoay" hay "pulse" lúc đầu; code nay là độ mờ 1 → 0,35.
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
- **Chưa so bằng mắt:** hiệu ứng nhấp nháy mới (độ mờ 1 → 0,35, mỗi chiều 0,8 giây, `NotchPulse.dimmedOpacity` và `halfPeriod`) với hiệu ứng pulse của symbol; hai AI "xong" chồng nhau thì activity không được `set` lại nên check thứ hai bị cắt ngắn (khoảng 3 giây thay vì 5, Minor review UI2b).

## 5. Sửa lại spec (Spec corrections)

- **§2 Mức 1, vị trí helper**: bản chép nằm ở `~/Library/Application Support/io.lucasvu.mynotch/Modules/aiagents/bin/mynotch-hook`; bản trong app ở `Contents/MacOS/mynotch-hook`.
- **§2 Mức 1, lệnh hook**: dạng có guard `[ -x ... ] && exec ...; exit 0` và `timeout` 5 giây; socket ở `.../Modules/aiagents/agent.sock` (dự phòng `/tmp/mynotch-<uid>/agent.sock` khi đường dẫn dài hơn 103 byte).
- **§3**: quy tắc 90 giây cũng áp cho `waitingForInput` của Claude khi registry idle; không áp cho Codex.
- **§4.2**: `preciseStatusInstalled` chỉ đọc không tồn tại; thay bằng `preciseStatus` (công tắc, mặc định false). `finishedSeconds` nằm trong khoảng 2 đến 30.
- **§4, bảng thành phần**: thêm `AgentHookKit` (library và product), `AgentSocket`, `HookHelper`, `HookSetup`, `DayUsageLedger`.
- **§4.1**: click phiên chỉ mở Terminal; chưa có tuỳ chọn app khác.
- **§4, thành phần**: thêm `HookListenStatus` (lỗi mở socket hiện trong Settings) và kiểm chủ sở hữu thư mục socket dự phòng (`directoryNotOwned`).
- **§3, ưu tiên activity (UI2)**: "đang làm" là `.low` (không phải `.normal`) để nhạc đang phát luôn là chính; "chờ" `.high`; "xong" `.normal` có `expiresAfter = finishedSeconds + 1 giây` (notice). Spec không có cái nào trong ba chỗ này.
- **§3, giao diện**: glyph "đang làm" dùng `.notchPulse` (độ mờ, render server) thay cho hiệu ứng symbol lặp (mục 7).

## 6. Cần kiểm thử tay

Xem [mục AI agents trong checklist gộp](../../manual-test-checklist-all.html#ai-agents). Cài hook thật **sửa file cấu hình của bạn** (`~/.claude/settings.json`, `~/.codex/hooks.json`, hoặc cài plugin Claude Code); app tạo bản sao lưu trước, nhưng hãy xem hộp xác nhận.

## 7. Ba thay đổi từ 2026-10-14 tối (UI2, PERF1)

- **"Đang làm" là `.low` (`043560f`).** Việc nền của agent kéo dài hàng giờ và có thể bắt đầu trước nhạc; với luật "cái sống đầu tiên thắng" một agent `.normal` đến trước sẽ ở lại làm chính và nhạc (cùng dải lời) bị đẩy vào bubble. Ở `.low` nhạc luôn là chính, agent là bubble; "chờ" (`.high`) tạm lên chính và nhạc vào bubble tới khi người dùng trả lời; "xong" giữ `.normal`. Test: `workingRunsAtLowPriorityAndFinishedAtNormal`, `workingNeverHidesMediaThatStartedLater`, `waitingTakesTheNotchFromMediaAndMediaStepsBackIn` (một test khác, `workingNeverHidesMediaThatStartedFirst`, qua cả khi `.normal` vì luật dính, nên không kiểm thay đổi này).
- **Kiểm tra "xong" là notice (`2ec7afb`, `94f5f64`).** Activity "xong" có `expiresAfter = finishedSeconds + 1 giây` (`AIAgentsModule.finishedExpiryMargin`), nên theo luật mới nó chiếm notch vài giây kể cả khi nhạc đang phát rồi trả lại; "đang làm" và "chờ" không có hạn. **Bộ hẹn giờ của store vẫn nằm đó** vì nó không chỉ là đồng hồ của activity: nó chuyển phiên từ `finished` sang `idle` (tab, các dòng phiên, `AgentActivityContent`). Lý do của 1 giây dôi ra (`94f5f64`): bản đầu dùng đúng `finishedSeconds`, hai hạn chạm cùng lúc dưới scheduler tay, center xoá mục trong cùng một lần `advance` còn `module.publishedActivity` (theo store qua một bước quan sát) vẫn đọc `.finished`, nên `aFinishedTurnShowsACheckmarkThenClears` đỏ. Với hạn của center chậm sau bộ hẹn giờ của store 1 giây, module luôn hành động trước, hạn của center chỉ để đánh dấu notice và làm lưới an toàn. Độ dài người dùng thấy không đổi. Test mới `AgentFinishedNoticeTests` (4). **Ruling** ở ghi chú nền tảng, mục 3; **hạn chế:** hai lần "xong" chồng nhau thì không gì `set` lại activity nên hạn của center tính từ lần đầu (Minor review UI2b).
- **Glyph nhấp nháy trên render server (`44a2ace`, `d133d1e`).** Thủ phạm của 16 đến 20 % CPU (PERF1, ghi chú nền tảng mục 11) là `Image(systemName:).symbolEffect(.pulse, options: .repeating)` của glyph "đang làm" trong `AgentActivityViews.swift`: SwiftUI vẽ lại nó theo tần số làm tươi (120 hay 144 Hz), mỗi lần qua `NSHostingView.layout()`. `AgentActivityLeading` nay dùng `.notchPulse` (nội dung trong một hosting view riêng, độ mờ do `CABasicAnimation` chạy trên render server, gỡ khi notch ngoài màn hình). **Ngoài phạm vi PERF1 được giao** (AIAgents), một dòng, hoàn lại riêng được. Số đo thật: 3,7 đến 5,2 % CPU với nhạc cộng bubble Claude, từ 16 đến 20 %.
