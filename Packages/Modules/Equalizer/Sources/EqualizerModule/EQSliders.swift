import Foundation
import MyNotchCore
import NotchUI
import SwiftUI

/// A gain as the sliders print it: a decimal comma, a sign on what is not zero, and no decimals on a whole number.
enum GainFormat {
    static func text(_ db: Double) -> String {
        var number = String(format: "%.1f", abs(db))
        if number.hasSuffix(".0") { number.removeLast(2) }
        if number == "0" { return "0 dB" }
        return (db < 0 ? "-" : "+") + number.replacingOccurrences(of: ".", with: ",") + " dB"
    }
}

/// How a touch on a track becomes a gain, and a gain a place on it.
enum GainScale {
    /// The sliders move in half decibels.
    static let step = 0.5

    /// `fraction` runs from 0 (the bottom of a vertical track, the left of a horizontal one) to 1, and is held to that.
    static func gain(atFraction fraction: Double) -> Double {
        let range = EQProfile.gainRange
        let held = min(max(fraction, 0), 1)
        let raw = range.lowerBound + held * (range.upperBound - range.lowerBound)
        return (raw / step).rounded() * step
    }

    static func fraction(of gain: Double) -> Double {
        let range = EQProfile.gainRange
        return (min(max(gain, range.lowerBound), range.upperBound) - range.lowerBound) / (range.upperBound - range.lowerBound)
    }
}

/// The names of the ten bands: short under a slider, and spelled out for VoiceOver.
enum EQBandLabel {
    static let short = EQProfile.frequencies.map { $0 >= 1000 ? "\(Int($0 / 1000))k" : "\(Int($0))" }

    static func spoken(_ frequency: Double) -> String {
        frequency >= 1000 ? "\(Int(frequency / 1000)) kHz" : "\(Int(frequency)) Hz"
    }
}

/// One gain track, vertical for a band and horizontal for the preamp. A press sets the gain where it lands and a drag follows
/// the pointer, as `VolumeRow` does; a double click goes back to 0 dB. The notch is told about a drag so it stays open when
/// the pointer leaves it.
struct GainSlider: View {
    enum Axis {
        case vertical
        case horizontal
    }

    static let knobSize: CGFloat = 10
    static let trackWidth: CGFloat = 4

    let axis: Axis
    let value: Double
    /// What VoiceOver calls it, e.g. "1 kHz".
    let name: String
    let set: (Double) -> Void

    @Environment(\.notch) private var notch
    @Environment(\.notchAccent) private var accent
    @State private var isDragging = false

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let length = axis == .vertical ? size.height : size.width
            let across = (axis == .vertical ? size.width : size.height) / 2
            let travel = max(length - Self.knobSize, 1)
            let zero = place(GainScale.fraction(of: 0), travel: travel)
            let knob = place(GainScale.fraction(of: value), travel: travel)
            ZStack {
                Capsule()
                    .fill(NotchTokens.fill(0.18))
                    .frame(width: axis == .vertical ? Self.trackWidth : length, height: axis == .vertical ? length : Self.trackWidth)
                    .position(point(length / 2, across))
                Capsule()
                    .fill(accent)
                    .frame(
                        width: axis == .vertical ? Self.trackWidth : max(abs(knob - zero), 0),
                        height: axis == .vertical ? max(abs(knob - zero), 0) : Self.trackWidth
                    )
                    .position(point((knob + zero) / 2, across))
                Capsule()
                    .fill(NotchTokens.fill(0.45))
                    .frame(width: axis == .vertical ? 10 : 1.5, height: axis == .vertical ? 1.5 : 10)
                    .position(point(zero, across))
                Circle()
                    .fill(NotchTokens.primaryText)
                    .frame(width: Self.knobSize, height: Self.knobSize)
                    .position(point(knob, across))
            }
            .contentShape(Rectangle())
            .gesture(drag(travel: travel))
            .simultaneousGesture(TapGesture(count: 2).onEnded { set(0) })
        }
        .accessibilityElement()
        .accessibilityLabel(name)
        .accessibilityValue(GainFormat.text(value))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: set(GainScale.gain(atFraction: GainScale.fraction(of: value + GainScale.step)))
            case .decrement: set(GainScale.gain(atFraction: GainScale.fraction(of: value - GainScale.step)))
            @unknown default: break
            }
        }
        .onDisappear { if isDragging { notch.setDragging(false) } }
    }

    /// Where along the track the centre of a knob at `fraction` sits; a vertical track grows upward.
    private func place(_ fraction: Double, travel: CGFloat) -> CGFloat {
        Self.knobSize / 2 + travel * CGFloat(axis == .vertical ? 1 - fraction : fraction)
    }

    private func point(_ along: CGFloat, _ across: CGFloat) -> CGPoint {
        axis == .vertical ? CGPoint(x: across, y: along) : CGPoint(x: along, y: across)
    }

    private func drag(travel: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !isDragging {
                    isDragging = true
                    notch.setDragging(true)
                }
                let along = axis == .vertical ? value.location.y : value.location.x
                let fraction = Double((along - Self.knobSize / 2) / travel)
                set(GainScale.gain(atFraction: axis == .vertical ? 1 - fraction : fraction))
            }
            .onEnded { _ in
                isDragging = false
                notch.setDragging(false)
            }
    }
}

/// The ten band sliders with their labels. With no profile (the user deleted them all) they show flat and do nothing.
struct EQBandSliders: View {
    static let sliderHeight: CGFloat = 70
    static let labelHeight: CGFloat = 12
    static let spacing: CGFloat = 3
    static var height: CGFloat { sliderHeight + spacing + labelHeight }

    let state: EqualizerState

    var body: some View {
        let gains = state.selected?.gains ?? []
        HStack(spacing: 0) {
            ForEach(EQProfile.frequencies.indices, id: \.self) { band in
                VStack(spacing: Self.spacing) {
                    GainSlider(
                        axis: .vertical, value: band < gains.count ? gains[band] : 0,
                        name: EQBandLabel.spoken(EQProfile.frequencies[band]), set: { state.setGain($0, band: band) }
                    )
                    .frame(height: Self.sliderHeight)
                    Text(EQBandLabel.short[band])
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(NotchTokens.secondaryText)
                        .frame(height: Self.labelHeight)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .opacity(state.selected == nil ? 0.4 : 1)
        .disabled(state.selected == nil)
    }
}
