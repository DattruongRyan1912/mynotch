import NotchUI
import SwiftUI

/// The Shortcuts tab: a button for each favourite.
struct ShortcutsTabView: View {
    static let noFavoritesMessage = "Chưa chọn shortcut ưa thích.\nChọn trong Cài đặt → Shortcuts."

    let module: ShortcutsModule

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .task { await module.refresh() }
    }

    @ViewBuilder private var content: some View {
        let favorites = module.favoriteShortcuts
        if favorites.isEmpty {
            Text(message)
                .font(.callout)
                .foregroundStyle(NotchTokens.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], spacing: 8) {
                    ForEach(favorites) { shortcut in
                        ShortcutButton(shortcut: shortcut, isRunning: module.state.running.contains(shortcut.id)) {
                            module.run(shortcut.id)
                        }
                    }
                }
            }
            .scrollIndicators(.never)
        }
    }

    private var message: String {
        if let error = module.state.listError, module.state.shortcuts.isEmpty { return "Không đọc được danh sách shortcut: \(error)" }
        return module.state.isLoading && module.state.shortcuts.isEmpty ? "Đang tải…" : Self.noFavoritesMessage
    }
}

private struct ShortcutButton: View {
    let shortcut: ShortcutInfo
    let isRunning: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(shortcut.name)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if isRunning {
                    ProgressView().controlSize(.small)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .foregroundStyle(NotchTokens.primaryText)
        .disabled(isRunning)
    }
}
