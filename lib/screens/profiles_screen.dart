import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/vpn_provider.dart';
import '../models/profile.dart';
import 'import_screen.dart';

class ProfilesScreen extends StatelessWidget {
  const ProfilesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final vpn = context.watch<VpnProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('Profiles')),
      body: vpn.profiles.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.list_alt_outlined,
                      size: 64, color: Colors.grey.shade700),
                  const SizedBox(height: 16),
                  Text('No profiles yet',
                      style: TextStyle(color: Colors.grey.shade600)),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: () => _openImport(context),
                    icon: const Icon(Icons.add),
                    label: const Text('Import profile'),
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
                  onDelete: () => _confirmDelete(context, vpn, p),
                );
              },
            ),
      floatingActionButton: vpn.profiles.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _openImport(context),
              icon: const Icon(Icons.add),
              label: const Text('Import'),
            ),
    );
  }

  void _openImport(BuildContext context) => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ImportScreen()),
      );

  Future<void> _confirmDelete(
      BuildContext context, VpnProvider vpn, VpnProfile p) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete profile?'),
        content: Text(p.name),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete')),
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
          ? colors.primaryContainer.withOpacity(0.15)
          : const Color(0xFF1C1C1C),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isActive
            ? BorderSide(color: colors.primary.withOpacity(0.4))
            : BorderSide.none,
      ),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: CircleAvatar(
          backgroundColor: isActive
              ? colors.primary.withOpacity(0.2)
              : Colors.grey.shade800,
          child: Icon(
            _icon(profile.protocol),
            size: 20,
            color: isActive ? colors.primary : Colors.grey,
          ),
        ),
        title: Text(profile.name,
            style: const TextStyle(fontWeight: FontWeight.w500)),
        subtitle: Text(
          '${profile.protocolLabel}  •  ${profile.serverHost}',
          style: const TextStyle(fontSize: 12, color: Colors.grey),
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isActive)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Icon(Icons.check_circle_rounded,
                    color: colors.primary, size: 18),
              ),
            IconButton(
              icon: const Icon(Icons.delete_outline,
                  size: 20, color: Colors.grey),
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
      };
}
