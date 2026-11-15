import SwiftUI

/// The timeline of the editor, left to right the whole recording: a ruler, a strip of pictures with what is cut dimmed and a
/// handle at each end, and a lane of zoom blocks. A drag shows a draft as it goes and tells the model once, when it ends.
struct RecordingTimelineView: View {
    let model: RecordingEditorModel

    static let rulerHeight: CGFloat = 18
    static let stripHeight: CGFloat = 56
    static let laneHeight: CGFloat = 30
    static let handleWidth: CGFloat = 10

    /// An edge of a zoom block or an end of the strip being dragged, and where it is now.
    private struct Draft: Equatable {
        enum Part: Equatable {
            case trimStart, trimEnd, zoomStart(Int), zoomEnd(Int)

            var isStart: Bool {
                switch self {
                case .trimStart, .zoomStart: true
                case .trimEnd, .zoomEnd: false
                }
            }
        }
        var part: Part
        var time: TimeInterval
    }

    @State private var draft: Draft?
    /// The two ends of a drag on the strip that is picking a stretch.
    @State private var picking: (from: CGFloat, to: CGFloat)?

    var body: some View {
        GeometryReader { proxy in
            let geometry = TimelineGeometry(width: proxy.size.width, duration: model.duration)
            ZStack(alignment: .topLeading) {
                VStack(spacing: 4) {
                    ruler(geometry)
                    strip(geometry)
                    lane(geometry)
                }
                playhead(geometry)
            }
            // The origin of a drag of a handle: the handle moves as it is dragged, the timeline does not.
            .coordinateSpace(name: Self.space)
        }
        .frame(height: Self.rulerHeight + Self.stripHeight + Self.laneHeight + 8)
        .padding(.horizontal, 16)
    }

    // MARK: Ruler

    private func ruler(_ geometry: TimelineGeometry) -> some View {
        Canvas { context, size in
            for tick in geometry.rulerTicks() {
                let x = geometry.x(for: tick.time)
                context.fill(Path(CGRect(x: x, y: size.height - 5, width: 1, height: 5)), with: .color(.secondary))
                // A label that would run past the end is left out; its mark stays.
                guard x + 40 <= size.width else { continue }
                context.draw(Text(tick.label).font(.caption2.monospacedDigit()).foregroundStyle(.secondary), at: CGPoint(x: x + 3, y: 6), anchor: .leading)
            }
        }
        .frame(height: Self.rulerHeight)
        .contentShape(.rect)
        .gesture(
            DragGesture(minimumDistance: 0).onChanged { value in model.seek(toRecording: geometry.time(at: value.location.x)) }
        )
        .accessibilityLabel("Thước thời gian")
        .accessibilityHint("Bấm hoặc kéo để tua")
    }

    // MARK: Strip

