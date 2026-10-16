import IOKit

public struct SMCKeyInfo: Equatable, Sendable {
    public let size: Int
    public let type: String

    public init(size: Int, type: String) {
        self.size = size
        self.type = type
    }
}

/// What the module asks the SMC: the name of the key at an index, the size and type of a key, and a key's bytes. All reads.
public protocol SMCChannel: Sendable {
    func keyName(at index: Int) -> String?
    func info(of key: String) -> SMCKeyInfo?
    func bytes(of key: String, info: SMCKeyInfo) -> [UInt8]?
}

/// The SMC's request commands this module sends. There is no case for the write command (6): nothing here can write to the
/// SMC, and a test pins the list.
enum SMCCommand: UInt8, CaseIterable {
    case readKey = 5
    case keyAtIndex = 8
    case keyInfo = 9
}

struct SMCVersion {
    var major: UInt8 = 0
    var minor: UInt8 = 0
    var build: UInt8 = 0
    var reserved: UInt8 = 0
    var release: UInt16 = 0
}

struct SMCPLimitData {
    var version: UInt16 = 0
    var length: UInt16 = 0
    var cpuPLimit: UInt32 = 0
    var gpuPLimit: UInt32 = 0
    var memPLimit: UInt32 = 0
}

/// Three bytes of padding make it 12 bytes like the C struct; Swift would leave it at 9 and shift every later field.
struct SMCKeyInfoData {
    var dataSize: UInt32 = 0
    var dataType: UInt32 = 0
    var dataAttributes: UInt8 = 0
    var padding: (UInt8, UInt8, UInt8) = (0, 0, 0)
}

/// The 80-byte request and reply of the SMC's user client, field for field as the kernel declares it.
struct SMCParamStruct {
    typealias Bytes = (
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
    )

    var key: UInt32 = 0
    var vers = SMCVersion()
    var pLimitData = SMCPLimitData()
    var keyInfo = SMCKeyInfoData()
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: Bytes = (
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    )
}

/// The connection to the `AppleSMC` service. Opening it needs no permission outside the App Sandbox, which MyNotch is not in.
public final class AppleSMCChannel: SMCChannel {
    /// The one external method of the user client: it takes the request struct and fills the reply struct.
    private static let handleYPCEvent: UInt32 = 2
    private let connection: io_connect_t

    /// Nil when the service is missing or refuses the connection.
    public init?() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != IO_OBJECT_NULL else { return nil }
        defer { IOObjectRelease(service) }
        var connection: io_connect_t = 0
        guard IOServiceOpen(service, mach_task_self_, 0, &connection) == KERN_SUCCESS else { return nil }
        self.connection = connection
    }

    deinit { IOServiceClose(connection) }

    public func keyName(at index: Int) -> String? {
        var request = SMCParamStruct()
        request.data32 = UInt32(truncatingIfNeeded: index)
        return call(request, .keyAtIndex).map { SMCKey.name($0.key) }
    }

    public func info(of key: String) -> SMCKeyInfo? {
        guard let code = SMCKey.code(key) else { return nil }
        var request = SMCParamStruct()
        request.key = code
        guard let reply = call(request, .keyInfo) else { return nil }
        return SMCKeyInfo(size: Int(reply.keyInfo.dataSize), type: SMCKey.name(reply.keyInfo.dataType))
    }

    public func bytes(of key: String, info: SMCKeyInfo) -> [UInt8]? {
        guard let code = SMCKey.code(key), info.size <= 32 else { return nil }
        var request = SMCParamStruct()
        request.key = code
        request.keyInfo.dataSize = UInt32(info.size)
        guard let reply = call(request, .readKey) else { return nil }
        return withUnsafeBytes(of: reply.bytes) { Array($0.prefix(info.size)) }
    }

    private func call(_ request: SMCParamStruct, _ command: SMCCommand) -> SMCParamStruct? {
        var input = request
        input.data8 = command.rawValue
        var output = SMCParamStruct()
        var outputSize = MemoryLayout<SMCParamStruct>.stride
        let status = IOConnectCallStructMethod(
            connection, Self.handleYPCEvent, &input, MemoryLayout<SMCParamStruct>.stride, &output, &outputSize
        )
        return status == KERN_SUCCESS && output.result == 0 ? output : nil
    }
}
