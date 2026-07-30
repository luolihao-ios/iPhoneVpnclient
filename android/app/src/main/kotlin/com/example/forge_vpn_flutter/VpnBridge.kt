package com.example.forge_vpn_flutter

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.VpnService
import android.os.Build
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.nekohasekai.libbox.Libbox
import java.lang.ref.WeakReference

/** Bridges Flutter commands and native Android VPN state. */
object VpnBridge {
    private const val CHANNEL = "dev.forge.vpn/vpn_service"

    private var methodChannel: MethodChannel? = null
    private var activityReference: WeakReference<Activity>? = null
    private val state = VpnStateStore()

    fun register(flutterEngine: FlutterEngine, activity: Activity) {
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        activityReference = WeakReference(activity)
        val context = activity.applicationContext

        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "connect" -> connect(context, call.argument<String>("config"), result)
                "requestPermission" -> requestPermission(result)
                "disconnect" -> disconnect(context, result)
                "isRunning" -> result.success(state.isRunning())
                "getState" -> result.success(state.snapshot())
                "diagnose" -> diagnose(context, result)
                else -> result.notImplemented()
            }
        }
    }

    private fun connect(context: Context, configJson: String?, result: MethodChannel.Result) {
        if (configJson.isNullOrEmpty()) {
            result.error("INVALID_CONFIG", "Config JSON is empty", null)
            return
        }
        transition(VpnRuntimeState.CONNECTING, "Starting VPN service")
        val intent = Intent(context, ForgeVpnService::class.java).apply {
            action = ForgeVpnService.ACTION_CONNECT
            putExtra(ForgeVpnService.CONFIG_EXTRA, configJson)
        }
        startForegroundService(context, intent)
        result.success(true)
    }

    private fun disconnect(context: Context, result: MethodChannel.Result) {
        transition(VpnRuntimeState.DISCONNECTING, "Stopping VPN service")
        val intent = Intent(context, ForgeVpnService::class.java).apply {
            action = ForgeVpnService.ACTION_DISCONNECT
        }
        context.startService(intent)
        result.success(true)
    }

    private fun diagnose(context: Context, result: MethodChannel.Result) {
        val abi = Build.SUPPORTED_ABIS.firstOrNull() ?: "unknown"
        val assetPath = ForgeVpnService.assetPathForAbi(abi) ?: "unknown"
        val assetDirectory = "flutter_assets/assets/binaries"
        val availableAssets = context.assets.list(assetDirectory)?.toList() ?: emptyList()
        val assetAvailable = assetPath != "unknown" &&
            context.assets.list(assetDirectory)?.contains(assetPath.substringAfterLast('/')) == true
        result.success(
            mapOf(
                "platform" to "android",
                "abi" to abi,
                "assetPath" to assetPath,
                "assetAvailable" to assetAvailable,
                "availableAssets" to availableAssets,
                "libboxVersion" to runCatching { Libbox.version() }.getOrNull(),
                "installedBinary" to false,
                "permissionGranted" to (state.snapshot()["permissionGranted"] ?: false),
                "status" to (state.snapshot()["status"] ?: "idle")
            )
        )
    }

    private fun requestPermission(result: MethodChannel.Result) {
        val activity = activityReference?.get()
        if (activity == null) {
            reportError("VPN permission requires an active Android activity")
            result.error("NO_ACTIVITY", "VPN permission requires an active Android activity", null)
            return
        }
        if (state.snapshot()["status"] == VpnRuntimeState.PERMISSION_PENDING.wireValue) {
            result.success(true)
            return
        }

        transition(VpnRuntimeState.PERMISSION_PENDING, "Waiting for VPN permission")
        val permissionIntent = VpnService.prepare(activity)
        if (permissionIntent == null) {
            onPermissionResult(true)
        } else {
            activity.startActivityForResult(permissionIntent, MainActivity.VPN_REQUEST_CODE)
        }
        result.success(true)
    }

    fun onPermissionResult(granted: Boolean) {
        state.setPermissionGranted(granted)
        if (granted) {
            transition(VpnRuntimeState.READY, "VPN permission granted")
            emitStatus("permission_granted", "")
        } else {
            state.update(VpnRuntimeState.IDLE, "VPN permission denied")
            emitStatus("permission_denied", "")
        }
    }

    fun reportConnected(message: String = "") = transition(VpnRuntimeState.CONNECTED, message)

    fun reportDisconnected(message: String = "") {
        state.update(VpnRuntimeState.IDLE, message)
        emitStatus("disconnected", message)
    }

    fun reportError(message: String) = transition(VpnRuntimeState.ERROR, message)

    fun sendLog(context: Context, line: String) {
        context.runOnUiThread { methodChannel?.invokeMethod("onLog", line) }
    }

    private fun transition(nextState: VpnRuntimeState, message: String) {
        state.update(nextState, message)
        emitStatus(nextState.wireValue, message)
    }

    private fun emitStatus(status: String, message: String) {
        android.os.Handler(android.os.Looper.getMainLooper()).post {
            methodChannel?.invokeMethod("onStatus", mapOf("status" to status, "message" to message))
        }
    }

    private fun startForegroundService(context: Context, intent: Intent) {
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
            context.startForegroundService(intent)
        } else {
            context.startService(intent)
        }
    }

    private fun Context.runOnUiThread(action: () -> Unit) {
        android.os.Handler(android.os.Looper.getMainLooper()).post(action)
    }
}
