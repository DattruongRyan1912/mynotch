import AppKit
import MyNotchCore
import MyNotchTestSupport
import SwiftUI
import Testing
@testable import NotchUI

/// A module that draws in the open notch and tests where the pointer is needs to know where its content really is.
@Suite struct NotchContentFrameTests {
    let macBook = NotchGeometry(screen: NotchGeometryTests.macBook14, config: NotchLayoutConfig())

    @Test func startsBelowTheNotchBodyInsideTheCornersAndPadding() {
        // 600 wide and centred 1.5 pt left of the screen's middle; 22 pt in from each side (8 corner + 14 padding).
        let frame = macBook.contentFrame(height: 88, in: NotchGeometryTests.macBook14.frame)
        #expect(frame == CGRect(x: 454.5 + 22, y: 982 - 32 - 88, width: 556, height: 88))
    }

    @Test func followsTheConfiguredOpenWidth() {
        let narrow = NotchGeometry(screen: NotchGeometryTests.macBook14, config: NotchLayoutConfig(openWidth: 480))
        let sides: CGFloat = 44
        #expect(narrow.contentFrame(height: 50, in: NotchGeometryTests.macBook14.frame).width == CGFloat(480) - sides)
        let wide = NotchGeometry(screen: NotchGeometryTests.macBook14, config: NotchLayoutConfig(openWidth: 9999))
        #expect(wide.contentFrame(height: 50, in: NotchGeometryTests.macBook14.frame).width == NotchGeometry.maxOpenWidth - sides)
    }

    @Test func staysOnAScreenWhoseOriginIsNotZeroAndUsesItsOwnNotchHeight() {
        let geometry = NotchGeometry(screen: NotchGeometryTests.external, config: NotchLayoutConfig())
        let frame = geometry.contentFrame(height: 88, in: NotchGeometryTests.external.frame)
        #expect(frame == CGRect(x: 1512 + 960 - 300 + 22, y: 1080 - 25 - 88, width: 556, height: 88))
        let above = NotchGeometry(screen: NotchGeometryTests.externalAboveLeft, config: NotchLayoutConfig())
        let top: CGFloat = 982 + 1080 - 25
        #expect(above.contentFrame(height: 88, in: NotchGeometryTests.externalAboveLeft.frame).maxY == top)
    }

    // MARK: the picture

    /// The area SwiftUI really gives a toast's content, found by filling it with a colour and measuring: a toast of a
    /// notch with no tab under it, drawn offscreen at the panel's size.
    func measuredContent(of geometry: NotchGeometry, screen: ScreenDescriptor) throws -> CGRect {
        let harness = RegistryHarness([])
        let model = NotchViewModel(scheduler: harness.scheduler, availableTabs: { [] }, delays: { (.zero, .zero) })
        model.showToast(AnyView(Color(.sRGB, red: 1, green: 0, blue: 0)), duration: .seconds(60))
        let view = NotchRootView(model: model, activities: harness.activities, registry: harness.registry, geometry: geometry)
            .frame(width: geometry.panelSize.width, height: geometry.panelSize.height)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        let bitmap = NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
        var minX = Int.max, maxX = -1, minY = Int.max, maxY = -1
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                guard let color = bitmap.colorAt(x: x, y: y), color.redComponent > 0.9, color.greenComponent < 0.1 else { continue }
                (minX, maxX, minY, maxY) = (min(minX, x), max(maxX, x), min(minY, y), max(maxY, y))
            }
        }
        try #require(maxX >= 0, "the toast's colour is drawn")
        // From the bitmap (x right, y down from the panel's top left) to the screen (y up).
        let panel = geometry.panelFrame(in: screen.frame)
        return CGRect(
            x: panel.minX + CGFloat(minX), y: panel.maxY - CGFloat(maxY + 1), width: CGFloat(maxX - minX + 1), height: CGFloat(maxY - minY + 1)
        )
    }

    @Test func theMathIsWhereTheViewReallyPutsAToastsContent() throws {
        for (screen, config) in [
            (NotchGeometryTests.macBook14, NotchLayoutConfig()),
            (NotchGeometryTests.macBook14, NotchLayoutConfig(openWidth: 480)),
            (NotchGeometryTests.external, NotchLayoutConfig(virtualNotchWidth: 240, openWidth: 700)),
        ] {
            let geometry = NotchGeometry(screen: screen, config: config)
            let measured = try measuredContent(of: geometry, screen: screen)
            // The toast of a notch with no tab is `NotchTab.defaultHeight` tall, with the padding below the content.
            let expected = geometry.contentFrame(height: NotchTab.defaultHeight - NotchTokens.padding, in: screen.frame)
            #expect(measured == expected, "\(screen.frame) \(config)")
        }
    }
}
