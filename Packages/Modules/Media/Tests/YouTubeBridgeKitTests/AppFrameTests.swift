import Foundation
import Testing
@testable import YouTubeBridgeKit

@Suite struct AppFrameTests {
    @Test func aFrameIsABigEndianLengthThenThePayload() throws {
        let frame = try #require(AppFrame.encode(Data("abc".utf8)))
        #expect(Array(frame) == [0, 0, 0, 3, 0x61, 0x62, 0x63])
        let long = try #require(AppFrame.encode(Data(repeating: 0x20, count: 0x0102_03)))
        #expect(Array(long.prefix(4)) == [0, 1, 2, 3])
    }

    @Test func aPayloadOfMoreThanFourMebibytesIsNotEncoded() throws {
        #expect(AppFrame.maxLength == 4 << 20)
        #expect(AppFrame.encode(Data(repeating: 0x20, count: AppFrame.maxLength)) != nil)
        #expect(AppFrame.encode(Data(repeating: 0x20, count: AppFrame.maxLength + 1)) == nil)
    }

    @Test func theDecoderGivesBackWhatWasEncodedWhateverTheChunking() throws {
        let payloads = ["{\"a\":1}", "", String(repeating: "é", count: 3_000), "x"].map { Data($0.utf8) }
        let stream = payloads.reduce(into: Data()) { $0 += AppFrame.encode($1)! }
        for chunk in [1, 2, 3, 5, 100, stream.count] {
            var decoder = AppFrameDecoder()
            var frames: [Data] = []
            for start in stride(from: 0, to: stream.count, by: chunk) {
                decoder.append(stream[start..<min(start + chunk, stream.count)])
                while case .frame(let frame) = decoder.next() { frames.append(frame) }
            }
            #expect(frames == payloads, "chunk size \(chunk)")
            #expect(decoder.next() == .needMore)
        }
    }

    @Test func aPartialHeaderOrBodyWaitsForTheRest() throws {
        var decoder = AppFrameDecoder()
        #expect(decoder.next() == .needMore)
        decoder.append(Data([0, 0]))
        #expect(decoder.next() == .needMore)
        decoder.append(Data([0, 4, 1, 2]))
        #expect(decoder.next() == .needMore)
        decoder.append(Data([3, 4, 0, 0]))
        #expect(decoder.next() == .frame(Data([1, 2, 3, 4])))
        #expect(decoder.next() == .needMore)
        decoder.append(Data([0, 1, 7]))
        #expect(decoder.next() == .frame(Data([7])))
        #expect(decoder.next() == .needMore)
    }

    @Test func aLengthAboveTheLimitIsReportedAndStaysReported() {
        var decoder = AppFrameDecoder()
        decoder.append(Data([0x00, 0x40, 0x00, 0x01]) + Data("ignored".utf8))
        #expect(decoder.next() == .tooLarge(AppFrame.maxLength + 1))
        decoder.append(Data([0, 0, 0, 1, 1]))
        #expect(decoder.next() == .tooLarge(AppFrame.maxLength + 1))
    }

    @Test func aFrameOfExactlyTheLimitIsAccepted() throws {
        var decoder = AppFrameDecoder()
        decoder.append(try #require(AppFrame.encode(Data(repeating: 0x20, count: AppFrame.maxLength))))
        #expect(decoder.next() == .frame(Data(repeating: 0x20, count: AppFrame.maxLength)))
    }
}
