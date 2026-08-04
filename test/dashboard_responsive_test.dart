import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:forge_vpn_flutter/providers/app_provider.dart';
import 'package:forge_vpn_flutter/screens/dashboard_screen.dart';
import 'package:forge_vpn_flutter/widgets/responsive.dart';
import 'package:forge_vpn_flutter/l10n/app_localizations.dart';

void main() {
  testWidgets('phone screen content has the additional top spacing',
      (tester) async {
    late EdgeInsets padding;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(360, 800)),
        child: Builder(builder: (context) {
          padding = Responsive.screenPadding(context);
          return const SizedBox.shrink();
        }),
      ),
    );
    expect(padding.top, 32);
  });

  test('路由模式会保存到本地', () async {
    SharedPreferences.setMockInitialValues({});
    final provider = AppProvider();

    await provider.saveSettings(const AppSettings(routeMode: 'rule'));

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('route_mode'), 'rule');
  });

  testWidgets('phone dashboard does not overflow the server header',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final provider = AppProvider();
    await provider.importSubscriptionText(
      '[{"type":"vmess","name":"Test","server":"example.com","port":443,"id":"test-id"}]',
    );

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(360, 800)),
        child: ChangeNotifierProvider.value(
          value: provider,
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Scaffold(body: DashboardScreen()),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}
