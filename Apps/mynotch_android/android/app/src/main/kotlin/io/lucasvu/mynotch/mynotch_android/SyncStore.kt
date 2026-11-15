package io.lucasvu.mynotch.mynotch_android

import android.content.ClipData
import android.content.ClipDescription
import android.content.Context
import android.os.Build
import android.os.SystemClock

/** Pairing credentials, mirrored here from the Flutter side so native senders work without a Flutter engine. */
data class SyncCredentials(
    val channelId: String,
    val authToken: String,
    val aesKeyBase64: String,
    val relayServerUrl: String,
    val sessionId: String? = null,
)

/** Native state shared by the senders, the clipboard watcher and the Flutter bridge. */
object SyncStore {
    private const val PREFS = "mynotch_sync"

    /** Text this app put on the clipboard (received from the Mac), and when: copies of it are not sent back. */
    @Volatile var lastOwnWrite: String? = null
    @Volatile var lastOwnWriteAt = 0L
    /** Text last sent to the Mac, so the same clipboard is not sent twice. */
    @Volatile var lastSent: String? = null

    fun credentials(context: Context): SyncCredentials? {
        val p = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        return SyncCredentials(
            p.getString("channel_id", null) ?: return null,
            p.getString("auth_token", null) ?: return null,
            p.getString("aes_key", null) ?: return null,
            p.getString("server_url", null) ?: return null,
            p.getString("session_id", null),
        )
    }

    fun sessionId(context: Context): String? =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString("session_id", null)

    fun setSessionId(context: Context, sessionId: String?) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putString("session_id", sessionId)
            .apply()
    }

    fun setCredentials(context: Context, creds: SyncCredentials?) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putString("channel_id", creds?.channelId)
            .putString("auth_token", creds?.authToken)
            .putString("aes_key", creds?.aesKeyBase64)
            .putString("server_url", creds?.relayServerUrl)
            .putString("session_id", creds?.sessionId)
            .apply()
    }

    fun isWatchEnabled(context: Context) =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getBoolean("watch_enabled", false)

    fun setWatchEnabled(context: Context, enabled: Boolean) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putBoolean("watch_enabled", enabled).apply()
    }

    /**
     * The text of [clip]. With [skipSensitive], a clip its app marked sensitive (a password manager, Android 13+) gives
     * null, as on the Mac: only a copy the user sends by hand goes out then.
     */
    fun clipText(context: Context, clip: ClipData?, skipSensitive: Boolean): String? {
        if (clip == null || clip.itemCount == 0) return null
        if (skipSensitive && Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            clip.description.extras?.getBoolean(ClipDescription.EXTRA_IS_SENSITIVE) == true
        ) return null
        val item = clip.getItemAt(0)
        // If clipboard contains a file/content URI, do NOT coerce to text string for auto-sync
        if (item.uri != null && (item.uri.scheme == "content" || item.uri.scheme == "file")) {
            return null
        }
        return item.coerceToText(context)?.toString()
    }

    fun recordOwnWrite(text: String) {
        lastOwnWrite = text
        lastOwnWriteAt = SystemClock.elapsedRealtime()
    }

    /** True when the clipboard change was most likely this app writing a clip received from the Mac. */
    fun isRecentOwnWrite(windowMs: Long = 1500) = SystemClock.elapsedRealtime() - lastOwnWriteAt < windowMs

    /** Whether [text] should go to the Mac: not empty, not what the Mac just sent, not already sent. */
    fun shouldSend(text: String?) = !text.isNullOrBlank() && text != lastOwnWrite && text != lastSent
}
