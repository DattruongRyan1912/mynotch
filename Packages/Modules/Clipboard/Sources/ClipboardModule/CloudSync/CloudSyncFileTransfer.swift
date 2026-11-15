import CryptoKit
import Foundation

public enum CloudSyncFileTransferError: Error, LocalizedError {
    case exceedsSizeLimit(Int64)
    case outOfOrderChunk(expected: Int, got: Int)
    case duplicateChunk(Int)
    case hashMismatch(expected: String, actual: String)
    case incompleteTransfer(received: Int, total: Int)
    case unsafeFileName(String)
    case diskWriteFailed
    case sizeMismatch(expected: Int64, actual: Int)
    case chunkDataTampered(Int)

    public var errorDescription: String? {
        switch self {
        case .exceedsSizeLimit(let size): return "Dung lượng file (\(size) bytes) vượt quá giới hạn 15 MiB"
        case .outOfOrderChunk(let exp, let got): return "Chunk sai thứ tự: mong đợi \(exp), nhận được \(got)"
        case .duplicateChunk(let seq): return "Chunk \(seq) bị lặp lại"
        case .hashMismatch(let exp, let act): return "SHA-256 không khớp! Mong đợi: \(exp), thực tế: \(act)"
        case .incompleteTransfer(let rec, let tot): return "Chưa nhận đủ chunks: đã nhận \(rec)/\(tot)"
        case .unsafeFileName(let name): return "Tên file không an toàn: \(name)"
        case .diskWriteFailed: return "Ghi file xuống ổ đĩa thất bại"
        case .sizeMismatch(let exp, let act): return "Kích thước file không khớp! Mong đợi \(exp), thực tế: \(act)"
        case .chunkDataTampered(let seq): return "Dữ liệu chunk \(seq) bị thay đổi so với chunk đã nhận"
        }
    }
}

public enum CloudSyncFileTransfer: Sendable {
    nonisolated public static let maxFileSizeBytes: Int64 = 15_728_640 // 15 MiB
    nonisolated public static let inlineThresholdBytes: Int64 = 1_048_576 // 1 MiB
    nonisolated public static let chunkSizeBytes: Int = 524_288 // 512 KiB

    nonisolated public static func isFileSizeAllowed(fileSize: Int64) -> Bool {
        fileSize >= 0 && fileSize <= maxFileSizeBytes
    }

    nonisolated public static func calculateChunkCount(fileSize: Int64, chunkSize: Int = chunkSizeBytes) -> Int {
        if fileSize <= inlineThresholdBytes {
            return 1
        }
        let total = Int(ceil(Double(fileSize) / Double(chunkSize)))
        return max(1, total)
    }
}

public struct CloudSyncChunkAssembler {
    public let transferId: String
    public let fileName: String
    public let mimeType: String
    public let fileSize: Int64
    public let fileHash: String
    public let totalChunks: Int

    private var receivedChunks: [Int: Data] = [:]
    private var nextExpectedSequence = 0

    public init(
        transferId: String,
        fileName: String,
        mimeType: String,
        fileSize: Int64,
        fileHash: String,
        totalChunks: Int
    ) {
        self.transferId = transferId
        self.fileName = fileName
        self.mimeType = mimeType
        self.fileSize = fileSize
        self.fileHash = fileHash
        self.totalChunks = totalChunks
    }

    public var isComplete: Bool {
        receivedChunks.count == totalChunks
    }

    public var currentBytes: Int {
        receivedChunks.values.reduce(0) { $0 + $1.count }
    }

    public mutating func addChunk(sequence: Int, data: Data) throws {
        guard sequence >= 0 && sequence < totalChunks else {
            throw CloudSyncFileTransferError.outOfOrderChunk(expected: nextExpectedSequence, got: sequence)
        }
        if let existing = receivedChunks[sequence] {
            guard existing == data else {
                throw CloudSyncFileTransferError.chunkDataTampered(sequence)
            }
            // Idempotent duplicate
            return
        }
        guard Int64(currentBytes + data.count) <= fileSize else {
            throw CloudSyncFileTransferError.sizeMismatch(expected: fileSize, actual: currentBytes + data.count)
        }
        if sequence != nextExpectedSequence {
            throw CloudSyncFileTransferError.outOfOrderChunk(expected: nextExpectedSequence, got: sequence)
        }

        receivedChunks[sequence] = data
        nextExpectedSequence += 1
    }

    public func finalizeAndVerify() throws -> Data {
        guard isComplete else {
            throw CloudSyncFileTransferError.incompleteTransfer(received: receivedChunks.count, total: totalChunks)
        }

        var assembled = Data()
        for i in 0..<totalChunks {
            guard let chunk = receivedChunks[i] else {
                throw CloudSyncFileTransferError.incompleteTransfer(received: receivedChunks.count, total: totalChunks)
            }
            assembled.append(chunk)
        }

        guard assembled.count == Int(fileSize) else {
            throw CloudSyncFileTransferError.sizeMismatch(expected: fileSize, actual: assembled.count)
        }

        let computedHash = SHA256.hash(data: assembled).compactMap { String(format: "%02x", $0) }.joined()
        guard computedHash.lowercased() == fileHash.lowercased() else {
            throw CloudSyncFileTransferError.hashMismatch(expected: fileHash, actual: computedHash)
        }

        return assembled
    }
}
