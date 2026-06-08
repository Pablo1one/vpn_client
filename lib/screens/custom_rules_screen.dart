import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/route_rule.dart';
import '../providers/vpn_provider.dart';

// экран своих правил маршрутизации: 3 группы (напрямую/через vpn/блок),
// в каждой - домены, ключевые слова, ip-cidr, приложения
class CustomRulesScreen extends StatelessWidget {
  const CustomRulesScreen({super.key});

  static String matchLabel(RuleMatch m) => switch (m) {
        RuleMatch.domainSuffix => 'домен',
        RuleMatch.domainKeyword => 'слово в домене',
        RuleMatch.ipCidr => 'ip / cidr',
        RuleMatch.process => 'приложение',
      };

  @override
  Widget build(BuildContext context) {
    final vpn = context.watch<VpnProvider>();
    return Scaffold(
      appBar: AppBar(title: const Text('Свои правила')),
      body: ListView(
        children: [
          if (vpn.isConnected)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Правила применяются при следующем подключении',
                style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
              ),
            ),
          _Group(action: RuleAction.direct, title: 'Напрямую', hint: 'мимо VPN'),
          _Group(
              action: RuleAction.proxy,
              title: 'Через VPN',
              hint: 'принудительно в туннель'),
          _Group(action: RuleAction.block, title: 'Блок', hint: 'резать трафик'),
        ],
      ),
    );
  }
}

class _Group extends StatelessWidget {
  final RuleAction action;
  final String title;
  final String hint;
  const _Group({required this.action, required this.title, required this.hint});

  @override
  Widget build(BuildContext context) {
    final vpn = context.watch<VpnProvider>();
    final all = vpn.customRules;
    // (исходный индекс, правило) - индекс нужен для удаления из общего списка
    final items = <(int, RouteRule)>[
      for (var i = 0; i < all.length; i++)
        if (all[i].action == action) (i, all[i]),
    ];
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
          child: Text('$title · $hint',
              style: theme.textTheme.labelLarge
                  ?.copyWith(color: theme.colorScheme.primary)),
        ),
        if (items.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Text('пусто', style: TextStyle(fontSize: 12)),
          ),
        ...items.map((e) => ListTile(
              dense: true,
              title: Text(e.$2.value),
              subtitle: Text(CustomRulesScreen.matchLabel(e.$2.match),
                  style: const TextStyle(fontSize: 11)),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline, size: 20),
                onPressed: () => vpn.removeCustomRuleAt(e.$1),
              ),
            )),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 16, 0),
          child: Row(
            children: [
              TextButton.icon(
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Домен / IP'),
                onPressed: () => _showAddDialog(context, vpn, action),
              ),
              TextButton.icon(
                icon: const Icon(Icons.apps, size: 18),
                label: const Text('Приложение'),
                onPressed: () => _pickApps(context, vpn, action),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _showAddDialog(
      BuildContext context, VpnProvider vpn, RuleAction action) async {
    final rule = await showDialog<RouteRule>(
      context: context,
      builder: (_) => _AddRuleDialog(action: action),
    );
    if (rule != null) await vpn.addCustomRule(rule);
  }

  Future<void> _pickApps(
      BuildContext context, VpnProvider vpn, RuleAction action) async {
    final picked = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _AppPickDialog(
        loadApps: () => Platform.isAndroid
            ? vpn.getInstalledApps()
            : vpn.getRunningProcesses(),
      ),
    );
    if (picked == null) return;
    for (final pkg in picked) {
      await vpn.addCustomRule(
          RouteRule(action: action, match: RuleMatch.process, value: pkg));
    }
  }
}

class _AddRuleDialog extends StatefulWidget {
  final RuleAction action;
  const _AddRuleDialog({required this.action});

  @override
  State<_AddRuleDialog> createState() => _AddRuleDialogState();
}

class _AddRuleDialogState extends State<_AddRuleDialog> {
  RuleMatch _match = RuleMatch.domainSuffix;
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  String get _placeholder => switch (_match) {
        RuleMatch.domainSuffix => 'example.com',
        RuleMatch.domainKeyword => 'youtube',
        RuleMatch.ipCidr => '1.2.3.0/24',
        RuleMatch.process => 'chrome.exe',
      };

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Новое правило'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButton<RuleMatch>(
            value: _match,
            isExpanded: true,
            // приложения добавляются через пикер (кнопка «Приложение»), тут - домены/ip
            items: const [
              RuleMatch.domainSuffix,
              RuleMatch.domainKeyword,
              RuleMatch.ipCidr,
            ]
                .map((m) => DropdownMenuItem(
                    value: m, child: Text(CustomRulesScreen.matchLabel(m))))
                .toList(),
            onChanged: (m) => setState(() => _match = m ?? _match),
          ),
          TextField(
            controller: _ctrl,
            autofocus: true,
            decoration: InputDecoration(hintText: _placeholder),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена')),
        TextButton(onPressed: _submit, child: const Text('Добавить')),
      ],
    );
  }

  void _submit() {
    final v = _ctrl.text.trim();
    if (v.isEmpty) return;
    Navigator.pop(
        context, RouteRule(action: widget.action, match: _match, value: v));
  }
}

// компактный пикер приложений (мульти-выбор) для правил. грузит список через
// провайдер: запущенные процессы (винда) или установленные приложения (android)
class _AppPickDialog extends StatefulWidget {
  final Future<List<Map<String, String>>> Function() loadApps;
  const _AppPickDialog({required this.loadApps});

  @override
  State<_AppPickDialog> createState() => _AppPickDialogState();
}

class _AppPickDialogState extends State<_AppPickDialog> {
  List<Map<String, String>> _apps = [];
  final Set<String> _sel = {};
  String _q = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    widget.loadApps().then((a) {
      if (mounted) setState(() {
            _apps = a;
            _loading = false;
          });
    });
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _q.isEmpty
        ? _apps
        : _apps
            .where((a) =>
                (a['name'] ?? '').toLowerCase().contains(_q) ||
                (a['package'] ?? '').toLowerCase().contains(_q))
            .toList();
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      expand: false,
      builder: (_, ctrl) => Column(
        children: [
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Expanded(
                  child: Text('Выбор приложений',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, _sel.toList()),
                  child: const Text('OK'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              onChanged: (v) => setState(() => _q = v.toLowerCase()),
              decoration: const InputDecoration(
                  hintText: 'Поиск', prefixIcon: Icon(Icons.search, size: 18)),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    controller: ctrl,
                    itemCount: filtered.length,
                    itemBuilder: (_, i) {
                      final app = filtered[i];
                      final pkg = app['package'] ?? '';
                      final name = app['name'] ?? pkg;
                      return CheckboxListTile(
                        value: _sel.contains(pkg),
                        onChanged: (v) => setState(() {
                          if (v == true) {
                            _sel.add(pkg);
                          } else {
                            _sel.remove(pkg);
                          }
                        }),
                        title:
                            Text(name, style: const TextStyle(fontSize: 14)),
                        subtitle: Text(pkg,
                            style: const TextStyle(fontSize: 11)),
                        dense: true,
                        controlAffinity: ListTileControlAffinity.trailing,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
