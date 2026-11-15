package io.lucasvu.mynotch.mynotch_android

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.os.Bundle
import android.provider.OpenableColumns
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    /** A `mynotch://pair?...` link opened in a debug build, waiting for Flutter to pick it up. */
    private var pendingPairUri: String? = null
    private val ioExecutor = java.util.concurrent.Executors.newSingleThreadExecutor()
    private val mainHandler = android.os.Handler(android.os.Looper.getMainLooper())

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleIntentActions(intent)
        if (SyncStore.isWatchEnabled(this) && !ClipWatchService.isRunning) ClipWatchService.start(this)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleIntentActions(intent)
    }

    // Handles pairing links and debug URI permission grants for testing.
    private fun handleIntentActions(intent: Intent?) {
        if (intent == null) return
        val debuggable = applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0
        if (debuggable && intent.action == Intent.ACTION_VIEW && intent.data?.scheme == "mynotch") {
            pendingPairUri = intent.dataString
        }
        if (debuggable && intent.action == "io.lucasvu.mynotch.ACTION_GRANT_URI_PERMISSION") {
            val targetPkg = intent.getStringExtra("target_package") ?: "com.android.shell"
            val uriStr = intent.getStringExtra("uri")
            if (uriStr != null) {
                grantUriPermission(targetPkg, android.net.Uri.parse(uriStr), Intent.FLAG_GRANT_READ_URI_PERMISSION)
                android.util.Log.i("MainActivity", "Granted URI read permission to $targetPkg for $uriStr")
            }
        }
        if (debuggable && intent.action == "io.lucasvu.mynotch.ACTION_REVOKE_URI_PERMISSION") {
            val uriStr = intent.getStringExtra("uri")
            if (uriStr != null) {
                revokeUriPermission(android.net.Uri.parse(uriStr), Intent.FLAG_GRANT_READ_URI_PERMISSION)
                android.util.Log.i("MainActivity", "Revoked URI read permission for $uriStr")
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "mynotch/native").setMethodCallHandler { call, result ->
            when (call.method) {
                "setCredentials" -> {
                    val channelId = call.argument<String>("channelId")
                    SyncStore.setCredentials(this, channelId?.let {
                        SyncCredentials(
                            it,
                            call.argument<String>("authToken")!!,
                            call.argument<String>("aesKeyBase64")!!,
                            call.argument<String>("relayServerUrl")!!,
                            call.argument<String>("sessionId"),
                        )
                    })
                    if (channelId == null) setWatch(false)
                    result.success(null)
                }
                "setSessionId" -> {
                    val sessionId = call.argument<String>("sessionId")
                    SyncStore.setSessionId(this, sessionId)
                    result.success(null)
                }
                "writeClipboard" -> {
                    val text = call.argument<String>("text")!!
                    SyncStore.recordOwnWrite(text)
                    (getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager)
                        .setPrimaryClip(ClipData.newPlainText("MyNotch", text))
                    result.success(null)
                }
                "saveAndCopyFile" -> {
                    val transferId = call.argument<String>("transferId")!!
                    val fileName = call.argument<String>("fileName")!!
                    val mimeType = call.argument<String>("mimeType")!!
                    val base64 = call.argument<String>("base64")!!
                    val path = ClipTransfer.saveAndCopyFile(this, transferId, fileName, mimeType, base64)
                    result.success(path)
                }
                "writeImageClipboard" -> {
                    val fileName = call.argument<String>("fileName") ?: "image.png"
                    val base64 = call.argument<String>("base64")!!
                    val path = ClipTransfer.writeImageClipboard(this, fileName, base64)
                    result.success(path)
                }
                "openFile" -> {
                    val path = call.argument<String>("path")
                    if (path != null) {
                        val file = File(path)
                        if (file.exists()) {
                            val uri = FileProvider.getUriForFile(this, "io.lucasvu.mynotch.mynotch_android.syncfiles", file)
                            val intent = Intent(Intent.ACTION_VIEW).apply {
                                setDataAndType(uri, contentResolver.getType(uri) ?: "*/*")
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            startActivity(Intent.createChooser(intent, "Mở tệp").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                            result.success(true)
                        } else {
                            result.error("NOT_FOUND", "Tệp tin không tồn tại", null)
                        }
                    } else {
                        result.error("INVALID_ARG", "Đường dẫn không hợp lệ", null)
                    }
                }
                "getClipboardUri" -> {
                    val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                    val clip = clipboard.primaryClip
                    if (clip != null && clip.itemCount > 0) {
                        val uri = clip.getItemAt(0).uri
                        if (uri != null && (uri.scheme == "content" || uri.scheme == "file")) {
                            val mime = clip.description?.getMimeType(0) ?: "application/octet-stream"
                            result.success(mapOf("uri" to uri.toString(), "mimeType" to mime))
                        } else {
                            result.success(null)
                        }
                    } else {
                        result.success(null)
                    }
                }
                "readClipboardUriData" -> {
                    val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                    val clip = clipboard.primaryClip
                    val uri = if (clip != null && clip.itemCount > 0) clip.getItemAt(0).uri else null
                    if (uri != null && (uri.scheme == "content" || uri.scheme == "file")) {
                        val clipMime = clip?.description?.getMimeType(0)
                        ioExecutor.execute {
                            try {
                                var fileName = "file.bin"
                                var declaredSize: Long = -1
                                contentResolver.query(uri, null, null, null, null)?.use { cursor ->
                                    val nameIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                                    if (cursor.moveToFirst() && nameIndex != -1) {
                                        fileName = cursor.getString(nameIndex) ?: "file.bin"
                                    }
                                    val sizeIndex = cursor.getColumnIndex(OpenableColumns.SIZE)
                                    if (cursor.moveToFirst() && sizeIndex != -1) {
                                        declaredSize = cursor.getLong(sizeIndex)
                                    }
                                }
                                val maxLimit = 15L * 1024 * 1024
                                if (declaredSize > maxLimit) {
                                    mainHandler.post {
                                        result.error("SIZE_LIMIT", "Dung lượng tệp ($declaredSize bytes) vượt quá 15 MiB", null)
                                    }
                                    return@execute
                                }

                                val mime = contentResolver.getType(uri) ?: clipMime ?: "application/octet-stream"
                                val inputStream = contentResolver.openInputStream(uri)
                                if (inputStream != null) {
                                    val outputStream = java.io.ByteArrayOutputStream()
                                    val buffer = ByteArray(8192)
                                    var totalRead = 0L
                                    var read: Int
                                    var exceeded = false
                                    inputStream.use { stream ->
                                        while (stream.read(buffer).also { read = it } != -1) {
                                            totalRead += read
                                            if (totalRead > maxLimit) {
                                                exceeded = true
                                                break
                                            }
                                            outputStream.write(buffer, 0, read)
                                        }
                                    }

                                    if (exceeded) {
                                        mainHandler.post {
                                            result.error("SIZE_LIMIT", "Dung lượng tệp vượt quá 15 MiB", null)
                                        }
                                    } else {
                                        val bytes = outputStream.toByteArray()
                                        mainHandler.post {
                                            result.success(mapOf(
                                                "fileName" to fileName,
                                                "mimeType" to mime,
                                                "bytes" to bytes
                                            ))
                                        }
                                    }
                                } else {
                                    mainHandler.post { result.success(null) }
                                }
                            } catch (e: Exception) {
                                mainHandler.post {
                                    result.error("READ_ERROR", "Lỗi đọc tệp URI: ${e.message}", null)
                                }
                            }
                        }
                    } else {
                        result.success(null)
                    }
                }
                "watchStatus" -> result.success(watchStatus())
                "setWatch" -> {
                    setWatch(call.argument<Boolean>("enabled") == true)
                    result.success(watchStatus())
                }
                "takePairUri" -> {
                    result.success(pendingPairUri)
                    pendingPairUri = null
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun setWatch(enabled: Boolean) {
        SyncStore.setWatchEnabled(this, enabled)
        if (enabled) ClipWatchService.start(this) else ClipWatchService.stop(this)
    }

    private fun watchStatus() = mapOf(
        "enabled" to SyncStore.isWatchEnabled(this),
        "running" to ClipWatchService.isRunning,
        "readLogs" to ClipWatchService.canReadLogs(this),
        "overlay" to ClipWatchService.canDrawOverlays(this),
        "packageName" to packageName,
    )
}
