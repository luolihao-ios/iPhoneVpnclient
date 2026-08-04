package com.example.forge_vpn_flutter

enum class VpnRuntimeState(val wireValue: String) {
    IDLE("idle"),
    PERMISSION_PENDING("permission_pending"),
    READY("ready"),
    CONNECTING("connecting"),
    CONNECTED("connected"),
    DISCONNECTING("disconnecting"),
    ERROR("error")
}

class VpnStateStore {
    @Volatile private var state = VpnRuntimeState.IDLE
    @Volatile private var message = ""
    @Volatile private var permissionGranted = false

    fun update(nextState: VpnRuntimeState, nextMessage: String = "") {
        state = nextState
        message = nextMessage
    }

    fun setPermissionGranted(granted: Boolean) {
        permissionGranted = granted
    }

    fun reset(reason: String = "") {
        state = VpnRuntimeState.IDLE
        message = reason
    }

    fun isRunning(): Boolean = state == VpnRuntimeState.CONNECTED

    fun snapshot(): Map<String, Any> = mapOf(
        "status" to state.wireValue,
        "message" to message,
        "permissionGranted" to permissionGranted
    )
}
