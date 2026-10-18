import CoreGraphics
import CoreMedia
import Foundation
import Testing
@testable import ScreenshotModule

/// The stream's settings only; nothing here starts a stream, asks for a permission or reads the screen.
@Suite struct ScreenCaptureKitSourceTests {
    static let display = DisplayInfo(id: 3, frame: CGRect(x: 0, y: 0, width: 1000, height: 600), scale: 2)

    func configuration(options: RecordingOptions = RecordingOptions()) throws -> RecordingSourceConfiguration {
        let region = try #require(RecordingRegion(display: Self.display, selection: CGRect(x: 100, y: 100, width: 400, height: 300)))
        return RecordingSourceConfiguration(region: region, options: options)
    }

    @Test func theStreamCoversTheRegionAtItsOwnPixelSize() throws {
        let stream = ScreenCaptureKitSource.makeConfiguration(for: try configuration())

        // 400 × 300 pt at 2× is 800 × 600 px, taken from 100 pt from the left and (600 − 400) = 200 pt from the top.
        #expect(stream.width == 800 && stream.height == 600)
        #expect(stream.sourceRect == CGRect(x: 100, y: 200, width: 400, height: 300))
    }

    @Test func itRunsAtTheAskedFrameRateWithTheCursorDrawnIn() throws {
        let stream = ScreenCaptureKitSource.makeConfiguration(for: try configuration(options: .init(fps: 60)))

        #expect(stream.minimumFrameInterval == CMTime(value: 1, timescale: 60))
        #expect(stream.showsCursor)
        #expect(stream.pixelFormat == kCVPixelFormatType_32BGRA)
        #expect(stream.queueDepth == 6)
        #expect(ScreenCaptureKitSource.makeConfiguration(for: try configuration(options: .init(fps: 30))).minimumFrameInterval == CMTime(value: 1, timescale: 30))
    }

    @Test func theDefaultMicrophoneIsCapturedWithoutNamingADevice() throws {
        let stream = ScreenCaptureKitSource.makeConfiguration(for: try configuration(options: .init(microphone: .systemDefault)))

        #expect(stream.captureMicrophone)
        #expect(stream.microphoneCaptureDeviceID == nil)
    }

    @Test func aChosenMicrophoneIsCapturedByItsID() throws {
        let stream = ScreenCaptureKitSource.makeConfiguration(for: try configuration(options: .init(microphone: .device("BuiltInMicrophoneDevice"))))

        #expect(stream.captureMicrophone)
        #expect(stream.microphoneCaptureDeviceID == "BuiltInMicrophoneDevice")
    }

    @Test func noMicrophoneIsOpenedWhenNoneIsAsked() throws {
        let stream = ScreenCaptureKitSource.makeConfiguration(for: try configuration(options: .init(microphone: nil)))

        #expect(!stream.captureMicrophone)
    }

    @Test func systemAudioIsOffUnlessAskedAndNeverIncludesMyNotchsOwnSound() throws {
        let off = ScreenCaptureKitSource.makeConfiguration(for: try configuration())
        let on = ScreenCaptureKitSource.makeConfiguration(for: try configuration(options: .init(systemAudio: true)))

        #expect(!off.capturesAudio)
        #expect(on.capturesAudio)
        #expect(on.excludesCurrentProcessAudio && off.excludesCurrentProcessAudio)
        #expect(on.sampleRate == 48_000)
    }
}
