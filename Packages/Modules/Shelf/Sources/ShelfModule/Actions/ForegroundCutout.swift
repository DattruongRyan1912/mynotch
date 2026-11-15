import CoreGraphics
import CoreImage
import CoreVideo
import Foundation
import Vision

/// Cuts the subject out of an image. A protocol so tests of the actions need no Vision model.
nonisolated protocol ForegroundCutting: Sendable {
    /// `image` with everything but the foreground made transparent. Throws `FileActionError.noSubject` when
    /// there is no subject.
    func cutOut(_ image: CGImage) async throws -> CGImage
}

/// `VNGenerateForegroundInstanceMaskRequest`, which runs on the device and needs no network.
nonisolated struct VisionForegroundCutter: ForegroundCutting {
    @concurrent
    func cutOut(_ image: CGImage) async throws -> CGImage {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            throw FileActionError.cutOutFailed
        }
        guard let observation = request.results?.first, !observation.allInstances.isEmpty else { throw FileActionError.noSubject }
        try Task.checkCancellation()
        guard let buffer = try? observation.generateMaskedImage(ofInstances: observation.allInstances, from: handler, croppedToInstancesExtent: false),
              let result = Self.cgImage(from: buffer) else { throw FileActionError.cutOutFailed }
        return result
    }

    /// The masked picture Vision makes, with its transparency, as a plain image.
    static func cgImage(from buffer: CVPixelBuffer) -> CGImage? {
        let image = CIImage(cvPixelBuffer: buffer)
        return CIContext().createCGImage(image, from: image.extent, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
    }
}
