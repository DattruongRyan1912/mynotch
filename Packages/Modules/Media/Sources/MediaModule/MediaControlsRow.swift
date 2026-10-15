import NotchUI
import SwiftUI

/// The row under the progress bar: play and pause in the middle, the buttons the user chose on both sides, and the volume
/// slider in their place while it is open. Empty slots keep their width, so play and pause stay centred under the bar
/// whatever the choice, and the default row looks as it always did.
struct MediaControlsRow: View {
    static let buttonSize: CGFloat = 28
    static let spacing: CGFloat = 14

    let store: NowPlayingStore
    let actions: MediaActions
    let volume: VolumeModel
    @State private var volumeIsOpen = false

    var body: some View {
        Group {
            if volumeIsOpen {
                VolumeRow(volume: volume, close: closeVolume)
            } else {
                buttons
                    .frame(maxWidth: .infinity)
                    // An overlay, so the buttons stay centred under the progress bar.
                    .overlay(alignment: .trailing) { NowPlayingBars(store: store) }
            }
        }
        .frame(maxWidth: .infinity)
        .onAppear { volume.refresh() }
        .onDisappear(perform: closeVolume)
        .onChange(of: volume.isAvailable) { _, isAvailable in if !isAvailable { closeVolume() } }
    }

    /// The slots left to right as the row draws them: a button it does not draw (no button, a like the source cannot send)
    /// is an empty slot.
    static func drawn(_ layout: MediaControlLayout, in context: MediaControlContext) -> [MediaControlButton] {
        layout.slots.map { $0.isDrawn(in: context) ? $0 : .none }
    }

    private var buttons: some View {
        let context = store.controlContext(hasVolume: volume.isAvailable, volumeIsOpen: volumeIsOpen)
        let drawn = Self.drawn(store.controlLayout, in: context)
        let half = drawn.count / 2
        return HStack(spacing: Self.spacing) {
            ForEach(0..<half, id: \.self) { slot(drawn[$0], context) }
            PlayPauseButton(isPlaying: store.state.isPlaying) { actions.send(.togglePlayPause) }
            ForEach(half..<drawn.count, id: \.self) { slot(drawn[$0], context) }
        }
    }

    @ViewBuilder
    private func slot(_ button: MediaControlButton, _ context: MediaControlContext) -> some View {
        if button == .none {
            Color.clear.frame(width: Self.buttonSize, height: Self.buttonSize)
        } else {
            ControlButton(look: button.look(in: context)) { press(button) }
        }
    }

    private func press(_ button: MediaControlButton) {
        if button == .volume {
            openVolume()
        } else {
            actions.press(button)
        }
    }

    /// Opens on what was last read: nothing waits for the device. The button is faded while there is no volume to set, and a
    /// device that loses it while the slider is open closes the slider.
    private func openVolume() {
        guard volume.isAvailable else {
            volume.refresh()
            return
        }
        volumeIsOpen = true
        volume.startWatching()
    }

    private func closeVolume() {
        volumeIsOpen = false
        volume.stopWatching()
    }
}

/// Play and pause: bigger than the others, and always in the middle.
struct PlayPauseButton: View {
    let isPlaying: Bool
    let action: () -> Void

    var body: some View {
        RowButton(
            symbol: isPlaying ? "pause.fill" : "play.fill", label: isPlaying ? "Tạm dừng" : "Phát",
            symbolSize: 20, isActive: false, action: action
        )
    }
}

struct ControlButton: View {
    let look: MediaControlLook
    let action: () -> Void

    var body: some View {
        RowButton(symbol: look.symbol, label: look.label, symbolSize: 14, isActive: look.isActive, action: action)
            .disabled(!look.isEnabled)
            .opacity(look.isEnabled ? 1 : 0.35)
    }
}

struct RowButton: View {
    let symbol: String
    let label: String
    let symbolSize: CGFloat
    let isActive: Bool
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: symbolSize, weight: .semibold))
                .foregroundStyle(isActive ? NotchTokens.accent : NotchTokens.primaryText)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: MediaControlsRow.buttonSize, height: MediaControlsRow.buttonSize)
                .background(Circle().fill(Color.white.opacity(isHovering ? 0.14 : 0)))
                .contentShape(Circle())
        }
        .buttonStyle(PressableButtonStyle())
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovering)
        .help(label)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}

struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.86 : 1)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// The system output volume in the row's place: the speaker closes it, then a bar to drag and the level in percent.
private struct VolumeRow: View {
    /// One step of the accessibility adjust action.
    static let adjustStep: Float = 0.0625

    let volume: VolumeModel
    let close: () -> Void
    @Environment(\.notch) private var notch
    @State private var isDragging = false

    var body: some View {
        HStack(spacing: 8) {
            // A muted speaker and a dimmed level say that nothing is heard; moving the slider unmutes.
            RowButton(symbol: volume.symbol, label: "Đóng thanh âm lượng", symbolSize: 14, isActive: !volume.isMuted, action: close)
            bar
            Text("\(volume.percent ?? 0)%")
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .foregroundStyle(NotchTokens.secondaryText)
                .frame(width: 34, alignment: .trailing)
        }
        .opacity(volume.isMuted ? 0.55 : 1)
        .frame(height: MediaControlsRow.buttonSize)
        .onDisappear { if isDragging { notch.setDragging(false) } }
    }

    private var bar: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let filled = width * CGFloat(volume.level ?? 0)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.18))
                Capsule().fill(NotchTokens.accent).frame(width: filled)
                Circle()
                    .fill(NotchTokens.primaryText)
                    .frame(width: 10, height: 10)
                    .offset(x: min(max(filled - 5, 0), max(width - 10, 0)))
            }
            .frame(height: 6)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(drag(width: width))
        }
        .frame(height: 10)
        .accessibilityElement()
        .accessibilityLabel("Âm lượng")
        .accessibilityValue(volume.isMuted ? "\(volume.percent ?? 0)%, tắt tiếng" : "\(volume.percent ?? 0)%")
        .accessibilityAdjustableAction { direction in
            let level = volume.level ?? 0
            switch direction {
            case .increment: volume.set(level + Self.adjustStep)
            case .decrement: volume.set(level - Self.adjustStep)
            @unknown default: break
            }
        }
    }

    /// The notch stays open while the pointer is outside it during a drag, as with the progress bar.
    private func drag(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !isDragging {
                    isDragging = true
                    notch.setDragging(true)
                }
                volume.set(width > 0 ? Float(min(max(value.location.x / width, 0), 1)) : 0)
            }
            .onEnded { _ in
                isDragging = false
                notch.setDragging(false)
            }
    }
}
