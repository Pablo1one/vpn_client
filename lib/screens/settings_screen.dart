import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/vpn_provider.dart';
import '../providers/language_provider.dart';
import '../services/update_service.dart';
import '../utils/config_builder.dart';
import '../l10n/strings.dart';
import '../theme.dart';
import 'logs_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final vpn = context.watch<VpnProvider>();
    context.watch<LanguageProvider>();
    final s = L10n.of(context);
    final lang = context.read<LanguageProvider>();

    return Scaffold(
      appBar: AppBar(title: Text(s.settingsTab)),
      body: ListView(
        children: [
          // ── Connection ──────────────────────────────────────────────────
          _SectionHeader(s.connection),
          SwitchListTile(
            title: Text(s.killSwitch),
            subtitle: Text(s.killSwitchDesc),
            value: vpn.killSwitch,
            onChanged: vpn.setKillSwitch,
          ),
          const Divider(height: 1),

          // ── Routing ─────────────────────────────────────────────────────
          _SectionHeader(s.routing),
          _RoutingModeSelector(vpn: vpn, s: s),
          if (vpn.routingMode == RoutingMode.custom) ...[
            const SizedBox(height: 4),
            _BypassDomainsTile(vpn: vpn, s: s),
          ],
          const Divider(height: 1),

          // ── Per-app (Android only) ───────────────────────────────────────
          if (Platform.isAndroid) ...[
            _SectionHeader(s.perApp),
            ListTile(
              title: Text(s.excludedApps),
              subtitle: Text(
                vpn.excludedApps.isEmpty
                    ? s.noExcludedApps
                    : '${vpn.excludedApps.length} app(s)',
                style:
                    const TextStyle(fontSize: 12, color: Color(0xFF5A6480)),
              ),
              trailing: const Icon(Icons.chevron_right,
                  size: 20, color: Color(0xFF5A6480)),
              onTap: () => _openAppPicker(context, vpn, s),
            ),
            const Divider(height: 1),
          ],

          // ── Updates ──────────────────────────────────────────────────────
          _SectionHeader(s.updates),
          const _UpdateTile(),
          const Divider(height: 1),

          // ── Logs ─────────────────────────────────────────────────────────
          _SectionHeader(s.logs),
          ListTile(
            leading: const Icon(Icons.receipt_long_outlined,
                size: 20, color: Color(0xFF5A6480)),
            title: Text(s.logsTitle),
            trailing: const Icon(Icons.chevron_right,
                size: 20, color: Color(0xFF5A6480)),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const LogsScreen()),
            ),
          ),
          const Divider(height: 1),

          // ── Language ─────────────────────────────────────────────────────
          _SectionHeader(s.language),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'ru', label: Text('Русский')),
                ButtonSegment(value: 'en', label: Text('English')),
              ],
              selected: {lang.locale.languageCode},
              onSelectionChanged: (v) =>
                  lang.setLocale(Locale(v.first)),
              style: ButtonStyle(
                backgroundColor: WidgetStateProperty.resolveWith((s) =>
                    s.contains(WidgetState.selected)
                        ? AppTheme.cyan.withOpacity(0.15)
                        : Colors.transparent),
                foregroundColor: WidgetStateProperty.resolveWith((s) =>
                    s.contains(WidgetState.selected)
                        ? AppTheme.cyan
                        : const Color(0xFF5A6480)),
                side: WidgetStateProperty.all(
                    const BorderSide(color: Color(0xFF2A2A4A))),
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Future<void> _openAppPicker(
      BuildContext context, VpnProvider vpn, L10n s) async {
    final result = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.card,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _AppPickerSheet(
        excluded: vpn.excludedApps,
        loadApps: vpn.getInstalledApps,
        s: s,
      ),
    );
    if (result != null) vpn.setExcludedApps(result);
  }
}

