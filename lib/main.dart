import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/app_provider.dart';
import 'screens/dashboard_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/logs_screen.dart';
import 'widgets/responsive.dart';
import 'l10n/app_localizations.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ForgeVpnApp());
}

Locale resolveForgeLocale(List<Locale>? locales) {
  for (final locale in locales ?? const <Locale>[]) {
    if (locale.languageCode == 'zh') return const Locale('zh');
    if (locale.languageCode == 'en') return const Locale('en');
  }
  return const Locale('en');
}

class ForgeVpnApp extends StatelessWidget {
  const ForgeVpnApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppProvider(),
      child: MaterialApp(
        title: 'Forge VPN',
        debugShowCheckedModeBanner: false,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        localeListResolutionCallback: (locales, supportedLocales) =>
            resolveForgeLocale(locales),
        theme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: Responsive.bgColor,
          colorScheme: const ColorScheme.dark(
            primary: Color(0xFF21B892),
            secondary: Color(0xFF5D8CFF),
            error: Color(0xFFE15D52),
            surface: Color(0xFF161B22),
          ),
          appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xFF0D1117),
            elevation: 0,
            centerTitle: true,
          ),
          bottomNavigationBarTheme: const BottomNavigationBarThemeData(
            backgroundColor: Color(0xFF0D1117),
            selectedItemColor: Color(0xFF21B892),
            unselectedItemColor: Color(0xFF8B949E),
            type: BottomNavigationBarType.fixed,
          ),
          useMaterial3: true,
        ),
        home: const MainShell(),
      ),
    );
  }
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;

  final _pages = const [
    DashboardScreen(),
    SettingsScreen(),
    LogsScreen(),
  ];

  List<({IconData icon, IconData activeIcon, String label})> _navItems(
      AppLocalizations l10n) {
    return [
      (
        icon: Icons.speed_outlined,
        activeIcon: Icons.speed,
        label: l10n.dashboard
      ),
      (
        icon: Icons.settings_outlined,
        activeIcon: Icons.settings,
        label: l10n.settings
      ),
      (
        icon: Icons.terminal_outlined,
        activeIcon: Icons.terminal,
        label: l10n.logs
      ),
    ];
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppProvider>().initialize('');
    });
  }

  Widget _buildBottomNav(AppLocalizations l10n) {
    final navItems = _navItems(l10n);
    return BottomNavigationBar(
      currentIndex: _currentIndex,
      onTap: (i) => setState(() => _currentIndex = i),
      items: navItems
          .map((e) => BottomNavigationBarItem(
                icon: Icon(e.icon),
                activeIcon: Icon(e.activeIcon),
                label: e.label,
              ))
          .toList(),
    );
  }

  Widget _buildNavRail(AppLocalizations l10n) {
    final navItems = _navItems(l10n);
    return NavigationRail(
      selectedIndex: _currentIndex,
      onDestinationSelected: (i) => setState(() => _currentIndex = i),
      labelType: NavigationRailLabelType.all,
      backgroundColor: const Color(0xFF111720),
      indicatorColor: const Color(0xFF21B892).withValues(alpha: 0.15),
      destinations: navItems
          .map((e) => NavigationRailDestination(
                icon: Icon(e.icon),
                selectedIcon: Icon(e.activeIcon),
                label: Text(e.label),
              ))
          .toList(),
    );
  }

  Widget _buildUpdateBanner(BuildContext context) {
    return Consumer<AppProvider>(
      builder: (context, provider, child) {
        final update = provider.availableUpdate;
        if (update == null) return const SizedBox.shrink();
        return MaterialBanner(
          backgroundColor: const Color(0xFF16382F),
          content: Text('发现新版本 ${update.version}，建议下载安装。'),
          actions: [
            TextButton(
              onPressed: provider.openUpdate,
              child: const Text('立即更新'),
            ),
            TextButton(
              onPressed: provider.dismissUpdate,
              child: const Text('稍后提醒'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final type = Responsive.of(context);
    final l10n = AppLocalizations.of(context);

    if (type == ScreenType.phone) {
      return Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              _buildUpdateBanner(context),
              Expanded(
                child: IndexedStack(index: _currentIndex, children: _pages),
              ),
            ],
          ),
        ),
        bottomNavigationBar: _buildBottomNav(l10n),
      );
    }

    // Tablet + desktop: NavigationRail + body
    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            _buildNavRail(l10n),
            const VerticalDivider(width: 1, color: Color(0xFF2D3643)),
            Expanded(
              child: Column(
                children: [
                  _buildUpdateBanner(context),
                  Expanded(
                    child: IndexedStack(index: _currentIndex, children: _pages),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
