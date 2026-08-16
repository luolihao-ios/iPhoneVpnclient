package com.example.forge_vpn_flutter

import android.util.Log
import io.nekohasekai.libbox.CommandServer
import io.nekohasekai.libbox.CommandServerHandler
import io.nekohasekai.libbox.Libbox
import io.nekohasekai.libbox.OverrideOptions
import io.nekohasekai.libbox.PlatformInterface
import io.nekohasekai.libbox.SetupOptions
import io.nekohasekai.libbox.SystemProxyStatus
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URLEncoder
import java.net.URL

/** Owns the libbox command server and translates its callbacks to the app bridge. */
class LibboxServiceController(
    private val platform: LibboxPlatformInterface,
    private val packageName: String,
    private val onStopped: () -> Unit,
) : CommandServerHandler {

    private var commandServer: CommandServer? = null
    private var started = false

    @Synchronized
    fun start(configJson: String) {
        if (commandServer != null) {
            close()
        }

        Libbox.touch()
        setupLibbox()
        val server = CommandServer(this, platform)
        server.start()
        commandServer = server

        val override = OverrideOptions().apply {
            setExcludePackage(LibboxPlatformInterface.StringArray(listOf(packageName).iterator()))
        }
        server.startOrReloadService(configJson, override)
        started = true
    }

    @Synchronized
    fun close() {
        val server = commandServer
        commandServer = null
        if (server != null) {
            runCatching { server.closeService() }
                .onFailure { Log.w(TAG, "failed to close libbox service", it) }
            runCatching { server.close() }
                .onFailure { Log.w(TAG, "failed to close libbox command server", it) }
        }
        platform.closeTun()
        started = false
    }

    fun diagnosticSnapshot(): Map<String, Any> = mapOf(
        "commandServerReady" to (commandServer != null),
        "serviceStarted" to started,
        "tunEstablished" to platform.hasTun(),
    )

    /**
     * Ask sing-box's in-process Clash API to URL-test one outbound. The API
     * invokes the candidate protocol itself; a reachable TCP port alone never
     * becomes an available Forge VPN node.
     */
    fun checkNodeHealth(outboundTag: String, timeoutMs: Int): Map<String, Any> {
        if (!started || commandServer == null) {
            return healthFailure("VPN core is not running")
        }
        val timeout = timeoutMs.coerceIn(1, 3000)
        return try {
            val encodedTag = URLEncoder.encode(outboundTag, Charsets.UTF_8.name())
            val encodedUrl = URLEncoder.encode(
                "http://www.gstatic.com/generate_204",
                Charsets.UTF_8.name(),
            )
            val url = URL(
                "http://127.0.0.1:9090/proxies/$encodedTag/delay?url=$encodedUrl&timeout=$timeout",
            )
            val connection = (url.openConnection() as HttpURLConnection).apply {
                connectTimeout = timeout
                readTimeout = timeout
                requestMethod = "GET"
            }
            try {
                val code = connection.responseCode
                val body = if (code == HttpURLConnection.HTTP_OK) {
                    connection.inputStream.bufferedReader().use { it.readText() }
                } else {
                    connection.errorStream?.bufferedReader()?.use { it.readText() }.orEmpty()
                }
                val delay = runCatching { JSONObject(body).optInt("delay", -1) }.getOrDefault(-1)
                if (code == HttpURLConnection.HTTP_OK && delay >= 0) {
                    VpnBridge.sendLog(platformService(), "[health] outbound=$outboundTag HTTP 204 latency=${delay}ms")
                    mapOf("ok" to true, "latency" to delay, "target" to "HTTP 204")
                } else {
                    healthFailure("core URLTest failed (HTTP $code)")
                }
            } finally {
                connection.disconnect()
            }
        } catch (error: Throwable) {
            Log.w(TAG, "node health check failed", error)
            healthFailure(error.message ?: "core URLTest failed")
        }
    }

    /** Select one member of the `proxy` selector in the running core. */
    fun selectOutbound(outboundTag: String): Map<String, Any> {
        if (!started || commandServer == null) {
            return mapOf("ok" to false, "error" to "VPN core is not running")
        }
        return try {
            val url = URL("http://127.0.0.1:9090/proxies/proxy")
            val connection = (url.openConnection() as HttpURLConnection).apply {
                connectTimeout = 3000
                readTimeout = 3000
                requestMethod = "PUT"
                doOutput = true
                setRequestProperty("Content-Type", "application/json")
            }
            try {
                connection.outputStream.bufferedWriter().use {
                    it.write(JSONObject(mapOf("name" to outboundTag)).toString())
                }
                val code = connection.responseCode
                if (code == HttpURLConnection.HTTP_NO_CONTENT || code == HttpURLConnection.HTTP_OK) {
                    VpnBridge.sendLog(platformService(), "[selector] selected outbound=$outboundTag")
                    mapOf("ok" to true)
                } else {
                    mapOf("ok" to false, "error" to "selector API returned HTTP $code")
                }
            } finally {
                connection.disconnect()
            }
        } catch (error: Throwable) {
            Log.w(TAG, "failed to select outbound", error)
            mapOf("ok" to false, "error" to (error.message ?: "selector API failed"))
        }
    }

    private fun healthFailure(error: String): Map<String, Any> = mapOf(
        "ok" to false,
        "target" to "HTTP 204",
        "error" to error,
    )

    private fun setupLibbox() {
        val context = platform.context()
        val baseDir = context.filesDir.apply { mkdirs() }
        val workingDir = (context.getExternalFilesDir(null) ?: context.filesDir).apply { mkdirs() }
        val tempDir = context.cacheDir.apply { mkdirs() }
        val options = SetupOptions().apply {
            setBasePath(baseDir.path)
            setWorkingPath(workingDir.path)
            setTempPath(tempDir.path)
            setFixAndroidStack(true)
            // The command server is used in-process by this app. Use a loopback
            // TCP listener so libbox does not try to create command.sock in a
            // read-only working directory on some Android emulator images.
            setCommandServerListenPort(COMMAND_SERVER_PORT)
            setLogMaxLines(3000)
            setDebug(true)
        }
        Libbox.setup(options)
    }

    override fun getSystemProxyStatus(): SystemProxyStatus = SystemProxyStatus().apply {
        setAvailable(false)
        setEnabled(false)
    }

    override fun serviceReload() {
        VpnBridge.sendLog(platformService(), "[libbox] service reload requested")
    }

    override fun serviceStop() {
        onStopped()
    }

    override fun setSystemProxyEnabled(isEnabled: Boolean) = Unit

    override fun writeDebugMessage(message: String?) {
        val line = message.orEmpty()
        Log.d(TAG, line)
        VpnBridge.sendLog(platformService(), line)
    }

    private fun platformService(): android.content.Context = platform.context()

    companion object {
        private const val TAG = "ForgeLibbox"
        private const val COMMAND_SERVER_PORT = 35123
    }
}