// ── Section header ────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
        child: Text(
          title.toUpperCase(),
          style: const TextStyle(
            fontSize: 10,
            letterSpacing: 1.4,
            color: AppTheme.cyan,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
}

// ── Routing mode selector ─────────────────────────────────────────────────────

class _RoutingModeSelector extends StatelessWidget {
  final VpnProvider vpn;
  final L10n s;
  const _RoutingModeSelector({required this.vpn, required this.s});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Wrap(
        spacing: 8,
        children: [
          _ModeChip(
            label: s.routingFull,
            selected: vpn.routingMode == RoutingMode.fullVpn,
            onTap: () => vpn.setRoutingMode(RoutingMode.fullVpn),
          ),
          _ModeChip(
            label: s.routingRussia,
            selected: vpn.routingMode == RoutingMode.russiaBypass,
            onTap: () => vpn.setRoutingMode(RoutingMode.russiaBypass),
          ),
          _ModeChip(
            label: s.routingCustom,
            selected: vpn.routingMode == RoutingMode.custom,
            onTap: () => vpn.setRoutingMode(RoutingMode.custom),
          ),
        ],
      ),
    );
  }
}

class _ModeChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _ModeChip(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => FilterChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
        selectedColor: AppTheme.cyan.withOpacity(0.15),
        checkmarkColor: AppTheme.cyan,
        labelStyle: TextStyle(
            color: selected ? AppTheme.cyan : const Color(0xFF8090A8),
            fontSize: 13),
        side: BorderSide(
            color: selected
                ? AppTheme.cyan.withOpacity(0.4)
                : const Color(0xFF2A2A4A)),
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        showCheckmark: false,
      );
}

// ── Bypass domains tile ───────────────────────────────────────────────────────

class _BypassDomainsTile extends StatelessWidget {
  final VpnProvider vpn;
  final L10n s;
  const _BypassDomainsTile({required this.vpn, required this.s});

  @override
  Widget build(BuildContext context) => ListTile(
        title: Text(s.bypassDomains),
        subtitle: Text(
          vpn.bypassDomains.isEmpty
              ? s.bypassDomainsDesc
              : vpn.bypassDomains.join(', '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12, color: Color(0xFF5A6480)),
        ),
        trailing: const Icon(Icons.chevron_right,
            size: 20, color: Color(0xFF5A6480)),
        onTap: () => _editBypass(context),
      );

  Future<void> _editBypass(BuildContext context) async {
    final ctrl = TextEditingController(text: vpn.bypassDomains.join('\n'));
    final result = await showDialog<List<String>>(
      context: context,
      builder: (_) => _BypassDialog(controller: ctrl, s: s),
    );
    if (result != null) vpn.setBypassDomains(result);
  }
}

class _BypassDialog extends StatelessWidget {
  final TextEditingController controller;
  final L10n s;
  const _BypassDialog({required this.controller, required this.s});

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(s.bypassDomains),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s.bypassDomainsDesc,
                style: const TextStyle(
                    fontSize: 13, color: Color(0xFF5A6480))),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              maxLines: 8,
              style:
                  const TextStyle(fontSize: 13, fontFamily: 'monospace'),
              decoration: InputDecoration(
                hintText: s.bypassDomainsHint,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(s.cancel),
          ),
          FilledButton(
            onPressed: () {
              final lines = controller.text
                  .split('\n')
                  .map((l) => l.trim())
                  .where((l) => l.isNotEmpty)
                  .toList();
              Navigator.pop(context, lines);
            },
            child: const Text('OK'),
          ),
        ],
      );
}

// ── App picker sheet ──────────────────────────────────────────────────────────

class _AppPickerSheet extends StatefulWidget {
  final List<String> excluded;
  final Future<List<Map<String, String>>> Function() loadApps;
  final L10n s;

  const _AppPickerSheet({
    required this.excluded,
    required this.loadApps,
    required this.s,
  });

  @override
  State<_AppPickerSheet> createState() => _AppPickerSheetState();
}

