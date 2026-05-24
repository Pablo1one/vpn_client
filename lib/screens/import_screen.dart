import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/vpn_provider.dart';
import '../models/profile.dart';
import '../utils/link_parser.dart';

class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key});

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  final _ctrl = TextEditingController();
  String? _error;
  VpnProfile? _parsed;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _parse(String text) {
    if (text.trim().isEmpty) {
      setState(() { _parsed = null; _error = null; });
      return;
    }
    final result = LinkParser.parse(text);
    setState(() {
      _parsed = result.profile;
      _error  = result.error;
    });
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null) {
      _ctrl.text = data!.text!;
      _parse(data.text!);
    }
  }

  Future<void> _import() async {
    if (_parsed == null) return;
    await context.read<VpnProvider>().addProfile(_parsed!);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Import profile')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _ctrl,
              maxLines: 7,
              style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
              decoration: InputDecoration(
                hintText:
                    'Paste link or config:\n\nvless://...\ntuic://...\nhysteria2://...\n\n[Interface]\nPrivateKey = ...',
                hintStyle:
                    const TextStyle(fontSize: 12, color: Colors.grey),
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.content_paste_rounded),
                  tooltip: 'Paste from clipboard',
                  onPressed: _paste,
                ),
              ),
              onChanged: _parse,
            ),
            const SizedBox(height: 16),
            if (_error != null)
              _Banner(
                icon: Icons.error_outline,
                color: colors.error,
                text: _error!,
              ),
            if (_parsed != null)
              _Banner(
                icon: Icons.check_circle_outline,
                color: const Color(0xFF00E676),
                text: '${_parsed!.name}  •  ${_parsed!.protocolLabel}',
              ),
            const Spacer(),
            FilledButton.icon(
              onPressed: _parsed != null ? _import : null,
              icon: const Icon(Icons.save_outlined),
              label: const Text('Save profile'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  const _Banner({required this.icon, required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: TextStyle(color: color, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}
