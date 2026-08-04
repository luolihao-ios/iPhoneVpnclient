import 'package:flutter_test/flutter_test.dart';
import 'package:forge_vpn_flutter/core/update_checker.dart';

void main() {
  test('compares release versions numerically', () {
    expect(compareVersions('0.1.1', '0.1.0'), greaterThan(0));
    expect(compareVersions('v1.2.0-windows', '1.2.0'), 0);
    expect(compareVersions('1.1', '1.2.0'), lessThan(0));
  });

  test('selects the newest release that has a Windows installer', () {
    final update = selectLatestWindowsRelease([
      {
        'tag_name': 'ios-test-103',
        'html_url': 'https://example.com/ios',
        'assets': [
          {'name': 'app.ipa', 'browser_download_url': 'https://example.com/app.ipa'},
        ],
      },
      {
        'tag_name': 'v0.1.1-windows',
        'html_url': 'https://example.com/windows',
        'assets': [
          {'name': 'ForgeVPN-Setup-0.1.1.exe', 'browser_download_url': 'https://example.com/app.exe'},
        ],
      },
    ], currentVersion: '0.1.0');

    expect(update?.version, '0.1.1');
    expect(update?.downloadUrl, 'https://example.com/app.exe');
  });
}
