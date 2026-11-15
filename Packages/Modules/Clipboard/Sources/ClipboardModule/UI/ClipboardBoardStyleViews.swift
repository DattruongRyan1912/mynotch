import NotchUI
import SwiftUI

extension ClipboardBoardColor {
    /// The colour of the icon. `accent` is whatever accent the surrounding window draws with, passed in because the notch and
    /// a window have different ones.
    func color(accent: Color) -> Color {
        switch self {
        case .accent: accent
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .mint: .mint
        case .teal: .teal
        case .blue: .blue
        case .indigo: .indigo
        case .purple: .purple
        case .pink: .pink
        case .gray: .gray
        }
    }
}

/// A board in the notch's row, drawn like the other pills with its icon in the board's colour. Only the look: the row adds the
/// click, the drag and the menu.
struct ClipboardBoardPill: View {
    let board: ClipboardBoard
    let isSelected: Bool

    @Environment(\.notchAccent) private var accent

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: board.systemImage)
                .foregroundStyle(board.color.color(accent: accent))
            Text(board.name)
            if let lock = board.lock {
                Image(systemName: lock.isUnlocked ? "lock.open.fill" : "lock.fill")
                    .font(.system(size: 9))
                    .accessibilityLabel(lock.isUnlocked ? "đã mở khoá" : "đã khoá")
            }
        }
        .font(.system(size: 11, weight: .medium))
        .lineLimit(1)
        .padding(.horizontal, 8)
        .frame(height: 22)
        .foregroundStyle(isSelected ? NotchTokens.primaryText : NotchTokens.secondaryText)
        .background(isSelected ? NotchTokens.fill(0.14) : .clear, in: Capsule())
        .contentShape(Capsule())
    }
}

/// What replaces the notch's row of boards while one board's icon and colour are chosen: the board as it will look, the icons,
/// the colours, and "Xong". A choice applies at once.
struct ClipboardBoardStyleStrip: View {
    let board: ClipboardBoard
    let onIcon: (String) -> Void
    let onColor: (ClipboardBoardColor) -> Void
    let onDone: () -> Void

    @Environment(\.notchAccent) private var accent

    var body: some View {
        HStack(spacing: 6) {
            ClipboardBoardPill(board: board, isSelected: true)
            ScrollView(.horizontal) {
                HStack(spacing: 2) {
                    ForEach(ClipboardBoardIcon.curated) { icon in
                        iconButton(icon)
                    }
                    Divider()
                        .frame(height: 14)
                        .padding(.horizontal, 4)
                    ForEach(ClipboardBoardColor.allCases, id: \.self) { color in
                        colorButton(color)
                    }
                }
            }
            .scrollIndicators(.never)
            Button(action: onDone) {
                Text("Xong")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(NotchTokens.primaryText)
                    .padding(.horizontal, 10)
                    .frame(height: 22)
                    .background(accent.opacity(0.7), in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    private func iconButton(_ icon: ClipboardBoardIcon) -> some View {
        let isSelected = board.systemImage == icon.name
        return Button { onIcon(icon.name) } label: {
            Image(systemName: icon.name)
                .font(.system(size: 11))
                .foregroundStyle(isSelected ? NotchTokens.primaryText : NotchTokens.secondaryText)
                .frame(width: 24, height: 22)
                .background(isSelected ? NotchTokens.fill(0.18) : .clear, in: Capsule())
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(icon.title)
        .accessibilityLabel(icon.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func colorButton(_ color: ClipboardBoardColor) -> some View {
        let isSelected = board.color == color
        return Button { onColor(color) } label: {
            Circle()
                .fill(color.color(accent: accent))
                .frame(width: 13, height: 13)
                .overlay { Circle().strokeBorder(NotchTokens.fill(isSelected ? 0.95 : 0), lineWidth: 1.5).padding(-3) }
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(color.title)
        .accessibilityLabel("Màu \(color.title.lowercased())")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// The library's picker, in a popover from the board: a grid of icons over a row of colours. Drawn in the system's colours and
/// the accent of the window, which the default colour takes.
struct ClipboardBoardStylePicker: View {
    let board: ClipboardBoard
    let onIcon: (String) -> Void
    let onColor: (ClipboardBoardColor) -> Void

    @Environment(\.notchAccent) private var accent

    private static let columns = 8

    /// The icons in rows of eight.
    private var rows: [[ClipboardBoardIcon]] {
        let icons = ClipboardBoardIcon.curated
        return stride(from: 0, to: icons.count, by: Self.columns).map { Array(icons[$0..<min($0 + Self.columns, icons.count)]) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Grid(horizontalSpacing: 4, verticalSpacing: 4) {
                ForEach(rows.indices, id: \.self) { row in
                    GridRow {
                        ForEach(rows[row]) { icon in
                            iconButton(icon)
                        }
                    }
                }
            }
            // Twelve of 25 points are as wide as eight icons of 34 with 4 between.
            HStack(spacing: 0) {
                ForEach(ClipboardBoardColor.allCases, id: \.self) { color in
                    let isSelected = board.color == color
                    Button { onColor(color) } label: {
                        Circle()
                            .fill(color.color(accent: accent))
                            .frame(width: 16, height: 16)
                            .overlay { Circle().strokeBorder(Color.primary.opacity(isSelected ? 0.9 : 0), lineWidth: 2).padding(-3) }
                            .frame(width: 25, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(color.title)
                    .accessibilityLabel("Màu \(color.title.lowercased())")
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
        }
        .padding(14)
    }

    private func iconButton(_ icon: ClipboardBoardIcon) -> some View {
        let isSelected = board.systemImage == icon.name
        return Button { onIcon(icon.name) } label: {
            Image(systemName: icon.name)
                .font(.system(size: 14))
                .foregroundStyle(board.color.color(accent: accent))
                .frame(width: 34, height: 30)
                .background(isSelected ? Color.primary.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(icon.title)
        .accessibilityLabel(icon.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
