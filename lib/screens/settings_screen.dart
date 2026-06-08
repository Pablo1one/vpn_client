import 'dart:io';
import 'package:country_flags/country_flags.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/vpn_provider.dart';
import '../providers/language_provider.dart';
import '../providers/theme_provider.dart';
import '../services/update_service.dart';
import '../services/engine_versions_service.dart';
import '../utils/config_builder.dart';
import '../l10n/strings.dart';
import '../theme.dart';
import 'logs_screen.dart';
import 'conn_check_screen.dart';
import 'cdn_screen.dart';
import 'custom_rules_screen.dart';

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
          // ── Routing ─────────────────────────────────────────────────────
          _SectionHeader(s.routing),
          _RoutingModeSelector(vpn: vpn, s: s),
          if (vpn.routingMode == RoutingMode.custom) ...[
            const SizedBox(height: 4),
            _BypassDomainsTile(vpn: vpn, s: s),
          ],
          const Divider(height: 1),

          // ── Advanced (MUX / fragmentation / tls) ─────────────────────────
          _SectionHeader(s.advanced),
          SwitchListTile(
            title: Text(s.fragmentTitle),
            subtitle: Text(s.fragmentDesc),
            value: vpn.fragment,
            onChanged: vpn.isConnected ? null : vpn.setFragment,
          ),
          // режим по tls-записям - стойче против dpi, но ломает sni-роутинг на
          // некоторых серверах (включая наш haproxy), потому off by default
          if (vpn.fragment)
            SwitchListTile(
              title: const Text('Дробить по TLS-записям'),
              subtitle: const Text(
                  'стойче, но не для всех серверов (если страницы не грузятся - выключить)'),
              value: vpn.fragmentRecord,
              onChanged: vpn.isConnected ? null : vpn.setFragmentRecord,
            ),
          SwitchListTile(
            title: Text(s.muxTitle),
            subtitle: Text(s.muxDesc),
            value: vpn.mux,
            onChanged: vpn.isConnected ? null : vpn.setMux,
          ),
          SwitchListTile(
            secondary: Icon(Icons.block_rounded,
                size: 20, color: context.ac.textMuted),
            title: Text(s.adblockTitle),
            subtitle: Text(s.adblockDesc),
            value: vpn.blockAds,
            onChanged: vpn.isConnected ? null : vpn.setBlockAds,
          ),
          SwitchListTile(
            title: Text(s.allowInsecureTitle),
            subtitle: Text(s.allowInsecureDesc),
            value: vpn.allowInsecure,
            onChanged: vpn.isConnected ? null : vpn.setAllowInsecure,
          ),
          SwitchListTile(
            title: Text(s.tfoTitle),
            subtitle: Text(s.tfoDesc),
            value: vpn.tfo,
            onChanged: vpn.isConnected ? null : vpn.setTfo,
          ),
          SwitchListTile(
            title: Text(s.killSwitch),
            subtitle: Text(s.killSwitchDesc),
            value: vpn.killSwitch,
            onChanged: vpn.isConnected ? null : vpn.setKillSwitch,
          ),
          _DnsTile(vpn: vpn, s: s),
          ListTile(
            title: Text(s.subRefreshTitle),
            subtitle: Text(s.subRefreshDesc),
            trailing: DropdownButton<int>(
              value: vpn.subRefreshHours,
              underline: const SizedBox.shrink(),
              items: [
                DropdownMenuItem(value: 0, child: Text(s.subRefreshOff)),
                const DropdownMenuItem(value: 6, child: Text('6 ч')),
                const DropdownMenuItem(value: 12, child: Text('12 ч')),
                const DropdownMenuItem(value: 24, child: Text('24 ч')),
              ],
              onChanged: (v) {
                if (v != null) vpn.setSubRefreshHours(v);
              },
            ),
          ),
          if (Platform.isWindows)
            SwitchListTile(
              secondary: Icon(Icons.power_settings_new_rounded,
                  size: 20, color: context.ac.textMuted),
              title: Text(s.autostartTitle),
              subtitle: Text(s.autostartDesc),
              value: vpn.launchOnStartup,
              onChanged: vpn.setLaunchOnStartup,
            ),
          if (Platform.isWindows) const _RouteCleanupTile(),
          const Divider(height: 1),

          // ── warp ─────────────────────────────────────────────────────────
          _SectionHeader(s.warpTitle),
          SwitchListTile(
            secondary: Icon(Icons.public_rounded,
                size: 20, color: context.ac.textMuted),
            title: Text(s.warpCascadeTitle),
            subtitle: Text(s.warpCascadeDesc),
            value: vpn.warpCascade,
            onChanged: vpn.isConnected ? null : vpn.setWarpCascade,
          ),
          ListTile(
            leading: Icon(Icons.cloud_outlined,
                size: 20, color: context.ac.textMuted),
            title: Text(s.warpTitle),
            subtitle: Text(s.warpDesc),
            trailing: Icon(Icons.chevron_right,
                size: 20, color: context.ac.textMuted),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CdnScreen()),
            ),
          ),
          const Divider(height: 1),

          // ── Theme ────────────────────────────────────────────────────────
          _SectionHeader(s.themeSection),
          _ThemeSelector(s: s),
          const Divider(height: 1),

          // ── Updates ──────────────────────────────────────────────────────
          _SectionHeader(s.updates),
          const _UpdateTile(),
          const Divider(height: 1),

          // ── Cores & versions ─────────────────────────────────────────────
          _SectionHeader(s.coresTitle),
          const _CoresTile(),
          const Divider(height: 1),

          // ── Logs ─────────────────────────────────────────────────────────
          _SectionHeader(s.logs),
          ListTile(
            leading: Icon(Icons.receipt_long_outlined,
                size: 20, color: context.ac.textMuted),
            title: Text(s.logsTitle),
            trailing: Icon(Icons.chevron_right,
                size: 20, color: context.ac.textMuted),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const LogsScreen()),
            ),
          ),
          ListTile(
            leading: Icon(Icons.travel_explore_outlined,
                size: 20, color: context.ac.textMuted),
            title: Text(s.connCheck),
            trailing: Icon(Icons.chevron_right,
                size: 20, color: context.ac.textMuted),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ConnCheckScreen()),
            ),
          ),
          const Divider(height: 1),

          // ── Language ─────────────────────────────────────────────────────
          _SectionHeader(s.language),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: _LanguageSelector(lang: lang),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

}

