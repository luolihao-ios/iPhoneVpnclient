package com.example.forge_vpn_flutter

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class VpnStateStoreTest {
    @Test
    fun `android binary path points into Flutter asset bundle`() {
        assertEquals(
            "flutter_assets/assets/binaries/sing-box-android-amd64",
            ForgeVpnService.assetPathForAbi("x86_64")
        )
    }

    @Test
    fun `connected state is reported as running and retains its message`() {
        val state = VpnStateStore()

        state.update(VpnRuntimeState.CONNECTED, "Tunnel established")

        assertTrue(state.isRunning())
        assertEquals("connected", state.snapshot()["status"])
        assertEquals("Tunnel established", state.snapshot()["message"])
    }

    @Test
    fun `permission result is represented in the state snapshot`() {
        val state = VpnStateStore()

        state.setPermissionGranted(true)
        state.update(VpnRuntimeState.READY, "Permission granted")

        assertTrue(state.snapshot()["permissionGranted"] as Boolean)
        assertFalse(state.isRunning())
    }

    @Test
    fun `terminal cleanup clears a stale connected state`() {
        val state = VpnStateStore()
        state.update(VpnRuntimeState.CONNECTED, "Tunnel established")

        state.reset("Service stopped")

        assertFalse(state.isRunning())
        assertEquals("idle", state.snapshot()["status"])
        assertEquals("Service stopped", state.snapshot()["message"])
    }
}
