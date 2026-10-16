import Foundation
import ObjectiveC
import Testing
@testable import FanHelperKit

/// An archive that says it holds a ping but has only some of the fields.
@objc(MyNotchTestPartialPing)
final class PartialPing: NSObject, NSSecureCoding {
    static let supportsSecureCoding = true
    override init() { super.init() }
    required init?(coder: NSCoder) { nil }
    func encode(with coder: NSCoder) { coder.encode("1" as NSString, forKey: "version") }
}

@Suite struct FanHelperProtocolTests {
    func roundTrip<T: NSObject & NSSecureCoding>(_ object: T) throws -> T {
        let data = try NSKeyedArchiver.archivedData(withRootObject: object, requiringSecureCoding: true)
        let decoded = try NSKeyedUnarchiver.unarchivedObject(ofClass: T.self, from: data)
        return try #require(decoded)
    }

    @Test func aPingSurvivesSecureCoding() throws {
        let ping = FanHelperPing(version: "1", buildID: "0a1b2c3d4e5f60718293a4b5c6d7e8f901234567", euid: 0, pid: 4321)
        let decoded = try roundTrip(ping)
        #expect(decoded.version == "1")
        #expect(decoded.buildID == "0a1b2c3d4e5f60718293a4b5c6d7e8f901234567")
        #expect(decoded.euid == 0 && decoded.pid == 4321)
    }

    @Test func aFanSurvivesSecureCoding() throws {
        let fan = FanHelperFan(index: 1, rpm: 5635.25, minRPM: 1200, maxRPM: 6241, mode: 0, target: 5653)
        let decoded = try roundTrip(fan)
        #expect(decoded.index == 1)
        #expect(decoded.rpm == 5635.25 && decoded.minRPM == 1200 && decoded.maxRPM == 6241)
        #expect(decoded.mode == 0 && decoded.target == 5653)
    }

    @Test func aFanWithoutModeOrTargetKeepsThemUnknown() throws {
        let decoded = try roundTrip(FanHelperFan(index: 0, rpm: 3000, minRPM: 1200, maxRPM: 5779))
        #expect(decoded.mode == FanHelperFan.unknown && decoded.target == FanHelperFan.unknown)
    }

    @Test func aPingMissingItsFieldsIsNotDecoded() {
        let archiver = NSKeyedArchiver(requiringSecureCoding: true)
        archiver.setClassName("MyNotchFanHelperPing", for: PartialPing.self)
        archiver.encode(PartialPing(), forKey: NSKeyedArchiveRootObjectKey)
        archiver.finishEncoding()
        let decoded = try? NSKeyedUnarchiver.unarchivedObject(ofClass: FanHelperPing.self, from: archiver.encodedData)
        #expect(decoded == nil)
    }

    @Test func theInterfaceNamesTheClassesEachReplyMayContain() throws {
        let interface = FanHelperInterface.make()
        let ping = interface.classes(for: #selector(FanHelperProtocol.ping(reply:)), argumentIndex: 0, ofReply: true)
        #expect(ping.contains { $0 as? AnyClass === FanHelperPing.self })
        let fans = interface.classes(for: #selector(FanHelperProtocol.readFans(reply:)), argumentIndex: 0, ofReply: true)
        #expect(fans.contains { $0 as? AnyClass === NSArray.self })
        #expect(fans.contains { $0 as? AnyClass === FanHelperFan.self })
    }

    /// There is no write operation: the protocol has these two methods and no others, so a connection cannot ask for more.
    @Test func theProtocolHasTheTwoSpikeOperationsAndNothingElse() throws {
        let proto = try #require(objc_getProtocol("MyNotchFanHelperProtocol"))
        var count: UInt32 = 0
        let required = protocol_copyMethodDescriptionList(proto, true, true, &count)
        defer { free(required) }
        let names = (0..<Int(count)).map { NSStringFromSelector(required![$0].name!) }.sorted()
        #expect(names == ["pingWithReply:", "readFansWithReply:"])
        var optionalCount: UInt32 = 0
        free(protocol_copyMethodDescriptionList(proto, false, true, &optionalCount))
        #expect(optionalCount == 0)
        var classMethods: UInt32 = 0
        free(protocol_copyMethodDescriptionList(proto, true, false, &classMethods))
        #expect(classMethods == 0)
    }
}
