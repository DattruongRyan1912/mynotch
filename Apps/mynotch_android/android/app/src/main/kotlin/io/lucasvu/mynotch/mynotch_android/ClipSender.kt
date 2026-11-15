package io.lucasvu.mynotch.mynotch_android

import android.content.Context
import android.net.Uri
import android.provider.OpenableColumns
import java.util.Base64
import android.util.Log
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.security.MessageDigest
import java.security.SecureRandom
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import javax.crypto.Cipher
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

/**
 * Sends clips and files to the Mac via V2 encrypted WebSocket relay.
 */
object ClipSender {
    private const val TAG = "MyNotchSync"
    private const val SENDER_ID = "android"
    private const val TAG_BYTES = 16
    private const val CHUNK_SIZE = 524288 // 512 KiB
    private const val MAX_FILE_SIZE = 15728640 // 15 MiB

    private val client by lazy {
        OkHttpClient.Builder().connectTimeout(10, TimeUnit.SECONDS).build()
    }

    fun send(context: Context, text: String) {
        val creds = SyncStore.credentials(context) ?: run {
            Log.w(TAG, "Not paired, clip not sent")
            return
        }
        val now = System.currentTimeMillis()
        val payload = JSONObject()
            .put("kind", "text")
            .put("content", text)
            .put("sourceApp", "Android")
            .put("timestamp", now)
            .toString()

        val envelope = try {
            encryptV2(payload, creds.aesKeyBase64)
        } catch (e: Exception) {
            Log.e(TAG, "Encrypting clip failed", e)
            return
        }

        sendEnvelope(creds, envelope, "${text.length} chars")
        SyncStore.lastSent = text
    }

    private val executor = Executors.newSingleThreadExecutor()

    fun sendFile(context: Context, uri: Uri, mimeType: String, callback: ((Boolean, String) -> Unit)? = null) {
        val creds = SyncStore.credentials(context) ?: run {
            Log.w(TAG, "Not paired, file not sent")
            callback?.invoke(false, "Chưa ghép đôi với Mac")
            return
        }

        executor.execute {
            processAndSendFileDirect(context, uri, mimeType, creds, callback)
        }
    }

    private fun processAndSendFileDirect(
        context: Context,
        uri: Uri,
        mimeType: String,
        creds: SyncCredentials,
        callback: ((Boolean, String) -> Unit)?
    ) {
        try {
            var fileName = "file.bin"
            var querySize = 0L

            context.contentResolver.query(uri, null, null, null, null)?.use { cursor ->
                val nameIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                val sizeIndex = cursor.getColumnIndex(OpenableColumns.SIZE)
                if (cursor.moveToFirst()) {
                    if (nameIndex != -1) fileName = cursor.getString(nameIndex) ?: "file.bin"
                    if (sizeIndex != -1) querySize = cursor.getLong(sizeIndex)
                }
            }

            if (querySize > MAX_FILE_SIZE) {
                callback?.invoke(false, "File vượt quá 15 MiB")
                return
            }

            val safeName = fileName.replace(Regex("[^a-zA-Z0-9._-]"), "_")
            val inputStream = context.contentResolver.openInputStream(uri)
                ?: throw IOException("Không thể mở tệp: luồng đọc rỗng")

            val outputStream = ByteArrayOutputStream()
            val buffer = ByteArray(65536)
            var totalRead = 0
            inputStream.use { stream ->
                while (true) {
                    val read = stream.read(buffer)
                    if (read == -1) break
                    totalRead += read
                    if (totalRead > MAX_FILE_SIZE) {
                        callback?.invoke(false, "File vượt quá 15 MiB")
                        return
                    }
                    outputStream.write(buffer, 0, read)
                }
            }
            val bytes = outputStream.toByteArray()

            val md = MessageDigest.getInstance("SHA-256")
            val digest = md.digest(bytes)
            val fileHash = digest.joinToString("") { "%02x".format(it) }
            val transferId = UUID.randomUUID().toString()
            val senderSessionId = UUID.randomUUID().toString()
            val isImage = mimeType.startsWith("image/")
            sendFileDirectWithHandshake(creds, bytes, safeName, mimeType, isImage, callback)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to read/send file URI", e)
            callback?.invoke(false, "Lỗi đọc tệp: ${e.message}")
        }
    }

