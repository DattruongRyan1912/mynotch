import AppKit
import SwiftUI

/// Counts the passes in which SwiftUI evaluates and lays out the views of a hosting view.
final class CountingHostingView<Content: View>: NSHostingView<Content> {
    private(set) var layouts = 0

    override func layout() {
        layouts += 1
        super.layout()
    }
}
