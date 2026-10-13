import SwiftUI

/// Shared look of the notch. Modules use these instead of hard-coded values.
public enum NotchTokens {
    public static let background = Color.black
    public static let accent = Color(red: 0.49, green: 0.36, blue: 1.0)
    public static let primaryText = Color.white
    public static let secondaryText = Color.white.opacity(0.6)
    public static let padding: CGFloat = 14
    public static let spring = Animation.spring(response: 0.38, dampingFraction: 0.8)
}
