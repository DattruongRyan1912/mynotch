import CoreGraphics
import Foundation
import Testing
@testable import ScreenshotModule

/// The crop is part of the document: saved, restored, and what makes a document an edit.
@Suite struct MarkupCropDocumentTests {
    let size = CGSize(width: 400, height: 300)

    @Test func theCropSurvivesTheJSONRoundTrip() throws {
        var document = MarkupDocument(imageSize: size, annotations: [.redact(CGRect(x: 10, y: 10, width: 20, height: 20))])
        document.crop = CGRect(x: 40, y: 30, width: 200, height: 120)

        let decoded = try JSONDecoder().decode(MarkupDocument.self, from: JSONEncoder().encode(document))

        #expect(decoded == document)
        #expect(decoded.crop == CGRect(x: 40, y: 30, width: 200, height: 120))
    }

    @Test func markupSavedBeforeCroppingOpensWithoutACrop() throws {
        let json = #"{"imageSize":[40,50],"annotations":[]}"#
        let decoded = try JSONDecoder().decode(MarkupDocument.self, from: Data(json.utf8))
        #expect(decoded.crop == nil)
    }

    @Test func aCropIsAnEditEvenWithoutAnnotations() {
        var document = MarkupDocument(imageSize: size)
        #expect(!document.hasEdits)
        document.crop = CGRect(x: 0, y: 0, width: 100, height: 100)
        #expect(document.hasEdits)
        #expect(MarkupDocument(imageSize: size, annotations: [.redact(.zero)]).hasEdits)
    }

    @Test func theOutputIsTheCaptureUntilItIsCropped() {
        let document = MarkupDocument(imageSize: size)
        #expect(document.outputBounds == CGRect(x: 0, y: 0, width: 400, height: 300))
        #expect(document.cropWithinCanvas == nil)
    }

    @Test func theOutputIsTheCropInsideTheCapture() {
        var document = MarkupDocument(imageSize: size)
        document.crop = CGRect(x: 40, y: 30, width: 200, height: 120)
        #expect(document.outputBounds == CGRect(x: 40, y: 30, width: 200, height: 120))
        #expect(document.cropWithinCanvas == CGRect(x: 40, y: 30, width: 200, height: 120))
    }

    @Test func aCropMayReachIntoThePaddingTheAnnotationsGrew() {
        var document = MarkupDocument(imageSize: size, annotations: [.step(number: 1, at: CGPoint(x: 395, y: 100), radius: 10, color: .red)])
        // The badge's ink reaches x = 405, 5 past the capture, and the crop takes all of that.
        document.crop = CGRect(x: 300, y: 50, width: 105, height: 100)
        #expect(document.outputBounds == CGRect(x: 300, y: 50, width: 105, height: 100))
        document.crop = CGRect(x: 300, y: 50, width: 120, height: 100)
        #expect(document.outputBounds == CGRect(x: 300, y: 50, width: 105, height: 100))
    }

    @Test func aCropPastTheCanvasIsClippedToIt() {
        var document = MarkupDocument(imageSize: size)
        document.crop = CGRect(x: 300, y: 200, width: 500, height: 500)
        #expect(document.outputBounds == CGRect(x: 300, y: 200, width: 100, height: 100))
    }

    @Test func aCropThatMissesTheCanvasIsIgnored() {
        var document = MarkupDocument(imageSize: size)
        document.crop = CGRect(x: 900, y: 900, width: 50, height: 50)
        #expect(document.cropWithinCanvas == nil)
        #expect(document.outputBounds == CGRect(x: 0, y: 0, width: 400, height: 300))
    }

    @Test func everyAnnotationReportsItsInkIncludingRedactionAndErasing() {
        let style = Annotation.StrokeStyle(color: .red, width: 6)
        #expect(Annotation.redact(CGRect(x: 10, y: 20, width: 30, height: 40)).inkBounds == CGRect(x: 10, y: 20, width: 30, height: 40))
        #expect(Annotation.erase(CGRect(x: 40, y: 20, width: -30, height: 40)).inkBounds == CGRect(x: 10, y: 20, width: 30, height: 40))
        #expect(Annotation.rectangle(CGRect(x: 10, y: 20, width: 100, height: 50), style: style).inkBounds == CGRect(x: 7, y: 17, width: 106, height: 56))
        let step = Annotation.step(number: 1, at: CGPoint(x: 50, y: 50), radius: 10, color: .red)
        #expect(step.inkBounds == CGRect(x: 40, y: 40, width: 20, height: 20))
    }
}
