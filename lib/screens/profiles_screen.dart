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
                  Icon(Icons.list_alt_outlined,
                      size: 64, color: const Color(0xFF2A3A4A)),
                  const SizedBox(height: 16),
                  Text(s.noProfiles,
                      style:
                          const TextStyle(color: Color(0xFF3A4A5A))),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: () => _openImport(context),
                    icon: const Icon(Icons.add),
                    label: Text(s.importProfile),
                  ),
                ],
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
              itemCount: vpn.profiles.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final p = vpn.profiles[i];
                final isActive = vpn.activeProfile?.id == p.id;
                return _ProfileTile(
                  profile: p,
                  isActive: isActive,
                  onTap: () => vpn.selectProfile(p),
                  onDelete: () => _confirmDelete(context, vpn, p, s),
                );
              },
            ),
      floatingActionButton: vpn.profiles.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _openImport(context),
              icon: const Icon(Icons.add),
              label: Text(s.importProfile),
            ),
    );
  }

  void _openImport(BuildContext context) => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ImportScreen()),
      );

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
    final colors = Theme.of(context).colorScheme;

    return Card(
      color: isActive
          ? AppTheme.cyan.withOpacity(0.07)
          : AppTheme.card,
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
          style:
              const TextStyle(fontSize: 12, color: Color(0xFF4A5A6A)),
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
