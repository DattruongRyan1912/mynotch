import FanHelperKit
import Foundation
import os

private let serviceLog = Logger(subsystem: "io.lucasvu.mynotch.fanhelper", category: "service")

/// What the helper does for a connection. Everything it needs from the system is passed in, so a test can run it over a real
/// XPC connection to an anonymous listener with a fake SMC, and nothing here can reach the real one.
public final class FanHelperService: NSObject, FanHelperProtocol, @unchecked Sendable {
    private let version: String
    private let buildID: String
    private let euid: @Sendable () -> Int32
    private let pid: @Sendable () -> Int32
    private let openChannel: @Sendable () -> (any SMCChannel)?
    private let openWriter: @Sendable () -> (any SMCWriteChannel)?
    private let controller: FanController?
    private let onRequest: @Sendable (String) -> Void

    /// `controller` is nil where fan control is not available (the writer could not be made): the three setting commands then
    /// answer that, and the two reads work as ever.
    public init(
        version: String = FanHelperIdentity.version,
        buildID: String,
        euid: @escaping @Sendable () -> Int32 = { Int32(bitPattern: geteuid()) },
        pid: @escaping @Sendable () -> Int32 = { getpid() },
        openChannel: @escaping @Sendable () -> (any SMCChannel)? = { AppleSMCChannel() },
        openWriter: @escaping @Sendable () -> (any SMCWriteChannel)? = { AppleSMCWriter() },
        controller: FanController? = nil,
        onRequest: @escaping @Sendable (String) -> Void = { _ in }
    ) {
        self.version = version
        self.buildID = buildID
        self.euid = euid
        self.pid = pid
        self.openChannel = openChannel
        self.openWriter = openWriter
        self.controller = controller
        self.onRequest = onRequest
    }

    /// `onRequest` hears the name of each request that is served: a connection that the system turned away never gets this far,
    /// which is how the log shows the difference between a peer that was received and one that was served.
    public func ping(reply: @escaping @Sendable (FanHelperPing) -> Void) {
        onRequest("ping")
        reply(FanHelperPing(version: version, buildID: buildID, euid: euid(), pid: pid()))
    }

    /// A connection of its own for each read: the helper is idle between calls, and opening the SMC is cheap.
    public func readFans(reply: @escaping @Sendable ([FanHelperFan], String?) -> Void) {
        onRequest("readFans")
        guard let channel = openChannel() else {
            reply([], "cannot open the SMC")
            return
        }
        reply(FanSMC.readFans(on: channel), nil)
    }

    public func setFloor(fan: Int, rpm: Double, reply: @escaping @Sendable (FanHelperResult) -> Void) {
        onRequest("setFloor")
        reply(controller?.setFloor(fan: fan, rpm: rpm) ?? Self.unavailable)
    }

    public func setForced(fan: Int, rpm: Double, reply: @escaping @Sendable (FanHelperResult) -> Void) {
        onRequest("setForced")
        reply(controller?.setForced(fan: fan, rpm: rpm) ?? Self.unavailable)
    }

    public func setAuto(fan: Int, reply: @escaping @Sendable (FanHelperResult) -> Void) {
        onRequest("setAuto")
        reply(controller?.setAuto(fan: fan) ?? Self.unavailable)
    }

    private static let directAttemptChargeKeys: Set<String> = [
        "CHTE", "CHIB", "CHIC", "CH0B", "CH0C", "CH0I", "CHLT", "BCLM", "CHWA", "CHIE", "ACLC"
    ]

    private func isWritable(_ key: String = "", info: SMCKeyInfo) -> Bool {
        if Self.directAttemptChargeKeys.contains(key) {
            return true
        }
        return info.attributes == 0 || (info.attributes & 0x40) != 0
    }