class _AppPickerSheetState extends State<_AppPickerSheet> {
  List<Map<String, String>> _apps = [];
  Set<String> _selected = {};
  String _query = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _selected = Set.from(widget.excluded);
    _load();
  }

  Future<void> _load() async {
    final apps = await widget.loadApps();
    if (mounted) {
      setState(() {
        _apps = apps;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _query.isEmpty
        ? _apps
        : _apps
            .where((a) =>
                (a['name'] ?? '').toLowerCase().contains(_query) ||
                (a['package'] ?? '').toLowerCase().contains(_query))
            .toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      expand: false,
      builder: (_, ctrl) => Column(
        children: [
          // Handle
          const SizedBox(height: 12),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFF3A4060),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.s.perApp,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
                FilledButton(
                  onPressed: () =>
                      Navigator.pop(context, _selected.toList()),
                  child: const Text('OK'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              onChanged: (v) =>
                  setState(() => _query = v.toLowerCase()),
              decoration: InputDecoration(
                hintText: widget.s.searchApps,
                prefixIcon: const Icon(Icons.search, size: 18),
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: AppTheme.cyan))
                : ListView.builder(
                    controller: ctrl,
                    itemCount: filtered.length,
                    itemBuilder: (_, i) {
                      final app = filtered[i];
                      final pkg = app['package'] ?? '';
                      final name = app['name'] ?? pkg;
                      final checked = _selected.contains(pkg);
                      return CheckboxListTile(
                        value: checked,
                        onChanged: (v) => setState(() {
                          if (v == true) {
                            _selected.add(pkg);
                          } else {
                            _selected.remove(pkg);
                          }
                        }),
                        title: Text(name,
                            style: const TextStyle(fontSize: 14)),
                        subtitle: Text(pkg,
                            style: const TextStyle(
                                fontSize: 11, color: Color(0xFF4A5A6A))),
                        activeColor: AppTheme.cyan,
                        checkColor: Colors.black,
                        controlAffinity: ListTileControlAffinity.trailing,
                        dense: true,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ── Update tile ───────────────────────────────────────────────────────────────

enum _UpdateState { idle, checking, upToDate, available }

class _UpdateTile extends StatefulWidget {
  const _UpdateTile();

  @override
  State<_UpdateTile> createState() => _UpdateTileState();
}

class _UpdateTileState extends State<_UpdateTile> {
  final _svc = UpdateService();
  _UpdateState _state = _UpdateState.idle;
  UpdateInfo? _info;
  String _currentVersion = '';

  @override
  void initState() {
    super.initState();
    _svc.currentVersion().then((v) {
      if (mounted) setState(() => _currentVersion = v);
    });
  }

  Future<void> _check() async {
    setState(() => _state = _UpdateState.checking);
    final info = await _svc.check();
    if (!mounted) return;
    setState(() {
      _info = info;
      _state = info != null ? _UpdateState.available : _UpdateState.upToDate;
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = L10n.of(context);
    final sub = switch (_state) {
      _UpdateState.checking => s.checkingForUpdates,
      _UpdateState.upToDate => s.upToDate,
      _UpdateState.available => '${s.updateAvailable}: v${_info!.version}',
      _UpdateState.idle => _currentVersion.isNotEmpty
          ? '${s.version} $_currentVersion'
          : '',
    };

    return ListTile(
      title: Text(s.checkForUpdates),
      subtitle: sub.isNotEmpty
          ? Text(sub,
              style: TextStyle(
                fontSize: 12,
                color: _state == _UpdateState.available
                    ? AppTheme.cyan
                    : const Color(0xFF5A6480),
              ))
          : null,
      trailing: _state == _UpdateState.checking
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: AppTheme.cyan),
            )
          : _state == _UpdateState.available
              ? FilledButton.tonal(
                  onPressed: () => launchUrl(Uri.parse(_info!.downloadUrl),
                      mode: LaunchMode.externalApplication),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.cyan.withOpacity(0.15),
                    foregroundColor: AppTheme.cyan,
                  ),
                  child: Text(s.download),
                )
              : TextButton(
                  onPressed: _state == _UpdateState.checking ? null : _check,
                  child: Text(s.checkForUpdates),
                ),
    );
  }
}
