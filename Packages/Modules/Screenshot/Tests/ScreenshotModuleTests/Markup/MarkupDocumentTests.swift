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
}
