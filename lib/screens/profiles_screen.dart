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

    return Scaffold(
      appBar: AppBar(title: Text(s.profilesTab)),
      body: vpn.profiles.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.vpn_key_outlined,
                      size: 64, color: const Color(0xFF2A3A4A)),
                  const SizedBox(height: 16),
                  Text(s.noProfiles,
                      style: const TextStyle(color: Color(0xFF3A4A5A))),
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
    final groups = <String?, List<VpnProfile>>{};
    for (final p in vpn.profiles) {
      groups.putIfAbsent(p.subscriptionUrl, () => []).add(p);
    }
    final subUrls = groups.keys.where((k) => k != null).cast<String>().toList();
    final standalone = groups[null] ?? [];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      children: [
        // подписки — каждая в своей карточке-группе
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
        // отдельные ключи
        if (standalone.isNotEmpty) ...[
          if (subUrls.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
              child: Text(
                s.standaloneKeys.toUpperCase(),
                style: const TextStyle(
                  fontSize: 10,
                  letterSpacing: 1.4,
                  color: Color(0xFF4A5A6A),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          for (final p in standalone) ...[
            _ProfileTile(
              profile: p,
              isActive: vpn.activeProfile?.id == p.id,
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

  String _shortUrl(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.host.isNotEmpty ? uri.host : url;
    } catch (_) {
      return url.length > 48 ? '${url.substring(0, 48)}…' : url;
    }
  }

  @override
  Widget build(BuildContext context) {
    final refreshing = vpn.isRefreshing(url);

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF1E1E38)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── заголовок подписки ─────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
            child: Row(
              children: [
                const Icon(Icons.link_rounded, size: 14, color: AppTheme.cyan),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _shortUrl(url),
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.cyan,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.2,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  '${profiles.length}',
                  style: const TextStyle(
                      fontSize: 11, color: Color(0xFF4A5A6A)),
                ),
                const SizedBox(width: 6),
                if (refreshing)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 1.5, color: AppTheme.cyan),
                  )
                else
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: () => vpn.refreshSubscription(url),
                      child: Tooltip(
                        message: s.refreshSubscription,
                        child: const Padding(
                          padding: EdgeInsets.all(6),
                          child: Icon(Icons.refresh_rounded,
                              size: 18, color: AppTheme.cyan),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFF1A1A2E)),
          // ── профили внутри ─────────────────────────────────────────────
          for (int i = 0; i < profiles.length; i++) ...[
            _InlineProfileTile(
              profile: profiles[i],
              isActive: vpn.activeProfile?.id == profiles[i].id,
              onTap: () => vpn.selectProfile(profiles[i]),
              onDelete: () => onDelete(profiles[i]),
            ),
            if (i < profiles.length - 1)
              const Divider(
                  height: 1, indent: 56, endIndent: 0,
                  color: Color(0xFF191929)),
          ],
        ],
      ),
    );
  }
}

// ── Inline tile (inside subscription group) ───────────────────────────────────

class _InlineProfileTile extends StatelessWidget {
  final VpnProfile profile;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _InlineProfileTile({
    required this.profile,
    required this.isActive,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(0),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
          child: Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: isActive
                    ? AppTheme.cyan.withOpacity(0.15)
                    : const Color(0xFF1A1A2E),
                child: Icon(
                  _icon(profile.protocol),
                  size: 16,
                  color: isActive ? AppTheme.cyan : const Color(0xFF3A4A5A),
                ),
              ),
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
                        color: isActive
                            ? AppTheme.cyan
                            : const Color(0xFFB0C4D8),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${profile.protocolLabel}  •  ${profile.serverHost}',
                      style: const TextStyle(
                          fontSize: 11, color: Color(0xFF4A5A6A)),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (isActive)
                const Padding(
                  padding: EdgeInsets.only(right: 4),
                  child: Icon(Icons.check_circle_rounded,
                      color: AppTheme.cyan, size: 16),
                ),
              IconButton(
                icon: const Icon(Icons.delete_outline,
                    size: 18, color: Color(0xFF3A4A5A)),
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

  IconData _icon(VpnProtocol p) => switch (p) {
        VpnProtocol.vless => Icons.security_rounded,
        VpnProtocol.wireguard => Icons.vpn_lock_rounded,
        VpnProtocol.tuic => Icons.bolt_rounded,
        VpnProtocol.hysteria2 => Icons.speed_rounded,
        VpnProtocol.amnezia => Icons.shield_rounded,
      };
}

// ── Standalone profile card tile ──────────────────────────────────────────────

class _ProfileTile extends StatelessWidget {
  final VpnProfile profile;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _ProfileTile({
    required this.profile,
    required this.isActive,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Card(
        color: isActive ? AppTheme.cyan.withOpacity(0.07) : AppTheme.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: isActive
              ? BorderSide(color: AppTheme.cyan.withOpacity(0.35))
              : const BorderSide(color: Color(0xFF1E1E38)),
        ),
        child: ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          leading: CircleAvatar(
            backgroundColor: isActive
                ? AppTheme.cyan.withOpacity(0.15)
                : const Color(0xFF1A1A2E),
            child: Icon(
              _icon(profile.protocol),
              size: 20,
              color: isActive ? AppTheme.cyan : const Color(0xFF3A4A5A),
            ),
          ),
          title: Text(profile.name,
              style: const TextStyle(fontWeight: FontWeight.w500)),
          subtitle: Text(
            '${profile.protocolLabel}  •  ${profile.serverHost}',
            style: const TextStyle(fontSize: 12, color: Color(0xFF4A5A6A)),
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isActive)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Icon(Icons.check_circle_rounded,
                      color: AppTheme.cyan, size: 18),
                ),
              IconButton(
                icon: const Icon(Icons.delete_outline,
                    size: 20, color: Color(0xFF3A4A5A)),
                onPressed: onDelete,
              ),
            ],
          ),
          onTap: onTap,
        ),
      ),
    );
  }

  IconData _icon(VpnProtocol p) => switch (p) {
        VpnProtocol.vless => Icons.security_rounded,
        VpnProtocol.wireguard => Icons.vpn_lock_rounded,
        VpnProtocol.tuic => Icons.bolt_rounded,
        VpnProtocol.hysteria2 => Icons.speed_rounded,
        VpnProtocol.amnezia => Icons.shield_rounded,
      };
}
