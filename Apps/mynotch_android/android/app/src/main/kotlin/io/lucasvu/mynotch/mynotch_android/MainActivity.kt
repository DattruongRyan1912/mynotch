package io.lucasvu.mynotch.mynotch_android

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    /** A `mynotch://pair?...` link opened in a debug build, waiting for Flutter to pick it up. */
    private var pendingPairUri: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        takePairLink(intent)
        if (SyncStore.isWatchEnabled(this) && !ClipWatchService.isRunning) ClipWatchService.start(this)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        takePairLink(intent)
    }

    // Pairing by link skips the QR scan on an emulator. Debug builds only: in a release build any app could re-pair us.
    private fun takePairLink(intent: Intent?) {
        val debuggable = applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0
        if (debuggable && intent?.action == Intent.ACTION_VIEW && intent.data?.scheme == "mynotch") {
            pendingPairUri = intent.dataString
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
                        )
                    })
                    if (channelId == null) setWatch(false)
                    result.success(null)
                }
                "writeClipboard" -> {
                    val text = call.argument<String>("text")!!
                    SyncStore.recordOwnWrite(text)
                    (getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager)
                        .setPrimaryClip(ClipData.newPlainText("MyNotch", text))
                    result.success(null)
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
