import NotchUI
import SwiftUI

/// Placeholder list until the real tab (search, filters, cards) replaces it.
struct ClipboardTabView: View {
    let module: ClipboardModule

    var body: some View {
        let state = module.state
        Group {
            if state.pasteboardDenied {
                message("MyNotch đang bị chặn đọc clipboard. Cho phép trong Cài đặt hệ thống → Quyền riêng tư & Bảo mật → Dán từ app khác.")
            } else if state.visibleItems.isEmpty {
                message("Chưa có gì trong lịch sử")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(state.visibleItems) { item in
                            Button { module.activate(item) } label: {
                                Label(item.content.plainText ?? "Ảnh", systemImage: item.content.kind.systemImage)
                                    .lineLimit(1)
                                    .foregroundStyle(NotchTokens.primaryText)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .onAppear { module.refreshPasteboardAccess() }
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(NotchTokens.secondaryText)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
