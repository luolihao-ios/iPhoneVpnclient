import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../widgets/responsive.dart';
import '../l10n/app_localizations.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppProvider>(
      builder: (context, provider, _) {
        final l10n = AppLocalizations.of(context);
        final settings = provider.settings;
        final connected = provider.runtime.connected;

        return ListView(
          padding: Responsive.screenPadding(context),
          children: [
            _GroupHeader(title: l10n.connection),
            const SizedBox(height: 8),
            _Card(
              child: Column(
                children: [
                  _SettingRow(
                    icon: Icons.language,
                    title: l10n.routeMode,
                    trailing: DropdownButton<String>(
                      value: settings.routeMode,
                      underline: const SizedBox(),
                      dropdownColor: Colors.white,
                      style: const TextStyle(
                          color: Color(0xFF172033), fontSize: 14),
                      items: [
                        DropdownMenuItem(
                            value: 'global', child: Text(l10n.globalProxy)),
                        DropdownMenuItem(
                            value: 'rule', child: Text(l10n.smartSplit)),
                      ],
                      onChanged: connected
                          ? null
                          : (v) => provider
                              .saveSettings(settings.copyWith(routeMode: v)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            _GroupHeader(title: l10n.systemProxy),
            const SizedBox(height: 8),
            _Card(
              child: _SettingRow(
                icon: Icons.settings_ethernet,
                title: l10n.systemProxy,
                subtitle: l10n.systemProxyManaged,
                trailing: Checkbox(
                  value: settings.systemProxy,
                  onChanged: connected
                      ? null
                      : (value) => provider.saveSettings(
                          settings.copyWith(systemProxy: value ?? false)),
                  activeColor: const Color(0xFF21B892),
                  checkColor: Colors.white,
                  fillColor: WidgetStateProperty.all(
                      const Color(0xFF21B892).withValues(alpha: 0.2)),
                ),
              ),
            ),
            const SizedBox(height: 20),
            _GroupHeader(title: l10n.about),
            const SizedBox(height: 8),
            _Card(
              child: Column(
                children: [
                  _SettingRow(
                    icon: Icons.info_outline,
                    title: l10n.version,
                    trailing: Text(provider.appVersion,
                        style: TextStyle(color: Color(0xFF657083))),
                  ),
                  const Divider(color: Color(0xFFD7DEE8), height: 1),
                  _SettingRow(
                    icon: Icons.code,
                    title: l10n.engine,
                    trailing: const Text('sing-box',
                        style: TextStyle(color: Color(0xFF657083))),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _GroupHeader extends StatelessWidget {
  final String title;
  const _GroupHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(title.toUpperCase(),
          style: TextStyle(
              fontSize: 11, color: Color(0xFF657083), letterSpacing: 1)),
    );
  }
}

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Responsive.surfaceColor,
        borderRadius: BorderRadius.circular(Responsive.cardRadius(context)),
        border: Border.all(color: Responsive.borderColor),
      ),
      child: child,
    );
  }
}

class _SettingRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget trailing;

  const _SettingRow({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Color(0xFF657083)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        color: Color(0xFF172033), fontSize: 14)),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle!,
                      style: TextStyle(fontSize: 11, color: Color(0xFF657083))),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          trailing,
        ],
      ),
    );
  }
}
