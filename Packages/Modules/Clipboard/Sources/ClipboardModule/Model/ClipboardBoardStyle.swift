import CoreGraphics
import Foundation

/// The colour of a board's icon. `accent` follows the notch's accent colour (the system's in a window), the others are
/// fixed. Stored as its name; a name from a later version reads as the accent.
nonisolated enum ClipboardBoardColor: String, Codable, Sendable, CaseIterable {
    case accent, red, orange, yellow, green, mint, teal, blue, indigo, purple, pink, gray

    var title: String {
        switch self {
        case .accent: "Mặc định"
        case .red: "Đỏ"
        case .orange: "Cam"
        case .yellow: "Vàng"
        case .green: "Xanh lá"
        case .mint: "Bạc hà"
        case .teal: "Xanh ngọc"
        case .blue: "Xanh dương"
        case .indigo: "Chàm"
        case .purple: "Tím"
        case .pink: "Hồng"
        case .gray: "Xám"
        }
    }
}

/// An SF Symbol a board can wear, with the name VoiceOver reads for it.
nonisolated struct ClipboardBoardIcon: Identifiable, Hashable, Sendable {
    /// What a new board gets.
    static let defaultName = "tray.full"

    let name: String
    let title: String

    var id: String { name }

    /// What the picker offers: a small set that reads well at 11 pt, grouped roughly by what a board is for.
    static let curated: [ClipboardBoardIcon] = [
        ("tray.full", "Khay"), ("folder", "Thư mục"), ("star", "Sao"), ("heart", "Tim"), ("bookmark", "Dấu trang"),
        ("flag", "Cờ"), ("tag", "Nhãn"), ("pin", "Ghim"), ("briefcase", "Công việc"), ("house", "Nhà"),
        ("cart", "Mua sắm"), ("creditcard", "Thanh toán"), ("gift", "Quà"), ("graduationcap", "Học tập"), ("book", "Sách"),
        ("doc.text", "Tài liệu"), ("note.text", "Ghi chú"), ("pencil", "Bút"), ("paintbrush", "Thiết kế"), ("photo", "Ảnh"),
        ("camera", "Máy ảnh"), ("music.note", "Nhạc"), ("film", "Phim"), ("gamecontroller", "Trò chơi"), ("terminal", "Dòng lệnh"),
        ("chevron.left.forwardslash.chevron.right", "Mã"), ("laptopcomputer", "Máy tính"), ("globe", "Web"), ("link", "Liên kết"), ("envelope", "Thư"),
        ("phone", "Điện thoại"), ("message", "Tin nhắn"), ("person", "Cá nhân"), ("person.2", "Nhóm"), ("calendar", "Lịch"),
        ("clock", "Đồng hồ"), ("lock", "Khoá"), ("key", "Chìa khoá"), ("lightbulb", "Ý tưởng"), ("airplane", "Du lịch"),
    ].map { ClipboardBoardIcon(name: $0.0, title: $0.1) }

    /// Whether `name` has the shape of a symbol name: a file may hold anything, and the name only ever reaches
    /// `Image(systemName:)`, but a long or odd one is better replaced than kept.
    static func isValidName(_ name: String) -> Bool {
        name.wholeMatch(of: /[a-z0-9.]{1,64}/) != nil
    }
}

/// Where a board lands when it is dragged, as pure arithmetic.
nonisolated enum ClipboardBoardReorder {
    /// The index a board takes from a list's drag, which names the place to insert it as an offset into the list as it is
    /// now (so moving down passes the board's own row).
    static func index(moving source: Int, toOffset destination: Int) -> Int {
        destination > source ? destination - 1 : destination
    }

    /// The index the pill at `index` takes when it has been dragged along the row `translation` points sideways: the slot under the
    /// middle of the pill. Slot `i` starts where the widths and spacing before it end and runs up to the next one, so a
    /// drag past either end stops at the end. A bad index (or no pills) gives `index` back.
    static func destination(of index: Int, translation: CGFloat, widths: [CGFloat], spacing: CGFloat) -> Int {
        guard widths.indices.contains(index) else { return index }
        var starts: [CGFloat] = []
        var offset: CGFloat = 0
        for width in widths {
            starts.append(offset)
            offset += width + spacing
        }
        let center = starts[index] + widths[index] / 2 + translation
        return starts.lastIndex { $0 <= center } ?? 0
    }
}
