package io.lucasvu.mynotch.mynotch_android

import android.app.PendingIntent
import android.content.Intent
import android.os.Build
import android.service.quicksettings.TileService

/** Quick Settings tile: one tap sends the current clipboard to the Mac. */
class ClipTileService : TileService() {
    override fun onClick() {
        super.onClick()
        val intent = Intent(this, ClipSendActivity::class.java)
            .setAction(ClipSendActivity.ACTION_SEND_CLIPBOARD)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startActivityAndCollapse(PendingIntent.getActivity(this, 0, intent, PendingIntent.FLAG_IMMUTABLE))
        } else {
            @Suppress("DEPRECATION")
            startActivityAndCollapse(intent)
        }
    }
}
