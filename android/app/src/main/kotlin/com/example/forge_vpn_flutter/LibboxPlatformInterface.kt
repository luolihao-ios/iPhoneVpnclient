package com.example.forge_vpn_flutter

import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.IpPrefix
import android.net.VpnService
import android.os.Build
import android.system.OsConstants
import io.nekohasekai.libbox.ConnectionOwner
import io.nekohasekai.libbox.InterfaceUpdateListener
import io.nekohasekai.libbox.Libbox
import io.nekohasekai.libbox.LocalDNSTransport
import io.nekohasekai.libbox.NetworkInterfaceIterator
import io.nekohasekai.libbox.Notification
import io.nekohasekai.libbox.PlatformInterface
import io.nekohasekai.libbox.RoutePrefix
import io.nekohasekai.libbox.RoutePrefixIterator
import io.nekohasekai.libbox.StringIterator
import io.nekohasekai.libbox.TunOptions
import io.nekohasekai.libbox.WIFIState
import java.net.InetSocketAddress
import java.net.InetAddress
import java.net.Inet6Address
import java.net.NetworkInterface as JavaNetworkInterface
import java.util.Collections

/** Android platform callbacks consumed by the libbox AAR. */
class LibboxPlatformInterface(
    private val vpnService: VpnService,
) : PlatformInterface {

    fun context(): android.content.Context = vpnService

    private var tunFileDescriptor: android.os.ParcelFileDescriptor? = null
    private var defaultInterfaceListener: InterfaceUpdateListener? = null

    override fun usePlatformAutoDetectInterfaceControl(): Boolean = true

    override fun autoDetectInterfaceControl(fd: Int) {
        if (!vpnService.protect(fd)) {
            throw IllegalStateException("android: failed to protect fd $fd")
        }
    }

    override fun openTun(options: TunOptions): Int {
        if (VpnService.prepare(vpnService) != null) {
            throw IllegalStateException("android: missing vpn permission")
        }

        val builder = vpnService.Builder()
            .setSession("Forge VPN")
            .setMtu(options.getMTU())
            .setBlocking(false)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            builder.setMetered(false)
        }

        addAddresses(builder, options.getInet4Address())
        addAddresses(builder, options.getInet6Address())

        if (options.getAutoRoute()) {
            addDns(builder, options)
            addRoutes(builder, options)
            addPackages(builder, options.getIncludePackage(), allowed = true)
            addPackages(builder, options.getExcludePackage(), allowed = false)
        }

        val pfd = builder.establish()
            ?: throw IllegalStateException("android: failed to establish TUN")
        tunFileDescriptor?.close()
        tunFileDescriptor = pfd
        return pfd.fd
    }

    fun closeTun() {
        tunFileDescriptor?.close()
        tunFileDescriptor = null
    }

    private fun addDns(builder: VpnService.Builder, options: TunOptions) {
        runCatching { options.getDNSServerAddress().getValue() }
            .getOrNull()
            ?.takeIf { it.isNotBlank() }
            ?.let { builder.addDnsServer(it) }
    }

    private fun addAddresses(builder: VpnService.Builder, iterator: RoutePrefixIterator) {
        while (iterator.hasNext()) {
            val address = iterator.next()
            builder.addAddress(address.address(), address.prefix())
        }
    }

    private fun addRoutes(builder: VpnService.Builder, options: TunOptions) {
        var addedRoute = false
        val inet4Routes = options.getInet4RouteAddress()
        while (inet4Routes.hasNext()) {
            addRoute(builder, inet4Routes.next())
            addedRoute = true
        }
        val inet6Routes = options.getInet6RouteAddress()
        while (inet6Routes.hasNext()) {
            addRoute(builder, inet6Routes.next())
            addedRoute = true
        }

        if (!addedRoute) {
            val inet4Ranges = options.getInet4RouteRange()
            while (inet4Ranges.hasNext()) {
                addRoute(builder, inet4Ranges.next())
            }
            val inet6Ranges = options.getInet6RouteRange()
            while (inet6Ranges.hasNext()) {
                addRoute(builder, inet6Ranges.next())
            }
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            addExcludedRoutes(builder, options.getInet4RouteExcludeAddress())
            addExcludedRoutes(builder, options.getInet6RouteExcludeAddress())
        }
    }

    private fun addRoute(builder: VpnService.Builder, route: RoutePrefix) {
        builder.addRoute(route.address(), route.prefix())
    }

    private fun addExcludedRoutes(builder: VpnService.Builder, iterator: RoutePrefixIterator) {
        while (iterator.hasNext()) {
            val route = iterator.next()
            builder.excludeRoute(IpPrefix(InetAddress.getByName(route.address()), route.prefix()))
        }
    }

    private fun addPackages(
        builder: VpnService.Builder,
        iterator: StringIterator,
        allowed: Boolean,
    ) {
        while (iterator.hasNext()) {
            val packageName = iterator.next()
            try {
                if (allowed) {
                    builder.addAllowedApplication(packageName)
                } else {
                    builder.addDisallowedApplication(packageName)
                }
            } catch (_: PackageManager.NameNotFoundException) {
                VpnBridge.sendLog(vpnService, "[libbox] package not found: $packageName")
            }
        }
    }

    override fun clearDNSCache() = Unit

    override fun closeDefaultInterfaceMonitor(listener: InterfaceUpdateListener) {
        if (defaultInterfaceListener === listener) {
            defaultInterfaceListener = null
        }
    }

    override fun startDefaultInterfaceMonitor(listener: InterfaceUpdateListener) {
        defaultInterfaceListener = listener
        publishDefaultInterface(listener)
    }

    /** Publish the emulator's physical default interface, not the VPN TUN. */
    private fun publishDefaultInterface(listener: InterfaceUpdateListener) {
        val connectivity = vpnService.getSystemService(ConnectivityManager::class.java)
        val network = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            connectivity.activeNetwork
        } else {
            null
        }
        if (network == null) {
            listener.updateDefaultInterface("", -1, false, false)
            return
        }

        repeat(10) {
            val interfaceName = connectivity.getLinkProperties(network)?.interfaceName
            if (!interfaceName.isNullOrBlank()) {
                val index = runCatching {
                    JavaNetworkInterface.getByName(interfaceName).index
                }.getOrDefault(-1)
                if (index >= 0) {
                    listener.updateDefaultInterface(interfaceName, index, false, false)
                    VpnBridge.sendLog(vpnService, "[libbox] default interface: $interfaceName (index=$index)")
                    return
                }
            }
            Thread.sleep(100)
        }
        listener.updateDefaultInterface("", -1, false, false)
    }

    override fun getInterfaces(): NetworkInterfaceIterator {
        val connectivity = vpnService.getSystemService(ConnectivityManager::class.java)
        val javaInterfaces = runCatching {
            JavaNetworkInterface.getNetworkInterfaces()?.let { Collections.list(it) }.orEmpty()
        }.getOrDefault(emptyList())
        val interfaces = mutableListOf<io.nekohasekai.libbox.NetworkInterface>()

        for (network in connectivity.allNetworks) {
            val linkProperties = connectivity.getLinkProperties(network) ?: continue
            val capabilities = connectivity.getNetworkCapabilities(network) ?: continue
            val interfaceName = linkProperties.interfaceName ?: continue
            val networkInterface = javaInterfaces.firstOrNull { it.name == interfaceName } ?: continue
            val boxInterface = io.nekohasekai.libbox.NetworkInterface().apply {
                setIndex(networkInterface.index)
                setName(interfaceName)
                setMTU(runCatching { networkInterface.mtu }.getOrDefault(0))
                setAddresses(StringArray(networkInterface.interfaceAddresses.map {
                    "${formatHostAddress(it.address)}/${it.networkPrefixLength}"
                }.iterator()))
                setDNSServer(StringArray(linkProperties.dnsServers.mapNotNull {
                    formatHostAddress(it)
                }.iterator()))
                setType(
                    when {
                        capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> Libbox.InterfaceTypeWIFI
                        capabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> Libbox.InterfaceTypeCellular
                        capabilities.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> Libbox.InterfaceTypeEthernet
                        else -> Libbox.InterfaceTypeOther
                    },
                )
                setMetered(!capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED))
                var flags = 0
                if (capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)) {
                    flags = flags or OsConstants.IFF_UP or OsConstants.IFF_RUNNING
                }
                if (networkInterface.isLoopback) flags = flags or OsConstants.IFF_LOOPBACK
                if (networkInterface.isPointToPoint) flags = flags or OsConstants.IFF_POINTOPOINT
                if (runCatching { networkInterface.supportsMulticast() }.getOrDefault(false)) {
                    flags = flags or OsConstants.IFF_MULTICAST
                }
                setFlags(flags)
            }
            interfaces += boxInterface
        }
        return NetworkInterfaceArray(interfaces)
    }

    /** netip.ParsePrefix rejects IPv6 zone identifiers such as %eth0. */
    private fun formatHostAddress(address: InetAddress): String =
        if (address is Inet6Address) {
            Inet6Address.getByAddress(address.address).hostAddress
        } else {
            address.hostAddress
        }

    override fun findConnectionOwner(
        ipProtocol: Int,
        sourceAddress: String,
        sourcePort: Int,
        destinationAddress: String,
        destinationPort: Int,
    ): ConnectionOwner {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            throw UnsupportedOperationException("connection owner lookup requires Android 10")
        }
        val connectivity = vpnService.getSystemService(ConnectivityManager::class.java)
        val uid = connectivity.getConnectionOwnerUid(
            ipProtocol,
            InetSocketAddress(sourceAddress, sourcePort),
            InetSocketAddress(destinationAddress, destinationPort),
        )
        if (uid < 0) throw IllegalStateException("android: connection owner not found")
        return ConnectionOwner().apply {
            setUserId(uid)
            setUserName(vpnService.packageManager.getPackagesForUid(uid)?.firstOrNull().orEmpty())
            setAndroidPackageNames(StringArray(vpnService.packageManager.getPackagesForUid(uid)?.toList()?.iterator()
                ?: emptyList<String>().iterator()))
        }
    }

    override fun includeAllNetworks(): Boolean = false

    override fun underNetworkExtension(): Boolean = false

    override fun useProcFS(): Boolean = Build.VERSION.SDK_INT < Build.VERSION_CODES.Q

    override fun localDNSTransport(): LocalDNSTransport? = null

    override fun readWIFIState(): WIFIState? = null

    override fun sendNotification(notification: Notification) {
        VpnBridge.sendLog(vpnService, "[libbox] ${notification.getTitle()}: ${notification.getBody()}")
    }

    override fun systemCertificates(): StringIterator = StringArray(emptyList<String>().iterator())

    private class NetworkInterfaceArray(
        private val values: List<io.nekohasekai.libbox.NetworkInterface>,
    ) : NetworkInterfaceIterator {
        private var index = 0
        override fun hasNext(): Boolean = index < values.size
        override fun next(): io.nekohasekai.libbox.NetworkInterface = values[index++]
    }

    class StringArray(
        private val iterator: Iterator<String>,
    ) : StringIterator {
        override fun hasNext(): Boolean = iterator.hasNext()
        override fun next(): String = iterator.next()
        override fun len(): Int = 0
    }
}
