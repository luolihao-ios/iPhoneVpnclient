import 'package:flutter_test/flutter_test.dart';
import 'package:forge_vpn_flutter/core/remote_dns.dart';

void main() {
  test('三组 DoH 使用固定 IP、443、TLS 名称和路径', () {
    expect(
      remoteDnsEndpoint(RemoteDnsProvider.cloudflare),
      const RemoteDnsEndpoint(
        id: 'cloudflare',
        name: 'Cloudflare',
        server: '1.1.1.1',
        port: 443,
        serverName: 'cloudflare-dns.com',
        path: '/dns-query',
      ),
    );
    expect(
      remoteDnsEndpoint(RemoteDnsProvider.google),
      const RemoteDnsEndpoint(
        id: 'google',
        name: 'Google',
        server: '8.8.8.8',
        port: 443,
        serverName: 'dns.google',
        path: '/dns-query',
      ),
    );
    expect(
      remoteDnsEndpoint(RemoteDnsProvider.quad9),
      const RemoteDnsEndpoint(
        id: 'quad9',
        name: 'Quad9',
        server: '9.9.9.9',
        port: 443,
        serverName: 'dns.quad9.net',
        path: '/dns-query',
      ),
    );
  });

  test('上次成功项排第一并循环其余提供器', () {
    expect(
      orderedRemoteDnsProviders(RemoteDnsProvider.google),
      [
        RemoteDnsProvider.google,
        RemoteDnsProvider.quad9,
        RemoteDnsProvider.cloudflare,
      ],
    );
    expect(
      orderedRemoteDnsProviders(null),
      RemoteDnsProvider.values,
    );
  });

  test('持久化标识只接受三组内置解析器', () {
    expect(
      parseRemoteDnsProvider('cloudflare'),
      RemoteDnsProvider.cloudflare,
    );
    expect(parseRemoteDnsProvider('google'), RemoteDnsProvider.google);
    expect(parseRemoteDnsProvider('quad9'), RemoteDnsProvider.quad9);
    expect(parseRemoteDnsProvider('custom'), isNull);
    expect(parseRemoteDnsProvider(null), isNull);
  });
}
