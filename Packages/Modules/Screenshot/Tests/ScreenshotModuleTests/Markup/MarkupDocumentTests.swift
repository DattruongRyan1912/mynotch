import CoreGraphics
import Foundation
import Testing
@testable import ScreenshotModule

@Suite struct MarkupDocumentTests {
    static let everyKind = MarkupDocument(imageSize: CGSize(width: 3024, height: 1964), annotations: [
        .arrow(from: CGPoint(x: 10, y: 20), to: CGPoint(x: 300.5, y: 40.25), style: .init(color: .red, width: 8)),
        .rectangle(CGRect(x: 50, y: 60, width: 200, height: 100), style: .init(color: .blue, width: 4)),
        .text("Xin chào — Ảnh chụp", at: CGPoint(x: 70, y: 80), fontSize: 48, color: .black),
        .highlighter(points: [CGPoint(x: 1, y: 2), CGPoint(x: 3, y: 4), CGPoint(x: 5, y: 4)], color: .yellow, width: 32),
        .redact(CGRect(x: 400, y: 500, width: 120, height: 30)),
        .step(number: 3, at: CGPoint(x: 90, y: 100), radius: 28, color: .green),
        .magnifier(center: CGPoint(x: 600, y: 300), radius: 80, zoom: 2.5, style: .init(color: .blue, width: 8)),
        .ruler(from: CGPoint(x: 10, y: 900), to: CGPoint(x: 250, y: 900), style: .init(color: .red, width: 4), fontSize: 14, scale: 2),
        .erase(CGRect(x: 40, y: 50, width: 60, height: 20)),
    ])

    @Test func codableRoundTripKeepsEveryAnnotation() throws {
        let data = try JSONEncoder().encode(Self.everyKind)
        let decoded = try JSONDecoder().decode(MarkupDocument.self, from: data)
        #expect(decoded == Self.everyKind)
    }

    @Test func newDocumentHasNoAnnotations() {
        #expect(MarkupDocument(imageSize: CGSize(width: 4, height: 3)).annotations.isEmpty)
    }

    @Test func offersFiveNamedPresets() {
        #expect(RGBAColor.presets.map(\.name) == ["Đỏ", "Vàng", "Xanh lá", "Xanh dương", "Đen"])
        #expect(RGBAColor.presets.map(\.color) == [.red, .yellow, .green, .blue, .black])
        #expect(RGBAColor.black == RGBAColor(r: 0, g: 0, b: 0))
        for color in RGBAColor.presets.map(\.color) {
            #expect([color.r, color.g, color.b, color.a].allSatisfy { (0...1).contains($0) })
            #expect(color.a == 1)
        }
    }

    @Test func theCanvasFillFollowsTheSettingsSoItIsNotSavedWithTheAnnotations() throws {
        var document = Self.everyKind
        document.canvasFill = .black
        let json = try #require(String(data: JSONEncoder().encode(document), encoding: .utf8))
        #expect(!json.contains("canvasFill") && !json.contains("black"))
        let decoded = try JSONDecoder().decode(MarkupDocument.self, from: Data(json.utf8))
        #expect(decoded.canvasFill == .standard)
        #expect(decoded.annotations == document.annotations)
    }

    @Test func markupSavedBeforeTheNewToolsStillOpens() throws {
        let json = #"""
        {"imageSize":[40,50],"annotations":[{"redact":{"_0":[[0,0],[40,50]]}}]}
        """#
        let decoded = try JSONDecoder().decode(MarkupDocument.self, from: Data(json.utf8))
        #expect(decoded.annotations == [.redact(CGRect(x: 0, y: 0, width: 40, height: 50))])
        #expect(decoded.canvas.isZero)
    }

    @Test func theCanvasIsDerivedFromTheAnnotationsThatStickOut() {
        var document = MarkupDocument(imageSize: CGSize(width: 400, height: 300), annotations: [
            .step(number: 1, at: CGPoint(x: 100, y: 100), radius: 10, color: .red),
        ])
        #expect(document.canvas.isZero)
        document.annotations.append(.step(number: 2, at: CGPoint(x: 395, y: 100), radius: 10, color: .red))
        #expect(document.canvas == CanvasInsets(left: 0, top: 0, right: 5, bottom: 0))
        document.annotations.append(.step(number: 3, at: CGPoint(x: 100, y: -4), radius: 10, color: .red))
        #expect(document.canvas == CanvasInsets(left: 0, top: 14, right: 5, bottom: 0))
        document.annotations.removeLast()
        document.annotations.removeLast()
        #expect(document.canvas.isZero)
    }
}
