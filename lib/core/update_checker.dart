import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

const currentWindowsVersion = '0.1.1';
const windowsReleaseApi =
    'https://api.github.com/repos/luolihao-ios/iPhoneVpnclient/releases?per_page=30';

class WindowsUpdateInfo {
  const WindowsUpdateInfo({
    required this.version,
    required this.releaseUrl,
    required this.downloadUrl,
  });

  final String version;
  final String releaseUrl;
  final String downloadUrl;
}

Future<WindowsUpdateInfo?> fetchWindowsUpdate({
  http.Client? client,
  String currentVersion = currentWindowsVersion,
}) async {
  if (!Platform.isWindows) return null;
  final httpClient = client ?? http.Client();
  try {
    final response = await httpClient.get(Uri.parse(windowsReleaseApi), headers: const {
      'Accept': 'application/vnd.github+json',
      'User-Agent': 'Forge-VPN',
    }).timeout(const Duration(seconds: 5));
    if (response.statusCode != 200) return null;
    final data = jsonDecode(response.body);
    if (data is! List) return null;
    return selectLatestWindowsRelease(data, currentVersion: currentVersion);
  } catch (_) {
    return null;
  } finally {
    if (client == null) httpClient.close();
  }
}

WindowsUpdateInfo? selectLatestWindowsRelease(
  List<dynamic> releases, {
  String currentVersion = currentWindowsVersion,
}) {
  WindowsUpdateInfo? selected;
  for (final release in releases) {
    if (release is! Map) continue;
    final version = _normalizeVersion((release['tag_name'] ?? '').toString());
    final assets = release['assets'];
    if (version.isEmpty || assets is! List) continue;
    String? downloadUrl;
    for (final asset in assets) {
      if (asset is! Map) continue;
      final name = (asset['name'] ?? '').toString().toLowerCase();
      if (name.endsWith('.exe')) {
        downloadUrl = (asset['browser_download_url'] ?? '').toString();
        break;
      }
    }
    final releaseUrl = (release['html_url'] ?? '').toString();
    if (downloadUrl == null || downloadUrl.isEmpty || releaseUrl.isEmpty) {
      continue;
    }
    if (compareVersions(version, currentVersion) <= 0) continue;
    if (selected == null || compareVersions(version, selected.version) > 0) {
      selected = WindowsUpdateInfo(
        version: version,
        releaseUrl: releaseUrl,
        downloadUrl: downloadUrl,
      );
    }
  }
  return selected;
}

int compareVersions(String left, String right) {
  final a = _versionParts(left);
  final b = _versionParts(right);
  for (var i = 0; i < 3; i++) {
    final result = a[i].compareTo(b[i]);
    if (result != 0) return result;
  }
  return 0;
}

String _normalizeVersion(String value) => value
    .trim()
    .replaceFirst(RegExp(r'^[vV]'), '')
    .split('-')
    .first;

List<int> _versionParts(String value) {
  final parts = _normalizeVersion(value).split('.');
  return List<int>.generate(
    3,
    (index) => index < parts.length ? int.tryParse(parts[index]) ?? 0 : 0,
  );
}

Future<void> openWindowsUpdate(WindowsUpdateInfo update) async {
  await Process.start('explorer.exe', [update.downloadUrl]);
}
