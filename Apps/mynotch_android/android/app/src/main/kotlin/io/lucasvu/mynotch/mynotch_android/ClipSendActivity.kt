package io.lucasvu.mynotch.mynotch_android

import android.app.Activity
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.widget.Toast

/**
 * Invisible activity that sends text to the Mac and closes: from the text selection menu, the share sheet,
 * or the Quick Settings tile. The tile case reads the clipboard, which Android only allows once the window has focus.
 */
class ClipSendActivity : Activity() {
    companion object {
        const val ACTION_SEND_CLIPBOARD = "io.lucasvu.mynotch.action.SEND_CLIPBOARD"
        /** Started by the copy watcher: the clip is sent only if new and not marked sensitive, without a toast. */
        const val EXTRA_AUTO = "auto"
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (intent?.action == Intent.ACTION_SEND) {
            val streamUri = intent.getParcelableExtra<android.net.Uri>(Intent.EXTRA_STREAM)
            if (streamUri != null) {
                if (SyncStore.credentials(this) == null) {
                    Toast.makeText(applicationContext, "Chưa ghép đôi với Mac", Toast.LENGTH_SHORT).show()
                    finish()
                    return
                }
                Toast.makeText(applicationContext, "Đang gửi sang Mac...", Toast.LENGTH_SHORT).show()
                ClipSender.sendFile(applicationContext, streamUri, intent.type ?: "application/octet-stream") { _, msg ->
                    runOnUiThread {
                        Toast.makeText(applicationContext, msg, Toast.LENGTH_SHORT).show()
                        finish()
                    }
                }
                return
            }
        }

        if (intent?.action == Intent.ACTION_SEND_MULTIPLE) {
            val streamUris = intent.getParcelableArrayListExtra<android.net.Uri>(Intent.EXTRA_STREAM)
            if (!streamUris.isNullOrEmpty()) {
                if (SyncStore.credentials(this) == null) {
                    Toast.makeText(applicationContext, "Chưa ghép đôi với Mac", Toast.LENGTH_SHORT).show()
                    finish()
                    return
                }
                Toast.makeText(applicationContext, "Đang gửi ${streamUris.size} tệp sang Mac...", Toast.LENGTH_SHORT).show()
                ClipSender.sendMultipleFiles(applicationContext, streamUris, intent.type ?: "application/octet-stream") { _, msg ->
                    runOnUiThread {
                        Toast.makeText(applicationContext, msg, Toast.LENGTH_SHORT).show()
                        finish()
                    }
                }
                return
            }
        }

        val text = when (intent?.action) {
            Intent.ACTION_PROCESS_TEXT -> intent.getCharSequenceExtra(Intent.EXTRA_PROCESS_TEXT)?.toString()
            Intent.ACTION_SEND -> intent.getStringExtra(Intent.EXTRA_TEXT)
            ACTION_SEND_CLIPBOARD -> return // Sent from onWindowFocusChanged.
            else -> null
        }
        sendAndFinish(text)
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus && intent?.action == ACTION_SEND_CLIPBOARD && !isFinishing) {
            val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
            val auto = intent.getBooleanExtra(EXTRA_AUTO, false)
            val clip = clipboard.primaryClip

            // If manual send and clipboard contains URI (file or image), send actual binary file
            if (!auto && clip != null && clip.itemCount > 0) {
                val item = clip.getItemAt(0)
                val uri = item.uri
                if (uri != null && (uri.scheme == "content" || uri.scheme == "file")) {
                    val mime = clip.description?.getMimeType(0) ?: "application/octet-stream"
                    ClipSender.sendFile(applicationContext, uri, mime) { _, msg ->
                        runOnUiThread {
                            Toast.makeText(applicationContext, msg, Toast.LENGTH_SHORT).show()
                            finish()
                        }
                    }
                    return
                }
            }

            sendAndFinish(SyncStore.clipText(this, clipboard.primaryClip, skipSensitive = auto))
        }
    }

    private fun sendAndFinish(text: String?) {
        if (intent?.getBooleanExtra(EXTRA_AUTO, false) == true) {
            if (SyncStore.shouldSend(text)) ClipSender.send(applicationContext, text!!)
            finish()
            return
        }
        val message = when {
            text.isNullOrBlank() -> "Không có nội dung để gửi"
            SyncStore.credentials(this) == null -> "Chưa ghép đôi với Mac"
            else -> {
                ClipSender.send(applicationContext, text)
                "Đã gửi sang Mac"
            }
        }
        Toast.makeText(applicationContext, message, Toast.LENGTH_SHORT).show()
        finish()
    }
}
