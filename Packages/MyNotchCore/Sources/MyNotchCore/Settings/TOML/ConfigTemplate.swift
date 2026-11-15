import Foundation

/// Provides schema-driven starter templates and documented export rendering for MyNotch `config.toml`.
nonisolated public enum ConfigTemplate {
    public struct SchemaField: Sendable {
        public let key: String
        public let description: String
        public let defaultValue: TOMLValue

        public init(_ key: String, description: String, default defaultValue: TOMLValue) {
            self.key = key
            self.description = description
            self.defaultValue = defaultValue
        }
    }

    public struct SchemaSection: Sendable {
        public let name: String
        public let description: String
        public let fields: [SchemaField]

        public init(_ name: String, description: String, fields: [SchemaField]) {
            self.name = name
            self.description = description
            self.fields = fields
        }
    }

    /// Complete canonical schema of MyNotch settings matching codebase constants.
    public static let schema: [SchemaSection] = [
        SchemaSection("app", description: "Cài đặt tổng quan ứng dụng", fields: [
            SchemaField("showMenuBarIcon", description: "Hiện biểu tượng MyNotch trên thanh menu bar (true / false)", default: .boolean(true)),
            SchemaField("tabOrder", description: "Thứ tự sắp xếp các tab module trên Notch", default: .array([]))
        ]),
        SchemaSection("app.menuBarHider", description: "Thu gọn và ẩn bớt các biểu tượng trên menu bar", fields: [
            SchemaField("enabled", description: "Bật tính năng thu gọn menu bar (true / false)", default: .boolean(false)),
            SchemaField("autoCollapseSeconds", description: "Tự động thu gọn sau N giây (0 = không tự thu gọn, 0..300)", default: .integer(10)),
            SchemaField("revealOnHover", description: "Tự động mở thanh menu khi rê chuột lên (true / false)", default: .boolean(false)),
            SchemaField("alwaysHiddenEnabled", description: "Bật khu vực biểu tượng luôn ẩn (true / false)", default: .boolean(false)),
            SchemaField("startCollapsed", description: "Luôn ở trạng thái thu gọn khi khởi động (true / false)", default: .boolean(false)),
            SchemaField("itemsBar", description: "Hiển thị thanh biểu tượng phụ dưới Notch (true / false)", default: .boolean(true))
        ]),
        SchemaSection("app.equalizer", description: "Bộ cân bằng âm thanh hệ thống (Equalizer)", fields: [
            SchemaField("enabled", description: "Bật xử lý âm thanh EQ toàn máy (true / false)", default: .boolean(false)),
            SchemaField("loudness", description: "Bù âm trầm và cao khi nghe ở mức âm lượng thấp (true / false)", default: .boolean(false))
        ]),
        SchemaSection("interface", description: "Giao diện và tương tác tai thỏ (Notch / Pill)", fields: [
            SchemaField("displayMode", description: "Hiển thị trên màn hình: \"all\" (mọi màn), \"main\" (chính), \"cursor\" (theo chuột)", default: .string("all")),
            SchemaField("look", description: "Phong cách giao diện: \"classic\" (đen nguyên bản), \"liquidGlass\" (kính lỏng)", default: .string("classic")),
            SchemaField("accent", description: "Màu nhấn: \"system\", \"palette:<blue|purple|pink|red|orange|yellow|green|graphite>\", hoặc \"custom:#RRGGBB\"", default: .string("system")),
            SchemaField("virtualNotchStyle", description: "Màn hình không có tai thỏ phần cứng: \"notch\" (tai thỏ ảo), \"pill\" (viên thuốc nổi)", default: .string("notch")),
            SchemaField("openWidth", description: "Chiều rộng khi mở rộng (pt, 480..900)", default: .float(600.0)),
            SchemaField("openDelayMs", description: "Thời gian rê chuột (ms) trước khi Notch mở (0..1000)", default: .integer(150)),
            SchemaField("closeDelayMs", description: "Độ trễ (ms) trước khi Notch thu gọn lại khi chuột rời (0..1000)", default: .integer(300)),
            SchemaField("hideInFullscreen", description: "Tự động ẩn Notch khi có ứng dụng chạy toàn màn hình (true / false)", default: .boolean(true)),
            SchemaField("hideFromCapture", description: "Ẩn khỏi quay màn hình: \"never\" (không ẩn), \"whenCollapsed\" (khi đóng), \"always\" (luôn ẩn)", default: .string("never")),
            SchemaField("swipeBetweenTabs", description: "Vuốt hai ngón tay ngang để đổi tab (true / false)", default: .boolean(true)),
            SchemaField("swipeToOpen", description: "Vuốt hai ngón tay dọc để mở/đóng Notch (true / false)", default: .boolean(true)),
            SchemaField("swipeSensitivity", description: "Độ nhạy cử chỉ vuốt: \"low\", \"medium\", \"high\"", default: .string("medium")),
            SchemaField("haptics", description: "Phản hồi rung bàn di chuột khi tương tác (true / false)", default: .boolean(true))
        ]),
        SchemaSection("module.clipboard", description: "Module Clipboard - Quản lý lịch sử sao chép", fields: [
            SchemaField("enabled", description: "Bật module Clipboard", default: .boolean(true)),
            SchemaField("historyLimit", description: "Giới hạn số mục lưu trong lịch sử (50..5000)", default: .integer(500)),
            SchemaField("retention", description: "Thời gian lưu giữ: \"day\", \"week\", \"month\", \"year\", \"forever\"", default: .string("month")),
            SchemaField("mcpEnabled", description: "Bật MCP Server cục bộ cho AI Agents (Claude / Codex)", default: .boolean(false))
        ]),
        SchemaSection("module.media", description: "Module Media - Trình phát nhạc & Phụ đề", fields: [
            SchemaField("enabled", description: "Bật module Media", default: .boolean(true)),
            SchemaField("lyrics", description: "Hiển thị lời bài hát (true / false)", default: .boolean(false)),
            SchemaField("lyricsUnderNotch", description: "Hiển thị dải lời bài hát 2 dòng dưới Notch (true / false)", default: .boolean(false)),
            SchemaField("karaoke", description: "Tô màu lời bài hát theo thời gian thực (true / false)", default: .boolean(true)),
            SchemaField("tintFromArtwork", description: "Đổi màu hiệu ứng sóng âm theo ảnh bìa bài hát (true / false)", default: .boolean(true))
        ]),
        SchemaSection("module.translation", description: "Module Dịch thuật & Quy đổi", fields: [
            SchemaField("enabled", description: "Bật module Translation", default: .boolean(true)),
            SchemaField("preferredPair", description: "Cặp ngôn ngữ dịch ưa thích", default: .table([
                "first": .string("vi"),
                "second": .string("en")
            ]))
        ]),
        SchemaSection("module.aiagents", description: "Module Giám sát AI Agents (Claude Code / Codex)", fields: [
            SchemaField("enabled", description: "Bật module AI Agents", default: .boolean(true)),
            SchemaField("claudeEnabled", description: "Theo dõi các phiên chạy của Claude Code", default: .boolean(true)),
            SchemaField("codexEnabled", description: "Theo dõi các phiên chạy của Codex", default: .boolean(true))
        ]),
        SchemaSection("module.performance", description: "Module Hiệu năng hệ thống & Quạt SMC", fields: [
            SchemaField("enabled", description: "Bật module Performance", default: .boolean(true)),
            SchemaField("stripTemperature", description: "Hiện nhiệt độ SoC trên thanh Notch thu gọn", default: .boolean(false)),
            SchemaField("stripMemory", description: "Hiện dung lượng RAM trên thanh Notch thu gọn", default: .boolean(false))
        ]),
        SchemaSection("module.ports", description: "Module Quản lý cổng mạng & Buộc dừng tiến trình", fields: [
            SchemaField("enabled", description: "Bật module Ports", default: .boolean(true))
        ]),
        SchemaSection("module.shortcuts", description: "Module Phím tắt nhanh", fields: [
            SchemaField("enabled", description: "Bật module Shortcuts", default: .boolean(true))
        ]),
        SchemaSection("module.screenshot", description: "Module Chụp & Quay màn hình", fields: [
            SchemaField("enabled", description: "Bật module Screenshot", default: .boolean(true))
        ]),
        SchemaSection("module.equalizer", description: "Module Giao diện bộ cân bằng âm thanh", fields: [
            SchemaField("enabled", description: "Bật tab Equalizer", default: .boolean(true))
        ]),
        SchemaSection("module.pet", description: "Module Thú cưng tương tác (Capybara, Mèo, Hamster...)", fields: [
            SchemaField("enabled", description: "Bật module Thú cưng", default: .boolean(true))
        ]),
        SchemaSection("module.calendar", description: "Module Lịch & Lời nhắc", fields: [
            SchemaField("enabled", description: "Bật module Lịch", default: .boolean(true))
        ]),
        SchemaSection("module.todo", description: "Module Việc cần làm (Reminders)", fields: [
            SchemaField("enabled", description: "Bật module Việc cần làm", default: .boolean(true))
        ]),
        SchemaSection("module.timer", description: "Module Hẹn giờ & Bấm giờ", fields: [
            SchemaField("enabled", description: "Bật module Hẹn giờ", default: .boolean(true))
        ]),
        SchemaSection("module.battery", description: "Module Thông tin Pin & Nguồn điện", fields: [
            SchemaField("enabled", description: "Bật module Battery", default: .boolean(true))
        ]),
        SchemaSection("module.shelf", description: "Module Khay chứa tệp tạm thời", fields: [
            SchemaField("enabled", description: "Bật module Khay tệp", default: .boolean(true))
        ]),
        SchemaSection("module.windows", description: "Module Chia cửa sổ (Snap Layouts)", fields: [
            SchemaField("enabled", description: "Bật module Chia cửa sổ", default: .boolean(true)),
            SchemaField("layouts", description: "Danh sách bố cục kích hoạt", default: .array([])),
            SchemaField("gap", description: "Khoảng cách giữa các cửa sổ (0, 8, 16)", default: .integer(0))
        ]),
        SchemaSection("module.lockscreen", description: "Module Tiện ích Màn hình khoá", fields: [
            SchemaField("enabled", description: "Bật module Màn hình khoá (thử nghiệm)", default: .boolean(false))
        ]),
        SchemaSection("module.system", description: "Module Hoạt động hệ thống (Bluetooth, HUD, Mạng)", fields: [
            SchemaField("enabled", description: "Bật module System Activities", default: .boolean(true))
        ])
    ]

    /// Generates the initial starter file with full comments and commented-out examples.
    public static func starterTemplate() -> String {
        var lines: [String] = [
            "# ==============================================================================",
            "# MyNotch Configuration (config.toml)",
            "# ==============================================================================",
            "# Tệp cấu hình di động chuẩn dotfiles cho MyNotch.",
            "# Chỉnh sửa tệp này bằng Neovim / VS Code / Zed; ứng dụng sẽ tự động tải lại ngay.",
            "# ==============================================================================",
            ""
        ]

        for section in schema {
            lines.append("# " + String(repeating: "-", count: 78))
            lines.append("# [\(section.name)] - \(section.description)")
            lines.append("# " + String(repeating: "-", count: 78))
            lines.append("[\(section.name)]")
            for field in section.fields {
                lines.append("# \(field.description)")
                let valStr = TOMLSerializer.serializeValue(field.defaultValue, inline: true)
                lines.append("# \(field.key) = \(valStr)")
                lines.append("")
            }
        }

        return lines.joined(separator: "\n")
    }

    /// Renders current settings merged over schema defaults, fully documented with comments.
    public static func renderExport(storedRaw: [String: Data]) -> String {
        var lines: [String] = [
            "# ==============================================================================",
            "# MyNotch Configuration (config.toml) - Xuất ngày \(ISO8601DateFormatter().string(from: Date()))",
            "# ==============================================================================",
            "# Tệp cấu hình đầy đủ được xuất từ MyNotch, chứa các giá trị đang hoạt động.",
            "# ==============================================================================",
            ""
        ]

        var allStoredValues: [String: TOMLValue] = [:]
        for (k, data) in storedRaw {
            if k == "app.permissionIdentity" { continue }
            if let val = TOMLValue.fromJSONData(data) {
                allStoredValues[k] = val
            }
        }

        var renderedKeys = Set<String>()

        for section in schema {
            lines.append("# " + String(repeating: "-", count: 78))
            lines.append("# [\(section.name)] - \(section.description)")
            lines.append("# " + String(repeating: "-", count: 78))
            lines.append("[\(section.name)]")

            for field in section.fields {
                lines.append("# \(field.description)")
                let fullKey = "\(section.name).\(field.key)"
                renderedKeys.insert(fullKey)
                let activeValue = allStoredValues[fullKey] ?? field.defaultValue
                let valStr = TOMLSerializer.serializeValue(activeValue, inline: true)
                lines.append("\(field.key) = \(valStr)")
                lines.append("")
            }

            // Render any extra keys belonging directly to this section
            let prefix = "\(section.name)."
            let extraKeys = allStoredValues.keys
                .filter { $0.hasPrefix(prefix) && !renderedKeys.contains($0) }
                .sorted()
            for extraKey in extraKeys {
                let subKey = String(extraKey.dropFirst(prefix.count))
                if !subKey.contains(".") {
                    renderedKeys.insert(extraKey)
                    let val = allStoredValues[extraKey]!
                    let valStr = TOMLSerializer.serializeValue(val, inline: true)
                    lines.append("\(subKey) = \(valStr)")
                    lines.append("")
                }
            }
        }

        // Output any extra sections and keys not covered by schema
        let remainingKeys = allStoredValues.keys.filter { !renderedKeys.contains($0) }.sorted()
        if !remainingKeys.isEmpty {
            var extraSections: [String: [(key: String, val: TOMLValue)]] = [:]
            for key in remainingKeys {
                let parts = key.split(separator: ".").map(String.init)
                if parts.count >= 2 {
                    let section = parts.dropLast().joined(separator: ".")
                    let field = parts.last!
                    extraSections[section, default: []].append((field, allStoredValues[key]!))
                } else {
                    extraSections["", default: []].append((key, allStoredValues[key]!))
                }
            }

            for sec in extraSections.keys.sorted() {
                if !sec.isEmpty {
                    lines.append("[\(sec)]")
                }
                for item in extraSections[sec]!.sorted(by: { $0.key < $1.key }) {
                    lines.append("\(item.key) = \(TOMLSerializer.serializeValue(item.val, inline: true))")
                }
                lines.append("")
            }
        }

        return lines.joined(separator: "\n")
    }
}
