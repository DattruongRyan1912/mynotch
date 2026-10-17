import FanHelperKit
import Foundation

public enum FanWriteError: Error, Equatable, Sendable {
    case noSuchFan
    case notAFiniteSpeed
    case missingKey(String)
    case wrongType(String)
    case refused(String, UInt8)
    case failed(String, Int32)
    case readBackDiffers(String)

    /// A short English line for the log and for the reply.
    public var text: String {
        switch self {
        case .noSuchFan: "no such fan"
        case .notAFiniteSpeed: "the speed is not a number"
        case let .missingKey(key): "the SMC has no \(key)"
        case let .wrongType(key): "\(key) is not of the expected type"
        case let .refused(key, code): "the SMC refused \(key) (0x\(String(code, radix: 16)))"
        case let .failed(key, code): "writing \(key) failed (\(code))"
        case let .readBackDiffers(key): "\(key) does not read back as written"
        }
    }
}

/// Writes the two keys that set a fan, and nothing else: the mode (`F<N>Md`, or `F<N>md` on chips that spell it so) as a `ui8 `, and the
/// target (`F<N>Tg`) as a little-endian `flt `. The key names are made from a fan index that is below the number of fans the SMC
/// reports, the types are checked against what the SMC says each key is, a speed that is not a number is refused, and every write
/// is read back: anything that does not read back as written is an error. Each write is logged with the fan, the mode or the speed,
/// and nothing else.
public struct FanKeyWriter: Sendable {
    public static let mostFans = 8
    /// How far a target may read back from what was written: floats of this size are not exact.
    static let readBackTolerance = 1.0

    public let fanCount: Int
    private let channel: any SMCWriteChannel
    private let modeKeys: [String]
    private let log: @Sendable (String) -> Void

    /// The only key names this type writes, as a test pins them.
    public static func isAllowedKey(_ key: String) -> Bool {
        let bytes = Array(key.utf8)
        guard bytes.count == 4, bytes[0] == UInt8(ascii: "F"), (0x30...0x37).contains(bytes[1]) else { return false }
        let suffix = String(decoding: bytes[2...], as: UTF8.self)
        return suffix == "Md" || suffix == "md" || suffix == "Tg"
    }

    /// Looks the fans and their mode keys up. Throws when the SMC has no fans or a fan has no mode key of the right type.
    public init(channel: any SMCWriteChannel, log: @escaping @Sendable (String) -> Void = { _ in }) throws(FanWriteError) {
        self.channel = channel
        self.log = log
        guard let countInfo = channel.info(of: "FNum"), let countBytes = channel.bytes(of: "FNum", info: countInfo),
              let count = SMCValue.number(type: countInfo.type, bytes: countBytes), count >= 1
        else { throw .missingKey("FNum") }
        fanCount = min(Int(count), Self.mostFans)
        var keys: [String] = []
        for index in 0..<fanCount {
            guard let key = ["F\(index)Md", "F\(index)md"].first(where: { channel.info(of: $0) != nil }),
                  channel.info(of: key)?.type == "ui8 ", channel.info(of: key)?.size == 1
            else { throw .missingKey("F\(index)Md") }
            guard let target = channel.info(of: "F\(index)Tg") else { throw .missingKey("F\(index)Tg") }
            guard target.type == "flt ", target.size == 4 else { throw .wrongType("F\(index)Tg") }
            keys.append(key)
        }
        modeKeys = keys
    }

    /// 1 for manual, 0 for the system's own control.
    public func setManual(_ fan: Int, _ manual: Bool) throws(FanWriteError) {
        guard (0..<fanCount).contains(fan) else { throw .noSuchFan }
        let key = modeKeys[fan]
        try write(key, bytes: [manual ? 1 : 0], expecting: { $0 == [manual ? 1 : 0] })
        log("write fan \(fan) mode \(manual ? 1 : 0)")
    }

    public func setTarget(_ fan: Int, rpm: Double) throws(FanWriteError) {
        guard (0..<fanCount).contains(fan) else { throw .noSuchFan }
        guard rpm.isFinite, rpm >= 0 else { throw .notAFiniteSpeed }
        let key = "F\(fan)Tg"
        let bits = Float(rpm).bitPattern
        let bytes = [UInt8(bits & 0xff), UInt8(bits >> 8 & 0xff), UInt8(bits >> 16 & 0xff), UInt8(bits >> 24 & 0xff)]
        try write(key, bytes: bytes, expecting: { read in
            SMCValue.number(type: "flt ", bytes: read).map { abs($0 - rpm) <= Self.readBackTolerance } ?? false
        })
        log("write fan \(fan) target \(Int(rpm.rounded()))")
    }

    private func write(_ key: String, bytes: [UInt8], expecting matches: ([UInt8]) -> Bool) throws(FanWriteError) {
        precondition(Self.isAllowedKey(key), "not a key this type may write")
        guard let info = channel.info(of: key), info.size == bytes.count else { throw .wrongType(key) }
        let result = channel.write(key, info: info, bytes: bytes)
        // The firmware answers some writes with an error and applies them anyway, so the read-back decides.
        let readBack = channel.bytes(of: key, info: info)
        if let readBack, matches(readBack) { return }
        switch result {
        case .ok: throw .readBackDiffers(key)
        case let .smcError(code): throw .refused(key, code)
        case let .ioError(code): throw .failed(key, code)
        }
    }
}
