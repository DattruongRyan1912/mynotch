import AVFoundation
import CoreGraphics
import Foundation
import Testing
@testable import ScreenshotModule

@Suite struct ExportLevelTests {
    func plan(_ level: ExportLevel, _ width: Double, _ height: Double, fps: Int = 60) -> ExportPlan {
        level.plan(forVideoOfSize: CGSize(width: width, height: height), fps: fps)
    }

    // MARK: Gửi chat

    @Test func chatFitsInside1080pAndKeepsTheProportions() {
        let wide = plan(.chat, 3840, 2160)
        #expect(wide.size == CGSize(width: 1920, height: 1080))
        let retina = plan(.chat, 3456, 2234)
        #expect(retina.size.height == 1080)
        #expect(abs(retina.size.width / retina.size.height - 3456.0 / 2234) < 0.002)
    }

    @Test func chatNeverMakesTheVideoBigger() {
        #expect(plan(.chat, 1280, 720).size == CGSize(width: 1280, height: 720))
        #expect(plan(.chat, 1920, 1080).size == CGSize(width: 1920, height: 1080))
        #expect(plan(.chat, 400, 200).size == CGSize(width: 400, height: 200))
    }

    @Test func chatFitsAPortraitOrUltrawideRegionInsideTheSameBox() {
        // The box is 1920×1080, turned on its side for a region taller than it is wide.
        #expect(plan(.chat, 2160, 3840).size == CGSize(width: 1080, height: 1920))
        let ultrawide = plan(.chat, 5120, 1440)
        #expect(ultrawide.size == CGSize(width: 1920, height: 540))
        #expect(plan(.chat, 1000, 4000).size == CGSize(width: 480, height: 1920))
    }

    @Test func chatIsAtMostThirtyFramesASecond() {
        #expect(plan(.chat, 1920, 1080, fps: 60).frameRate == 30)
        #expect(plan(.chat, 1920, 1080, fps: 30).frameRate == 30)
        #expect(plan(.chat, 1920, 1080, fps: 24).frameRate == 24)
    }

    @Test func chatHasAboutFourToSixMegabitsAndAAC128() {
        for size in [CGSize(width: 1920, height: 1080), CGSize(width: 1280, height: 720), CGSize(width: 400, height: 200)] {
            let bitrate = plan(.chat, size.width, size.height).videoBitrate
            #expect((4_000_000...6_000_000).contains(bitrate), "\(size): \(bitrate)")
        }
        #expect(plan(.chat, 1920, 1080).audioBitrate == 128_000)
    }

    // MARK: Chất lượng cao

    @Test func highKeepsTheRecordingsSizeAndFrameRate() {
        let native = plan(.high, 2560, 1440, fps: 60)
        #expect(native.size == CGSize(width: 2560, height: 1440))
        #expect(native.frameRate == 60)
        #expect(plan(.high, 4096, 2304, fps: 30).size == CGSize(width: 4096, height: 2304))
        #expect(plan(.high, 4096, 2304, fps: 30).frameRate == 30)
    }

    @Test func highScalesAWiderRegionDownTo4096() {
        #expect(plan(.high, 5120, 2880, fps: 30).size == CGSize(width: 4096, height: 2304))
        #expect(plan(.high, 6016, 3384, fps: 30).size == CGSize(width: 4096, height: 2304))
        #expect(plan(.high, 8192, 1024).size == CGSize(width: 4096, height: 512))
    }

    @Test func highStaysInsideWhatH264Level52TakesWhateverTheRegionAndTheFrameRate() {
        // 36 864 macroblocks (16×16 pixels, each side counted up to whole blocks) in a frame, 2 073 600 a second: the hardware
        // encoder says yes to more and then writes level 6, which many players refuse.
        let regions: [(Double, Double, Int)] = [
            (5120, 3200, 30), (3000, 6000, 30), (5120, 2880, 60), (6016, 3384, 60), (4096, 2304, 60), (4096, 2304, 30), (3456, 2234, 60),
            (7680, 4320, 30), (2560, 1440, 120), (5120, 1440, 60), (4097, 2305, 60), (3840, 2160, 60), (1920, 1080, 60), (333, 777, 60),
        ]
        for (width, height, fps) in regions {
            let result = plan(.high, width, height, fps: fps)
            let blocks = ExportPlan.macroblocks(of: result.size)
            #expect(blocks <= 36_864, "\(width)×\(height): \(result.size) takes \(blocks) blocks")
            #expect(blocks * result.frameRate <= 2_073_600, "\(width)×\(height) at \(fps): \(blocks * result.frameRate) blocks a second")
            #expect(result.size.width <= 4096 && result.frameRate == fps)
            // The proportions are the region's, within the two pixels that making both sides even can cost.
            #expect(abs(result.size.width / result.size.height - width / height) < width / height * 0.02 + 0.01, "\(width)×\(height) became \(result.size)")
        }
    }

