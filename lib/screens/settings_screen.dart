import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/vpn_provider.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final vpn = context.watch<VpnProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          _SectionHeader('Connection'),
          SwitchListTile(
            title: const Text('Kill Switch'),
            subtitle: const Text('Block traffic if VPN drops'),
            value: vpn.killSwitch,
            onChanged: vpn.setKillSwitch,
          ),
          const Divider(height: 1),
          _SectionHeader('Split Tunneling'),
          ListTile(
            title: const Text('Bypass domains'),
            subtitle: Text(
              vpn.bypassDomains.isEmpty
                  ? 'None — all traffic through VPN'
                  : vpn.bypassDomains.join(', '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            trailing: const Icon(Icons.chevron_right, size: 20),
            onTap: () => _editBypass(context, vpn),
          ),
        ],
      ),
    );
  }

  Future<void> _editBypass(BuildContext context, VpnProvider vpn) async {
    final ctrl = TextEditingController(
      text: vpn.bypassDomains.join('\n'),
    );
    final result = await showDialog<List<String>>(
      context: context,
      builder: (_) => _BypassDialog(controller: ctrl),
    );
    if (result != null) vpn.setBypassDomains(result);
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          letterSpacing: 1.2,
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _BypassDialog extends StatelessWidget {
  final TextEditingController controller;
  const _BypassDialog({required this.controller});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Bypass domains'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'One domain per line. These will route outside the VPN.',
            style: TextStyle(fontSize: 13, color: Colors.grey),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            maxLines: 8,
            style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
            decoration: const InputDecoration(
              hintText: 'example.com\nlocal.corp',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final lines = controller.text
                .split('\n')
                .map((s) => s.trim())
                .where((s) => s.isNotEmpty)
                .toList();
            Navigator.pop(context, lines);
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
