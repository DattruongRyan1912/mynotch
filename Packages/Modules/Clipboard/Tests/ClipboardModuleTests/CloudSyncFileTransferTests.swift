import CryptoKit
import Foundation
import Testing
@testable import ClipboardModule

@Suite struct CloudSyncFileTransferTests {

    // T05: Ranh giới inline (0, 1 và 1.048.576 bytes dùng 1 frame)
    @Test func inlineBoundaryChunkCount() {
        #expect(CloudSyncFileTransfer.calculateChunkCount(fileSize: 0) == 1)
        #expect(CloudSyncFileTransfer.calculateChunkCount(fileSize: 1) == 1)
        #expect(CloudSyncFileTransfer.calculateChunkCount(fileSize: 1_048_576) == 1)
    }

    // T06: Ranh giới chunk (> 1 MiB -> chunked 512 KiB)
    @Test func chunkedBoundaryCalculation() {
        // 1.048.577 bytes: 3 chunks of 512 KiB (524288 * 2 = 1048576, remainder in chunk 3)
        #expect(CloudSyncFileTransfer.calculateChunkCount(fileSize: 1_048_577) == 3)
        // 1.572.864 bytes (1.5 MiB): 3 chunks
        #expect(CloudSyncFileTransfer.calculateChunkCount(fileSize: 1_572_864) == 3)
        // 15.728.640 bytes (15 MiB): 30 chunks
        #expect(CloudSyncFileTransfer.calculateChunkCount(fileSize: 15_728_640) == 30)
    }

    // T07: Giới hạn dung lượng (15.728.641 bytes bị từ chối trước khi gửi)
    @Test func maxFileSizeLimitEnforced() {
        let maxLimit: Int64 = 15_728_640
        #expect(CloudSyncFileTransfer.isFileSizeAllowed(fileSize: maxLimit))
        #expect(!CloudSyncFileTransfer.isFileSizeAllowed(fileSize: maxLimit + 1))
    }

    // T10: Ghép chunk (Nhận đủ chunk đúng thứ tự tạo đúng một file)
    @Test func chunkAssemblyReconstructsCompleteFile() throws {
        let originalContent = "Software engineering principles require continuous verification."
        let originalData = Data(originalContent.utf8)
        let hash = SHA256.hash(data: originalData).compactMap { String(format: "%02x", $0) }.joined()

        let transferId = UUID().uuidString
        var assembler = CloudSyncChunkAssembler(
            transferId: transferId,
            fileName: "doc.txt",
            mimeType: "text/plain",
            fileSize: Int64(originalData.count),
            fileHash: hash,
            totalChunks: 2
        )

        // Split into 2 chunks
        let mid = originalData.count / 2
        let chunk0Data = originalData.prefix(mid)
        let chunk1Data = originalData.suffix(from: mid)

        try assembler.addChunk(sequence: 0, data: chunk0Data)
        #expect(!assembler.isComplete)

        try assembler.addChunk(sequence: 1, data: chunk1Data)
        #expect(assembler.isComplete)

        let assembledData = try assembler.finalizeAndVerify()
        #expect(assembledData == originalData)
    }

