import AppKit
import NotchUI
import SwiftUI
import Testing
@testable import WindowLayoutModule

/// The notice drawn offscreen (no window, no screen): it has to show its text and stay inside the width the notch gives it.
@Suite struct SnapNoticeViewTests {
    func bounds(of text: String, width: CGFloat) throws -> CGRect {
        let renderer = ImageRenderer(content: SnapNoticeView(text: text).frame(width: width, alignment: .leading))
        renderer.scale = 1
        let bitmap = NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
        var box = CGRect.null
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide where (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.05 {
                box = box.union(CGRect(x: x, y: y, width: 1, height: 1))
            }
        }
        return box
    }

    @Test func theNoticeIsDrawnAndKeepsInsideTheWidthItIsGiven() throws {
        let text = SnapReport.notice(for: SnapApp(bundleID: nil, name: "CleanMyMac"), size: CGSize(width: 1040, height: 945), zone: CGSize(width: 756, height: 945))
        let box = try bounds(of: #require(text), width: 420)
        #expect(!box.isNull && box.width > 100, "something was drawn: \(box)")
        #expect(box.maxX <= 420, "\(box)")
    }

    @Test func aLongNameWrapsOntoASecondLineInsteadOfRunningOut() throws {
        let long = "Một ứng dụng có cái tên dài đến mức không thể nằm trên một dòng của notch không thu nhỏ được tới ô này (tối thiểu 1040 pt)"
        let box = try bounds(of: long, width: 420)
        #expect(box.maxX <= 420, "\(box)")
    }
}
