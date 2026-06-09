import 'package:country_flags/country_flags.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/vpn_provider.dart';
import '../providers/language_provider.dart';
import '../models/profile.dart';
import '../l10n/strings.dart';
import '../theme.dart';
import 'import_screen.dart';

class ProfilesScreen extends StatelessWidget {
  const ProfilesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final vpn = context.watch<VpnProvider>();
    context.watch<LanguageProvider>();
    final s = L10n.of(context);
    final c = context.ac;

    return Scaffold(
      appBar: AppBar(
        title: Text(s.profilesTab),
        actions: [
          if (vpn.profiles.isNotEmpty) ...[
            IconButton(
              icon: const Icon(Icons.bolt_rounded),
              tooltip: 'Подключиться к быстрейшему',
              onPressed: vpn.pinging ? null : () => _connectFastest(context),
            ),
            vpn.pinging
                ? const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : IconButton(
                    icon: const Icon(Icons.speed_rounded),
                    tooltip: vpn.isConnected
                        ? 'Отключитесь для измерения пинга'
                        : 'Пинг',
                    onPressed: vpn.isConnected ? null : vpn.pingAll,
                  ),
          ],
        ],
      ),
      body: vpn.profiles.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.vpn_key_outlined, size: 64, color: c.textMuted),
                  const SizedBox(height: 16),
                  Text(s.noProfiles,
                      style: TextStyle(color: c.textMuted)),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: () => _openImport(context),
                    icon: const Icon(Icons.add),
                    label: Text(s.importProfile),
                  ),
                ],
              ),
            )
          : _ProfileList(vpn: vpn, s: s),
      floatingActionButton: vpn.profiles.isEmpty
          ? null
          : FloatingActionButton(
              onPressed: () => _openImport(context),
              child: const Icon(Icons.add),
            ),
    );
  }

  Future<void> _connectFastest(BuildContext context) async {
    final vpn = context.read<VpnProvider>();
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(
        content: Text('Ищу быстрейший сервер…'),
        duration: Duration(seconds: 2)));
    final best = await vpn.connectFastest();
    if (!context.mounted) return;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      content: Text(best == null
          ? 'Не удалось измерить пинг ни одного сервера'
          : 'Быстрейший: ${best.name}'),
      duration: const Duration(seconds: 2),
    ));
  }

  void _openImport(BuildContext context) => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ImportScreen()),
      );
}

// ── Grouped list ──────────────────────────────────────────────────────────────

class _ProfileList extends StatelessWidget {
  final VpnProvider vpn;
  final L10n s;
  const _ProfileList({required this.vpn, required this.s});

  @override
  Widget build(BuildContext context) {
    final c = context.ac;
    final groups = <String?, List<VpnProfile>>{};
    for (final p in vpn.profiles) {
      groups.putIfAbsent(p.subscriptionUrl, () => []).add(p);
    }
    final subUrls =
        groups.keys.where((k) => k != null).cast<String>().toList();
    final standalone = groups[null] ?? [];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      children: [
        for (final url in subUrls) ...[
          _SubscriptionGroup(
            url: url,
            profiles: groups[url]!,
            vpn: vpn,
            s: s,
            onDelete: (p) => _confirmDelete(context, vpn, p, s),
          ),
          const SizedBox(height: 12),
        ],
        if (standalone.isNotEmpty) ...[
          if (subUrls.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
              child: Text(
                s.standaloneKeys.toUpperCase(),
                style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 1.4,
                  color: c.textMuted,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          for (final p in standalone) ...[
            _ProfileTile(
              profile: p,
              isActive: vpn.activeProfile?.id == p.id,
              pingMs: vpn.pingResults[p.id],
              hasPing: vpn.pingResults.containsKey(p.id),
              onTap: () => vpn.selectProfile(p),
              onDelete: () => _confirmDelete(context, vpn, p, s),
            ),
            const SizedBox(height: 8),
          ],
        ],
      ],
    );
  }

  Future<void> _confirmDelete(
      BuildContext context, VpnProvider vpn, VpnProfile p, L10n s) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(s.deleteProfile),
        content: Text(p.name),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(s.cancel)),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(s.delete)),
        ],
      ),
    );
    if (confirm == true) vpn.removeProfile(p.id);
  }
}

// ── Subscription group card ───────────────────────────────────────────────────

class _SubscriptionGroup extends StatelessWidget {
  final String url;
  final List<VpnProfile> profiles;
  final VpnProvider vpn;
  final L10n s;
  final void Function(VpnProfile) onDelete;

  const _SubscriptionGroup({
    required this.url,
    required this.profiles,
    required this.vpn,
    required this.s,
    required this.onDelete,
  });

  String _shortUrl(String u) {
    try {
      final uri = Uri.parse(u);
      return uri.host.isNotEmpty ? uri.host : u;
    } catch (_) {
      return u.length > 48 ? '${u.substring(0, 48)}…' : u;
    }
  }

