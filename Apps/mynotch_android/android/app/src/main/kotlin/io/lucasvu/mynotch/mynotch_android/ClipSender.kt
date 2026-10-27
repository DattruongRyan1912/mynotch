package io.lucasvu.mynotch.mynotch_android

import android.content.Context
import android.util.Base64
import android.util.Log
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import org.json.JSONObject
import java.security.SecureRandom
import java.util.UUID
import java.util.concurrent.TimeUnit
import javax.crypto.Cipher
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

/**
 * Sends one clip to the Mac: connect to the relay, send the encrypted envelope, close.
 * The relay keeps the last clip for peers that connect later, so no long-lived socket is needed.
 */
object ClipSender {
    private const val TAG = "MyNotchSync"
    private const val SENDER_ID = "android"
    private const val TAG_BYTES = 16

    private val client by lazy {
        OkHttpClient.Builder().connectTimeout(10, TimeUnit.SECONDS).build()
    }

    fun send(context: Context, text: String) {
        val creds = SyncStore.credentials(context) ?: run {
            Log.w(TAG, "Not paired, clip not sent")
            return
        }
        val envelope = try {
            encrypt(text, creds.aesKeyBase64)
        } catch (e: Exception) {
            Log.e(TAG, "Encrypting clip failed", e)
            return
        }
        // OkHttp only takes http(s) URLs; ws(s) maps onto them.
        val url = creds.relayServerUrl.replaceFirst(Regex("^ws"), "http").toHttpUrlOrNull()?.newBuilder()
            ?.addQueryParameter("channel", creds.channelId)
            ?.addQueryParameter("auth", creds.authToken)
            ?.addQueryParameter("sender", SENDER_ID)
            ?.build() ?: run {
            Log.e(TAG, "Invalid relay URL")
            return
        }
        SyncStore.lastSent = text
        client.newWebSocket(Request.Builder().url(url).build(), object : WebSocketListener() {
            override fun onOpen(webSocket: WebSocket, response: Response) {
                webSocket.send(envelope)
                // Close waits for the queued envelope to go out. Whatever the relay pushes on connect is ignored.
                webSocket.close(1000, null)
                Log.i(TAG, "Sent clip to Mac (${text.length} chars)")
            }

            override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                Log.e(TAG, "Sending clip failed: ${t.message}")
                if (SyncStore.lastSent == text) SyncStore.lastSent = null
            }
        })
    }

    /** Same envelope as the Mac's CloudSyncCrypto: AES-256-GCM, 12-byte nonce, tag kept apart from the ciphertext. */
    private fun encrypt(text: String, keyBase64: String): String {
        val now = System.currentTimeMillis()
        val payload = JSONObject()
            .put("format", "text/plain")
            .put("content", text)
            .put("sourceApp", "Android")
            .put("timestamp", now)
            .toString()
        val nonce = ByteArray(12).also { SecureRandom().nextBytes(it) }
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(
            Cipher.ENCRYPT_MODE,
            SecretKeySpec(Base64.decode(keyBase64, Base64.DEFAULT), "AES"),
            GCMParameterSpec(TAG_BYTES * 8, nonce),
        )
        // Java appends the tag to the ciphertext.
        val sealed = cipher.doFinal(payload.toByteArray(Charsets.UTF_8))
        val ciphertext = sealed.copyOfRange(0, sealed.size - TAG_BYTES)
        val tag = sealed.copyOfRange(sealed.size - TAG_BYTES, sealed.size)
        fun b64(bytes: ByteArray) = Base64.encodeToString(bytes, Base64.NO_WRAP)
        return JSONObject()
            .put("type", "clip")
            .put("v", 1)
            .put("id", UUID.randomUUID().toString())
            .put("senderId", SENDER_ID)
            .put("timestamp", now)
            .put("nonce", b64(nonce))
            .put("tag", b64(tag))
            .put("ciphertext", b64(ciphertext))
            .toString()
    }
}
