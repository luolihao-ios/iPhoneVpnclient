import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../providers/app_provider.dart';
import 'responsive.dart';

/// Subscription URL input shared by the dashboard and the legacy Nodes page.
class SubscriptionImportCard extends StatefulWidget {
  const SubscriptionImportCard({super.key});

  @override
  State<SubscriptionImportCard> createState() => _SubscriptionImportCardState();
}

class _SubscriptionImportCardState extends State<SubscriptionImportCard> {
  final _controller = TextEditingController();
  FocusNode _focusNode = FocusNode();
  bool _isExpanded = true;
  String _lastSubscriptionUrl = '';

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _dismissKeyboard() {
    _focusNode.unfocus();
    FocusScope.of(context).unfocus();
  }

  void _collapseImportCard() {
    final oldFocusNode = _focusNode;
    setState(() {
      _isExpanded = false;
      _focusNode = FocusNode();
    });
    oldFocusNode.unfocus(disposition: UnfocusDisposition.scope);
    oldFocusNode.dispose();
  }

  Future<void> _import(AppProvider provider, AppLocalizations l10n) async {
    _dismissKeyboard();
    final url = _controller.text.trim();
    if (url.isEmpty) return;
    try {
      await provider.importSubscription(url);
      if (!mounted) return;
      _collapseImportCard();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(l10n.importedSuccessfully),
        backgroundColor: const Color(0xFF21B892),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(l10n.importFailed(e.toString())),
        backgroundColor: const Color(0xFFE15D52),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppProvider>(
      builder: (context, provider, _) {
        final l10n = AppLocalizations.of(context);
        final providerUrl = provider.subscriptionUrl;
        if (providerUrl != _lastSubscriptionUrl) {
          _lastSubscriptionUrl = providerUrl;
          if (providerUrl.isNotEmpty) {
            if (_isExpanded) {
              final oldFocusNode = _focusNode;
              _isExpanded = false;
              _focusNode = FocusNode();
              oldFocusNode.unfocus(disposition: UnfocusDisposition.scope);
              oldFocusNode.dispose();
            }
            if (!_focusNode.hasFocus && _controller.text != providerUrl) {
              _controller.text = providerUrl;
            }
          }
        }

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Responsive.surfaceColor,
            borderRadius: BorderRadius.circular(Responsive.cardRadius(context)),
            border: Border.all(color: Responsive.borderColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InkWell(
                key: const Key('subscription-import-toggle'),
                onTap: () => setState(() => _isExpanded = !_isExpanded),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          l10n.subscriptionUrl,
                          style:
                              TextStyle(fontSize: 12, color: Color(0xFF657083)),
                        ),
                      ),
                      Icon(
                        _isExpanded
                            ? Icons.keyboard_arrow_up
                            : Icons.keyboard_arrow_down,
                        size: 20,
                        color: Color(0xFF657083),
                      ),
                    ],
                  ),
                ),
              ),
              if (_isExpanded) ...[
                const SizedBox(height: 8),
                TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _import(provider, l10n),
                  onTapOutside: (_) => _dismissKeyboard(),
                  decoration: InputDecoration(
                    hintText: 'https://...',
                    hintStyle: TextStyle(color: Color(0xFF8A95A6)),
                    filled: true,
                    fillColor: Responsive.bgColor,
                    border: _border(),
                    enabledBorder: _border(),
                    focusedBorder: _border(const Color(0xFF21B892)),
                    isDense: true,
                    contentPadding: const EdgeInsets.all(12),
                  ),
                  style:
                      const TextStyle(fontSize: 14, color: Color(0xFF172033)),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => _import(provider, l10n),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF21B892),
                      foregroundColor: const Color(0xFF062019),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: Text(l10n.importAction,
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  OutlineInputBorder _border([Color color = const Color(0xFFD7DEE8)]) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: color),
    );
  }
}
