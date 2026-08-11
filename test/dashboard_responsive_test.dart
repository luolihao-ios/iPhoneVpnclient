import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:forge_vpn_flutter/core/models/node.dart';
import 'package:forge_vpn_flutter/core/node_health.dart' as health;
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

  testWidgets('节点检查期间按钮可停止并恢复检查状态', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final pendingCheck = Completer<health.HealthCheckResult>();
    addTearDown(() {
      if (!pendingCheck.isCompleted) {
        pendingCheck.complete(const health.HealthCheckResult(
          ok: false,
          healthStatus: 'unavailable',
          target: 'HTTPS',
        ));
      }
    });
    const node = VpnNode(
      id: 'checking-node',
      type: NodeType.vmess,
      name: 'Checking node',
      server: 'example.com',
      port: 443,
      uuid: '11111111-1111-1111-1111-111111111111',
    );
    final provider = AppProvider(
      subscriptionLoader: (url, onDiagnostic) async => [node],
      tcpChecker: (node) async => const health.HealthCheckResult(
        ok: true,
        latency: 10,
        healthStatus: 'available',
        target: 'Node',
      ),
      fullChecker: (node, corePath, runtimeDir) => pendingCheck.future,
    );
    await provider.importSubscription('https://example.com/sub');
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(1200, 800)),
        child: ChangeNotifierProvider.value(
          value: provider,
          child: const MaterialApp(
            locale: Locale('zh'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(body: DashboardScreen()),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('停止'), findsOneWidget);
    await tester.tap(find.text('停止'));
    await tester.pump();

    expect(provider.runtime.checkingNodes, isFalse);
    expect(find.text('检查'), findsOneWidget);
  });
}
