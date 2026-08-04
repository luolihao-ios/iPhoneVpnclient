import 'package:flutter_test/flutter_test.dart';
import 'package:forge_vpn_flutter/core/update_checker.dart';

void main() {
  test('compares release versions numerically', () {
    expect(compareVersions('0.1.1', '0.1.0'), greaterThan(0));
    expect(compareVersions('v1.2.0-windows', '1.2.0'), 0);
    expect(compareVersions('1.1', '1.2.0'), lessThan(0));
  });
}