    fun sendMultipleFiles(context: Context, uris: List<Uri>, mimeType: String, callback: ((Boolean, String) -> Unit)? = null) {
        if (uris.size > 10) {
            callback?.invoke(false, "Số lượng tệp tin (${uris.size}) vượt quá giới hạn tối đa 10 tệp")
            return
        }
        val creds = SyncStore.credentials(context) ?: run {
            callback?.invoke(false, "Chưa ghép đôi với Mac")
            return
        }

        executor.execute {
            // Check total batch size <= 15 MiB upfront
            var totalBatchBytes = 0L
            for (uri in uris) {
                var querySize = 0L
                context.contentResolver.query(uri, null, null, null, null)?.use { cursor ->
                    val sizeIndex = cursor.getColumnIndex(OpenableColumns.SIZE)
                    if (cursor.moveToFirst() && sizeIndex != -1) {
                        querySize = cursor.getLong(sizeIndex)
                    }
                }
                totalBatchBytes += querySize
                if (totalBatchBytes > MAX_FILE_SIZE) {
                    callback?.invoke(false, "Tổng dung lượng tệp tin (${totalBatchBytes} bytes) vượt quá 15 MiB")
                    return@execute
                }
            }

            var sentCount = 0
            for (uri in uris) {
                val latch = java.util.concurrent.CountDownLatch(1)
                var fileSuccess = false
                processAndSendFileDirect(context, uri, mimeType, creds) { ok, _ ->
                    fileSuccess = ok
                    latch.countDown()
                }
                latch.await(30, TimeUnit.SECONDS)
                if (fileSuccess) sentCount++
            }
            callback?.invoke(sentCount == uris.size, "Đã gửi $sentCount/${uris.size} tệp sang Mac")
        }
    }

    fun buildEnvelopes(
        bytes: ByteArray,
        safeName: String,
        mimeType: String,
        isImage: Boolean,
        transferId: String,
        senderSessionId: String,
        receiverSessionId: String,
        fileHash: String,
        keyBase64: String
    ): List<String> {
        val envelopes = mutableListOf<String>()
        if (isImage && bytes.size <= 1048576) {
            val payload = JSONObject()
                .put("kind", "image")
                .put("transfer_id", transferId)
                .put("sender_session_id", senderSessionId)
                .put("receiver_session_id", receiverSessionId)
                .put("file_hash", fileHash)
                .put("file_name", safeName)
                .put("mime_type", mimeType)
                .put("content_base64", b64(bytes))
                .put("sourceApp", "Android")
                .put("timestamp", System.currentTimeMillis())
                .toString()
            envelopes.add(encryptV2(payload, keyBase64))
            return envelopes
        }

        val totalChunks = if (bytes.size <= 1048576) 1 else ((bytes.size + CHUNK_SIZE - 1) / CHUNK_SIZE)
        if (totalChunks == 1) {
            val payload = JSONObject()
                .put("kind", "file")
                .put("transfer_id", transferId)
                .put("sender_session_id", senderSessionId)
                .put("receiver_session_id", receiverSessionId)
                .put("file_name", safeName)
                .put("mime_type", mimeType)
                .put("file_size", bytes.size)
                .put("file_hash", fileHash)
                .put("sequence", 0)
                .put("total_chunks", 1)
                .put("content_base64", b64(bytes))
                .put("sourceApp", "Android")
                .put("timestamp", System.currentTimeMillis())
                .toString()
            envelopes.add(encryptV2(payload, keyBase64))
        } else {
            for (seq in 0 until totalChunks) {
                val start = seq * CHUNK_SIZE
                val end = minOf(start + CHUNK_SIZE, bytes.size)
                val chunk = bytes.copyOfRange(start, end)

                val payload = JSONObject()
                    .put("kind", "file_chunk")
                    .put("transfer_id", transferId)
                    .put("sender_session_id", senderSessionId)
                    .put("receiver_session_id", receiverSessionId)
                    .put("file_name", safeName)
                    .put("mime_type", mimeType)
                    .put("file_size", bytes.size)
                    .put("file_hash", fileHash)
                    .put("sequence", seq)
                    .put("total_chunks", totalChunks)
                    .put("content_base64", b64(chunk))
                    .put("sourceApp", "Android")
                    .put("timestamp", System.currentTimeMillis())
                    .toString()
                envelopes.add(encryptV2(payload, keyBase64))
            }
        }
        return envelopes
    }

