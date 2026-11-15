package io.lucasvu.mynotch.mynotch_android

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.Base64

class ClipTransferTest {
    @Test
    fun testSafeFileNameSanitization() {
        val unsafe = "../hack/file name?.txt"
        val safe = ClipTransfer.sanitizeFileName(unsafe)
        assertTrue(!safe.contains("/"))
        assertTrue(!safe.contains("?"))
        assertEquals(".._hack_file_name_.txt", safe)
    }

    @Test
    fun testTransferIdSanitization() {
        val maliciousTransferId = "../../shared_prefs"
        val safeTransferId = ClipTransfer.sanitizeTransferId(maliciousTransferId)
        assertTrue(!safeTransferId.contains("/"))
        assertTrue(!safeTransferId.contains("."))
        assertEquals("______shared_prefs", safeTransferId)
    }

    @Test
    fun testKotlinCryptoEncryptV2MatchesEnvelopeSpec() {
        val key = ByteArray(32) { it.toByte() }
        val keyB64 = Base64.getEncoder().encodeToString(key)
        val payload = "{\"kind\":\"text\",\"content\":\"Test V2 Envelope\"}"

        val envelopeJson = ClipSender.encryptV2(payload, keyB64)
        val obj = org.json.JSONObject(envelopeJson)

        assertEquals("clip_v2", obj.getString("type"))
        assertEquals(2, obj.getInt("v"))
        assertEquals("android", obj.getString("senderId"))
        assertTrue(obj.has("id"))
        assertTrue(obj.has("timestamp"))
        assertTrue(obj.has("nonce"))
        assertTrue(obj.has("tag"))
        assertTrue(obj.has("ciphertext"))

        val nonce = Base64.getDecoder().decode(obj.getString("nonce"))
        val tag = Base64.getDecoder().decode(obj.getString("tag"))
        val ciphertext = Base64.getDecoder().decode(obj.getString("ciphertext"))

        assertEquals(12, nonce.size)
        assertEquals(16, tag.size)
        assertTrue(ciphertext.isNotEmpty())
    }

    @Test
    fun testBase64DecodingLength() {
        val original = "Hello Android ClipTransfer"
        val encoded = Base64.getEncoder().encodeToString(original.toByteArray())
        val decoded = String(Base64.getDecoder().decode(encoded))
        assertEquals(original, decoded)
    }

    @Test
    fun testNonOverwritingDuplicateFileNameGeneration() {
        val tempFolder = java.nio.file.Files.createTempDirectory("test_clip_transfer").toFile()
        try {
            val file1 = ClipTransfer.saveFileInternal(tempFolder, "t1", "document.pdf", "Version 1".toByteArray())
            val file2 = ClipTransfer.saveFileInternal(tempFolder, "t1", "document.pdf", "Version 2".toByteArray())
            val file3 = ClipTransfer.saveFileInternal(tempFolder, "t1", "document.pdf", "Version 3".toByteArray())

            assertEquals("document.pdf", file1.name)
            assertEquals("document (1).pdf", file2.name)
            assertEquals("document (2).pdf", file3.name)
            assertEquals("Version 1", file1.readText())
            assertEquals("Version 2", file2.readText())
            assertEquals("Version 3", file3.readText())
        } finally {
            tempFolder.deleteRecursively()
        }
    }

