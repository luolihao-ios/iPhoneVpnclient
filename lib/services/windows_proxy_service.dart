import 'dart:async';
import 'dart:io';

const _internetSettingsKey =
    r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings';
const _ownedMarker = 'ForgeVPNProxyOwned';
const _beforeEnableKey = 'ForgeVPNProxyBeforeEnable';
const _beforeServerKey = 'ForgeVPNProxyBeforeServer';
const _beforeOverrideKey = 'ForgeVPNProxyBeforeOverride';

abstract class WindowsRegistryAdapter {
  Future<String?> read(String name);
  Future<void> write(String name, String value, {required String type});
  Future<void> delete(String name);
}

class ProcessWindowsRegistryAdapter implements WindowsRegistryAdapter {
  String? _readSync(String name) {
    final result =
        Process.runSync('reg', ['query', _internetSettingsKey, '/v', name]);
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
      throw ProcessException(
          'reg', [], result.stderr.toString(), result.exitCode);
    }
  }

  void _deleteSync(String name) {
    final result = Process.runSync(
        'reg', ['delete', _internetSettingsKey, '/v', name, '/f']);
    if (result.exitCode != 0 && result.exitCode != 1) {
      throw ProcessException(
          'reg', [], result.stderr.toString(), result.exitCode);
    }
  }

  @override
  Future<String?> read(String name) async {
    final result =
        await Process.run('reg', ['query', _internetSettingsKey, '/v', name]);
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
      throw ProcessException(
          'reg', [], result.stderr.toString(), result.exitCode);
    }
  }

  @override
  Future<void> delete(String name) async {
    final result = await Process.run(
        'reg', ['delete', _internetSettingsKey, '/v', name, '/f']);
    if (result.exitCode != 0 && result.exitCode != 1) {
      throw ProcessException(
          'reg', [], result.stderr.toString(), result.exitCode);
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
      for (final name in const [
        'ProxyEnable',
        'ProxyServer',
        'ProxyOverride'
      ]) {
        _before[name] = await _registry.read(name);
      }
      final persistedOwner = await _registry.read(_ownedMarker);
      if (persistedOwner != '1') {
        await _persistBeforeSettings();
      }
    }
    await _registry.write('ProxyEnable', '1', type: 'REG_DWORD');
    await _registry.write('ProxyServer', proxyServer, type: 'REG_SZ');
    _owned
      ..clear()
      ..addAll({'ProxyEnable': '1', 'ProxyServer': proxyServer});
    _restored = false;
  }

  /// Recover proxy settings left behind by a previous process or reboot.
  /// Only restore when the current registry values still match Forge VPN's
  /// local proxy, so a user's manual changes are never overwritten.
  Future<void> recoverStaleSettings() async {
    if (await _registry.read(_ownedMarker) != '1') return;
    final currentEnable = await _registry.read('ProxyEnable');
    final currentServer = await _registry.read('ProxyServer');
    if (currentEnable != '1' || currentServer != '127.0.0.1:2080') {
      await _clearPersistedSettings();
      return;
    }
    final before = <String, String?>{
      'ProxyEnable': await _registry.read(_beforeEnableKey),
      'ProxyServer': await _registry.read(_beforeServerKey),
      'ProxyOverride': await _registry.read(_beforeOverrideKey),
    };
    await _restoreValues(before);
  }

  Future<void> restore() async {
    if (_restored || _owned.isEmpty) return;
    try {
      final currentEnable = await _registry.read('ProxyEnable');
      final currentServer = await _registry.read('ProxyServer');
      if (currentEnable == _owned['ProxyEnable'] &&
          currentServer == _owned['ProxyServer']) {
        await _restoreValues(_before);
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
        for (final name in const [
          'ProxyEnable',
          'ProxyServer',
          'ProxyOverride'
        ]) {
          final value = _before[name];
          if (value == null) {
            registry._deleteSync(name);
          } else {
            final type = name == 'ProxyEnable' ? 'REG_DWORD' : 'REG_SZ';
            registry._writeSync(name, value, type: type);
          }
        }
        for (final name in const [
          _ownedMarker,
          _beforeEnableKey,
          _beforeServerKey,
          _beforeOverrideKey,
        ]) {
          registry._deleteSync(name);
        }
      }
    } finally {
      _owned.clear();
      _before.clear();
      _restored = true;
    }
  }

  Future<void> _persistBeforeSettings() async {
    final values = <String, String?>{
      _beforeEnableKey: _before['ProxyEnable'],
      _beforeServerKey: _before['ProxyServer'],
      _beforeOverrideKey: _before['ProxyOverride'],
    };
    for (final entry in values.entries) {
      final value = entry.value;
      if (value == null) {
        await _registry.delete(entry.key);
      } else {
        await _registry.write(entry.key, value, type: 'REG_SZ');
      }
    }
    await _registry.write(_ownedMarker, '1', type: 'REG_SZ');
  }

  Future<void> _restoreValues(Map<String, String?> values) async {
    for (final name in const ['ProxyEnable', 'ProxyServer', 'ProxyOverride']) {
      final value = values[name];
      if (value == null) {
        await _registry.delete(name);
      } else {
        final type = name == 'ProxyEnable' ? 'REG_DWORD' : 'REG_SZ';
        await _registry.write(name, value, type: type);
      }
    }
    await _clearPersistedSettings();
  }

  Future<void> _clearPersistedSettings() async {
    for (final name in const [
      _ownedMarker,
      _beforeEnableKey,
      _beforeServerKey,
      _beforeOverrideKey,
    ]) {
      await _registry.delete(name);
    }
  }
}