// ── Кастомный dns ─────────────────────────────────────────────────────────────

class _DnsTile extends StatefulWidget {
  final VpnProvider vpn;
  final L10n s;
  const _DnsTile({required this.vpn, required this.s});

  @override
  State<_DnsTile> createState() => _DnsTileState();
}

class _DnsTileState extends State<_DnsTile> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.vpn.dns);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: TextField(
        controller: _ctrl,
        enabled: !widget.vpn.isConnected,
        decoration: InputDecoration(
          labelText: widget.s.dnsTitle,
          hintText: widget.s.dnsHint,
          isDense: true,
          prefixIcon: const Icon(Icons.dns_outlined, size: 18),
        ),
        onChanged: (v) => widget.vpn.setDns(v),
      ),
    );
  }
}

// ── Параметры tls-фрагментации (показываются при включённой фрагментации) ─────

// ── Section header ────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
        child: Text(
          title.toUpperCase(),
          style: TextStyle(
            fontSize: 10,
            letterSpacing: 1.4,
            color: context.ac.primary,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
}

// ── Theme selector ────────────────────────────────────────────────────────────

class _ThemeSelector extends StatelessWidget {
  final L10n s;
  const _ThemeSelector({required this.s});

  @override
  Widget build(BuildContext context) {
    final c = context.ac;
    final themeP = context.watch<ThemeProvider>();
    final current = themeP.themeName;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Wrap(
        spacing: 10,
        children: [
          _ThemeChip(
            label: s.themeMcQueen,
            icon: Icons.wb_sunny_rounded,
            selected: current == AppThemeName.lightningMcQueen,
            color: const Color(0xFFCC1100),
            onTap: () =>
                themeP.setTheme(AppThemeName.lightningMcQueen),
          ),
          _ThemeChip(
            label: s.themeJackson,
            icon: Icons.nights_stay_rounded,
            selected: current == AppThemeName.jacksonStorm,
            color: c.primary,
            onTap: () => themeP.setTheme(AppThemeName.jacksonStorm),
          ),
        ],
      ),
    );
  }
}

