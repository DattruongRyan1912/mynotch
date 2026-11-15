import NotchUI
import SwiftUI

/// Animated circular spinner using NotchTokens for theme-aware coloring.
struct ScreenshotSpinnerView: View {
    @State private var isAnimating = false

    var body: some View {
        Circle()
            .trim(from: 0, to: 0.72)
            .stroke(NotchTokens.primaryText, style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
            .frame(width: 13, height: 13)
            .rotationEffect(.degrees(isAnimating ? 360 : 0))
            .animation(.linear(duration: 0.8).repeatForever(autoreverses: false), value: isAnimating)
            .onAppear { isAnimating = true }
    }
}

/// Icon in the 64 pt beside the closed notch.
struct ScreenshotActivityIcon: View {
    let systemImage: String
    var isProcessing: Bool = false

    var body: some View {
        if isProcessing {
            ScreenshotSpinnerView()
        } else {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(NotchTokens.primaryText)
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
    var isProcessing: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            if isProcessing {
                ScreenshotSpinnerView()
            } else {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(NotchTokens.primaryText)
            }
            Text(text)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(NotchTokens.primaryText)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Capsule().fill(NotchTokens.fill(0.18)))
        .overlay(Capsule().strokeBorder(NotchTokens.fill(0.24), lineWidth: 1))
        .fixedSize()
    }
}
