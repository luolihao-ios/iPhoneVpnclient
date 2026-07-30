package com.example.forge_vpn_flutter

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.core.app.NotificationCompat
import java.util.concurrent.atomic.AtomicBoolean

/** Foreground Android service that owns the libbox VPN lifecycle. */
class ForgeVpnService : VpnService() {

    private val running = AtomicBoolean(false)
    private var platform: LibboxPlatformInterface? = null
    private var controller: LibboxServiceController? = null

    companion object {
        const val ACTION_CONNECT = "com.example.forge_vpn_flutter.CONNECT"
        const val ACTION_DISCONNECT = "com.example.forge_vpn_flutter.DISCONNECT"
        const val ACTION_RESTART = "com.example.forge_vpn_flutter.RESTART"
        const val CONFIG_EXTRA = "config_json"
        const val BINARY_NAME = "sing-box"

        private const val NOTIFICATION_ID = 1001
        private const val CHANNEL_ID = "forge_vpn_channel"

        fun assetPathForAbi(abi: String): String? {
            val binaryAbi = when (abi) {
                "arm64-v8a" -> "arm64"
                "armeabi-v7a" -> "armv7"
                "x86_64" -> "amd64"
                "x86" -> "386"
                else -> return null
            }
            return "flutter_assets/assets/binaries/sing-box-android-$binaryAbi"
        }
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_CONNECT -> intent.getStringExtra(CONFIG_EXTRA)?.let(::connect)
            ACTION_DISCONNECT -> disconnect()
            ACTION_RESTART -> {
                disconnect(reportStatus = false)
                intent.getStringExtra(CONFIG_EXTRA)?.let(::connect)
            }
        }
        return START_NOT_STICKY
    }

    override fun onRevoke() {
        disconnect(reportStatus = true, message = "VPN permission revoked")
        super.onRevoke()
    }

    override fun onDestroy() {
        disconnect(reportStatus = false)
        super.onDestroy()
    }

    private fun connect(configJson: String) {
        if (controller != null) {
            disconnect(reportStatus = false)
        }

        try {
            startForeground(NOTIFICATION_ID, buildNotification())
        } catch (error: Exception) {
            VpnBridge.reportError(error.message ?: "Unable to start foreground VPN service")
            return
        }

        val platformAdapter = LibboxPlatformInterface(this)
        val serviceController = LibboxServiceController(
            platform = platformAdapter,
            packageName = packageName,
            onStopped = { disconnect(reportStatus = true, message = "libbox stopped") },
        )
        platform = platformAdapter
        controller = serviceController

        Thread {
            try {
                serviceController.start(configJson)
                running.set(true)
                VpnBridge.reportConnected("libbox service started")
            } catch (error: Throwable) {
                running.set(false)
                VpnBridge.reportError(error.message ?: "Failed to start libbox")
                serviceController.close()
                clearController(serviceController)
                stopForegroundSafely()
            }
        }.apply {
            name = "forge-libbox-start"
            isDaemon = true
            start()
        }
    }

    private fun disconnect(
        reportStatus: Boolean = true,
        message: String = "User stopped",
    ) {
        running.set(false)
        val currentController = controller
        controller = null
        platform = null
        currentController?.close()
        stopForegroundSafely()
        if (reportStatus) {
            VpnBridge.reportDisconnected(message)
        }
    }

    private fun clearController(expected: LibboxServiceController) {
        Handler(Looper.getMainLooper()).post {
            if (controller === expected) {
                controller = null
                platform = null
            }
        }
    }

    private fun stopForegroundSafely() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
    }

    private fun buildNotification(): Notification {
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Forge VPN")
            .setContentText("Connected – securing your traffic")
            .setSmallIcon(android.R.drawable.ic_lock_lock)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setSilent(true)
            .build()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Forge VPN Service",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "VPN connection status"
                setShowBadge(false)
            }
            getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }
    }
}