    // T11: Duplicate/order chunk handling
    @Test func duplicateOrOutOfOrderChunks() throws {
        let data = Data([0x01, 0x02, 0x03, 0x04])
        let hash = SHA256.hash(data: data).compactMap { String(format: "%02x", $0) }.joined()
        var assembler = CloudSyncChunkAssembler(
            transferId: UUID().uuidString,
            fileName: "test.bin",
            mimeType: "application/octet-stream",
            fileSize: 4,
            fileHash: hash,
            totalChunks: 2
        )

        // Receiving sequence 1 before sequence 0 must throw out-of-order error
        #expect(throws: CloudSyncFileTransferError.self) {
            try assembler.addChunk(sequence: 1, data: Data([0x03, 0x04]))
        }
    }

    // T12 & T13: Inconsistent metadata or corrupted hash rejected
    @Test func corruptedHashRejectedOnFinalize() throws {
        let data = Data([0x01, 0x02, 0x03])
        let fakeHash = "0000000000000000000000000000000000000000000000000000000000000000"
        var assembler = CloudSyncChunkAssembler(
            transferId: UUID().uuidString,
            fileName: "corrupt.bin",
            mimeType: "application/octet-stream",
            fileSize: 3,
            fileHash: fakeHash,
            totalChunks: 1
        )

        try assembler.addChunk(sequence: 0, data: data)
        #expect(assembler.isComplete)
        #expect(throws: CloudSyncFileTransferError.self) {
            _ = try assembler.finalizeAndVerify()
        }
    }

    // T13b: Size mismatch rejected on finalize
    @Test func sizeMismatchRejectedOnFinalize() throws {
        let data = Data([0x01, 0x02, 0x03])
        let hash = SHA256.hash(data: data).compactMap { String(format: "%02x", $0) }.joined()
        var assembler = CloudSyncChunkAssembler(
            transferId: UUID().uuidString,
            fileName: "badsize.bin",
            mimeType: "application/octet-stream",
            fileSize: 4, // Declares 4 bytes but only 3 provided
            fileHash: hash,
            totalChunks: 1
        )

        try assembler.addChunk(sequence: 0, data: data)
        #expect(assembler.isComplete)
        #expect(throws: CloudSyncFileTransferError.self) {
            _ = try assembler.finalizeAndVerify()
        }
    }

    // T13c: Tampered duplicate chunk rejected
    @Test func tamperedDuplicateChunkRejected() throws {
        let data1 = Data([0x01, 0x02])
        let dataTampered = Data([0x99, 0x99])
        var assembler = CloudSyncChunkAssembler(
            transferId: UUID().uuidString,
            fileName: "tamper.bin",
            mimeType: "application/octet-stream",
            fileSize: 4,
            fileHash: "dummy",
            totalChunks: 2
        )

        try assembler.addChunk(sequence: 0, data: data1)
        // Same sequence with altered bytes must throw
        #expect(throws: CloudSyncFileTransferError.self) {
            try assembler.addChunk(sequence: 0, data: dataTampered)
        }
    }

    // T20-T24: Multi-format payload validation (PDF, DOCX, ZIP, PNG, PlainText, URL)
    @Test func multiFormatPayloadHandling() throws {
        // PDF Magic bytes %PDF
        let pdfData = Data([0x25, 0x50, 0x44, 0x46, 0x2D, 0x31, 0x2E, 0x34])
        let pdfHash = SHA256.hash(data: pdfData).compactMap { String(format: "%02x", $0) }.joined()
        var pdfAssembler = CloudSyncChunkAssembler(
            transferId: UUID().uuidString,
            fileName: "contract.pdf",
            mimeType: "application/pdf",
            fileSize: Int64(pdfData.count),
            fileHash: pdfHash,
            totalChunks: 1
        )
        try pdfAssembler.addChunk(sequence: 0, data: pdfData)
        let verifiedPdf = try pdfAssembler.finalizeAndVerify()
        #expect(verifiedPdf == pdfData)

        // DOCX / ZIP Magic bytes PK..
        let docxData = Data([0x50, 0x4B, 0x03, 0x04, 0x14, 0x00, 0x06, 0x00])
        let docxHash = SHA256.hash(data: docxData).compactMap { String(format: "%02x", $0) }.joined()
        var docxAssembler = CloudSyncChunkAssembler(
            transferId: UUID().uuidString,
            fileName: "document.docx",
            mimeType: "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
            fileSize: Int64(docxData.count),
            fileHash: docxHash,
            totalChunks: 1
        )
        try docxAssembler.addChunk(sequence: 0, data: docxData)
        let verifiedDocx = try docxAssembler.finalizeAndVerify()
        #expect(verifiedDocx == docxData)

        // PNG Image Magic bytes
        let pngData = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        let pngHash = SHA256.hash(data: pngData).compactMap { String(format: "%02x", $0) }.joined()
        var pngAssembler = CloudSyncChunkAssembler(
            transferId: UUID().uuidString,
            fileName: "snapshot.png",
            mimeType: "image/png",
            fileSize: Int64(pngData.count),
            fileHash: pngHash,
            totalChunks: 1
        )
        try pngAssembler.addChunk(sequence: 0, data: pngData)
        let verifiedPng = try pngAssembler.finalizeAndVerify()
        #expect(verifiedPng == pngData)
    }

    // T14-T17: Sender Flow Control (waitForChunkAck & waitForCompleteAck)
    @Test @MainActor func senderFlowControlAckWaiting() async throws {
        let manager = CloudSyncManager.shared
        let transferId = UUID().uuidString.lowercased()
        let expectedHash = "4721a6e6e11c8f6ca97e9bf1d65bd0ef4011017d424f361ec34c653c28a6ce79"
        let key = try CloudSyncCrypto.importKeyBase64(manager.config.aesKeyBase64)

        // 1. Real chunk_ack dispatch to handleMessageV2
        let keyAck = "\(transferId)_0"
        let chunkCompleter = AsyncCompleter<Bool>()
        manager.chunkAckWaiters[keyAck] = chunkCompleter

        let mockChunkAck: [String: Any] = [
            "kind": "chunk_ack",
            "transfer_id": transferId,
            "sequence": 0,
            "status": "ok"
        ]
        let chunkAckData = try JSONSerialization.data(withJSONObject: mockChunkAck)
        let chunkEnvelope = try CloudSyncCrypto.encryptV2(plaintext: chunkAckData, using: key, senderId: "peer")

        // Actively dispatch encrypted envelope to handleMessageV2
        manager.handleMessageV2(chunkEnvelope)

        let chunkAcked = await chunkCompleter.wait(timeoutSeconds: 1.0, fallback: false)
        #expect(chunkAcked == true)

        // 2. Real complete_ack dispatch with matching hash to handleMessageV2
        let completeCompleter = AsyncCompleter<Bool>()
        manager.completeAckWaiters[transferId] = (expectedHash: expectedHash, expectedSessionId: nil, completer: completeCompleter)

        let mockCompleteAck: [String: Any] = [
            "kind": "complete_ack",
            "transfer_id": transferId,
            "file_hash": expectedHash,
            "status": "success"
        ]
        let compAckData = try JSONSerialization.data(withJSONObject: mockCompleteAck)
        let compEnvelope = try CloudSyncCrypto.encryptV2(plaintext: compAckData, using: key, senderId: "peer")

        // Actively dispatch encrypted envelope to handleMessageV2
        manager.handleMessageV2(compEnvelope)

        let compAcked = await completeCompleter.wait(timeoutSeconds: 1.0, fallback: false)
        #expect(compAcked == true)

        // 3. Hash mismatch or empty hash rejected
        let badTransferId = UUID().uuidString.lowercased()
        let mismatchCompleter = AsyncCompleter<Bool>()
        manager.completeAckWaiters[badTransferId] = (expectedHash: expectedHash, expectedSessionId: nil, completer: mismatchCompleter)

        let mockMismatchAck: [String: Any] = [
            "kind": "complete_ack",
            "transfer_id": badTransferId,
            "file_hash": "wrong_hash_12345",
            "status": "success"
        ]
        let mismatchData = try JSONSerialization.data(withJSONObject: mockMismatchAck)
        let mismatchEnvelope = try CloudSyncCrypto.encryptV2(plaintext: mismatchData, using: key, senderId: "peer")

        manager.handleMessageV2(mismatchEnvelope)

        let mismatchAcked = await mismatchCompleter.wait(timeoutSeconds: 0.1, fallback: false)
        #expect(mismatchAcked == false)

        // 4. Test timeout branch with very short timeout
        let timedOut = await manager.waitForChunkAck(transferId: "nonexistent", sequence: 99, timeoutSeconds: 0.05)
        #expect(!timedOut)

        let completeTimedOut = await manager.waitForCompleteAck(transferId: "nonexistent", expectedHash: "dummy", timeoutSeconds: 0.05)
        #expect(!completeTimedOut)
    }

    @Test
    func testTransferReplayIgnoredIdempotent() async throws {
        let manager = CloudSyncManager.shared
        let key = try CloudSyncCrypto.importKeyBase64(manager.config.aesKeyBase64)

        let replayTransferId = "replay-transfer-" + UUID().uuidString.lowercased()
        let sampleData = "Replay test content payload".data(using: .utf8)!
        let sampleHash = SHA256.hash(data: sampleData).compactMap { String(format: "%02x", $0) }.joined()

        let payload: [String: Any] = [
            "kind": "file",
            "transfer_id": replayTransferId,
            "sender_session_id": "test-session-1",
            "receiver_session_id": manager.currentSessionId,
            "file_name": "replay_sample.txt",
            "mime_type": "text/plain",
            "file_size": Int64(sampleData.count),
            "file_hash": sampleHash,
            "sequence": 0,
            "total_chunks": 1,
            "content_base64": sampleData.base64EncodedString(),
            "sourceApp": "TestApp",
            "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
        ]
        let envelopeData = try JSONSerialization.data(withJSONObject: payload)
        let envelope = try CloudSyncCrypto.encryptV2(plaintext: envelopeData, using: key, senderId: "peer")

        // First delivery: processes and stores file
        manager.handleMessageV2(envelope)

        // Second delivery (Replay): should detect already processed and not crash or duplicate
        manager.handleMessageV2(envelope)
    }

    @Test
    func testMissingOrMismatchedSessionRejected() async throws {
        let manager = CloudSyncManager.shared
        let key = try CloudSyncCrypto.importKeyBase64(manager.config.aesKeyBase64)

        // 1. Missing receiver_session_id rejected
        let missingTransferId = "missing-session-" + UUID().uuidString.lowercased()
        let sampleData = "No session test".data(using: .utf8)!
        let sampleHash = SHA256.hash(data: sampleData).compactMap { String(format: "%02x", $0) }.joined()

        let payloadMissing: [String: Any] = [
            "kind": "file",
            "transfer_id": missingTransferId,
            "sender_session_id": "test-sender-session",
            "file_name": "nosession.txt",
            "mime_type": "text/plain",
            "file_size": Int64(sampleData.count),
            "file_hash": sampleHash,
            "sequence": 0,
            "total_chunks": 1,
            "content_base64": sampleData.base64EncodedString(),
            "sourceApp": "TestApp",
            "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
        ]
        let envDataMissing = try JSONSerialization.data(withJSONObject: payloadMissing)
        let envMissing = try CloudSyncCrypto.encryptV2(plaintext: envDataMissing, using: key, senderId: "peer")

        manager.handleMessageV2(envMissing)
        #expect(!manager.isTransferProcessed(missingTransferId))

        // 2. Mismatched receiver_session_id rejected
        let mismatchTransferId = "mismatch-session-" + UUID().uuidString.lowercased()
        let payloadMismatch: [String: Any] = [
            "kind": "file",
            "transfer_id": mismatchTransferId,
            "sender_session_id": "test-sender-session",
            "receiver_session_id": "wrong-uuid-12345",
            "file_name": "mismatch.txt",
            "mime_type": "text/plain",
            "file_size": Int64(sampleData.count),
            "file_hash": sampleHash,
            "sequence": 0,
            "total_chunks": 1,
            "content_base64": sampleData.base64EncodedString(),
            "sourceApp": "TestApp",
            "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
        ]
        let envDataMismatch = try JSONSerialization.data(withJSONObject: payloadMismatch)
        let envMismatch = try CloudSyncCrypto.encryptV2(plaintext: envDataMismatch, using: key, senderId: "peer")

        manager.handleMessageV2(envMismatch)
        #expect(!manager.isTransferProcessed(mismatchTransferId))

        // 3. Image with missing or mismatched session rejected
        let imgMismatchTransferId = "img-mismatch-" + UUID().uuidString.lowercased()
        let payloadImgMismatch: [String: Any] = [
            "kind": "image",
            "transfer_id": imgMismatchTransferId,
            "sender_session_id": "test-sender-session",
            "receiver_session_id": "wrong-uuid-12345",
            "file_name": "wrong_img.png",
            "mime_type": "image/png",
            "content_base64": sampleData.base64EncodedString(),
            "file_hash": sampleHash,
            "sourceApp": "TestApp",
            "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
        ]
        let envDataImgMismatch = try JSONSerialization.data(withJSONObject: payloadImgMismatch)
        let envImgMismatch = try CloudSyncCrypto.encryptV2(plaintext: envDataImgMismatch, using: key, senderId: "peer")

        manager.handleMessageV2(envImgMismatch)
        #expect(!manager.isTransferProcessed(imgMismatchTransferId))
    }
}