class _ThemeChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  const _ThemeChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.ac;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected
                ? color.withOpacity(0.12)
                : c.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected
                  ? color.withOpacity(0.5)
                  : c.border,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  size: 15,
                  color: selected ? color : c.textMuted),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected
                      ? FontWeight.w600
                      : FontWeight.w400,
                  color: selected ? color : c.textSecondary,
                ),
              ),
              if (selected) ...[
                const SizedBox(width: 6),
                Icon(Icons.check_rounded, size: 13, color: color),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── Language selector ─────────────────────────────────────────────────────────

class _LanguageSelector extends StatelessWidget {
  final LanguageProvider lang;
  const _LanguageSelector({required this.lang});

  @override
  Widget build(BuildContext context) {
    final current = lang.locale.languageCode;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _LangButton(
          countryCode: 'RU',
          label: 'RU',
          selected: current == 'ru',
          onTap: () => lang.setLocale(const Locale('ru')),
        ),
        const SizedBox(width: 8),
        _LangButton(
          countryCode: 'US',
          label: 'EN',
          selected: current == 'en',
          onTap: () => lang.setLocale(const Locale('en')),
        ),
      ],
    );
  }
}

class _LangButton extends StatelessWidget {
  final String countryCode;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _LangButton({
    required this.countryCode,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.ac;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: selected ? c.primary.withOpacity(0.12) : c.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? c.primary.withOpacity(0.4) : c.border,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: CountryFlag.fromCountryCode(
                    countryCode, width: 20, height: 14),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight:
                      selected ? FontWeight.w600 : FontWeight.w400,
                  color: selected ? c.primary : c.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Routing mode selector ─────────────────────────────────────────────────────

class _RoutingModeSelector extends StatelessWidget {
  final VpnProvider vpn;
  final L10n s;
  const _RoutingModeSelector({required this.vpn, required this.s});

  @override
  Widget build(BuildContext context) {
    final c = context.ac;
    final rulesCount = vpn.customRules.length;
    final active = rulesCount > 0;
    // активные правила: мятно-зелёный (тёмная тема) / светло-оранжевый (светлая)
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent =
        isDark ? const Color(0xFF6EE7B7) : const Color(0xFFFFB74D);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // взаимоисключающие режимы маршрутизации
          Wrap(
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
          // свои правила - независимый оверлей поверх любого режима (как раньше
          // был чип «приложения мимо VPN»)
          const SizedBox(height: 8),
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const CustomRulesScreen()),
              ),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: active ? accent.withOpacity(0.15) : c.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: active ? accent.withOpacity(0.6) : c.border,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.rule,
                        size: 16, color: active ? accent : c.textMuted),
                    const SizedBox(width: 8),
                    Text(
                      active ? 'Свои правила ($rulesCount)' : 'Свои правила',
                      style: TextStyle(
                        fontSize: 13,
                        color: active ? c.textPrimary : c.textMuted,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(Icons.chevron_right, size: 16, color: c.textMuted),
                  ],
                ),
              ),
            ),
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
  Widget build(BuildContext context) {
    final c = context.ac;
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: c.primary.withOpacity(0.15),
      checkmarkColor: c.primary,
      labelStyle: TextStyle(
          color: selected ? c.primary : c.textMuted, fontSize: 13),
      side: BorderSide(
          color: selected ? c.primary.withOpacity(0.4) : c.border),
      backgroundColor: c.surface,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      showCheckmark: false,
    );
  }
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
        ),
        trailing: Icon(Icons.chevron_right,
            size: 20, color: context.ac.textMuted),
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
                style: TextStyle(
                    fontSize: 13, color: context.ac.textSecondary)),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              maxLines: 8,
              style:
                  const TextStyle(fontSize: 13, fontFamily: 'monospace'),
              decoration: InputDecoration(hintText: s.bypassDomainsHint),
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


// ── Cores & versions tile ──────────────────────────────────────────────────────

class _CoresTile extends StatefulWidget {
  const _CoresTile();

  @override
  State<_CoresTile> createState() => _CoresTileState();
}

class _CoresTileState extends State<_CoresTile> {
  EngineVersions? _v;