    @Test func highDoesNotShrinkWhatTheLevelTakesAndGivesUpAsLittleAsItMustWhenItDoesNot() {
        // 4K at 60 fps is within the level, and so is 4096×2304 at 30.
        #expect(plan(.high, 3840, 2160, fps: 60).size == CGSize(width: 3840, height: 2160))
        #expect(plan(.high, 4096, 2304, fps: 30).size == CGSize(width: 4096, height: 2304))
        #expect(plan(.high, 2560, 1440, fps: 60).size == CGSize(width: 2560, height: 1440))
        // A 5K display at 60 fps does not fit 4096×2304 (2 211 840 blocks a second): it is a little under 4K's width, not far under.
        let fiveK = plan(.high, 5120, 2880, fps: 60)
        #expect(fiveK.size.width < 4096 && fiveK.size.width > 3800)
        #expect(ExportPlan.macroblocks(of: fiveK.size) * 60 <= 2_073_600)
        // A size that is under the pixel limit but over the block limit once its sides are counted up is brought under it.
        #expect(ExportPlan.macroblocks(of: CGSize(width: 3884, height: 2428)) > 36_864)
    }

    @Test func macroblocksAreCountedInWholeBlocks() {
        #expect(ExportPlan.macroblocks(of: CGSize(width: 4096, height: 2304)) == 36_864)
        #expect(ExportPlan.macroblocks(of: CGSize(width: 3840, height: 2160)) == 32_400)
        #expect(ExportPlan.macroblocks(of: CGSize(width: 17, height: 16)) == 2)
        #expect(ExportPlan.macroblocks(of: CGSize(width: 2, height: 2)) == 1)
    }

    @Test func highHasMoreBitsThanChatAndAAC192() {
        let high = plan(.high, 3840, 2160, fps: 60)
        #expect(high.videoBitrate > 20_000_000)
        #expect(high.videoBitrate <= 60_000_000)
        #expect(high.audioBitrate == 192_000)
        #expect(plan(.high, 640, 360, fps: 30).videoBitrate >= 8_000_000)
    }

    // MARK: Whatever the level

    @Test func bothSidesAreAlwaysEvenAndPositive() {
        for level in ExportLevel.allCases {
            for (width, height) in [(1921.0, 1081.0), (4097.0, 2305.0), (3455.0, 2233.0), (5119.0, 2881.0), (7.0, 5.0), (2.0, 2.0), (1.0, 1.0)] {
                let size = plan(level, width, height).size
                #expect(Int(size.width) % 2 == 0 && Int(size.height) % 2 == 0 && size.width >= 2 && size.height >= 2, "\(level) \(width)×\(height) → \(size)")
            }
        }
    }

    @Test func anEmptyVideoGetsASafeSizeInsteadOfCrashing() {
        let size = plan(.chat, 0, 0).size
        #expect(size.width >= 2 && size.height >= 2)
        #expect(plan(.chat, 1920, 1080, fps: 0).frameRate >= 1)
    }

    @Test func theLevelsHaveTitlesAndRoundTrip() throws {
        #expect(ExportLevel.chat.title == "Gửi chat")
        #expect(ExportLevel.high.title == "Chất lượng cao")
        for level in ExportLevel.allCases {
            #expect(try JSONDecoder().decode(ExportLevel.self, from: JSONEncoder().encode(level)) == level)
        }
    }

    // MARK: What the writer is told

    @Test func theVideoSettingsAskForH264WithTheChosenSizeAndBitrate() throws {
        let value = plan(.chat, 3840, 2160)
        let settings = value.videoSettings
        #expect(settings[AVVideoCodecKey] as? AVVideoCodecType == .h264)
        #expect(settings[AVVideoWidthKey] as? Int == 1920)
        #expect(settings[AVVideoHeightKey] as? Int == 1080)
        let compression = try #require(settings[AVVideoCompressionPropertiesKey] as? [String: Any])
        #expect(compression[AVVideoAverageBitRateKey] as? Int == value.videoBitrate)
        #expect(compression[AVVideoExpectedSourceFrameRateKey] as? Int == 30)
        #expect(compression[AVVideoProfileLevelKey] as? String == AVVideoProfileLevelH264HighAutoLevel)
        #expect(compression[AVVideoAllowFrameReorderingKey] as? Bool == false)
        // Hardware is preferred by the system but not demanded: an export is not real time, and a Mac without it still works.
        #expect(settings[AVVideoEncoderSpecificationKey] == nil)
    }

    @Test func theAudioSettingsAskForStereoAACAtTheLevelsBitrate() {
        for level in ExportLevel.allCases {
            let value = plan(level, 1920, 1080)
            let settings = value.audioSettings
            #expect(settings[AVFormatIDKey] as? AudioFormatID == kAudioFormatMPEG4AAC)
            #expect(settings[AVNumberOfChannelsKey] as? Int == 2)
            #expect(settings[AVSampleRateKey] as? Int == 48_000)
            #expect(settings[AVEncoderBitRateKey] as? Int == value.audioBitrate)
        }
    }
}
