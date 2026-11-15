# MyNotch — Trạng thái AI agent (dự án con 5)

- **Ngày:** 2026-10-13
- **Trạng thái:** Thiết kế
- **Nguồn:** tài liệu hooks của Claude Code và Codex CLI. Cấu trúc file thật trên máy được đọc ở chế độ chỉ đọc, chỉ xem tên khoá, không xem nội dung hội thoại.

## 1. Mục tiêu

Thấy ngay trong notch khi Claude Code hoặc Codex đang làm việc, đang chờ mình, hay vừa xong. Kèm token và chi phí của từng phiên và trong ngày.

**Nguyên tắc:**

- Mặc định không sửa cấu hình của người dùng.
- Chế độ "trạng thái chính xác" (biết lúc agent chờ duyệt quyền) là tuỳ chọn và chỉ cài khi người dùng bấm nút. Trước khi cài, app hiện rõ thay đổi và tạo bản sao lưu.
- Không hiển thị hay lưu nội dung prompt hoặc câu trả lời. Chỉ hiện tên tool và một tóm tắt ngắn: phần đầu lệnh Bash hoặc tên file.
- `~/.claude/settings.json` của máy này đã có hook của Orca và rtk. MyNotch chỉ được **thêm cạnh** chúng, không bao giờ thay thế, và không đụng `statusLine`.

## 2. Nguồn dữ liệu

### Mức 0 (mặc định, không cấu hình)

| Nguồn | Dùng để |
|---|---|
| `~/.claude/sessions/<pid>.json` (`sessionId`, `cwd`, `status` busy/idle, `name`, `startedAt`) | Danh sách phiên đang chạy, bận/rảnh |
| `~/.claude/projects/<slug>/<sessionId>.jsonl` | Tool hiện tại (khối `tool_use` cuối), thời điểm bắt đầu lượt (record `user` cuối), kết thúc (`stop_reason == "end_turn"`), token (`message.usage`, **khử trùng theo `message.id`**), chi phí (`cost-state.totalCostUSD` nếu có) |
| `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl` | `task_started`, `task_complete`, `turn_aborted`, `token_count` (token + rate limit) |

- Theo dõi bằng FSEvents (thư mục) và `DispatchSource` (file đang ghi).
- Đọc tiếp từ offset đã lưu, giữ phần dòng chưa trọn.
- Các định dạng này không được công bố và có thể đổi. Parser phải phòng thủ: thiếu trường nào thì bỏ trường đó, không bỏ cả record.

### Mức 1 (tuỳ chọn, nút "Bật trạng thái chính xác")

- Helper `mynotch-hook`:
  - là CLI Swift nhỏ, nằm trong app bundle; được chép tới `~/Library/Application Support/io.lucasvu.mynotch/bin/` để có đường dẫn ổn định;
  - đọc JSON hook từ stdin, chỉ giữ các trường trong danh sách cho phép: nguồn, sự kiện, session, cwd, tool, tóm tắt ≤ 120 ký tự, `notification_type`, thời điểm;
  - gửi **một datagram** (≤ 2 KB) không chặn tới socket `agent.sock` của app;
  - luôn thoát mã 0 và không in gì, vì stdout của một số hook bị chèn vào context của Claude;
  - app không chạy thì bỏ qua.
- Claude Code, cách ưu tiên:
  - app sinh một plugin cục bộ (`hooks/hooks.json`);
  - Settings hiện hai lệnh `claude plugin marketplace add …` và `claude plugin install …` để người dùng tự chạy;
  - gỡ bằng `claude plugin uninstall`.
- Claude Code, cách thay thế "Ghi vào settings.json":
  - hiện diff và tạo bản sao lưu `settings.json.mynotch-<thời điểm>.bak`;
  - thêm nhóm matcher riêng cho mỗi sự kiện, đánh dấu bằng đường dẫn helper để gỡ sạch;
  - ghi atomic.
- Codex: gộp `~/.codex/hooks.json` (có sao lưu), rồi nhắc người dùng tin cậy hook trong `/hooks`. Không đụng `notify`.