    public func setChargeInhibit(inhibit: Bool, reply: @escaping @Sendable (Bool) -> Void) {
        onRequest("setChargeInhibit")
        guard let writer = openWriter() else {
            serviceLog.error("setChargeInhibit: openWriter returned nil!")
            reply(false)
            return
        }
        var written = false

        if inhibit {
            // Khi Inhibit (Bật ngắt sạc): Dừng ngay ở họ key đầu tiên thành công, tránh ghi đè chồng chéo
            // 1. Try Tahoe charging limit / hold key CHTE
            if let info = writer.info(of: "CHTE") {
                if isWritable("CHTE", info: info) {
                    let bytes: [UInt8] = [0x01, 0x00, 0x00, 0x00]
                    let res = writer.write("CHTE", info: info, bytes: bytes)
                    serviceLog.info("write CHTE: \(String(describing: res), privacy: .public)")
                    if res == .ok { written = true }
                } else {
                    serviceLog.info("CHTE attr=0x\(info.attributes, format: .hex, privacy: .public) not writable")
                }
            }

            // 2. Try Apple Silicon Pro/Max CHIB / CHIC (nếu CHTE không tồn tại hoặc ghi thất bại)
            if !written {
                let infoB = writer.info(of: "CHIB")
                let infoC = writer.info(of: "CHIC")
                if let infoB, let infoC {
                    if !isWritable("CHIB", info: infoB) || !isWritable("CHIC", info: infoC) {
                        serviceLog.info("CHIB attr=0x\(infoB.attributes, format: .hex, privacy: .public), CHIC attr=0x\(infoC.attributes, format: .hex, privacy: .public) not writable")
                    } else {
                        // Try 0x01 flag first (Apple Silicon M1 Pro / macOS 15+ standard ui8 flag)
                        var resB = writer.write("CHIB", info: infoB, bytes: [0x01])
                        var resC = writer.write("CHIC", info: infoC, bytes: [0x01])
                        serviceLog.info("write CHIB(0x01)=\(String(describing: resB), privacy: .public), CHIC(0x01)=\(String(describing: resC), privacy: .public)")
                        if resB == .ok && resC == .ok {
                            written = true
                        } else {
                            // Fallback to 0x02 (legacy M1 format)
                            serviceLog.warning("Attempting 0x02 fallback for CHIB/CHIC")
                            resB = writer.write("CHIB", info: infoB, bytes: [0x02])
                            resC = writer.write("CHIC", info: infoC, bytes: [0x02])
                            serviceLog.info("write CHIB(0x02)=\(String(describing: resB), privacy: .public), CHIC(0x02)=\(String(describing: resC), privacy: .public)")
                            if resB == .ok && resC == .ok {
                                written = true
                            } else {
                                serviceLog.warning("Rolling back CHIB/CHIC due to failure: resB=\(String(describing: resB), privacy: .public), resC=\(String(describing: resC), privacy: .public)")
                                if resB == .ok { _ = writer.write("CHIB", info: infoB, bytes: [0x00]) }
                                if resC == .ok { _ = writer.write("CHIC", info: infoC, bytes: [0x00]) }
                            }
                        }
                    }
                } else if let info = infoB {
                    if !isWritable("CHIB", info: info) {
                        serviceLog.info("CHIB attr=0x\(info.attributes, format: .hex, privacy: .public) not writable")
                    } else {
                        var res = writer.write("CHIB", info: info, bytes: [0x01])
                        if res != .ok { res = writer.write("CHIB", info: info, bytes: [0x02]) }
                        serviceLog.info("write single CHIB: \(String(describing: res), privacy: .public)")
                        if res == .ok { written = true }
                    }
                } else if let info = infoC {
                    if !isWritable("CHIC", info: info) {
                        serviceLog.info("CHIC attr=0x\(info.attributes, format: .hex, privacy: .public) not writable")
                    } else {
                        var res = writer.write("CHIC", info: info, bytes: [0x01])
                        if res != .ok { res = writer.write("CHIC", info: info, bytes: [0x02]) }
                        serviceLog.info("write single CHIC: \(String(describing: res), privacy: .public)")
                        if res == .ok { written = true }
                    }
                }
            }

            // 3. Try legacy M1 CH0B / CH0C (chỉ khi họ trên chưa thành công)
            if !written {
                if let infoB = writer.info(of: "CH0B"), let infoC = writer.info(of: "CH0C"), isWritable("CH0B", info: infoB), isWritable("CH0C", info: infoC) {
                    let bytes: [UInt8] = [0x02]
                    let resB = writer.write("CH0B", info: infoB, bytes: bytes)
                    let resC = writer.write("CH0C", info: infoC, bytes: bytes)
                    if resB == .ok && resC == .ok {
                        written = true
                    } else {
                        if resB == .ok { _ = writer.write("CH0B", info: infoB, bytes: [0x00]) }
                        if resC == .ok { _ = writer.write("CH0C", info: infoC, bytes: [0x00]) }
                    }
                } else {
                    if let info = writer.info(of: "CH0B"), isWritable("CH0B", info: info) {
                        if writer.write("CH0B", info: info, bytes: [0x02]) == .ok { written = true }
                    }
                    if let info = writer.info(of: "CH0C"), isWritable("CH0C", info: info) {
                        if writer.write("CH0C", info: info, bytes: [0x02]) == .ok { written = true }
                    }
                }
            }

            // 4. Try Intel SMC key CH0I (chỉ khi họ trên chưa thành công)
            if !written, let info = writer.info(of: "CH0I"), isWritable("CH0I", info: info) {
                if writer.write("CH0I", info: info, bytes: [0x01]) == .ok {
                    written = true
                }
            }
        } else {
            // Khi Un-inhibit (Mở sạc lại): Xóa triệt để 0x00 trên TẤT CẢ các họ key tồn tại
            if let info = writer.info(of: "CHTE"), isWritable("CHTE", info: info) {
                if writer.write("CHTE", info: info, bytes: [0x00, 0x00, 0x00, 0x00]) == .ok { written = true }
            }
            if let info = writer.info(of: "CHIB"), isWritable("CHIB", info: info) {
                if writer.write("CHIB", info: info, bytes: [0x00]) == .ok { written = true }
            }
            if let info = writer.info(of: "CHIC"), isWritable("CHIC", info: info) {
                if writer.write("CHIC", info: info, bytes: [0x00]) == .ok { written = true }
            }
            if let info = writer.info(of: "CH0B"), isWritable("CH0B", info: info) {
                if writer.write("CH0B", info: info, bytes: [0x00]) == .ok { written = true }
            }
            if let info = writer.info(of: "CH0C"), isWritable("CH0C", info: info) {
                if writer.write("CH0C", info: info, bytes: [0x00]) == .ok { written = true }
            }
            if let info = writer.info(of: "CH0I"), isWritable("CH0I", info: info) {
                if writer.write("CH0I", info: info, bytes: [0x00]) == .ok { written = true }
            }
        }
        // SAFETY: Always ensure CHIE is clear (0x00) during charge inhibit.
        // CHIE = 0x08 isolates the AC adapter entirely — the Mac runs on battery
        // even while plugged in (−20 W to −40 W drain). Only setDischarge may use 0x08.
        if let info = writer.info(of: "CHIE"), isWritable("CHIE", info: info) {
            _ = writer.write("CHIE", info: info, bytes: [0x00])
        }
        // Sync MagSafe LED: green when holding/inhibited, auto when charging
        if inhibit, written, let info = writer.info(of: "ACLC"), isWritable("ACLC", info: info) {
            _ = writer.write("ACLC", info: info, bytes: [0x03])
        } else if !inhibit, let info = writer.info(of: "ACLC"), isWritable("ACLC", info: info) {
            _ = writer.write("ACLC", info: info, bytes: [0x00])
        }
        serviceLog.info("setChargeInhibit(\(inhibit, privacy: .public)): finished, reply written=\(written, privacy: .public)")
        reply(written)
    }

