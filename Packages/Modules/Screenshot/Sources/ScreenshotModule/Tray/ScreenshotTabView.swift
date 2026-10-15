import AppKit
import NotchUI
import SwiftUI

/// The Screenshot tab: the recent captures as a strip of thumbnails, newest first.
struct ScreenshotTabView: View {
    static let emptyMessage = "Chưa có ảnh chụp nào.\nDùng phím tắt chụp màn hình (mặc định ⌃⌥S)."

    let module: ScreenshotModule

    @Environment(\.notch) private var notch
    /// A menu of this app is being tracked, e.g. a card's context menu.
    @State private var isMenuOpen = false
    /// "Lưu thành…" is open: its panel is a window of this app, so a click there would otherwise close the notch.
    @State private var isSaving = false

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            // The pin is set right here, not in `onChange`, which could wait until the menu's tracking loop ends.
            .onReceive(NotificationCenter.default.publisher(for: NSMenu.didBeginTrackingNotification)) { _ in
                isMenuOpen = true
                notch.setPinned(true)
            }
            .onReceive(NotificationCenter.default.publisher(for: NSMenu.didEndTrackingNotification)) { _ in
                isMenuOpen = false
                notch.setPinned(isSaving)
            }
            .onDisappear {
                if isMenuOpen || isSaving { notch.setPinned(false) }
            }
    }

    @ViewBuilder private var content: some View {
        let records = module.state.records
        if records.isEmpty {
            Text(Self.emptyMessage)
                .font(.callout)
                .foregroundStyle(NotchTokens.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 10) {
                    ForEach(records) { record in
                        ScreenshotCardView(record: record, module: module)
                            .onTapGesture(count: 2) { Task { await module.edit(record) } }
                            .onDrag { startDrag(record) }
                            .contextMenu { menu(for: record) }
                    }
                }
            }
            .scrollIndicators(.never)
        }
    }

    @ViewBuilder private func menu(for record: CaptureRecord) -> some View {
        Button("Chép", systemImage: "doc.on.doc") { Task { await module.copy(record) } }
        Button("Lưu vào \(module.saveLocation.title)", systemImage: "square.and.arrow.down") { Task { await module.save(record) } }
        Button("Lưu thành…", systemImage: "square.and.arrow.down.on.square") { saveAs(record) }
        Button("OCR (chép chữ)", systemImage: "text.viewfinder") { Task { await module.recognizeText(in: record) } }
        Button("Sửa", systemImage: "pencil.and.scribble") { Task { await module.edit(record) } }
        Divider()
        Button("Xoá", systemImage: "trash", role: .destructive) { module.delete(record) }
    }

    private func saveAs(_ record: CaptureRecord) {
        isSaving = true
        notch.setPinned(true)
        Task {
            await module.saveAs(record)
            isSaving = false
            notch.setPinned(isMenuOpen)
        }
    }

    /// SwiftUI reports no end of a drag, so the notch hears it ended once the mouse button is up again.
    private func startDrag(_ record: CaptureRecord) -> NSItemProvider {
        let notch = notch
        notch.setDragging(true)
        Task {
            repeat {
                try? await Task.sleep(for: .milliseconds(100))
            } while NSEvent.pressedMouseButtons & 1 != 0
            notch.setDragging(false)
        }
        return module.dragFileURL(for: record).map { NSItemProvider(object: $0 as NSURL) } ?? NSItemProvider()
    }
}

/// One capture: its thumbnail, with the time it was taken and its size in pixels.
struct ScreenshotCardView: View {
    static let thumbnailSize = CGSize(width: 156, height: 104)
    /// Twice the point size, for Retina displays.
    static let thumbnailMaxPixel = 320

    let record: CaptureRecord
    let module: ScreenshotModule

    @State private var thumbnail: CGImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack {
                NotchTokens.fill(0.08)
                if let thumbnail {
                    Image(decorative: thumbnail, scale: 2)
                        .resizable()
                        .scaledToFit()
                }
            }
            .frame(width: Self.thumbnailSize.width, height: Self.thumbnailSize.height)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            HStack(spacing: 4) {
                Text(record.createdAt, format: .dateTime.hour().minute())
                Spacer(minLength: 0)
                if record.hasMarkup {
                    Image(systemName: "pencil.tip")
                }
                Text("\(record.pixelWidth)×\(record.pixelHeight)")
            }
            .font(.system(size: 10))
            .foregroundStyle(NotchTokens.secondaryText)
            .lineLimit(1)
        }
        .frame(width: Self.thumbnailSize.width)
        // Every markup save changes the record (`editedAt`), which makes the old thumbnail stale.
        .task(id: record) { thumbnail = await module.thumbnail(for: record, maxPixel: Self.thumbnailMaxPixel) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Ảnh chụp lúc \(record.createdAt.formatted(date: .omitted, time: .shortened)), \(record.pixelWidth) × \(record.pixelHeight) pixel")
    }
}
