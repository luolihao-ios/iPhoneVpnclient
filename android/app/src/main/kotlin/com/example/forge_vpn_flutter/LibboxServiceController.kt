package com.example.forge_vpn_flutter

import android.util.Log
import io.nekohasekai.libbox.CommandServer
import io.nekohasekai.libbox.CommandServerHandler
import io.nekohasekai.libbox.Libbox
import io.nekohasekai.libbox.OverrideOptions
import io.nekohasekai.libbox.PlatformInterface
import io.nekohasekai.libbox.SetupOptions
import io.nekohasekai.libbox.SystemProxyStatus

/** Owns the libbox command server and translates its callbacks to the app bridge. */
class LibboxServiceController(
    private val platform: LibboxPlatformInterface,
    private val packageName: String,
    private val onStopped: () -> Unit,
) : CommandServerHandler {

    private var commandServer: CommandServer? = null

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
    }

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