## 3. Trạng thái phiên

| Sự kiện | Trạng thái |
|---|---|
| Lượt mới / `PreToolUse` / `PostToolUse` / registry `busy` | `working(tool?)` |
| `PermissionRequest`, `Notification` loại `permission_prompt`/`elicitation_dialog` | `waitingForInput` (chỉ có ở mức 1) |
| `Stop` / `end_turn` / `task_complete` | `finished` (5 giây) → `idle` |
| `StopFailure` / `turn_aborted` | `error` / `idle` |
| `SessionEnd` / PID chết / file registry bị xoá | xoá phiên |

Có ngắt lượt mà không có `Stop`: sau 90 giây không có sự kiện và registry báo `idle` thì chuyển về `idle`.

## 4. Thiết kế

Package `Packages/Modules/AIAgents`, product `AIAgentsModule`; target CLI `mynotch-hook` trong `project.yml`.

| Thành phần | Vai trò |
|---|---|
| `JSONLTailer` | Đọc tiếp file JSONL theo offset, dòng chưa trọn được giữ lại, xử lý file bị cắt hoặc đổi tên |
| `ClaudeTranscriptParser`, `CodexRolloutParser` | Thuần: record → sự kiện chuẩn hoá (`AgentEvent`) và usage |
| `ClaudeSessionRegistry` | Đọc `~/.claude/sessions/*.json`, kiểm tra PID còn sống |
| `AgentSessionStore` | `@Observable`: phiên theo `(nguồn, sessionId)`, máy trạng thái, thời gian đã chạy, usage hôm nay |
| `AgentEventServer` | Mức 1: socket datagram Unix, thư mục 0700, `DispatchSource.makeReadSource` |
| `HookInstaller` | Mức 1: sinh plugin, gộp/gỡ hook có sao lưu (thuần + test với thư mục tạm) |
| `UsageCalculator` | Token theo model; chi phí từ `cost-state`, nếu không có thì ước tính theo bảng giá đi kèm (ghi rõ "ước tính") |
| `AIAgentsModule` | Activity, tab, cài đặt |

### 4.1 Giao diện

- **Activity:**
  - đang làm việc: icon agent (Claude/Codex) + vòng xoay, bên phải là thời gian đã chạy;
  - chờ người dùng: icon + dấu "!" màu cam, ưu tiên `.high`;
  - vừa xong: dấu ✓ trong 5 giây.
- **Tab "AI":**
  - mỗi phiên một dòng: dự án (tên thư mục + nhánh git), trạng thái, tool hiện tại, thời gian;
  - cuối tab: token và chi phí hôm nay theo từng agent.
  - Click một phiên mở thư mục dự án trong Terminal. Mặc định không làm gì khác; có tuỳ chọn mở bằng app khác.

### 4.2 Cài đặt (`module.aiagents.*`)

`claudeEnabled` (true), `codexEnabled` (true), `showWorkingActivity` (true), `finishedSeconds` (5), `preciseStatusInstalled` (chỉ đọc, do installer ghi).

## 5. Kiểm thử

| Phần | Test tự động |
|---|---|
| Tailer | Ghi thêm từng phần, dòng chưa trọn, file bị cắt |
| Parser | Dòng JSONL mẫu (tự viết theo cấu trúc, không chép hội thoại thật): tool, end_turn, usage khử trùng theo `message.id`, Codex `token_count` |
| Store | Chuỗi sự kiện → trạng thái; finished → idle sau 5 giây (ManualScheduler); ngắt không có Stop |
| HookInstaller | Gộp vào settings giả có hook của bên khác: giữ nguyên hook cũ, tạo bản sao lưu, gỡ sạch |
| Helper | Lọc trường, cắt tóm tắt, gói ≤ 2 KB, không in stdout |

**Kiểm thử tay:** chạy Claude Code thật ở hai dự án; activity khi làm việc và khi xong; bật mức 1 rồi chờ duyệt quyền; Codex nếu được cài.
