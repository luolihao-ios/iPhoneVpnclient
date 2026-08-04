import 'package:flutter_test/flutter_test.dart';
import 'package:forge_vpn_flutter/services/windows_proxy_service.dart';

class MemoryRegistry implements WindowsRegistryAdapter {
  final values = <String, String>{};
  final writes = <String>[];

  @override
  Future<String?> read(String name) async => values[name];

  @override
  Future<void> write(String name, String value, {required String type}) async {
    values[name] = value;
    writes.add('$name=$value:$type');
  }

  @override
  Future<void> delete(String name) async => values.remove(name);
}

void main() {
  test('启用系统代理并在断开时恢复原始设置', () async {
    final registry = MemoryRegistry()
      ..values.addAll({'ProxyEnable': '0', 'ProxyServer': 'old:8080'});
    final service = WindowsProxyService(registry: registry);

    await service.enable(proxyServer: '127.0.0.1:2080');
    expect(registry.values['ProxyEnable'], '1');
    expect(registry.values['ProxyServer'], '127.0.0.1:2080');

    await service.restore();
    expect(registry.values['ProxyEnable'], '0');
    expect(registry.values['ProxyServer'], 'old:8080');
  });

  test('用户手动修改代理后不覆盖当前设置', () async {
    final registry = MemoryRegistry();
    final service = WindowsProxyService(registry: registry);

    await service.enable(proxyServer: '127.0.0.1:2080');
    registry.values['ProxyServer'] = 'manual:9000';
    await service.restore();

    expect(registry.values['ProxyServer'], 'manual:9000');
  });

  test('重启后恢复 Forge VPN 接管前的系统代理', () async {
    final registry = MemoryRegistry()
      ..values.addAll({'ProxyEnable': '0', 'ProxyServer': 'old:8080'});
    await WindowsProxyService(registry: registry)
        .enable(proxyServer: '127.0.0.1:2080');

    await WindowsProxyService(registry: registry).recoverStaleSettings();

    expect(registry.values['ProxyEnable'], '0');
    expect(registry.values['ProxyServer'], 'old:8080');
    expect(registry.values.containsKey('ForgeVPNProxyOwned'), isFalse);
  });
}
