import CoreGraphics

/// Reads the text in an image. A protocol so the module's tests need no Vision.
protocol TextRecognizing: AnyObject {
    func recognize(_ image: CGImage, languages: [String]) async throws -> String
}

/// Vision's recognition, which `OCRService` runs off the main actor.
final class VisionTextRecognizer: TextRecognizing {
    func recognize(_ image: CGImage, languages: [String]) async throws -> String {
        try await OCRService().recognize(image, languages: languages)
    }
}
