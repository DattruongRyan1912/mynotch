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

    @Test func aResultSurvivesSecureCoding() throws {
        let result = FanHelperResult(ok: true, state: .forced, appliedRPM: 3200, detail: "clamped to the fan's range", leaseSeconds: 14.5)
        let decoded = try roundTrip(result)
        #expect(decoded.ok && decoded.state == .forced)
        #expect(decoded.appliedRPM == 3200 && decoded.detail == "clamped to the fan's range" && decoded.leaseSeconds == 14.5)
    }

    @Test func aResultCarriesHowLongTheModesTookAndAnOlderOneWithoutItDecodesAsUnknown() throws {
        let timed = try roundTrip(FanHelperResult(ok: true, state: .forced, modeReadBackMS: 150))
        #expect(timed.modeReadBackMS == 150)
        #expect(FanHelperResult(ok: true, state: .forced).modeReadBackMS == -1)

        let archiver = NSKeyedArchiver(requiringSecureCoding: true)
        archiver.setClassName("MyNotchFanHelperResult", for: ResultBeforeTheLatencyField.self)
        archiver.encode(ResultBeforeTheLatencyField(), forKey: NSKeyedArchiveRootObjectKey)
        archiver.finishEncoding()
        let old = try #require(try NSKeyedUnarchiver.unarchivedObject(ofClass: FanHelperResult.self, from: archiver.encodedData))
        #expect(old.modeReadBackMS == -1 && old.appliedRPM == 3200, "a helper from before the field was added still decodes")
    }

    /// The every-fan form of `setForced` is new in version 3, so the app must not take an older helper for the current one.
    @Test func theHelperVersionWasBumpedForTheEveryFanCommand() {
        #expect(Int(FanHelperIdentity.version).map { $0 >= 3 } == true)
    }

    @Test func eachStateOfAFanHasItsNumberOnTheWire() {
        #expect(FanHelperResult.State.automatic.rawValue == 0)
        #expect(FanHelperResult.State.floor.rawValue == 1)
        #expect(FanHelperResult.State.forced.rawValue == 2)
        #expect(FanHelperResult(ok: false, state: .automatic).appliedRPM == -1)
        #expect(FanHelperResult.allFans == -1)
    }

    @Test func aResultMissingItsFieldsIsNotDecoded() {
        let archiver = NSKeyedArchiver(requiringSecureCoding: true)
        archiver.setClassName("MyNotchFanHelperResult", for: PartialPing.self)
        archiver.encode(PartialPing(), forKey: NSKeyedArchiveRootObjectKey)
        archiver.finishEncoding()
        #expect((try? NSKeyedUnarchiver.unarchivedObject(ofClass: FanHelperResult.self, from: archiver.encodedData)) == nil)
    }

    @Test func theInterfaceNamesTheClassesEachReplyMayContain() throws {
        let interface = FanHelperInterface.make()
        let ping = interface.classes(for: #selector(FanHelperProtocol.ping(reply:)), argumentIndex: 0, ofReply: true)
        #expect(ping.contains { $0 as? AnyClass === FanHelperPing.self })
        let fans = interface.classes(for: #selector(FanHelperProtocol.readFans(reply:)), argumentIndex: 0, ofReply: true)
        #expect(fans.contains { $0 as? AnyClass === NSArray.self })
        #expect(fans.contains { $0 as? AnyClass === FanHelperFan.self })
        for selector in [
            #selector(FanHelperProtocol.setFloor(fan:rpm:reply:)), #selector(FanHelperProtocol.setForced(fan:rpm:reply:)),
            #selector(FanHelperProtocol.setAuto(fan:reply:)),
        ] {
            let classes = interface.classes(for: selector, argumentIndex: 0, ofReply: true)
            #expect(classes.contains { $0 as? AnyClass === FanHelperResult.self }, "\(selector)")
        }
    }

    /// The operations are pinned: two reads, three fan controls, and two charge controls.
    /// A new one cannot be added without this test saying so.
    @Test func theProtocolHasThePinnedOperationsAndNothingElse() throws {
        let proto = try #require(objc_getProtocol("MyNotchFanHelperProtocol"))
        var count: UInt32 = 0
        let required = protocol_copyMethodDescriptionList(proto, true, true, &count)
        defer { free(required) }
        let names = (0..<Int(count)).map { NSStringFromSelector(required![$0].name!) }.sorted()
        #expect(names == [
            "pingWithReply:", "readFansWithReply:", "setAutoWithFan:reply:", "setChargeInhibitWithInhibit:reply:",
            "setChargeLimitWithLimit:reply:", "setDischargeWithDischarge:reply:", "setFloorWithFan:rpm:reply:", "setForcedWithFan:rpm:reply:",
        ])
        var optionalCount: UInt32 = 0
        free(protocol_copyMethodDescriptionList(proto, false, true, &optionalCount))
        #expect(optionalCount == 0)
        var classMethods: UInt32 = 0
        free(protocol_copyMethodDescriptionList(proto, true, false, &classMethods))
        #expect(classMethods == 0)
    }

    @Test func noOperationTakesAKeyNameOrAFreeValue() throws {
        let proto = try #require(objc_getProtocol("MyNotchFanHelperProtocol"))
        var count: UInt32 = 0
        let required = protocol_copyMethodDescriptionList(proto, true, true, &count)
        defer { free(required) }
        for index in 0..<Int(count) {
            let selector = NSStringFromSelector(required![index].name!)
            #expect(selector.lowercased().contains("key") == false && selector.lowercased().contains("write") == false, "\(selector)")
        }
    }
}

/// What a version 2 helper sent: a result without the latency field.
@objc(MyNotchTestResultBeforeTheLatencyField)
final class ResultBeforeTheLatencyField: NSObject, NSSecureCoding {
    static let supportsSecureCoding = true
    override init() { super.init() }
    required init?(coder: NSCoder) { nil }
    func encode(with coder: NSCoder) {
        coder.encode(true, forKey: "ok")
        coder.encode(2, forKey: "state")
        coder.encode(3200.0, forKey: "appliedRPM")
        coder.encode("x" as NSString, forKey: "detail")
        coder.encode(14.5, forKey: "leaseSeconds")
    }
}
