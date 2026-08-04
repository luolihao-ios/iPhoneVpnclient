import 'dart:async';
import 'dart:io';

const _internetSettingsKey =
    r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings';

abstract class WindowsRegistryAdapter {
  Future<String?> read(String name);
  Future<void> write(String name, String value, {required String type});
  Future<void> delete(String name);
}

class ProcessWindowsRegistryAdapter implements WindowsRegistryAdapter {
  String? _readSync(String name) {
    final result = Process.runSync('reg', ['query', _internetSettingsKey, '/v', name]);
    if (result.exitCode != 0) return null;
    final line = result.stdout
        .toString()
        .split(RegExp(r'\r?\n'))
        .firstWhere((line) => line.contains(' $name '), orElse: () => '');
    if (line.isEmpty) return null;
    final parts = line.trim().split(RegExp(r'\s{2,}'));
    if (parts.length < 3) return null;
    final value = parts.last.trim();
    if (name == 'ProxyEnable' && value.toLowerCase().startsWith('0x')) {
      return int.tryParse(value.substring(2), radix: 16)?.toString() ?? value;
    }
    return value;
  }

  void _writeSync(String name, String value, {required String type}) {
    final result = Process.runSync('reg', [
      'add',
      _internetSettingsKey,
      '/v',
      name,
      '/t',
      type,
      '/d',
      value,
      '/f',
    ]);
    if (result.exitCode != 0) {
      throw ProcessException('reg', [], result.stderr.toString(), result.exitCode);
    }
  }

  void _deleteSync(String name) {
    final result = Process.runSync('reg', ['delete', _internetSettingsKey, '/v', name, '/f']);
    if (result.exitCode != 0 && result.exitCode != 1) {
      throw ProcessException('reg', [], result.stderr.toString(), result.exitCode);
    }
  }

  @override
  Future<String?> read(String name) async {
    final result = await Process.run('reg', ['query', _internetSettingsKey, '/v', name]);
    if (result.exitCode != 0) return null;
    final line = result.stdout
        .toString()
        .split(RegExp(r'\r?\n'))
        .firstWhere((line) => line.contains(' $name '), orElse: () => '');
    if (line.isEmpty) return null;
    final parts = line.trim().split(RegExp(r'\s{2,}'));
    if (parts.length < 3) return null;
    final value = parts.last.trim();
    if (name == 'ProxyEnable' && value.toLowerCase().startsWith('0x')) {
      return int.tryParse(value.substring(2), radix: 16)?.toString() ?? value;
    }
    return value;
  }

  @override
  Future<void> write(String name, String value, {required String type}) async {
    final result = await Process.run('reg', [
      'add',
      _internetSettingsKey,
      '/v',
      name,
      '/t',
      type,
      '/d',
      value,
      '/f',
    ]);
    if (result.exitCode != 0) {
      throw ProcessException('reg', [], result.stderr.toString(), result.exitCode);
    }
  }

  @override
  Future<void> delete(String name) async {
    final result = await Process.run('reg', ['delete', _internetSettingsKey, '/v', name, '/f']);
    if (result.exitCode != 0 && result.exitCode != 1) {
      throw ProcessException('reg', [], result.stderr.toString(), result.exitCode);
    }
  }
}

class WindowsProxyService {
  WindowsProxyService({WindowsRegistryAdapter? registry})
      : _registry = registry ?? ProcessWindowsRegistryAdapter();

  final WindowsRegistryAdapter _registry;
  final Map<String, String?> _before = {};
  final Map<String, String> _owned = {};
  bool _restored = true;

  bool get ownsCurrentSettings => !_restored && _owned.isNotEmpty;

  Future<void> enable({required String proxyServer}) async {
    if (_owned.isEmpty) {
      for (final name in const ['ProxyEnable', 'ProxyServer', 'ProxyOverride']) {
        _before[name] = await _registry.read(name);
      }
    }
    await _registry.write('ProxyEnable', '1', type: 'REG_DWORD');
    await _registry.write('ProxyServer', proxyServer, type: 'REG_SZ');
    _owned
      ..clear()
      ..addAll({'ProxyEnable': '1', 'ProxyServer': proxyServer});
    _restored = false;
  }

  Future<void> restore() async {
    if (_restored || _owned.isEmpty) return;
    try {
      final currentEnable = await _registry.read('ProxyEnable');
      final currentServer = await _registry.read('ProxyServer');
      if (currentEnable == _owned['ProxyEnable'] &&
          currentServer == _owned['ProxyServer']) {
        for (final name in const ['ProxyEnable', 'ProxyServer', 'ProxyOverride']) {
          final value = _before[name];
          if (value == null) {
            await _registry.delete(name);
          } else {
            final type = name == 'ProxyEnable' ? 'REG_DWORD' : 'REG_SZ';
            await _registry.write(name, value, type: type);
          }
        }
      }
    } finally {
      _owned.clear();
      _before.clear();
      _restored = true;
    }
  }

  /// Restore synchronously before the desktop process exits. An asynchronous
  /// registry command can be abandoned when Windows tears down the Flutter
  /// engine, leaving the system proxy enabled.
  void restoreSync() {
    if (_restored || _owned.isEmpty) return;
    final registry = _registry;
    if (registry is! ProcessWindowsRegistryAdapter) return;
    try {
      final currentEnable = registry._readSync('ProxyEnable');
      final currentServer = registry._readSync('ProxyServer');
      if (currentEnable == _owned['ProxyEnable'] &&
          currentServer == _owned['ProxyServer']) {
        for (final name in const ['ProxyEnable', 'ProxyServer', 'ProxyOverride']) {
          final value = _before[name];
          if (value == null) {
            registry._deleteSync(name);
          } else {
            final type = name == 'ProxyEnable' ? 'REG_DWORD' : 'REG_SZ';
            registry._writeSync(name, value, type: type);
          }
        }
      }
    } finally {
      _owned.clear();
      _before.clear();
      _restored = true;
    }
  }
}