  Future<void> _confirmDeleteSubscription(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(s.deleteSubscription),
        content: Text('${_shortUrl(url)}\n${profiles.length}'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(s.cancel)),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(s.delete)),
        ],
      ),
    );
    if (confirm == true) vpn.removeSubscription(url);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ac;
    final refreshing = vpn.isRefreshing(url);

    return Container(
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
            child: Row(
              children: [
                Icon(Icons.link_rounded, size: 14, color: c.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _shortUrl(url),
                    style: TextStyle(
                      fontSize: 12,
                      color: c.primary,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.2,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  '${profiles.length}',
                  style: TextStyle(fontSize: 11, color: c.textMuted),
                ),
                const SizedBox(width: 6),
                if (refreshing)
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 1.5, color: c.primary),
                  )
                else
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: () => vpn.refreshSubscription(url),
                      child: Tooltip(
                        message: s.refreshSubscription,
                        child: Padding(
                          padding: const EdgeInsets.all(6),
                          child: Icon(Icons.refresh_rounded,
                              size: 18, color: c.primary),
                        ),
                      ),
                    ),
                  ),
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () => _confirmDeleteSubscription(context),
                    child: Tooltip(
                      message: s.deleteSubscription,
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Icon(Icons.delete_sweep_rounded,
                            size: 18, color: c.textMuted),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: c.border),
          for (int i = 0; i < profiles.length; i++) ...[
            _InlineProfileTile(
              profile: profiles[i],
              isActive: vpn.activeProfile?.id == profiles[i].id,
              pingMs: vpn.pingResults[profiles[i].id],
              hasPing: vpn.pingResults.containsKey(profiles[i].id),
              onTap: () => vpn.selectProfile(profiles[i]),
              onDelete: () => onDelete(profiles[i]),
            ),
            if (i < profiles.length - 1)
              Divider(
                  height: 1,
                  indent: 56,
                  endIndent: 0,
                  color: c.borderFaint),
          ],
        ],
      ),
    );
  }
}

// ── Avatar: флаг страны + бейдж протокола ──────────────────────────────────────

IconData _protoIcon(VpnProtocol p) => switch (p) {
      VpnProtocol.vless => Icons.security_rounded,
      VpnProtocol.wireguard => Icons.vpn_lock_rounded,
      VpnProtocol.tuic => Icons.bolt_rounded,
      VpnProtocol.hysteria2 => Icons.speed_rounded,
      VpnProtocol.amnezia => Icons.shield_rounded,
    };

class _ProfileAvatar extends StatelessWidget {
  final VpnProfile profile;
  final bool isActive;
  final double radius;
  const _ProfileAvatar({
    required this.profile,
    required this.isActive,
    this.radius = 16,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.ac;
    final cc = context.read<VpnProvider>().countryCodeFor(profile.serverHost);
    final fg = isActive ? c.primary : c.textMuted;
    final bg = isActive ? c.primary.withValues(alpha: 0.15) : c.avatarBg;
    final hasFlag = cc != null && cc.length == 2;

    if (!hasFlag) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: bg,
        child: Icon(_protoIcon(profile.protocol), size: radius, color: fg),
      );
    }

    return SizedBox(
      width: radius * 2,
      height: radius * 2,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ClipOval(
            child: CountryFlag.fromCountryCode(
              cc.toUpperCase(),
              width: radius * 2,
              height: radius * 2,
            ),
          ),
          Positioned(
            right: -2,
            bottom: -2,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: c.card,
                shape: BoxShape.circle,
                border: Border.all(color: c.border, width: 0.5),
              ),
              child: Icon(_protoIcon(profile.protocol),
                  size: radius * 0.72, color: fg),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Ping badge ────────────────────────────────────────────────────────────────

class _PingBadge extends StatelessWidget {
  final int? ms;
  final bool hasPing;
  const _PingBadge({required this.ms, required this.hasPing});

  @override
  Widget build(BuildContext context) {
    if (!hasPing) return const SizedBox.shrink();
    final color = ms == null
        ? Colors.red
        : ms! < 150
            ? const Color(0xFF44DD66)
            : ms! < 400
                ? Colors.orange
                : Colors.red;
    return Container(
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        ms == null ? '—' : '${ms}ms',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

// ── Inline tile (inside subscription group) ───────────────────────────────────

class _InlineProfileTile extends StatelessWidget {
  final VpnProfile profile;
  final bool isActive;
  final int? pingMs;
  final bool hasPing;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _InlineProfileTile({
    required this.profile,
    required this.isActive,
    required this.pingMs,
    required this.hasPing,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.ac;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(0),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
          child: Row(
            children: [
              _ProfileAvatar(profile: profile, isActive: isActive, radius: 16),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile.name,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: isActive ? c.primary : c.textPrimary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${profile.protocolLabel}  •  ${profile.serverHost}',
                      style: TextStyle(fontSize: 11, color: c.textMuted),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              _PingBadge(ms: pingMs, hasPing: hasPing),
              if (isActive)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Icon(Icons.check_circle_rounded,
                      color: c.primary, size: 16),
                ),
              IconButton(
                icon: Icon(Icons.delete_outline,
                    size: 18, color: c.textMuted),
                onPressed: onDelete,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                visualDensity: VisualDensity.compact,
              ),
              const SizedBox(width: 4),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Standalone profile card tile ──────────────────────────────────────────────

class _ProfileTile extends StatelessWidget {
  final VpnProfile profile;
  final bool isActive;
  final int? pingMs;
  final bool hasPing;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _ProfileTile({
    required this.profile,
    required this.isActive,
    required this.pingMs,
    required this.hasPing,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.ac;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Card(
        color: isActive ? c.primary.withValues(alpha: 0.07) : c.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: isActive
              ? BorderSide(color: c.primary.withValues(alpha: 0.35))
              : BorderSide(color: c.border),
        ),
        child: ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          leading: _ProfileAvatar(
              profile: profile, isActive: isActive, radius: 20),
          title: Text(profile.name,
              style: const TextStyle(fontWeight: FontWeight.w500)),
          subtitle: Text(
            '${profile.protocolLabel}  •  ${profile.serverHost}',
            style: TextStyle(fontSize: 12, color: c.textMuted),
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _PingBadge(ms: pingMs, hasPing: hasPing),
              if (isActive)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Icon(Icons.check_circle_rounded,
                      color: c.primary, size: 18),
                ),
              IconButton(
                icon: Icon(Icons.delete_outline,
                    size: 20, color: c.textMuted),
                onPressed: onDelete,
              ),
            ],
          ),
          onTap: onTap,
        ),
      ),
    );
  }
}
