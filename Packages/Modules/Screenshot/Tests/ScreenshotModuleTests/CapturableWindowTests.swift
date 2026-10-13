import CoreGraphics
import Foundation
import Testing
@testable import ScreenshotModule

@Suite struct CapturableWindowTests {
    /// Mirrors one `CGWindowListCopyWindowInfo` entry, whose numbers arrive bridged as `NSNumber`.
    static func entry(id: Int = 7, pid: Int = 42, layer: Int = 0, bounds: CGRect = CGRect(x: 10, y: 20, width: 300, height: 200)) -> [String: Any] {
        [
            kCGWindowNumber as String: NSNumber(value: id),
            kCGWindowOwnerPID as String: NSNumber(value: pid),
            kCGWindowLayer as String: NSNumber(value: layer),
            kCGWindowBounds as String: bounds.dictionaryRepresentation,
            kCGWindowOwnerName as String: "Safari",
            kCGWindowName as String: "Apple",
        ]
    }

    @Test func parsesWindowListEntries() {
        let windows = CapturableWindow.parse([Self.entry(), Self.entry(id: 8, pid: 43, layer: 25)])
        #expect(windows == [
            CapturableWindow(id: 7, ownerPID: 42, layer: 0, bounds: CGRect(x: 10, y: 20, width: 300, height: 200), ownerName: "Safari", title: "Apple"),
            CapturableWindow(id: 8, ownerPID: 43, layer: 25, bounds: CGRect(x: 10, y: 20, width: 300, height: 200), ownerName: "Safari", title: "Apple"),
        ])
    }

    @Test func namesAreOptional() {
        var entry = Self.entry()
        entry[kCGWindowOwnerName as String] = nil
        entry[kCGWindowName as String] = NSNumber(value: 1)
        let window = CapturableWindow.parse([entry]).first
        #expect(window?.id == 7)
        #expect(window?.ownerName == nil)
        #expect(window?.title == nil)
    }

    @Test func skipsMalformedEntries() {
        var missingID = Self.entry()
        missingID[kCGWindowNumber as String] = nil
        var negativeID = Self.entry()
        negativeID[kCGWindowNumber as String] = NSNumber(value: -1)
        var textPID = Self.entry()
        textPID[kCGWindowOwnerPID as String] = "42"
        var missingLayer = Self.entry()
        missingLayer[kCGWindowLayer as String] = nil
        var garbageBounds = Self.entry()
        garbageBounds[kCGWindowBounds as String] = ["Width": 3] as NSDictionary
        var textBounds = Self.entry()
        textBounds[kCGWindowBounds as String] = "{{0, 0}, {10, 10}}"

        let windows = CapturableWindow.parse([missingID, negativeID, textPID, missingLayer, garbageBounds, textBounds, Self.entry(id: 9), [:]])
        #expect(windows.map(\.id) == [9])
    }
}
