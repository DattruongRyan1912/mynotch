import NotchUI
import SwiftUI

/// The chip beside a new capture: its thumbnail, and "Sửa" and "Chép". It draws on a black fill of its own, as the notch
/// does, so its text is light whatever the system's appearance is.
struct CaptureChipView: View {
    static let thumbnailSize = CGSize(width: 64, height: 44)
    /// Twice the point size, for Retina displays.
    static let thumbnailMaxPixel = 128

    let thumbnail: CGImage?
    let edit: () -> Void
    let copy: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            picture
            VStack(alignment: .leading, spacing: 6) {
                Text("Đã chụp")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(NotchTokens.secondaryText)
                HStack(spacing: 6) {
                    Button("Sửa", action: edit)
                        .buttonStyle(CaptureChipButtonStyle(isPrimary: true))
                        .help("Sửa ảnh vừa chụp")
                    Button("Chép", action: copy)
                        .buttonStyle(CaptureChipButtonStyle(isPrimary: false))
                        .help("Chép ảnh vừa chụp")
                }
            }
        }
        .padding(10)
        .background(Color.black.opacity(0.92), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.14), lineWidth: 1) }
        .notchOnDarkBackground()
        .fixedSize()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Ảnh vừa chụp")
    }

    /// The camera when the thumbnail could not be made.
    @ViewBuilder private var picture: some View {
        Group {
            if let thumbnail {
                Image(decorative: thumbnail, scale: 2)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(NotchTokens.primaryText)
            }
        }
        .frame(width: Self.thumbnailSize.width, height: Self.thumbnailSize.height)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

/// A capsule, filled with the accent for the button most likely wanted. Never focusable: the chip must not take a key press.
private struct CaptureChipButtonStyle: ButtonStyle {
    let isPrimary: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(NotchTokens.primaryText)
            .lineLimit(1)
            .padding(.horizontal, 12)
            .frame(height: 22)
            .background(Capsule().fill(isPrimary ? NotchTokens.accent.opacity(configuration.isPressed ? 0.7 : 0.9) : Color.white.opacity(configuration.isPressed ? 0.28 : 0.16)))
            .contentShape(Capsule())
            .focusable(false)
    }
}
