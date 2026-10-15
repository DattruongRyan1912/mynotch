import AppKit
import MyNotchCore
import NotchUI
import SwiftUI

/// The "Khay" tab: a row of cards and a button that clears them.
struct ShelfTabView: View {
    let state: ShelfState
    let module: ShelfModule

    @Environment(\.notch) private var notch
    /// A menu of this app is being tracked: a card's context menu, or one of the action buttons.
    @State private var isMenuOpen = false

    var body: some View {
        let items = state.store?.items ?? []
        let isIdle = state.actions.phase == .idle
        VStack(spacing: 6) {
            if items.isEmpty && isIdle {
                Text("Thả file, link hoặc văn bản vào notch")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack {
                    Text("\(items.count) mục").font(.system(size: 11)).foregroundStyle(.secondary)
                    Spacer()
                    Button("Xoá tất cả", action: module.removeAll)
                        .buttonStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .disabled(state.actions.isRunning)
                }
                if isIdle {
                    ScrollView(.horizontal) {
                        LazyHGrid(rows: [GridItem(.fixed(78))], spacing: 8) {
                            ForEach(items) { item in
                                ShelfCardView(item: item, state: state, module: module)
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                    ShelfActionsRow(module: module)
                } else {
                    ShelfActionStatusView(state: state, module: module)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { state.store?.refreshLocations() }
        // The menus are outside the notch's reach: a click there counts as outside and the pointer may leave the
        // notch, so it stays pinned while one is open. The pin is set right here, not in `onChange`, which could wait
        // until the menu's tracking loop ends.
        .onReceive(NotificationCenter.default.publisher(for: NSMenu.didBeginTrackingNotification)) { _ in
            isMenuOpen = true
            notch.setPinned(true)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSMenu.didEndTrackingNotification)) { _ in
            isMenuOpen = false
            notch.setPinned(state.sharingID != nil)
        }
        .onChange(of: state.sharingID) { notch.setPinned(state.sharingID != nil || isMenuOpen) }
        .onDisappear {
            if isMenuOpen { notch.setPinned(false) }
        }
    }
}

struct ShelfCardView: View {
    let item: ShelfItem
    let state: ShelfState
    let module: ShelfModule

    var body: some View {
        VStack(spacing: 4) {
            icon.frame(width: 40, height: 40)
            Text(title)
                .font(.system(size: 10))
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .frame(width: 76, height: 78)
        .background(NotchTokens.fill(0.08), in: .rect(cornerRadius: 8))
        .overlay(alignment: .topLeading) { selectionMark }
        .background(ShelfShareAnchor(items: { module.shareItems(for: item) }, isPresented: isSharing))
        .overlay(ShelfCardDragSource(item: item, module: module, image: dragImage))
        .contextMenu {
            Button("Mở", systemImage: "arrow.up.forward.app") { module.open(item) }
            if case .file = item.kind {
                Button("Hiện trong Finder", systemImage: "folder") { module.revealInFinder(item) }
            }
            Button("AirDrop", systemImage: "airdrop") { module.airDrop(item) }
            Button("Chia sẻ…", systemImage: "square.and.arrow.up") { state.sharingID = item.id }
            Divider()
            Button("Xoá khỏi khay", systemImage: "trash", role: .destructive) { module.remove(item) }
        }
    }

    /// A ring and a tick on a card picked for an action.
    @ViewBuilder private var selectionMark: some View {
        if module.isSelected(item) {
            RoundedRectangle(cornerRadius: 8).stroke(Color.accentColor, lineWidth: 2)
                .overlay(alignment: .topLeading) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.accentColor, .white)
                        .padding(3)
                }
                .accessibilityLabel("Đã chọn")
        }
    }

    private var isSharing: Binding<Bool> {
        Binding(get: { state.sharingID == item.id }, set: { if !$0 { state.sharingID = nil } })
    }

    @ViewBuilder private var icon: some View {
        switch item.kind {
        case .file:
            if let path = state.store?.url(of: item)?.path {
                Image(nsImage: NSWorkspace.shared.icon(forFile: path)).resizable()
            } else {
                Image(systemName: "questionmark.square.dashed").resizable().scaledToFit()
            }
        case .text:
            Image(systemName: "text.alignleft").resizable().scaledToFit().padding(6)
        case .link:
            Image(systemName: "link").resizable().scaledToFit().padding(6)
        }
    }

    private var title: String {
        switch item.kind {
        case .file(_, let name, _): name
        case .text(let text): text.trimmingCharacters(in: .whitespacesAndNewlines)
        case .link(let url): url.host() ?? url.absoluteString
        }
    }

    /// The icon the card shows, at the size the drag preview uses.
    private func dragImage() -> NSImage {
        let source: NSImage = switch item.kind {
        case .file: state.store?.url(of: item).map { NSWorkspace.shared.icon(forFile: $0.path) } ?? NSImage()
        case .text: NSImage(systemSymbolName: "text.alignleft", accessibilityDescription: nil) ?? NSImage()
        case .link: NSImage(systemSymbolName: "link", accessibilityDescription: nil) ?? NSImage()
        }
        return NSImage(size: NSSize(width: 40, height: 40), flipped: false) { rect in
            source.draw(in: rect)
            return true
        }
    }
}

/// An invisible view the share picker points at; SwiftUI has no picker of its own for arbitrary items.
struct ShelfShareAnchor: NSViewRepresentable {
    /// Built only when the picker is shown: a file's location is looked up again then.
    let items: () -> [Any]
    @Binding var isPresented: Bool

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.dismissed = { isPresented = false }
        guard isPresented, !context.coordinator.isShown else { return }
        context.coordinator.isShown = true
        let picker = NSSharingServicePicker(items: items())
        picker.delegate = context.coordinator
        picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, NSSharingServicePickerDelegate {
        var isShown = false
        var dismissed: () -> Void = {}

        /// Called with a nil service when the picker is dismissed without a choice.
        func sharingServicePicker(_ picker: NSSharingServicePicker, didChoose service: NSSharingService?) {
            isShown = false
            dismissed()
        }
    }
}

/// Plain rows: the Settings page provides the Form and the section.
struct ShelfSettingsView: View {
    let settings: ModuleSettings
    let keys: ShelfSettingKeys

    var body: some View {
        Group {
            Toggle("Xoá khay khi thoát app", isOn: settings.binding(keys.clearOnQuit))
            Stepper(
                "Giữ tối đa \(settings.value(keys.maxItems)) mục",
                value: settings.binding(keys.maxItems), in: ShelfSettingKeys.maxItemsRange, step: 10
            )
            Toggle("Xoá khỏi khay sau khi kéo ra", isOn: settings.binding(keys.removeAfterDragOut))
            VStack(alignment: .leading, spacing: 2) {
                Text("Chất lượng ảnh JPEG, HEIC và PDF: \(Int((settings.value(keys.imageQuality) * 100).rounded())) %")
                Slider(value: settings.binding(keys.imageQuality), in: ShelfSettingKeys.imageQualityRange, step: 0.05)
            }
            Toggle("Xoá vị trí (GPS) khỏi ảnh đã xử lý", isOn: settings.binding(keys.stripLocation))
        }
    }
}
