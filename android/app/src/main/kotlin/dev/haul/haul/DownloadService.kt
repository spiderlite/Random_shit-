package dev.haul.haul

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat

/**
 * Keeps the app process alive while yt-dlp works, so downloads carry on
 * when you switch back to YouTube or lock the phone. Shows one quiet,
 * self-updating notification and goes away by itself when the queue is idle.
 */
class DownloadService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val notification = build(this, lastActive, lastQueued, lastProgress, lastTitle)
        try {
            ServiceCompat.startForeground(
                this,
                ONGOING_ID,
                notification,
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC else 0,
            )
        } catch (_: Throwable) {
            stopSelf()
        }
        return START_NOT_STICKY
    }

    override fun onTimeout(startId: Int, fgsType: Int) {
        // Android 15 caps dataSync services; bow out gracefully.
        stopSelf()
    }

    companion object {
        private const val CHANNEL = "downloads"
        private const val CHANNEL_DONE = "finished"
        private const val ONGOING_ID = 1
        private const val DONE_ID = 2

        @Volatile private var running = false
        private var lastActive = 0
        private var lastQueued = 0
        private var lastProgress: Double? = null
        private var lastTitle: String? = null
        private var sessionPeak = 0

        fun update(context: Context, active: Int, queued: Int, progress: Double?, title: String?, appVisible: Boolean) {
            lastActive = active
            lastQueued = queued
            lastProgress = progress
            lastTitle = title
            ensureChannels(context)
            val nm = context.getSystemService(NotificationManager::class.java)

            if (active == 0) {
                if (running) {
                    running = false
                    context.stopService(Intent(context, DownloadService::class.java))
                    if (!appVisible && sessionPeak > 0) {
                        nm.notify(DONE_ID, done(context))
                    }
                }
                sessionPeak = 0
                return
            }

            sessionPeak = maxOf(sessionPeak, active + queued)
            if (!running) {
                try {
                    ContextCompat.startForegroundService(context, Intent(context, DownloadService::class.java))
                    running = true
                } catch (_: Throwable) {
                    // Background start not allowed right now; the next update
                    // from the foreground will try again.
                }
            } else {
                nm.notify(ONGOING_ID, build(context, active, queued, progress, title))
            }
        }

        private fun ensureChannels(context: Context) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
            val nm = context.getSystemService(NotificationManager::class.java)
            if (nm.getNotificationChannel(CHANNEL) == null) {
                nm.createNotificationChannel(
                    NotificationChannel(CHANNEL, "Downloads in progress", NotificationManager.IMPORTANCE_LOW).apply {
                        setShowBadge(false)
                    },
                )
            }
            if (nm.getNotificationChannel(CHANNEL_DONE) == null) {
                nm.createNotificationChannel(
                    NotificationChannel(CHANNEL_DONE, "Finished downloads", NotificationManager.IMPORTANCE_DEFAULT),
                )
            }
        }

        private fun openApp(context: Context): PendingIntent = PendingIntent.getActivity(
            context,
            0,
            Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )

        private fun build(context: Context, active: Int, queued: Int, progress: Double?, title: String?): Notification {
            val heading = buildString {
                append(if (active == 1) "Downloading 1 video" else "Downloading $active videos")
                if (queued > 0) append(" · $queued waiting")
            }
            return NotificationCompat.Builder(context, CHANNEL)
                .setSmallIcon(R.drawable.ic_stat_haul)
                .setContentTitle(heading)
                .setContentText(title ?: "Getting things ready…")
                .setOnlyAlertOnce(true)
                .setOngoing(true)
                .setSilent(true)
                .setCategory(NotificationCompat.CATEGORY_PROGRESS)
                .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
                .setProgress(100, ((progress ?: 0.0) * 100).toInt(), progress == null)
                .setContentIntent(openApp(context))
                .build()
        }

        private fun done(context: Context): Notification =
            NotificationCompat.Builder(context, CHANNEL_DONE)
                .setSmallIcon(R.drawable.ic_stat_haul)
                .setContentTitle("Downloads finished")
                .setContentText("Tap to see them in Haul")
                .setAutoCancel(true)
                .setContentIntent(openApp(context))
                .build()
    }
}