  @override
  void initState() {
    super.initState();
    EngineVersionService().load().then((v) {
      if (mounted) setState(() => _v = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ac;
    final v = _v;
    final rows = <(String, String)>[
      ('LightningMcQueen', v?.app ?? '…'),
      ('Xray-core', v?.xray ?? '…'),
      ('sing-box', v?.singbox ?? '…'),
      ('AmneziaWG', v?.amneziawg ?? '…'),
      ('WinTun', v?.wintun ?? '…'),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      child: Column(
        children: [
          for (final (name, ver) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(name,
                        style: TextStyle(fontSize: 13, color: c.textSecondary)),
                  ),
                  Text(
                    ver,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: c.textPrimary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ── Route cleanup tile ──────────────────────────────────────────────────────

class _RouteCleanupTile extends StatefulWidget {
  const _RouteCleanupTile();

  @override
  State<_RouteCleanupTile> createState() => _RouteCleanupTileState();
}

class _RouteCleanupTileState extends State<_RouteCleanupTile> {
  bool _running = false;

  Future<void> _run() async {
    setState(() => _running = true);
    final vpn = context.read<VpnProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final n = await vpn.cleanBypassRoutes();
    if (!mounted) return;
    setState(() => _running = false);
    messenger.showSnackBar(SnackBar(
      content: Text(n > 0
          ? 'Удалено маршрутов в обход VPN: $n'
          : 'Маршрутов в обход VPN не найдено'),
      duration: const Duration(seconds: 2),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ac;
    return ListTile(
      leading: Icon(Icons.alt_route_rounded, size: 20, color: c.textMuted),
      title: const Text('Очистить маршруты в обход VPN'),
      subtitle: Text(
        'Удаляет чужие маршруты (split-tunnel других VPN), уводящие трафик мимо туннеля',
        style: TextStyle(fontSize: 12, color: c.textMuted),
      ),
      trailing: _running
          ? SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: c.primary),
            )
          : TextButton(onPressed: _run, child: const Text('Очистить')),
    );
  }
}

// ── Update tile ───────────────────────────────────────────────────────────────

enum _UpdateState { idle, checking, upToDate, available, downloading, error }

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
  double _progress = 0;

  @override
  void initState() {
    super.initState();
    _svc.currentVersion().then((v) {
      if (mounted) setState(() => _currentVersion = v);
    });
  }

  Future<void> _check() async {
    setState(() => _state = _UpdateState.checking);
    try {
      final info = await _svc.check();
      if (!mounted) return;
      setState(() {
        _info = info;
        _state = info != null ? _UpdateState.available : _UpdateState.upToDate;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _state = _UpdateState.error);
    }
  }

  Future<void> _downloadAndRun() async {
    if (_info == null) return;
    setState(() {
      _state = _UpdateState.downloading;
      _progress = 0;
    });
    try {
      await _svc.downloadAndRun(_info!, onProgress: (p) {
        if (mounted) setState(() => _progress = p);
      });
      // при успехе приложение закрывается из downloadAndRun (exit 0)
    } catch (_) {
      if (!mounted) return;
      // фоллбэк - открыть страницу релиза в браузере
      await launchUrl(Uri.parse(_info!.downloadUrl),
          mode: LaunchMode.externalApplication);
      if (mounted) setState(() => _state = _UpdateState.available);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ac;
    final s = L10n.of(context);
    final sub = switch (_state) {
      _UpdateState.checking => s.checkingForUpdates,
      _UpdateState.upToDate => s.upToDate,
      _UpdateState.error => s.updateCheckFailed,
      _UpdateState.available => '${s.updateAvailable}: v${_info!.version}',
      _UpdateState.downloading =>
        'Загрузка… ${(_progress * 100).toStringAsFixed(0)}%',
      _UpdateState.idle =>
        _currentVersion.isNotEmpty ? '${s.version} $_currentVersion' : '',
    };

    return ListTile(
      title: Text(s.checkForUpdates),
      subtitle: sub.isNotEmpty
          ? Text(sub,
              style: TextStyle(
                fontSize: 12,
                color: _state == _UpdateState.available
                    ? c.primary
                    : c.textMuted,
              ))
          : null,
      trailing: _state == _UpdateState.checking
          ? SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: c.primary),
            )
          : _state == _UpdateState.downloading
              ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: c.primary,
                      value: _progress > 0 ? _progress : null),
                )
              : _state == _UpdateState.available
                  ? FilledButton.tonal(
                      onPressed: _downloadAndRun,
                      style: FilledButton.styleFrom(
                        backgroundColor: c.primary.withOpacity(0.15),
                        foregroundColor: c.primary,
                      ),
                      child: Text(s.download),
                    )
                  : TextButton(
                      onPressed:
                          _state == _UpdateState.checking ? null : _check,
                      child: Text(s.checkForUpdates),
                    ),
    );
  }
}