    public func setChargeLimit(limit: Int, reply: @escaping @Sendable (Bool) -> Void) {
        onRequest("setChargeLimit")
        guard let writer = openWriter() else {
            reply(false)
            return
        }
        let clamped = UInt8(clamping: max(50, min(100, limit)))
        var hasHardwareLimitRegister = false
        var written = false
        if let info = writer.info(of: "CHLT"), isWritable("CHLT", info: info) {
            hasHardwareLimitRegister = true
            var bytes = [UInt8](repeating: 0x00, count: info.size)
            if info.size >= 1 { bytes[0] = clamped }
            if info.size >= 2 { bytes[1] = 0x05 }
            if info.size >= 3 { bytes[2] = 0x05 }
            let res = writer.write("CHLT", info: info, bytes: bytes)
            serviceLog.info("write CHLT [\(clamped, privacy: .public), 5, 5]: \(String(describing: res), privacy: .public)")
            if res == .ok {
                written = true
            }
        }
        if let info = writer.info(of: "BCLM"), isWritable("BCLM", info: info) {
            hasHardwareLimitRegister = true
            if writer.write("BCLM", info: info, bytes: [clamped]) == .ok {
                written = true
            }
        }
        if let info = writer.info(of: "CHWA"), isWritable("CHWA", info: info) {
            hasHardwareLimitRegister = true
            if writer.write("CHWA", info: info, bytes: [clamped]) == .ok {
                written = true
            }
        }
        if !hasHardwareLimitRegister {
            // Apple Silicon has no writable static BCLM/CHLT register; software watchdog enforces threshold
            reply(true)
        } else {
            reply(written)
        }
    }

    public func setDischarge(discharge: Bool, reply: @escaping @Sendable (Bool) -> Void) {
        onRequest("setDischarge")
        guard let writer = openWriter() else {
            reply(false)
            return
        }
        var written = false
        if let info = writer.info(of: "CHIE") {
            let bytes: [UInt8] = discharge ? [0x08] : [0x00]
            if writer.write("CHIE", info: info, bytes: bytes) == .ok {
                written = true
            }
        }
        // Sync MagSafe LED: amber (0x04) when discharging, auto (0x00) when idle
        if let info = writer.info(of: "ACLC") {
            let bytes: [UInt8] = discharge ? [0x04] : [0x00]
            _ = writer.write("ACLC", info: info, bytes: bytes)
        }
        reply(written)
    }

    private static var unavailable: FanHelperResult {
        FanHelperResult(ok: false, state: .automatic, detail: "fan control is not available")
    }
}
