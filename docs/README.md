# Thư mục Tài liệu & Kiến thức Dự án MyNotch (`docs/`)

Chào mừng bạn đến với trung tâm lưu trữ tri thức và hướng dẫn kỹ thuật của dự án **MyNotch**.

---

## 📑 Tài liệu Đọc Chính (HTML-First)

Theo quy chuẩn kỹ thuật của dự án, mọi tài liệu bàn giao, kiến trúc và vận hành được đóng gói dưới định dạng **HTML độc lập (Standalone HTML)** với giao diện chuẩn macOS, hỗ trợ copy code 1-click, sơ đồ trực quan và tìm kiếm nhanh:

- **👉 [PROJECT_KNOWLEDGE_BASE.html](PROJECT_KNOWLEDGE_BASE.html)**: **Sổ tay Tri thức Dự án Toàn diện (Chính thức)** — Bao gồm tổng quan, kiến trúc phân tầng, danh mục 18 module, cơ chế bảo mật TCC, cấu hình chứng chỉ Apple Development, quy trình phát triển và sổ tay xử lý sự cố.
- **[manual-test-checklist-all.html](manual-test-checklist-all.html)**: Danh sách kịch bản kiểm thử tay toàn diện cho tất cả các module.
- **[manual-test-checklist.html](manual-test-checklist.html)**: Kịch bản kiểm thử riêng cho phần lõi nền tảng.

---

## 🗂 Cấu trúc Tài liệu trong `docs/`

```text
docs/
├── README.md                           # Trang chỉ mục này
├── PROJECT_KNOWLEDGE_BASE.html         # Tài liệu tri thức dự án toàn diện (HTML-First)
├── PROJECT_KNOWLEDGE_BASE.md           # Bản Markdown tham chiếu song hành
├── manual-test-checklist-all.html      # Checklist kiểm thử tay cho tất cả module
├── manual-test-checklist.html          # Checklist kiểm thử tay nền tảng
└── superpowers/                        # Lịch sử thiết kế và ghi chú phát triển
    ├── specs/                          # Thiết kế chi tiết từng module (Specs)
    ├── plans/                          # Kế hoạch thực thi theo giai đoạn (Plans)
    └── notes/                          # Ghi chú sau triển khai (Implementation Notes)
```

---

## 🧭 Điều hướng Nhanh các Chủ đề Trọng yếu

| Chủ đề | Vị trí tra cứu | Tóm tắt nội dung |
|---|---|---|
| **Kiến trúc hệ thống** | `PROJECT_KNOWLEDGE_BASE.html#architecture` | Phân tầng App, `MyNotchCore`, `NotchUI`, Helper Daemons và vòng đời On-Demand Demand. |
| **Danh mục 18 Module** | `PROJECT_KNOWLEDGE_BASE.html#modules` | Chi tiết Media (Smart Tab Focus), Performance (CPU/SMC/Quạt), Screenshot, Clipboard... |
| **Bảo mật & Quyền TCC** | `PROJECT_KNOWLEDGE_BASE.html#security-tcc` | Lý do mất quyền khi dùng Ad-hoc, Designated Requirement, chứng chỉ Apple Development. |
| **Quy trình Phát triển** | `PROJECT_KNOWLEDGE_BASE.html#dev-workflow` | Các lệnh `xcodegen`, `swift test`, `./scripts/verify.sh`, deploy vào `/Applications`. |
| **Sự cố thường gặp (FAQ)** | `PROJECT_KNOWLEDGE_BASE.html#troubleshooting` | Khắc phục lỗi quyền, không chuyển tab YouTube, kiểm tra process chạy đè. |
