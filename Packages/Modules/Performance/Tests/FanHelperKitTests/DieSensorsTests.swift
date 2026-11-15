import Foundation
import Testing
@testable import FanHelperKit

/// A channel that lists its keys, as the real SMC does.
struct ListedChannel: SMCChannel {
    var keys: [(name: String, type: String, bytes: [UInt8])]

    func keyName(at index: Int) -> String? { index == 0 ? "#KEY" : keys.indices.contains(index - 1) ? keys[index - 1].name : nil }

    func info(of key: String) -> SMCKeyInfo? {
        if key == "#KEY" { return SMCKeyInfo(size: 4, type: "ui32") }
        return keys.first { $0.name == key }.map { SMCKeyInfo(size: $0.bytes.count, type: $0.type) }
    }

    func bytes(of key: String, info: SMCKeyInfo) -> [UInt8]? {
        if key == "#KEY" {
            let count = UInt32(keys.count + 1)
            return [UInt8(count >> 24), UInt8(count >> 16 & 0xff), UInt8(count >> 8 & 0xff), UInt8(count & 0xff)]
        }
        return keys.first { $0.name == key }?.bytes
    }
}

@Suite struct DieSensorsTests {
    static func float(_ value: Float) -> [UInt8] {
        let bits = value.bitPattern
        return [UInt8(bits & 0xff), UInt8(bits >> 8 & 0xff), UInt8(bits >> 16 & 0xff), UInt8(bits >> 24 & 0xff)]
    }

    func channel() -> ListedChannel {
        ListedChannel(keys: [
            ("TCMz", "flt ", Self.float(99)),          // an aggregate: not a die sensor
            ("Tp00", "flt ", Self.float(63.4)), ("Tp01", "flt ", Self.float(81.5)), ("Te01", "flt ", Self.float(73.9)),
            ("Tg05", "flt ", Self.float(68.1)), ("Tg0H", "ioft", [0, 0, 0, 0, 0, 0, 0, 0]),
            ("Ta05", "flt ", Self.float(8.5)),
        ])
    }

    @Test func theHottestDieSensorIsTheHottestOfTheCPUAndTheGPUKeysAndNothingElse() throws {
        let channel = channel()
        let sensors = try #require(DieSensors(channel: channel))
        #expect(sensors.hottest(on: channel) == Double(Float(81.5)))
    }

    @Test func aSensorThatReadsImplausiblyIsLeftOut() throws {
        var channel = channel()
        channel.keys[2].bytes = Self.float(0)
        channel.keys[1].bytes = Self.float(0)
        let sensors = try #require(DieSensors(channel: channel))
        #expect(sensors.hottest(on: channel) == Double(Float(73.9)))
    }

    @Test func noDieSensorsIsNoReader() {
        #expect(DieSensors(channel: ListedChannel(keys: [("TCMz", "flt ", Self.float(70))])) == nil)
        #expect(DieSensors(channel: FanKeysChannel()) == nil)
    }
}