    @Test
    fun testEmpiricalEvidenceSaveFile() {
        var current = java.io.File(".").canonicalFile
        while (current != null && !java.io.File(current, "Packages").exists()) {
            current = current.parentFile
        }
        val repoRoot = current ?: java.io.File(".")
        val evidenceDir = java.io.File(repoRoot, "docs/evidence/cloud-sync-v2/android_sync_received")
        if (!evidenceDir.exists()) evidenceDir.mkdirs()

        val sourceFile = java.io.File(repoRoot, "docs/evidence/cloud-sync-v2/empirical_source_test.bin")
        val bytes = if (sourceFile.exists()) sourceFile.readBytes() else ByteArray(65536) { 0x42 }

        val transferId = "android-transfer-empirical-001"
        java.io.File(evidenceDir, transferId).deleteRecursively()
        val file1 = ClipTransfer.saveFileInternal(evidenceDir, transferId, "empirical_test.bin", bytes)
        val file2 = ClipTransfer.saveFileInternal(evidenceDir, transferId, "empirical_test.bin", bytes)

        assertEquals("empirical_test.bin", file1.name)
        assertEquals("empirical_test (1).bin", file2.name)
        assertTrue(file1.exists())
        assertTrue(file2.exists())
        assertEquals(bytes.size.toLong(), file1.length())
        assertEquals(bytes.size.toLong(), file2.length())
    }

    @Test
    fun testMultiFormatFileSaveAndIntegrity() {
        val tempFolder = java.nio.file.Files.createTempDirectory("test_multiformat").toFile()
        try {
            // PDF
            val pdfBytes = byteArrayOf(0x25, 0x50, 0x44, 0x46, 0x2D, 0x31, 0x2E, 0x34)
            val pdfFile = ClipTransfer.saveFileInternal(tempFolder, "t_pdf", "statement.pdf", pdfBytes)
            assertEquals("statement.pdf", pdfFile.name)
            assertTrue(pdfFile.readBytes().contentEquals(pdfBytes))

            // DOCX / ZIP
            val docxBytes = byteArrayOf(0x50, 0x4B, 0x03, 0x04, 0x14, 0x00)
            val docxFile = ClipTransfer.saveFileInternal(tempFolder, "t_docx", "proposal.docx", docxBytes)
            assertEquals("proposal.docx", docxFile.name)
            assertTrue(docxFile.readBytes().contentEquals(docxBytes))

            // PNG
            val pngBytes = byteArrayOf(0x89.toByte(), 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A)
            val pngFile = ClipTransfer.saveFileInternal(tempFolder, "t_png", "screenshot.png", pngBytes)
            assertEquals("screenshot.png", pngFile.name)
            assertTrue(pngFile.readBytes().contentEquals(pngBytes))
        } finally {
            tempFolder.deleteRecursively()
        }
    }

