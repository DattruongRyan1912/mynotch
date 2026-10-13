import AppKit
import MyNotchCore
import SwiftUI

/// The "Khay" tab: a row of cards and a button that clears them.
struct ShelfTabView: View {
    let state: ShelfState
    let module: ShelfModule

    @Environment(\.notch) private var notch

    var body: some View {
        let items = state.store?.items ?? []
        VStack(spacing: 6) {
            if items.isEmpty {
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
                }
                ScrollView(.horizontal) {
                    LazyHGrid(rows: [GridItem(.fixed(78))], spacing: 8) {
                        ForEach(items) { item in
                            ShelfCardView(item: item, state: state, module: module)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: state.sharingID) { notch.setPinned(state.sharingID != nil) }
    }
}

struct ShelfCardView: View {
    let item: ShelfItem
    let state: ShelfState
    let module: ShelfModule

    @Environment(\.notch) private var notch

    var body: some View {
        VStack(spacing: 4) {
            icon.frame(width: 40, height: 40)
            Text(title)
                .font(.system(size: 10))
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .frame(width: 76, height: 78)
        .background(.white.opacity(0.08), in: .rect(cornerRadius: 8))
        .background(ShelfShareAnchor(items: module.shareItems(for: item), isPresented: isSharing))
        .onDrag { startDrag() }
        .onTapGesture(count: 2) { module.open(item) }
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

    /// SwiftUI reports no end of a drag, so the notch hears it ended once the mouse button is up again.
    private func startDrag() -> NSItemProvider {
        let notch = notch, module = module, item = item
        notch.setDragging(true)
        Task {
            repeat {
                try? await Task.sleep(for: .milliseconds(100))
            } while NSEvent.pressedMouseButtons & 1 != 0
            notch.setDragging(false)
            module.didDragOut(item)
        }
        return module.dragProvider(for: item)
    }
}

/// An invisible view the share picker points at; SwiftUI has no picker of its own for arbitrary items.
struct ShelfShareAnchor: NSViewRepresentable {
    let items: [Any]
    @Binding var isPresented: Bool

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.dismissed = { isPresented = false }
        guard isPresented, !context.coordinator.isShown else { return }
        context.coordinator.isShown = true
        let picker = NSSharingServicePicker(items: items)
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
        }
    }
}
