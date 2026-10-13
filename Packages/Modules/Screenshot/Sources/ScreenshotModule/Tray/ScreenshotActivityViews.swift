import NotchUI
import SwiftUI

/// Icon in the 64 pt beside the closed notch.
struct ScreenshotActivityIcon: View {
    let systemImage: String

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(NotchTokens.primaryText)
    }
}

/// The new capture, 16 pt, or the camera when its thumbnail could not be made.
struct ScreenshotActivityThumbnail: View {
    let image: CGImage?

    var body: some View {
        if let image {
            Image(decorative: image, scale: 2)
                .resizable()
                .scaledToFill()
                .frame(width: 16, height: 16)
                .clipShape(RoundedRectangle(cornerRadius: 3))
        } else {
            ScreenshotActivityIcon(systemImage: "camera.viewfinder")
        }
    }
}

/// A short line in the 64 pt beside the closed notch; two lines at most, so "Đã chép 120 ký tự" fits.
struct ScreenshotActivityText: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(NotchTokens.primaryText)
            .multilineTextAlignment(.leading)
            .lineLimit(2)
            .minimumScaleFactor(0.8)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A short message over the open tab; activities would stay hidden until the notch closes.
struct ScreenshotToast: View {
    let text: String
    let systemImage: String

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.callout.weight(.semibold))
            .foregroundStyle(NotchTokens.primaryText)
            .lineLimit(2)
    }
}