    @Test
    fun testFlowControlCompleteAckPayloadValidation() {
        val transferId = "test-transfer-ack-123"
        val expectedHash = "4721a6e6e11c8f6ca97e9bf1d65bd0ef4011017d424f361ec34c653c28a6ce79"
        val aesKeyBase64 = "MDEyMzQ1Njc4OWFiY2RlZjAxMjM0NTY3ODlhYmNkZWY=" // 32 bytes valid AES key
        val creds = SyncCredentials(
            channelId = "chan123",
            authToken = "tok123",
            aesKeyBase64 = aesKeyBase64,
            relayServerUrl = "wss://example.com/ws"
        )

        // 1. Test real encrypted chunk_ack handling
        val chunkAckJson = org.json.JSONObject()
            .put("kind", "chunk_ack")
            .put("transfer_id", transferId)
            .put("sequence", 0)
            .put("status", "ok")
            .toString()
        val chunkEnvelope = ClipSender.encryptV2(chunkAckJson, aesKeyBase64)

        var nextChunkCalled = false
        var nextChunkIndex = -1
        val chunkHandled = ClipSender.handleIncomingTransferMessage(
            text = chunkEnvelope,
            creds = creds,
            transferId = transferId,
            fileHash = expectedHash,
            totalEnvelopes = 2,
            currentIndex = 0,
            onNextChunk = { idx ->
                nextChunkCalled = true
                nextChunkIndex = idx
            },
            onComplete = { _, _ -> },
            onError = { }
        )
        assertTrue(chunkHandled)
        assertTrue(nextChunkCalled)
        assertEquals(1, nextChunkIndex)

        // 2. Test real encrypted complete_ack with matching hash and matching session
        val senderSession = "session-test-456"
        val completeAckJson = org.json.JSONObject()
            .put("kind", "complete_ack")
            .put("transfer_id", transferId)
            .put("file_hash", expectedHash)
            .put("sender_session_id", senderSession)
            .put("status", "success")
            .toString()
        val completeEnvelope = ClipSender.encryptV2(completeAckJson, aesKeyBase64)

        var completeSuccess = false
        val completeHandled = ClipSender.handleIncomingTransferMessage(
            text = completeEnvelope,
            creds = creds,
            transferId = transferId,
            fileHash = expectedHash,
            senderSessionId = senderSession,
            totalEnvelopes = 2,
            currentIndex = 1,
            onNextChunk = { },
            onComplete = { success, _ -> completeSuccess = success },
            onError = { }
        )
        assertTrue(completeHandled)
        assertTrue(completeSuccess)

        // 3. Test real encrypted complete_ack with mismatched hash rejected
        val mismatchAckJson = org.json.JSONObject()
            .put("kind", "complete_ack")
            .put("transfer_id", transferId)
            .put("file_hash", "tampered_hash_value_123")
            .put("sender_session_id", senderSession)
            .put("status", "success")
            .toString()
        val mismatchEnvelope = ClipSender.encryptV2(mismatchAckJson, aesKeyBase64)

        var mismatchSuccess = true
        val mismatchHandled = ClipSender.handleIncomingTransferMessage(
            text = mismatchEnvelope,
            creds = creds,
            transferId = transferId,
            fileHash = expectedHash,
            senderSessionId = senderSession,
            totalEnvelopes = 2,
            currentIndex = 1,
            onNextChunk = { },
            onComplete = { success, _ -> mismatchSuccess = success },
            onError = { }
        )
        assertTrue(mismatchHandled)
        assertFalse(mismatchSuccess)

        // 4. Test real encrypted complete_ack with empty hash rejected
        val emptyHashAckJson = org.json.JSONObject()
            .put("kind", "complete_ack")
            .put("transfer_id", transferId)
            .put("file_hash", "")
            .put("sender_session_id", senderSession)
            .put("status", "success")
            .toString()
        val emptyEnvelope = ClipSender.encryptV2(emptyHashAckJson, aesKeyBase64)

        var emptySuccess = true
        val emptyHandled = ClipSender.handleIncomingTransferMessage(
            text = emptyEnvelope,
            creds = creds,
            transferId = transferId,
            fileHash = expectedHash,
            senderSessionId = senderSession,
            totalEnvelopes = 2,
            currentIndex = 1,
            onNextChunk = { },
            onComplete = { success, _ -> emptySuccess = success },
            onError = { }
        )
        assertTrue(emptyHandled)
        assertFalse(emptySuccess)
    }

    @Test
    fun testBuildEnvelopesNegotiatedPeerSession() {
        val aesKeyBase64 = "MDEyMzQ1Njc4OWFiY2RlZjAxMjM0NTY3ODlhYmNkZWY="
        val bytes = "Hello from Android to Mac".toByteArray()
        val expectedPeerSession = "mac-peer-uuid-9999"
        val senderSession = "android-sender-uuid-1111"
        val transferId = "trans-123"
        val fileHash = "abcdef"

        val envelopes = ClipSender.buildEnvelopes(
            bytes = bytes,
            safeName = "hello.txt",
            mimeType = "text/plain",
            isImage = false,
            transferId = transferId,
            senderSessionId = senderSession,
            receiverSessionId = expectedPeerSession,
            fileHash = fileHash,
            keyBase64 = aesKeyBase64
        )

        assertEquals(1, envelopes.size)
        val envelopeJson = org.json.JSONObject(envelopes[0])
        val decrypted = ClipSender.decryptV2(envelopeJson, aesKeyBase64)
        val payload = org.json.JSONObject(decrypted)

        assertEquals("file", payload.getString("kind"))
        assertEquals(expectedPeerSession, payload.getString("receiver_session_id"))
        assertEquals(senderSession, payload.getString("sender_session_id"))
        assertEquals(transferId, payload.getString("transfer_id"))
    }