    private fun sendFileDirectWithHandshake(
        creds: SyncCredentials,
        bytes: ByteArray,
        safeName: String,
        mimeType: String,
        isImage: Boolean,
        callback: ((Boolean, String) -> Unit)? = null
    ) {
        val url = creds.relayServerUrl.replaceFirst(Regex("^ws"), "http").toHttpUrlOrNull()?.newBuilder()
            ?.addQueryParameter("channel", creds.channelId)
            ?.addQueryParameter("auth", creds.authToken)
            ?.addQueryParameter("sender", SENDER_ID)
            ?.build() ?: run {
            callback?.invoke(false, "URL relay không hợp lệ")
            return
        }

        val md = MessageDigest.getInstance("SHA-256")
        val fileHash = md.digest(bytes).joinToString("") { "%02x".format(it) }
        val transferId = UUID.randomUUID().toString()
        val senderSessionId = creds.sessionId ?: UUID.randomUUID().toString()

        val completed = java.util.concurrent.atomic.AtomicBoolean(false)
        var envelopes = mutableListOf<String>()
        var currentIndex = 0
        var activeWebSocket: WebSocket? = null
        var handshakeCompleted = false

        val timer = java.util.Timer()
        timer.schedule(object : java.util.TimerTask() {
            override fun run() {
                if (completed.compareAndSet(false, true)) {
                    activeWebSocket?.close(1000, "Timeout")
                    callback?.invoke(false, "Hết thời gian chờ phản hồi từ thiết bị nhận")
                }
            }
        }, 30000)

        client.newWebSocket(Request.Builder().url(url).build(), object : WebSocketListener() {
            override fun onOpen(webSocket: WebSocket, response: Response) {
                activeWebSocket = webSocket
                try {
                    // Initiate handshake to discover Mac's current UUID session
                    val helloJson = JSONObject()
                        .put("kind", "hello")
                        .put("session_id", senderSessionId)
                        .put("senderId", SENDER_ID)
                        .put("transient", true)
                        .put("timestamp", System.currentTimeMillis())
                        .toString()
                    val helloEnv = encryptV2(helloJson, creds.aesKeyBase64)
                    webSocket.send(helloEnv)
                } catch (e: Exception) {
                    timer.cancel()
                    Log.e(TAG, "Failed sending hello: ${e.message}")
                    if (completed.compareAndSet(false, true)) {
                        callback?.invoke(false, "Lỗi handshake: ${e.message}")
                    }
                }
            }

            override fun onMessage(webSocket: WebSocket, text: String) {
                try {
                    val json = JSONObject(text)
                    if (json.optString("type") != "clip_v2") return
                    val decrypted = decryptV2(json, creds.aesKeyBase64)
                    val payload = JSONObject(decrypted)
                    val kind = payload.optString("kind")

                    if (!handshakeCompleted && (kind == "ready" || kind == "hello")) {
                        val peerSession = payload.optString("session_id")
                        if (peerSession.isNotEmpty()) {
                            handshakeCompleted = true
                            if (kind == "hello") {
                                val readyJson = JSONObject()
                                    .put("kind", "ready")
                                    .put("session_id", senderSessionId)
                                    .put("peer_session_id", peerSession)
                                    .put("senderId", SENDER_ID)
                                    .put("timestamp", System.currentTimeMillis())
                                    .toString()
                                webSocket.send(encryptV2(readyJson, creds.aesKeyBase64))
                            }
                            envelopes = buildEnvelopes(
                                bytes = bytes,
                                safeName = safeName,
                                mimeType = mimeType,
                                isImage = isImage,
                                transferId = transferId,
                                senderSessionId = senderSessionId,
                                receiverSessionId = peerSession,
                                fileHash = fileHash,
                                keyBase64 = creds.aesKeyBase64
                            ).toMutableList()
                            if (envelopes.isNotEmpty()) {
                                webSocket.send(envelopes[0])
                            }
                            return
                        }
                    }

                    handleIncomingTransferMessage(
                        text = text,
                        creds = creds,
                        transferId = transferId,
                        fileHash = fileHash,
                        senderSessionId = senderSessionId,
                        totalEnvelopes = envelopes.size,
                        currentIndex = currentIndex,
                        onNextChunk = { nextIndex ->
                            currentIndex = nextIndex
                            if (currentIndex < envelopes.size) {
                                webSocket.send(envelopes[currentIndex])
                            }
                        },
                        onComplete = { success, msg ->
                            timer.cancel()
                            webSocket.close(1000, "Done")
                            if (completed.compareAndSet(false, true)) {
                                callback?.invoke(success, msg)
                            }
                        },
                        onError = { errMsg ->
                            timer.cancel()
                            webSocket.close(1002, errMsg)
                            if (completed.compareAndSet(false, true)) {
                                callback?.invoke(false, "Lỗi từ Mac: $errMsg")
                            }
                        }
                    )
                } catch (e: Exception) {
                    Log.d(TAG, "Message parsing: ${e.message}")
                }
            }

            override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                timer.cancel()
                if (completed.compareAndSet(false, true)) {
                    callback?.invoke(false, "Lỗi kết nối: ${t.message}")
                }
            }

            override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                timer.cancel()
                if (!completed.get()) {
                    if (completed.compareAndSet(false, true)) {
                        callback?.invoke(false, "Kết nối đóng: $code $reason")
                    }
                }
            }
        })
    }

    private fun sendEnvelope(creds: SyncCredentials, envelope: String, label: String) {
        sendEnvelopesSequential(creds, listOf(envelope), label, "", "", null)
    }

    private fun sendEnvelopesSequential(
        creds: SyncCredentials,
        envelopes: List<String>,
        label: String,
        transferId: String,
        fileHash: String = "",
        callback: ((Boolean, String) -> Unit)? = null
    ) {
        val url = creds.relayServerUrl.replaceFirst(Regex("^ws"), "http").toHttpUrlOrNull()?.newBuilder()
            ?.addQueryParameter("channel", creds.channelId)
            ?.addQueryParameter("auth", creds.authToken)
            ?.addQueryParameter("sender", SENDER_ID)
            ?.build() ?: run {
            callback?.invoke(false, "URL relay không hợp lệ")
            return
        }

        val completed = java.util.concurrent.atomic.AtomicBoolean(false)
        var currentIndex = 0
        var activeWebSocket: WebSocket? = null

        val timer = java.util.Timer()
        timer.schedule(object : java.util.TimerTask() {
            override fun run() {
                if (completed.compareAndSet(false, true)) {
                    activeWebSocket?.close(1000, "Timeout")
                    callback?.invoke(false, "Hết thời gian chờ phản hồi từ thiết bị nhận")
                }
            }
        }, 30000)

        client.newWebSocket(Request.Builder().url(url).build(), object : WebSocketListener() {
            override fun onOpen(webSocket: WebSocket, response: Response) {
                activeWebSocket = webSocket
                try {
                    if (envelopes.isNotEmpty()) {
                        val sent = webSocket.send(envelopes[0])
                        if (!sent) {
                            timer.cancel()
                            webSocket.close(1001, "Send buffer full")
                            if (completed.compareAndSet(false, true)) {
                                callback?.invoke(false, "Buffer mạng bị tràn")
                            }
                            return
                        }
                    }
                    if (envelopes.size <= 1 && transferId.isEmpty()) {
                        // Plain text or legacy message without transferId: complete immediately
                        timer.cancel()
                        webSocket.close(1000, "Done")
                        if (completed.compareAndSet(false, true)) {
                            callback?.invoke(true, "Đã gửi $label sang Mac")
                        }
                    }
                } catch (e: Exception) {
                    timer.cancel()
                    Log.e(TAG, "Failed sending envelopes: ${e.message}")
                    if (completed.compareAndSet(false, true)) {
                        callback?.invoke(false, "Lỗi gửi: ${e.message}")
                    }
                }
            }

            override fun onMessage(webSocket: WebSocket, text: String) {
                try {
                    handleIncomingTransferMessage(
                        text = text,
                        creds = creds,
                        transferId = transferId,
                        fileHash = fileHash,
                        totalEnvelopes = envelopes.size,
                        currentIndex = currentIndex,
                        onNextChunk = { nextIndex ->
                            currentIndex = nextIndex
                            if (currentIndex < envelopes.size) {
                                val sent = webSocket.send(envelopes[currentIndex])
                                if (!sent) {
                                    timer.cancel()
                                    webSocket.close(1001, "Send buffer full")
                                    if (completed.compareAndSet(false, true)) {
                                        callback?.invoke(false, "Buffer mạng bị tràn")
                                    }
                                }
                            }
                        },
                        onComplete = { success, msg ->
                            timer.cancel()
                            if (success) {
                                webSocket.close(1000, "Done")
                                if (completed.compareAndSet(false, true)) {
                                    Log.i(TAG, "Transfer $transferId completed with verified ACK")
                                    callback?.invoke(true, "Đã gửi $label sang Mac ($msg)")
                                }
                            } else {
                                webSocket.close(1002, "ACK verification failed")
                                if (completed.compareAndSet(false, true)) {
                                    callback?.invoke(false, msg)
                                }
                            }
                        },
                        onError = { errMsg ->
                            timer.cancel()
                            webSocket.close(1002, errMsg)
                            if (completed.compareAndSet(false, true)) {
                                callback?.invoke(false, "Thiết bị nhận báo lỗi: $errMsg")
                            }
                        }
                    )
                } catch (e: Exception) {
                    Log.d(TAG, "Message parsing non-critical: ${e.message}")
                }
            }

            override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                timer.cancel()
                Log.e(TAG, "Sending envelope failed: ${t.message}")
                if (completed.compareAndSet(false, true)) {
                    callback?.invoke(false, "Lỗi kết nối: ${t.message}")
                }
            }

            override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                timer.cancel()
                if (transferId.isEmpty() && code == 1000 && !completed.get()) {
                    if (completed.compareAndSet(false, true)) {
                        callback?.invoke(true, "Đã gửi $label sang Mac")
                    }
                } else if (!completed.get()) {
                    if (completed.compareAndSet(false, true)) {
                        callback?.invoke(false, "Kết nối đóng trước khi nhận biên nhận hoàn tất ($code: $reason)")
                    }
                }
            }
        })
    }

    internal fun handleIncomingTransferMessage(
        text: String,
        creds: SyncCredentials,
        transferId: String,
        fileHash: String,
        senderSessionId: String = "",
        totalEnvelopes: Int,
        currentIndex: Int,
        onNextChunk: (Int) -> Unit,
        onComplete: (Boolean, String) -> Unit,
        onError: (String) -> Unit
    ): Boolean {
        val json = JSONObject(text)
        if (json.optString("type") != "clip_v2") return false
        val decrypted = decryptV2(json, creds.aesKeyBase64)
        val payload = JSONObject(decrypted)
        val kind = payload.optString("kind")
        val ackTransferId = payload.optString("transfer_id")

        if (ackTransferId != transferId || transferId.isEmpty()) return false

        when (kind) {
            "chunk_ack" -> {
                val ackSeq = payload.optInt("sequence", -1)
                if (ackSeq == currentIndex) {
                    onNextChunk(currentIndex + 1)
                    return true
                }
            }
            "complete_ack" -> {
                val status = payload.optString("status")
                val receivedHash = payload.optString("file_hash")
                val ackSenderSession = payload.optString("sender_session_id")
                val sessionValid = senderSessionId.isNotEmpty() &&
                    ackSenderSession.isNotEmpty() &&
                    ackSenderSession == senderSessionId
                val validReceipt = status == "success" &&
                    fileHash.isNotEmpty() &&
                    receivedHash.isNotEmpty() &&
                    receivedHash == fileHash &&
                    sessionValid &&
                    currentIndex >= totalEnvelopes - 1

                if (validReceipt) {
                    onComplete(true, "Xác nhận lưu thành công")
                } else {
                    onComplete(false, "Xác thực biên nhận thất bại: status=$status, hash=$receivedHash, session=$ackSenderSession")
                }
                return true
            }
            "error" -> {
                val errMsg = payload.optString("message", "Lỗi từ thiết bị đích")
                onError(errMsg)
                return true
            }
        }
        return false
    }

    private fun b64(bytes: ByteArray): String = Base64.getEncoder().encodeToString(bytes)
    private fun b64Decode(str: String): ByteArray = Base64.getDecoder().decode(str)

    /** V2 Authenticated Encryption with Canonical AAD */
    fun encryptV2(plaintextJson: String, keyBase64: String): String {
        val now = System.currentTimeMillis()
        val id = UUID.randomUUID().toString()
        val aad = "mynotch\nclip_v2\n2\n$id\n$SENDER_ID\n$now"

        val nonce = ByteArray(12).also { SecureRandom().nextBytes(it) }
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(
            Cipher.ENCRYPT_MODE,
            SecretKeySpec(b64Decode(keyBase64), "AES"),
            GCMParameterSpec(TAG_BYTES * 8, nonce),
        )
        cipher.updateAAD(aad.toByteArray(Charsets.UTF_8))

        val sealed = cipher.doFinal(plaintextJson.toByteArray(Charsets.UTF_8))
        val ciphertext = sealed.copyOfRange(0, sealed.size - TAG_BYTES)
        val tag = sealed.copyOfRange(sealed.size - TAG_BYTES, sealed.size)

        return JSONObject()
            .put("type", "clip_v2")
            .put("v", 2)
            .put("id", id)
            .put("senderId", SENDER_ID)
            .put("timestamp", now)
            .put("nonce", b64(nonce))
            .put("tag", b64(tag))
            .put("ciphertext", b64(ciphertext))
            .toString()
    }

    /** V2 Authenticated Decryption with Canonical AAD */
    fun decryptV2(envelopeJson: JSONObject, keyBase64: String): String {
        val id = envelopeJson.getString("id")
        val senderId = envelopeJson.getString("senderId")
        val timestamp = envelopeJson.getLong("timestamp")
        val aad = "mynotch\nclip_v2\n2\n$id\n$senderId\n$timestamp"

        val nonce = b64Decode(envelopeJson.getString("nonce"))
        val tag = b64Decode(envelopeJson.getString("tag"))
        val ciphertext = b64Decode(envelopeJson.getString("ciphertext"))

        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(
            Cipher.DECRYPT_MODE,
            SecretKeySpec(b64Decode(keyBase64), "AES"),
            GCMParameterSpec(TAG_BYTES * 8, nonce),
        )
        cipher.updateAAD(aad.toByteArray(Charsets.UTF_8))

        val combined = ByteArray(ciphertext.size + tag.size)
        System.arraycopy(ciphertext, 0, combined, 0, ciphertext.size)
        System.arraycopy(tag, 0, combined, ciphertext.size, tag.size)

        val decrypted = cipher.doFinal(combined)
        return String(decrypted, Charsets.UTF_8)
    }
}
