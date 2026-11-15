import CoreGraphics
import Testing
@testable import ScreenshotModule

@Suite struct AnnotationExtentTests {
    let image = CGSize(width: 400, height: 300)
    let style = Annotation.StrokeStyle(color: .red, width: 6)

    @Test func shapesInsideTheImageNeverGrowTheCanvas() {
        let inside: [Annotation] = [
            .arrow(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 390, y: 290), style: style),
            .rectangle(CGRect(x: 10, y: 10, width: 100, height: 100), style: style),
            .text("Chào", at: CGPoint(x: 20, y: 20), fontSize: 24, color: .red),
            .highlighter(points: [CGPoint(x: 10, y: 10), CGPoint(x: 200, y: 20)], color: .yellow, width: 20),
            .step(number: 1, at: CGPoint(x: 50, y: 50), radius: 12, color: .red),
            .magnifier(center: CGPoint(x: 200, y: 150), radius: 40, zoom: 2, style: style),
            .ruler(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 300, y: 100), style: style, fontSize: 14, scale: 2),
        ]
        for annotation in inside { #expect(annotation.extent(beyond: image) == nil, "\(annotation)") }
    }

    @Test func aStrokeWhoseCentreLineSitsOnTheEdgeDoesNotAddASliverOfPadding() {
        let flush = Annotation.rectangle(CGRect(x: 0, y: 0, width: 400, height: 300), style: style)
        #expect(flush.extent(beyond: image) == nil)
        let arrow = Annotation.arrow(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 400, y: 150), style: style)
        #expect(arrow.extent(beyond: image) == nil)
    }

    @Test func strokesPastTheEdgeReportTheirFullInkIncludingTheStrokeWidth() throws {
        let rectangle = try #require(Annotation.rectangle(CGRect(x: -10, y: 20, width: 100, height: 50), style: style).extent(beyond: image))
        #expect(rectangle == CGRect(x: -13, y: 17, width: 106, height: 56))
        let arrow = try #require(Annotation.arrow(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 450, y: 10), style: style).extent(beyond: image))
        #expect(arrow.maxX >= 450 + style.width / 2)
        #expect(arrow.minX <= 10 - style.width / 2)
        let highlighter = try #require(Annotation.highlighter(points: [CGPoint(x: 10, y: 10), CGPoint(x: 10, y: 320)], color: .yellow, width: 20).extent(beyond: image))
        #expect(highlighter == CGRect(x: 0, y: 0, width: 20, height: 330))
    }

    @Test func textReportsItsMeasuredBox() throws {
        let text = Annotation.text("Hello\nWorld", at: CGPoint(x: 20, y: 280), fontSize: 40, color: .black)
        let extent = try #require(text.extent(beyond: image))
        #expect(extent.origin == CGPoint(x: 20, y: 280))
        #expect(extent.height > 2 * 40)
        #expect(extent.width > 40)
        #expect(extent.maxY > 300)
    }

    @Test func badgesLensesAndRulersReportWhereTheyReachPastTheEdge() throws {
        let step = try #require(Annotation.step(number: 1, at: CGPoint(x: 395, y: 100), radius: 10, color: .red).extent(beyond: image))
        #expect(step == CGRect(x: 385, y: 90, width: 20, height: 20))
        let lens = try #require(Annotation.magnifier(center: CGPoint(x: 390, y: 150), radius: 30, zoom: 2, style: style).extent(beyond: image))
        #expect(lens == CGRect(x: 357, y: 117, width: 66, height: 66))
        let ruler = try #require(Annotation.ruler(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 450, y: 100), style: style, fontSize: 14, scale: 1).extent(beyond: image))
        #expect(ruler.minX <= 100 && ruler.maxX >= 450)
    }

    @Test func redactionAndErasingWorkOnPixelsAndNeverGrowTheCanvas() {
        #expect(Annotation.redact(CGRect(x: -50, y: -50, width: 600, height: 600)).extent(beyond: image) == nil)
        #expect(Annotation.erase(CGRect(x: -50, y: -50, width: 600, height: 600)).extent(beyond: image) == nil)
    }
}
