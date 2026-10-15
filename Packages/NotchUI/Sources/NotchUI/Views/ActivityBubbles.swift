import MyNotchCore
import SwiftUI

/// The icon an activity shows in its bubble and in its row of the list: its `minimal` view, else its `leading` view
/// clipped to a circle.
struct ActivityIcon: View {
    let activity: LiveActivity
    /// Side of the circle the `leading` view is clipped to (the bubble's diameter, or the row's icon).
    let size: CGFloat
    /// Side of the box a `minimal` view gets.
    let minimalSize: CGFloat

    var body: some View {
        if let minimal = activity.minimal {
            minimal.frame(width: minimalSize, height: minimalSize)
        } else {
            activity.leading.frame(width: size, height: size).clipShape(Circle())
        }
    }
}

/// The other live activities beside the collapsed notch: black circles as tall as the notch, to the right of it.
/// Laid out in the fixed panel, so a bubble coming or going moves nothing but the bubbles.
struct ActivityBubbles: View {
    let slots: [ActivitySlot]
    let geometry: NotchGeometry
    let label: (ActivityCenter.Entry) -> String
    let activate: (ActivitySlot) -> Void
    @Environment(\.notchSurface) private var surface

    var body: some View {
        // The row is as wide as the panel with the notch's centre line in the middle, so each bubble's layout frame is
        // where `NotchGeometry.bubbleFrame(at:)` (and with it the hit area) says it is, and a bubble can scale on its own.
        let half = geometry.panelSize.width / 2
        HStack(spacing: 0) {
            Spacer().frame(width: half).allowsHitTesting(false)
            HStack(spacing: NotchGeometry.bubbleGap) {
                ForEach(slots) { slot in
                    ActivityBubble(slot: slot, diameter: geometry.bubbleDiameter, label: label, activate: activate)
                        // On glass the shape materializes where it is (the glass transition of `ActivityBubble`), so only what is
                        // drawn on it fades.
                        .transition(
                            surface.isLiquidGlass
                                ? .opacity : .scale(scale: NotchTokens.bubbleAppearScale, anchor: .leading).combined(with: .opacity)
                        )
                }
            }
            .padding(.leading, geometry.bubbleFrame(at: 0).minX)
            .frame(width: half, height: geometry.bubbleDiameter, alignment: .leading)
            .animation(NotchTokens.spring, value: slots)
        }
        .frame(width: 2 * half, height: geometry.bubbleDiameter)
    }
}

private struct ActivityBubble: View {
    let slot: ActivitySlot
    let diameter: CGFloat
    let label: (ActivityCenter.Entry) -> String
    let activate: (ActivitySlot) -> Void
    @Environment(\.notchSurface) private var surface
    @Environment(\.notchGlassPlan) private var plan
    @Environment(\.notchGlassNamespace) private var namespace

    /// The glass this bubble draws, if the notch is Liquid Glass.
    private var planned: NotchGlassPlan.Shape? { plan.bubble(id: slot.id) }

    var body: some View {
        Button { activate(slot) } label: {
            ZStack {
                // Black, or nothing: on glass the circle is the glass.
                if !surface.isLiquidGlass { Circle().fill(NotchTokens.background) }
                switch slot {
                case .activity(let entry):
                    ActivityIcon(activity: entry.activity, size: diameter, minimalSize: NotchTokens.bubbleIconSize)
                case .overflow(let count):
                    Text("+\(count)").font(.system(size: 11, weight: .semibold)).foregroundStyle(surface.primaryStyle)
                }
            }
            // The content only, as in the notch: the glass keeps the system's scheme (a debug switch can force the content dark).
            .notchContentScheme(plan.contentScheme)
            .frame(width: diameter, height: diameter)
            .notchGlass(planned, in: Circle(), namespace: namespace)
            .glassBubbleTransition(planned: planned != nil)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        switch slot {
        case .activity(let entry): label(entry)
        case .overflow(let count): ActivityLabel.overflow(count: count)
        }
    }
}

private extension View {
    /// A bubble's glass materializes where it is and dematerializes there. It does not morph into the shapes next to it: the
    /// bubbles leave when the notch opens, and a morph then would pull them into the notch while it grows (and back out of it as
    /// it closes), which the classic notch's open and close never does.
    @ViewBuilder func glassBubbleTransition(planned: Bool) -> some View {
        if planned { glassEffectTransition(.materialize) } else { self }
    }
}
