import AppKit
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
    static let cautionThreshold: Double = 12.0

    static func isCaution(_ db: Double) -> Bool {
        db.isFinite && db > cautionThreshold
    }

    /// `fraction` runs from 0 (the bottom of a vertical track, the left of a horizontal one) to 1, and is held to that.
    static func gain(atFraction fraction: Double, range: ClosedRange<Double> = EQProfile.gainRange) -> Double {
        let held = min(max(fraction, 0), 1)
        let raw = range.lowerBound + held * (range.upperBound - range.lowerBound)
        return (raw / step).rounded() * step
    }

    static func fraction(of gain: Double, range: ClosedRange<Double> = EQProfile.gainRange) -> Double {
        return (min(max(gain, range.lowerBound), range.upperBound) - range.lowerBound) / (range.upperBound - range.lowerBound)
    }
}

/// The names of the ten bands: short under a slider, and spelled out for VoiceOver.
enum EQBandLabel {
    static let short = EQProfile.frequencies.map { $0 >= 1000 ? "\(Int($0 / 1000))k" : "\(Int($0))" }

    static func spoken(_ frequency: Double) -> String {
        frequency >= 1000 ? "\(Int(frequency / 1000)) kHz" : "\(Int(frequency)) Hz"
    }

    static func display(band: Int, activeGain: Double?) -> String {
        guard band >= 0, band < short.count else { return "" }
        if let gain = activeGain {
            return GainFormat.text(gain)
        }
        return short[band]
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
    var range: ClosedRange<Double> = EQProfile.gainRange
    var cautionAbove: Double? = nil
    var onActiveChange: ((Bool) -> Void)? = nil
    let set: (Double) -> Void

    static func isCaution(_ value: Double, cautionAbove: Double?) -> Bool {
        guard let cautionAbove else { return false }
        return value.isFinite && value > cautionAbove
    }

    @Environment(\.notch) private var notch
    @Environment(\.notchAccent) private var accent
    @State private var isDragging = false

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let length = axis == .vertical ? size.height : size.width
            let across = (axis == .vertical ? size.width : size.height) / 2
            let travel = max(length - Self.knobSize, 1)
            let zero = place(GainScale.fraction(of: 0, range: range), travel: travel)
            let knob = place(GainScale.fraction(of: value, range: range), travel: travel)
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
                    .fill(Color.white)
                    .overlay(Circle().stroke(Color.black.opacity(0.18), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.25), radius: 1.5, y: 0.5)
                    .frame(width: Self.knobSize, height: Self.knobSize)
                    .position(point(knob, across))
            }
            .contentShape(Rectangle())
            .gesture(drag(travel: travel))
            .simultaneousGesture(TapGesture(count: 2).onEnded { set(0) })
        }
        .onHover { isHovering in
            onActiveChange?(isHovering)
        }
        .accessibilityElement()
        .accessibilityLabel(name)
        .accessibilityValue(GainFormat.text(value))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: set(GainScale.gain(atFraction: GainScale.fraction(of: value + GainScale.step, range: range), range: range))
            case .decrement: set(GainScale.gain(atFraction: GainScale.fraction(of: value - GainScale.step, range: range), range: range))
            @unknown default: break
            }
        }
        .onDisappear {
            if isDragging {
                notch.setDragging(false)
                onActiveChange?(false)
            }
        }
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
                    onActiveChange?(true)
                }
                let along = axis == .vertical ? value.location.y : value.location.x
                let fraction = Double((along - Self.knobSize / 2) / travel)
                set(GainScale.gain(atFraction: axis == .vertical ? 1 - fraction : fraction, range: range))
            }
            .onEnded { _ in
                isDragging = false
                notch.setDragging(false)
                onActiveChange?(false)
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
    @State private var activeBand: Int? = nil

    var body: some View {
        let gains = state.selected?.gains ?? []
        HStack(spacing: 0) {
            ForEach(EQProfile.frequencies.indices, id: \.self) { band in
                let isBandActive = activeBand == band
                let gainVal = band < gains.count ? gains[band] : 0.0
                let isCaution = isBandActive && GainScale.isCaution(gainVal)
                VStack(spacing: Self.spacing) {
                    GainSlider(
                        axis: .vertical,
                        value: gainVal,
                        name: EQBandLabel.spoken(EQProfile.frequencies[band]),
                        cautionAbove: GainScale.cautionThreshold,
                        onActiveChange: { active in
                            if active {
                                activeBand = band
                            } else if activeBand == band {
                                activeBand = nil
                            }
                        },
                        set: { state.setGain($0, band: band) }
                    )
                    .frame(height: Self.sliderHeight)
                    Text(EQBandLabel.display(band: band, activeGain: isBandActive ? gainVal : nil))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(isCaution ? Color(red: 245/255, green: 158/255, blue: 11/255) : (isBandActive ? NotchTokens.primaryText : NotchTokens.secondaryText))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(height: Self.labelHeight)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .opacity(state.selected == nil ? 0.4 : 1)
        .disabled(state.selected == nil)
    }
}

/// Native AppKit vertical slider view providing smooth, continuous vertical mouse tracking and hit-testing
/// for frequency band gain adjustments without the coordinate rotation artifacts of SwiftUI Slider.
final class VerticalBandSliderNSView: NSView {
    var value: Double = 0.0 {
        didSet {
            if oldValue != value { needsDisplay = true }
        }
    }
    var range: ClosedRange<Double> = EQProfile.gainRange
    var name: String = ""
    var onValueChanged: ((Double) -> Void)?

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupAccessibility()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupAccessibility()
    }

    private func setupAccessibility() {
        setAccessibilityElement(true)
        setAccessibilityRole(.slider)
        setAccessibilityOrientation(.vertical)
        setAccessibilityMinValue(range.lowerBound)
        setAccessibilityMaxValue(range.upperBound)
    }

    override func accessibilityValue() -> Any? {
        GainFormat.text(value)
    }

    override func accessibilityLabel() -> String? {
        name
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            value = 0.0
            onValueChanged?(0.0)
            needsDisplay = true
            return
        }
        handleMouse(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        handleMouse(with: event)
    }

    private func handleMouse(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        let knobRadius: CGFloat = 5.0
        let travel = max(bounds.height - knobRadius * 2, 1.0)
        let clampedY = min(bounds.height - knobRadius, max(knobRadius, loc.y))
        let fraction = 1.0 - Double((clampedY - knobRadius) / travel)
        let newGain = GainScale.gain(atFraction: fraction, range: range)
        if newGain != value {
            value = newGain
            onValueChanged?(newGain)
            needsDisplay = true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        let knobRadius: CGFloat = 5.0
        let trackWidth: CGFloat = 4.0
        let trackX = (bounds.width - trackWidth) / 2
        let travel = max(bounds.height - knobRadius * 2, 1.0)
        let fraction = GainScale.fraction(of: value, range: range)
        let knobY = (bounds.height - knobRadius) - CGFloat(fraction) * travel
        let zeroY = bounds.height / 2

        // 1. Background track
        let trackRect = NSRect(x: trackX, y: knobRadius, width: trackWidth, height: bounds.height - knobRadius * 2)
        let trackPath = NSBezierPath(roundedRect: trackRect, xRadius: 2, yRadius: 2)
        NSColor.separatorColor.withAlphaComponent(0.25).setFill()
        trackPath.fill()

        // 2. Active fill from 0 dB to current value
        let fillMinY = min(knobY, zeroY)
        let fillMaxY = max(knobY, zeroY)
        if fillMaxY - fillMinY > 0.5 {
            let fillRect = NSRect(x: trackX, y: fillMinY, width: trackWidth, height: fillMaxY - fillMinY)
            let fillPath = NSBezierPath(roundedRect: fillRect, xRadius: 2, yRadius: 2)
            NSColor.controlAccentColor.setFill()
            fillPath.fill()
        }

        // 3. 0 dB tick mark
        let tickRect = NSRect(x: (bounds.width - 10) / 2, y: zeroY - 0.75, width: 10, height: 1.5)
        let tickPath = NSBezierPath(roundedRect: tickRect, xRadius: 0.75, yRadius: 0.75)
        NSColor.separatorColor.withAlphaComponent(0.5).setFill()
        tickPath.fill()

        // 4. White circular knob with shadow and hairline border
        let knobRect = NSRect(x: bounds.width / 2 - knobRadius, y: knobY - knobRadius, width: knobRadius * 2, height: knobRadius * 2)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -1), blur: 2.0, color: NSColor.black.withAlphaComponent(0.3).cgColor)
        NSColor.white.setFill()
        let knobPath = NSBezierPath(ovalIn: knobRect)
        knobPath.fill()
        ctx.restoreGState()

        NSColor.black.withAlphaComponent(0.2).setStroke()
        knobPath.lineWidth = 0.5
        knobPath.stroke()
    }
}

/// SwiftUI wrapper for `VerticalBandSliderNSView` ensuring native NSView hierarchy presence for AppKit testing
/// and pixel-perfect vertical dragging ergonomics.
struct VerticalBandSlider: NSViewRepresentable {
    let value: Double
    let name: String
    var range: ClosedRange<Double> = EQProfile.gainRange
    let onValueChanged: (Double) -> Void

    func makeNSView(context: Context) -> VerticalBandSliderNSView {
        let view = VerticalBandSliderNSView()
        view.value = value
        view.name = name
        view.range = range
        view.onValueChanged = onValueChanged
        return view
    }

    func updateNSView(_ nsView: VerticalBandSliderNSView, context: Context) {
        nsView.value = value
        nsView.name = name
        nsView.range = range
        nsView.onValueChanged = onValueChanged
        nsView.needsDisplay = true
    }
}
