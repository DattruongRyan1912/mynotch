import FanHelperKit
import Foundation
import IOKit
import os

private let smcLog = Logger(subsystem: "io.lucasvu.mynotch.fanhelper", category: "smc")

public enum SMCWriteResult: Equatable, Sendable {
    case ok
    /// The SMC answered with a result byte other than 0 (0x82 bad command, 0x84 key not found, 0x85 not readable, 0x86 not writable, 0x87 size mismatch).
    case smcError(UInt8)
    /// The call into the kernel failed.
    case ioError(Int32)
}

/// An SMC that can also be written to. Only what `FanKeyWriter` needs: it never sees a key it should not write.
public protocol SMCWriteChannel: SMCChannel {
    func write(_ key: String, info: SMCKeyInfo, bytes: [UInt8]) -> SMCWriteResult
}

/// The one place in the project that sends the SMC's write command. It exists only in this target, which the app does not link,
/// and it can only be made by a process that is root: a test, which never is, gets nil, so no test can write to the real SMC.
public final class AppleSMCWriter: SMCWriteChannel {
    private static let handleYPCEvent: UInt32 = 2
    private static let writeKeyCommand: UInt8 = 6

    private let reader: AppleSMCChannel
    private let connection: io_connect_t

    /// Nil unless the process is root and the SMC can be opened.
    public init?() {
        guard geteuid() == 0, let reader = AppleSMCChannel() else { return nil }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != IO_OBJECT_NULL else { return nil }
        defer { IOObjectRelease(service) }
        var connection: io_connect_t = 0
        guard IOServiceOpen(service, mach_task_self_, 0, &connection) == KERN_SUCCESS else { return nil }
        self.reader = reader
        self.connection = connection
    }

    deinit { IOServiceClose(connection) }

    public func keyName(at index: Int) -> String? { reader.keyName(at: index) }
    public func info(of key: String) -> SMCKeyInfo? { reader.info(of: key) }
    public func bytes(of key: String, info: SMCKeyInfo) -> [UInt8]? { reader.bytes(of: key, info: info) }

    public func write(_ key: String, info: SMCKeyInfo, bytes: [UInt8]) -> SMCWriteResult {
        guard let code = SMCKey.code(key), bytes.count == info.size, bytes.count <= 32 else { return .smcError(0x87) }
        var input = SMCParamStruct()
        input.key = code
        input.data8 = Self.writeKeyCommand
        input.keyInfo.dataSize = UInt32(info.size)
        withUnsafeMutableBytes(of: &input.bytes) { destination in
            for (offset, byte) in bytes.enumerated() { destination[offset] = byte }
        }
        var output = SMCParamStruct()
        var outputSize = MemoryLayout<SMCParamStruct>.stride
        let status = IOConnectCallStructMethod(
            connection, Self.handleYPCEvent, &input, MemoryLayout<SMCParamStruct>.stride, &output, &outputSize
        )
        guard status == KERN_SUCCESS else {
            smcLog.error("write(\(key, privacy: .public)): IOConnectCallStructMethod failed status=\(status, privacy: .public)")
            return .ioError(Int32(bitPattern: UInt32(status)))
        }
        if output.result != 0 {
            smcLog.warning("write(\(key, privacy: .public)): SMC result error=0x\(String(output.result, radix: 16), privacy: .public)")
            return .smcError(output.result)
        }
        smcLog.info("write(\(key, privacy: .public)): SUCCESS ok")
        return .ok
    }
}
