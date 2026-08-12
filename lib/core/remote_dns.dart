/// Built-in encrypted DNS providers used by Forge VPN.
enum RemoteDnsProvider { cloudflare, google, quad9 }

/// Immutable connection details for a DNS-over-HTTPS provider.
class RemoteDnsEndpoint {
  const RemoteDnsEndpoint({
    required this.id,
    required this.name,
    required this.server,
    required this.port,
    required this.serverName,
    required this.path,
  });

  final String id;
  final String name;
  final String server;
  final int port;
  final String serverName;
  final String path;

  Map<String, dynamic> toSingBoxServer() => {
        'type': 'https',
        'tag': 'remote-$id',
        'server': server,
        'server_port': port,
        'path': path,
        'tls': {
          'enabled': true,
          'server_name': serverName,
        },
        'detour': 'proxy',
      };

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is RemoteDnsEndpoint &&
            id == other.id &&
            name == other.name &&
            server == other.server &&
            port == other.port &&
            serverName == other.serverName &&
            path == other.path;
  }

  @override
  int get hashCode => Object.hash(id, name, server, port, serverName, path);
}

RemoteDnsEndpoint remoteDnsEndpoint(RemoteDnsProvider provider) {
  return switch (provider) {
    RemoteDnsProvider.cloudflare => const RemoteDnsEndpoint(
        id: 'cloudflare',
        name: 'Cloudflare',
        server: '1.1.1.1',
        port: 443,
        serverName: 'cloudflare-dns.com',
        path: '/dns-query',
      ),
    RemoteDnsProvider.google => const RemoteDnsEndpoint(
        id: 'google',
        name: 'Google',
        server: '8.8.8.8',
        port: 443,
        serverName: 'dns.google',
        path: '/dns-query',
      ),
    RemoteDnsProvider.quad9 => const RemoteDnsEndpoint(
        id: 'quad9',
        name: 'Quad9',
        server: '9.9.9.9',
        port: 443,
        serverName: 'dns.quad9.net',
        path: '/dns-query',
      ),
  };
}

RemoteDnsProvider? parseRemoteDnsProvider(String? value) {
  for (final provider in RemoteDnsProvider.values) {
    if (remoteDnsEndpoint(provider).id == value) return provider;
  }
  return null;
}

List<RemoteDnsProvider> orderedRemoteDnsProviders(
  RemoteDnsProvider? preferred,
) {
  final providers = RemoteDnsProvider.values;
  if (preferred == null) return List.unmodifiable(providers);
  final start = providers.indexOf(preferred);
  return List.unmodifiable([
    ...providers.skip(start),
    ...providers.take(start),
  ]);
}
