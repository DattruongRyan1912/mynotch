import NotchUI
import SwiftUI

/// The row of tiles the notch shows while a window is dragged to it. Each tile is a small picture of its layout with the
/// zone under the pointer lit; the frames come from `SnapTiles`, which the session hit-tests with, so what is lit is
/// what a drop uses. Nothing here takes the pointer: the drag belongs to the other app, so the session follows it.
/// The row is `SnapTiles.height` tall at the top of whatever room the notch gives its content, which depends on the tab
/// the notch covers, so the tiles never stretch to fill it.
struct SnapTilesView: View {
    let model: SnapTilesModel

    var body: some View {
        GeometryReader { proxy in
            let row = CGRect(x: 0, y: 0, width: proxy.size.width, height: SnapTiles.height)
            let frames = SnapTiles.frames(count: model.layouts.count, in: row)
            ZStack(alignment: .topLeading) {
                ForEach(Array(zip(model.layouts, frames)), id: \.0) { layout, frame in
                    SnapTileView(layout: layout, hoveredZone: model.hovered?.layout == layout ? model.hovered?.zone : nil)
                        .frame(width: frame.width, height: frame.height)
                        .offset(x: frame.minX)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

private struct SnapTileView: View {
    let layout: SnapLayout
    let hoveredZone: Int?
    @Environment(\.notchAccent) private var accent

    var body: some View {
        VStack(spacing: 4) {
            glyph
                .padding(.horizontal, SnapTiles.glyphInset)
                .padding(.top, SnapTiles.glyphInset)
            Text(layout.title)
                .font(.system(size: 10, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.35)
                .padding(.horizontal, 1)
                .foregroundStyle(hoveredZone == nil ? NotchTokens.secondaryText : NotchTokens.primaryText)
            Spacer(minLength: 0)
        }
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(hoveredZone == nil ? NotchTokens.fill(0.08) : accent.opacity(0.28))
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(layout.title)
    }

    /// The layout as a screen with its zones; the one under the pointer is lit.
    private var glyph: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 3, style: .continuous).stroke(NotchTokens.fill(0.35), lineWidth: 1)
                ForEach(layout.zones.indices, id: \.self) { index in
                    let unit = layout.zones[index].unit
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(hoveredZone == index ? accent : NotchTokens.fill(0.28))
                        .frame(width: unit.width * proxy.size.width - 3, height: unit.height * proxy.size.height - 3)
                        .offset(x: unit.minX * proxy.size.width + 1.5, y: unit.minY * proxy.size.height + 1.5)
                }
            }
        }
        .aspectRatio(SnapTiles.glyphAspect, contentMode: .fit)
    }
}