    private func strip(_ geometry: TimelineGeometry) -> some View {
        ZStack(alignment: .topLeading) {
            pictures(geometry)
            ForEach(Array(model.cutMap.cuts.enumerated()), id: \.offset) { _, cut in cutOverlay(cut, geometry) }
            if let selection = pickedRange(geometry) {
                let span = geometry.span(of: selection)
                Rectangle().fill(Color.accentColor.opacity(0.25))
                    .overlay(Rectangle().stroke(Color.accentColor, lineWidth: 1.5))
                    .frame(width: max(span.width, 1), height: Self.stripHeight)
                    .offset(x: span.x)
                    .allowsHitTesting(false)
            }
            handle(.trimStart, at: trimStart(geometry), geometry)
            handle(.trimEnd, at: trimEnd(geometry), geometry)
        }
        .frame(width: geometry.width, height: Self.stripHeight, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(.rect)
        .gesture(stripGesture(geometry))
        .accessibilityLabel("Dải ảnh của bản quay")
        .accessibilityHint("Bấm để tua, kéo để chọn một đoạn")
    }

    private func pictures(_ geometry: TimelineGeometry) -> some View {
        HStack(spacing: 0) {
            ForEach(0..<RecordingEditorModel.thumbnailCount, id: \.self) { index in
                ZStack {
                    Rectangle().fill(Color(nsColor: .quaternaryLabelColor))
                    if index < model.thumbnails.count, let image = model.thumbnails[index] {
                        Image(decorative: image, scale: 1).resizable().scaledToFill()
                    }
                }
                .frame(width: geometry.width / CGFloat(RecordingEditorModel.thumbnailCount), height: Self.stripHeight)
                .clipped()
            }
        }
    }

    private func cutOverlay(_ cut: CutRange, _ geometry: TimelineGeometry) -> some View {
        let span = geometry.span(of: cut.start..<cut.end)
        return Rectangle()
            .fill(Color.black.opacity(0.62))
            .overlay(Image(systemName: "scissors").font(.caption).foregroundStyle(.white.opacity(0.8)).opacity(span.width > 24 ? 1 : 0))
            .frame(width: max(span.width, 1), height: Self.stripHeight)
            .offset(x: span.x)
            .allowsHitTesting(false)
    }

    private func handle(_ part: Draft.Part, at time: TimeInterval, _ geometry: TimelineGeometry) -> some View {
        let isStart = part.isStart
        let x = geometry.x(for: draft?.part == part ? draft?.time ?? time : time)
        return RoundedRectangle(cornerRadius: 3)
            .fill(Color.accentColor)
            .overlay(Capsule().fill(.white.opacity(0.9)).frame(width: 2, height: 18))
            .frame(width: Self.handleWidth, height: Self.stripHeight)
            // Inside what is kept, so each handle can still be taken when nothing is cut at its end.
            .offset(x: isStart ? x : x - Self.handleWidth)
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .named(Self.space))
                    .onChanged { value in draft = Draft(part: part, time: geometry.time(at: value.location.x)) }
                    .onEnded { value in
                        let time = geometry.time(at: value.location.x)
                        draft = nil
                        if isStart { model.trimStart(to: time) } else { model.trimEnd(to: time) }
                    }
            )
            .accessibilityLabel(isStart ? "Tay kéo cắt đầu" : "Tay kéo cắt cuối")
    }

    private func trimStart(_ geometry: TimelineGeometry) -> TimeInterval {
        model.cutMap.cuts.first { $0.start <= 0 }?.end ?? 0
    }

    private func trimEnd(_ geometry: TimelineGeometry) -> TimeInterval {
        model.cutMap.cuts.first { $0.end >= model.duration }?.start ?? model.duration
    }

    /// The stretch being picked, or the one picked last.
    private func pickedRange(_ geometry: TimelineGeometry) -> Range<TimeInterval>? {
        if let picking {
            let a = geometry.time(at: picking.from), b = geometry.time(at: picking.to)
            return min(a, b)..<max(a, b)
        }
        return model.selection
    }

    private func stripGesture(_ geometry: TimelineGeometry) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if abs(value.location.x - value.startLocation.x) >= 3 { picking = (value.startLocation.x, value.location.x) }
            }
            .onEnded { value in
                picking = nil
                let moved = abs(value.location.x - value.startLocation.x)
                let a = geometry.time(at: value.startLocation.x), b = geometry.time(at: value.location.x)
                if moved >= 3 {
                    model.selection = min(a, b)..<max(a, b)
                } else if let cut = model.cutMap.cuts.first(where: { $0.start <= b && b <= $0.end }) {
                    // A click on a cut stretch picks all of it, to bring it back.
                    model.selection = cut.start..<cut.end
                } else {
                    model.selection = nil
                    model.seek(toRecording: b)
                }
            }
    }

    // MARK: Zoom lane

    private func lane(_ geometry: TimelineGeometry) -> some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .quaternaryLabelColor).opacity(0.5))
            ForEach(Array(model.zoomSegments.enumerated()), id: \.offset) { index, segment in block(index, segment, geometry) }
            ForEach(Array(model.activity.clicks.enumerated()), id: \.offset) { _, click in
                clickMarker(click, geometry)
            }
        }
        .frame(width: geometry.width, height: Self.laneHeight, alignment: .topLeading)
        .contentShape(.rect)
        .onTapGesture { model.selectZoom(nil) }
        .accessibilityLabel("Dải zoom")
    }

    private func clickMarker(_ click: ActivityTrack.Click, _ geometry: TimelineGeometry) -> some View {
        let x = geometry.x(for: click.t)
        let isCovered = model.zoomSegments.contains { $0.start <= click.t && $0.end >= click.t }
        return Button {
            model.toggleZoom(atClick: click)
        } label: {
            Circle()
                .fill(isCovered ? Color.white : Color.yellow)
                .overlay(Circle().stroke(Color.black.opacity(0.4), lineWidth: 1))
                .frame(width: 8, height: 8)
                .contentShape(Rectangle().inset(by: -5))
        }
        .buttonStyle(.plain)
        .offset(x: max(0, x - 4), y: 11)
        .help(isCovered ? "Bỏ zoom tại cú bấm này (\(TimelineGeometry.label(for: click.t)))" : "Gán zoom tại cú bấm này (\(TimelineGeometry.label(for: click.t)))")
        .accessibilityLabel("Cú bấm chuột lúc \(TimelineGeometry.label(for: click.t))")
    }

    private func block(_ index: Int, _ segment: ZoomSegment, _ geometry: TimelineGeometry) -> some View {
        let start = draft?.part == .zoomStart(index) ? draft?.time ?? segment.start : segment.start
        let end = draft?.part == .zoomEnd(index) ? draft?.time ?? segment.end : segment.end
        let span = geometry.span(of: start..<max(end, start))
        let isSelected = model.selectedZoom == index
        let tint: Color = segment.manual ? .orange : .accentColor
        return ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 5).fill(tint.opacity(isSelected ? 0.9 : 0.55))
            if isSelected { RoundedRectangle(cornerRadius: 5).stroke(.white, lineWidth: 1.5) }
            Text(Self.scaleLabel(segment.scale)).font(.caption2.bold()).foregroundStyle(.white).padding(.leading, 8).opacity(span.width > 40 ? 1 : 0)
            if isSelected {
                edgeHandle(.zoomStart(index), geometry)
                edgeHandle(.zoomEnd(index), geometry).frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .frame(width: max(span.width, 4), height: Self.laneHeight - 6)
        .offset(x: span.x, y: 3)
        .onTapGesture { model.selectZoom(index) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Đoạn zoom \(Self.scaleLabel(segment.scale)) từ \(TimelineGeometry.label(for: segment.start))")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func edgeHandle(_ part: Draft.Part, _ geometry: TimelineGeometry) -> some View {
        Rectangle().fill(Color.white.opacity(0.001))
            .overlay(Capsule().fill(.white).frame(width: 3, height: 12))
            .frame(width: Self.handleWidth)
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .named(Self.space))
                    .onChanged { value in draft = Draft(part: part, time: geometry.time(at: value.location.x)) }
                    .onEnded { value in
                        let time = geometry.time(at: value.location.x)
                        draft = nil
                        switch part {
                        case .zoomStart(let index): model.setZoomStart(time, at: index)
                        case .zoomEnd(let index): model.setZoomEnd(time, at: index)
                        default: break
                        }
                    }
            )
            .accessibilityLabel(part.isStart ? "Kéo mép đầu của đoạn zoom" : "Kéo mép cuối của đoạn zoom")
    }

    static func scaleLabel(_ scale: Double) -> String {
        "\(scale.formatted(.number.precision(.fractionLength(0...2)).locale(Locale(identifier: "vi_VN"))))×"
    }

    // MARK: Playhead

    private func playhead(_ geometry: TimelineGeometry) -> some View {
        Rectangle().fill(Color.red)
            .frame(width: 2, height: Self.rulerHeight + Self.stripHeight + Self.laneHeight + 8)
            .offset(x: geometry.x(for: model.playhead) - 1)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private static let space = "recordingTimeline"
}