    @Test
    fun testCompleteAckSessionValidation() {
        val transferId = "test-session-ack"
        val expectedHash = "hash123"
        val senderSession = "session-valid-001"
        val aesKeyBase64 = "MDEyMzQ1Njc4OWFiY2RlZjAxMjM0NTY3ODlhYmNkZWY="
        val creds = SyncCredentials("c", "k", aesKeyBase64, "ws://localhost")

        // complete_ack with matching sender_session_id -> success
        val ackValid = org.json.JSONObject()
            .put("kind", "complete_ack")
            .put("transfer_id", transferId)
            .put("file_hash", expectedHash)
            .put("sender_session_id", senderSession)
            .put("status", "success")
            .toString()
        val ackValidEnv = ClipSender.encryptV2(ackValid, aesKeyBase64)

        var validComplete = false
        ClipSender.handleIncomingTransferMessage(
            text = ackValidEnv,
            creds = creds,
            transferId = transferId,
            fileHash = expectedHash,
            senderSessionId = senderSession,
            totalEnvelopes = 1,
            currentIndex = 0,
            onNextChunk = {},
            onComplete = { success, _ -> validComplete = success },
            onError = {}
        )
        assertTrue(validComplete)

        // complete_ack with mismatched sender_session_id -> failure
        val ackMismatch = org.json.JSONObject()
            .put("kind", "complete_ack")
            .put("transfer_id", transferId)
            .put("file_hash", expectedHash)
            .put("sender_session_id", "wrong-session-999")
            .put("status", "success")
            .toString()
        val ackMismatchEnv = ClipSender.encryptV2(ackMismatch, aesKeyBase64)

        var mismatchComplete = true
        ClipSender.handleIncomingTransferMessage(
            text = ackMismatchEnv,
            creds = creds,
            transferId = transferId,
            fileHash = expectedHash,
            senderSessionId = senderSession,
            totalEnvelopes = 1,
            currentIndex = 0,
            onNextChunk = {},
            onComplete = { success, _ -> mismatchComplete = success },
            onError = {}
        )
        assertFalse(mismatchComplete)

        // complete_ack with missing sender_session_id -> failure
        val ackMissing = org.json.JSONObject()
            .put("kind", "complete_ack")
            .put("transfer_id", transferId)
            .put("file_hash", expectedHash)
            .put("status", "success")
            .toString()
        val ackMissingEnv = ClipSender.encryptV2(ackMissing, aesKeyBase64)

        var missingComplete = true
        ClipSender.handleIncomingTransferMessage(
            text = ackMissingEnv,
            creds = creds,
            transferId = transferId,
            fileHash = expectedHash,
            senderSessionId = senderSession,
            totalEnvelopes = 1,
            currentIndex = 0,
            onNextChunk = {},
            onComplete = { success, _ -> missingComplete = success },
            onError = {}
        )
        assertFalse(missingComplete)

        // complete_ack with empty sender_session_id -> failure
        val ackEmpty = org.json.JSONObject()
            .put("kind", "complete_ack")
            .put("transfer_id", transferId)
            .put("file_hash", expectedHash)
            .put("sender_session_id", "")
            .put("status", "success")
            .toString()
        val ackEmptyEnv = ClipSender.encryptV2(ackEmpty, aesKeyBase64)

        var emptyComplete = true
        ClipSender.handleIncomingTransferMessage(
            text = ackEmptyEnv,
            creds = creds,
            transferId = transferId,
            fileHash = expectedHash,
            senderSessionId = senderSession,
            totalEnvelopes = 1,
            currentIndex = 0,
            onNextChunk = {},
            onComplete = { success, _ -> emptyComplete = success },
            onError = {}
        )
        assertFalse(emptyComplete)
    }
}
