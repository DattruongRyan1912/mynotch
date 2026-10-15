import SwiftUI

/// A strip of sample shapes for comparing glass on screen (`debug.glass.sample=1`): a card, a search field, two filter chips (one
/// selected) and an "on" tile, as the open notch's modules draw them. Not a feature: it is shown below the tab bar and above the
/// module's tab, which it takes room from, and only while the switch is on. With the debug panel `tiles` the card, the field and the
/// chips sit straight on the desktop as glass of their own; otherwise they are washes on the notch's glass.
struct NotchSampleStrip: View {
    /// Height of the strip, which is the card's.
    static let height: CGFloat = 56
    /// Room the strip takes in the tab page: its height and the space below it.
    static let slot: CGFloat = height + bottomGap
    static let bottomGap: CGFloat = NotchGlassPlan.tileGap

    /// The card's corner radius, which the caller works out from the notch's (`NotchCardPlan.concentricRadius`).
    let cardRadius: CGFloat

    @Environment(\.notchSurface) private var surface
    @Environment(\.notchGlassPlan) private var plan

    var body: some View {
        HStack(spacing: 8) {
            card
            field
            chip("Tất cả", selected: true)
            chip("Ảnh", selected: false)
            tile
        }
        // Straight on the desktop, so glass of their own: nothing here is inside other glass.
        .environment(\.notchOnDesktop, plan.cardsAreOnTheDesktop)
        .frame(maxWidth: .infinity)
        .frame(height: Self.height)
        .padding(.bottom, Self.bottomGap)
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Thẻ mẫu").font(.system(size: 12, weight: .semibold)).foregroundStyle(surface.primaryStyle)
            Text("Dòng thứ hai").font(.system(size: 11)).foregroundStyle(surface.secondaryStyle)
        }
        .padding(.horizontal, 10)
        .frame(width: 120, height: Self.height, alignment: .leading)
        .notchCard(in: RoundedRectangle(cornerRadius: cardRadius, style: .continuous))
    }

    private var field: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.system(size: 12, weight: .medium))
            Text("Tìm kiếm").font(.system(size: 12))
            Spacer(minLength: 0)
        }
        .foregroundStyle(surface.secondaryStyle)
        .padding(.horizontal, 12)
        .frame(minWidth: 96, maxWidth: 150)
        .frame(height: 32)
        .notchCard(in: Capsule(), interactive: true)
    }

    private func chip(_ title: String, selected: Bool) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(surface.primaryStyle)
            .padding(.horizontal, 12)
            .frame(height: 28)
            .notchCard(in: Capsule(), interactive: true, selected: selected)
    }

    /// An "on" tile as Control Center draws one: solid white with a dark glyph, whatever the switches say.
    private var tile: some View {
        Image(systemName: "rectangle.3.group")
            .font(.system(size: 18, weight: .medium))
            .foregroundStyle(Color.black)
            .frame(width: Self.height, height: Self.height)
            .background(Color.white, in: RoundedRectangle(cornerRadius: cardRadius, style: .continuous))
    }
}
