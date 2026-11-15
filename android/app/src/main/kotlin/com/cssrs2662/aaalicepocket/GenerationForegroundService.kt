package com.cssrs2662.aaalicepocket

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.os.PowerManager

class GenerationForegroundService : Service() {
    data class Progress(val current: Int, val total: Int, val percent: Int, val queue: Boolean)

    companion object {
        private const val channelId = "image_generation"
        private const val notificationId = 4101
        private var running: GenerationForegroundService? = null
        private var progress: Progress? = null

        fun updateProgress(next: Progress?) {
            val firstProgress = progress == null && next != null
            progress = next
            running?.refreshNotification(firstProgress)
        }

        fun clearProgress() {
            progress = null
        }
    }

    private var wakeLock: PowerManager.WakeLock? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startForeground(notificationId, buildNotification())
        running = this
        acquireWakeLock()
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        if (running === this) running = null
        wakeLock?.takeIf { it.isHeld }?.release()
        wakeLock = null
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    // Android 15 limits dataSync services to about six hours a day; a service
    // still running when the limit is reached must stop, or the app crashes.
    override fun onTimeout(startId: Int, fgsType: Int) {
        stopSelf()
    }

    private fun acquireWakeLock() {
        if (wakeLock?.isHeld == true) return
        val powerManager = getSystemService(POWER_SERVICE) as PowerManager
        wakeLock = powerManager.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "$packageName:image_generation",
        ).apply {
            setReferenceCounted(false)
            acquire()
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java)
        val channel = NotificationChannel(
            channelId,
            getString(R.string.generation_notification_channel),
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = getString(R.string.generation_notification_channel_description)
            setShowBadge(false)
        }
        manager.createNotificationChannel(channel)
    }

    private fun buildNotification(): Notification {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        val contentIntent = launchIntent?.let {
            PendingIntent.getActivity(
                this,
                0,
                it.addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, channelId)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        builder
            .setSmallIcon(R.drawable.ic_generation_notification)
            .setContentTitle(getString(R.string.generation_notification_title))
            .setContentText(getString(R.string.generation_notification_text))
            .setContentIntent(contentIntent)
            .setCategory(Notification.CATEGORY_PROGRESS)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
        progress?.let { value ->
            val title = if (value.queue) R.string.generation_queue_notification_title
                else R.string.generation_batch_notification_title
            val text = if (value.queue) R.string.generation_queue_notification_progress
                else R.string.generation_batch_notification_progress
            builder.setContentTitle(getString(title))
                .setContentText(getString(text, value.current, value.total, value.percent))
                .setProgress(100, value.percent, false)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                builder.setForegroundServiceBehavior(Notification.FOREGROUND_SERVICE_IMMEDIATE)
            }
        }
        return builder.build()
    }

    private fun refreshNotification(firstProgress: Boolean) {
        val notification = buildNotification()
        if (firstProgress) {
            startForeground(notificationId, notification)
        } else {
            getSystemService(NotificationManager::class.java).notify(notificationId, notification)
        }
    }
}
