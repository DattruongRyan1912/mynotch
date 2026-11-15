import AppKit
import MyNotchCore
import SwiftUI

/// Non-blocking Floating Toast Overlay positioned at the bottom center of the Dashboard.
/// Follows Linear / Vercel design principles: Dark Zinc 950 aesthetic, 1px hairline border,
/// non-blocking, zero layout shift, auto-dismissing.
struct DashboardToastOverlayView: View {
    let toastCenter: DashboardToastCenter

    var body: some View {
        VStack {
            Spacer()
            if let toast = toastCenter.currentToast {
                HStack(spacing: 8) {
                    if let systemImage = toast.systemImage {
                        Image(systemName: systemImage)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Color(red: 0.2, green: 0.8, blue: 0.5)) // Emerald green accent
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Color(red: 0.2, green: 0.8, blue: 0.5))
                    }

                    Text(toast.message)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white)
                        .lineLimit(1)

                    Button {
                        withAnimation(.easeOut(duration: 0.2)) {
                            toastCenter.dismiss()
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(Color.white.opacity(0.6))
                            .padding(4)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(red: 0.05, green: 0.05, blue: 0.06).opacity(0.92)) // Dark Zinc 950
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1) // 1px hairline border
                )
                .shadow(color: Color.black.opacity(0.25), radius: 8, x: 0, y: 4)
                .transition(.asymmetric(
                    insertion: .move(edge: .bottom).combined(with: .opacity),
                    removal: .opacity
                ))
                .padding(.bottom, 20)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: toastCenter.currentToast?.id)
        .allowsHitTesting(toastCenter.currentToast != nil)
    }
}
