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

class _ProfileList extends StatelessWidget {
  final VpnProvider vpn;
  final L10n s;
  const _ProfileList({required this.vpn, required this.s});

  @override
  Widget build(BuildContext context) {
    // группируем по subscriptionUrl
    final groups = <String?, List<VpnProfile>>{};
    for (final p in vpn.profiles) {
      groups.putIfAbsent(p.subscriptionUrl, () => []).add(p);
    }
    final subUrls = groups.keys.where((k) => k != null).cast<String>().toList();
    final standalone = groups[null] ?? [];

    final items = <Widget>[];

    for (final url in subUrls) {
      items.add(_SubscriptionHeader(url: url, vpn: vpn, s: s));
      for (final p in groups[url]!) {
        items.add(_ProfileTile(
          profile: p,
          isActive: vpn.activeProfile?.id == p.id,
          onTap: () => vpn.selectProfile(p),
          onDelete: () => _confirmDelete(context, vpn, p, s),
        ));
      }
      items.add(const SizedBox(height: 4));
    }

    if (standalone.isNotEmpty) {
      if (subUrls.isNotEmpty) {
        items.add(_SectionLabel(s.standaloneKeys));
      }
      for (final p in standalone) {
        items.add(_ProfileTile(
          profile: p,
          isActive: vpn.activeProfile?.id == p.id,
          onTap: () => vpn.selectProfile(p),
          onDelete: () => _confirmDelete(context, vpn, p, s),
        ));
      }
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      children: [
        for (final w in items) ...[w, if (w is _ProfileTile) const SizedBox(height: 8)],
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

class _SectionLabel extends StatelessWidget {
  final String title;
  const _SectionLabel(this.title);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
        child: Text(
          title.toUpperCase(),
          style: const TextStyle(
            fontSize: 10,
            letterSpacing: 1.4,
            color: Color(0xFF4A5A6A),
            fontWeight: FontWeight.w700,
          ),
        ),
      );
}

class _SubscriptionHeader extends StatelessWidget {
  final String url;
  final VpnProvider vpn;
  final L10n s;
  const _SubscriptionHeader(
      {required this.url, required this.vpn, required this.s});

  String _shortUrl(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.host.isNotEmpty ? uri.host : url;
    } catch (_) {
      return url.length > 40 ? '${url.substring(0, 40)}…' : url;
    }
  }

  @override
  Widget build(BuildContext context) {
    final refreshing = vpn.isRefreshing(url);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 0, 4),
      child: Row(
        children: [
          const Icon(Icons.link_rounded, size: 14, color: AppTheme.cyan),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              _shortUrl(url),
              style: const TextStyle(
                fontSize: 11,
                letterSpacing: 0.3,
                color: AppTheme.cyan,
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (refreshing)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                  strokeWidth: 1.5, color: AppTheme.cyan),
            )
          else
            IconButton(
              icon: const Icon(Icons.refresh_rounded,
                  size: 18, color: AppTheme.cyan),
              tooltip: s.refreshSubscription,
              onPressed: () => vpn.refreshSubscription(url),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              visualDensity: VisualDensity.compact,
            ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}

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
    return Card(
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
