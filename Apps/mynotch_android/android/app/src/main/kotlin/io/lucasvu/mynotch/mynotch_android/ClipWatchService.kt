package io.lucasvu.mynotch.mynotch_android

import android.Manifest
import android.annotation.TargetApi
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.graphics.PixelFormat
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.provider.Settings
import android.util.Log
import android.view.View
import android.view.WindowManager

/**
 * Sends every copy made on the phone to the Mac.
 *
 * Android 10+ hides the clipboard from background apps, but still logs each clipboard change it refuses to
 * report to this app's listener ("Denying clipboard access to <package>"). With READ_LOGS (granted once over adb)
 * that line is the copy signal; the clipboard is then read through a 1-pixel focusable overlay, since an app may
 * read it while one of its windows has focus (needs "display over other apps").
 */
class ClipWatchService : Service() {
    companion object {
        private const val TAG = "MyNotchSync"
        private const val CHANNEL_ID = "clip_watch"
        private const val NOTIFICATION_ID = 1

        fun canReadLogs(context: Context) =
            context.checkSelfPermission(Manifest.permission.READ_LOGS) == PackageManager.PERMISSION_GRANTED

        fun canDrawOverlays(context: Context) = Settings.canDrawOverlays(context)

        @Volatile var isRunning = false
            private set

        fun start(context: Context) {
            val intent = Intent(context, ClipWatchService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) context.startForegroundService(intent) else context.startService(intent)
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, ClipWatchService::class.java))
        }
    }

    private val main = Handler(Looper.getMainLooper())
    private lateinit var clipboard: ClipboardManager
    private var logcat: Process? = null
    private var overlay: View? = null

    // From Android 10 this is only registered so that Android logs a refusal on each copy: it is not called in the background.
    private val clipListener = ClipboardManager.OnPrimaryClipChangedListener {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q && !SyncStore.isRecentOwnWrite()) sendIfNew(readClip())
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        startInForeground()
        clipboard.addPrimaryClipChangedListener(clipListener)
        watchLog()
        isRunning = true
        Log.i(TAG, "Clipboard watcher started (readLogs=${canReadLogs(this)}, overlay=${canDrawOverlays(this)})")
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int) = START_STICKY

    override fun onDestroy() {
        isRunning = false
        clipboard.removePrimaryClipChangedListener(clipListener)
        logcat?.destroy()
        removeOverlay()
        super.onDestroy()
    }

    private fun startInForeground() {
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            getSystemService(NotificationManager::class.java).createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "Tự gửi clipboard", NotificationManager.IMPORTANCE_MIN)
            )
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        val notification = builder
            .setSmallIcon(R.drawable.ic_tile_send)
            .setContentTitle("Đang tự gửi clipboard sang Mac")
            .setOngoing(true)
            .build()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun watchLog() {
        val marker = "Denying clipboard access to $packageName"
        val nowMs = System.currentTimeMillis()
        // Start from now, so refusals logged before the service started are not taken for new copies.
        val since = "%d.%03d".format(nowMs / 1000, nowMs % 1000)
        Thread({
            try {
                val process = ProcessBuilder("logcat", "-b", "system", "-v", "brief", "-T", since, "ClipboardService:E", "*:S")
                    .redirectErrorStream(true).start()
                logcat = process
                process.inputStream.bufferedReader().forEachLine { line ->
                    if (line.contains(marker)) {
                        Log.d(TAG, "Copy seen in log")
                        main.post { onClipboardChanged() }
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "Reading logcat failed", e)
            }
        }, "clip-logcat").apply { isDaemon = true }.start()
    }

    private fun readClip() = SyncStore.clipText(this, clipboard.primaryClip, skipSensitive = true)

    private fun sendIfNew(text: String?) {
        if (SyncStore.shouldSend(text)) ClipSender.send(applicationContext, text!!)
    }

    private fun onClipboardChanged() {
        // Our own write of a clip from the Mac also triggers a refusal; it must not be echoed back.
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q || SyncStore.isRecentOwnWrite() || overlay != null) return
        if (!canDrawOverlays(this)) {
            Log.w(TAG, "Copy seen but overlay permission is missing, clip not read")
            return
        }
        readThroughOverlay()
    }

    @TargetApi(Build.VERSION_CODES.Q)
    private fun readThroughOverlay() {
        val windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        val view = object : View(this) {
            override fun onWindowFocusChanged(hasWindowFocus: Boolean) {
                super.onWindowFocusChanged(hasWindowFocus)
                if (!hasWindowFocus) return
                val text = readClip()
                Log.d(TAG, "Overlay focused, clip read (${text?.length ?: 0} chars)")
                removeOverlay()
                sendIfNew(text)
            }
        }
        val params = WindowManager.LayoutParams(
            1, 1,
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL,
            PixelFormat.TRANSLUCENT,
        )
        try {
            windowManager.addView(view, params)
            overlay = view
            // Apps that hide overlays (Settings, Contacts editor, banking apps) keep it from ever getting focus:
            // fall back to the invisible activity, which a visible overlay window is not needed for.
            main.postDelayed({
                if (overlay === view) {
                    removeOverlay()
                    readThroughActivity()
                }
            }, 400)
        } catch (e: Exception) {
            Log.e(TAG, "Adding overlay failed", e)
        }
    }

    private fun readThroughActivity() {
        Log.d(TAG, "Overlay got no focus, reading through the activity")
        startActivity(
            Intent(this, ClipSendActivity::class.java)
                .setAction(ClipSendActivity.ACTION_SEND_CLIPBOARD)
                .putExtra(ClipSendActivity.EXTRA_AUTO, true)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        )
    }

    private fun removeOverlay() {
        val view = overlay ?: return
        overlay = null
        try {
            (getSystemService(Context.WINDOW_SERVICE) as WindowManager).removeView(view)
        } catch (_: Exception) {
        }
    }
}
