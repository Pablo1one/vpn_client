import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/vpn_provider.dart';
import '../providers/language_provider.dart';
import '../models/profile.dart';
import '../utils/link_parser.dart';
import '../l10n/strings.dart';
import '../theme.dart';

class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key});

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  final _ctrl = TextEditingController();
  String? _error;
  VpnProfile? _parsed;
  List<VpnProfile>? _batch;
  bool _loading = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _onChanged(String text) {
    final t = text.trim();
    if (t.isEmpty) {
      setState(() {
        _parsed = null;
        _batch = null;
        _error = null;
        _loading = false;
      });
      return;
    }
    if (LinkParser.isSubscriptionUrl(t)) {
      setState(() {
        _parsed = null;
        _batch = null;
        _error = null;
        _loading = true;
      });
      _fetchSubscription(t);
      return;
    }
    final result = LinkParser.parse(t);
    setState(() {
      _parsed = result.profile;
      _batch = result.batch;
      _error = result.error == 'subscription_url' ? null : result.error;
      _loading = false;
    });
  }

  Future<void> _fetchSubscription(String url) async {
    final result = await LinkParser.parseSubscriptionUrl(url);
    if (!mounted) return;
    setState(() {
      _parsed = result.profile;
      _batch = result.batch;
      _error = result.error;
      _loading = false;
    });
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null) {
      _ctrl.text = data!.text!;
      _onChanged(data.text!);
    }
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['conf'],
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return;

    final path = result.files.first.path;
    if (path == null) return;

    try {
      final content = await File(path).readAsString();
      _ctrl.text = content;
      _onChanged(content);
    } catch (e) {
      setState(() => _error = 'Ошибка чтения файла: $e');
    }
  }

  Future<void> _import() async {
    final vpn = context.read<VpnProvider>();
    if (_batch != null) {
      await vpn.addProfiles(_batch!);
    } else if (_parsed != null) {
      await vpn.addProfile(_parsed!);
    } else {
      return;
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    context.watch<LanguageProvider>();
    final s = L10n.of(context);
    final colors = Theme.of(context).colorScheme;
    final canImport = _parsed != null || (_batch != null && _batch!.isNotEmpty);

    return Scaffold(
      appBar: AppBar(title: Text(s.importProfile)),
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
                hintText: s.importHint,
                hintStyle:
                    const TextStyle(fontSize: 12, color: Color(0xFF3A4060)),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.content_paste_rounded,
                          color: AppTheme.cyan),
                      tooltip: s.pasteBtn,
                      onPressed: _paste,
                    ),
                    IconButton(
                      icon: const Icon(Icons.folder_open_outlined,
                          color: AppTheme.cyan),
                      tooltip: s.openFile,
                      onPressed: _pickFile,
                    ),
                  ],
                ),
              ),
              onChanged: _onChanged,
            ),
            const SizedBox(height: 16),
            if (_loading)
              _Banner(
                icon: Icons.cloud_download_outlined,
                color: AppTheme.cyan,
                text: s.fetchingUrl,
              ),
            if (_error != null)
              _Banner(
                icon: Icons.error_outline,
                color: colors.error,
                text: _error!,
              ),
            if (_parsed != null)
              _Banner(
                icon: Icons.check_circle_outline,
                color: AppTheme.cyan,
                text: '${_parsed!.name}  •  ${_parsed!.protocolLabel}',
              ),
            if (_batch != null && _batch!.isNotEmpty)
              _Banner(
                icon: Icons.check_circle_outline,
                color: AppTheme.cyan,
                text: s.foundProfiles(_batch!.length),
              ),
            const Spacer(),
            FilledButton.icon(
              onPressed: canImport ? _import : null,
              icon: const Icon(Icons.save_outlined),
              label: Text(
                  _batch != null ? s.importAll : s.saveProfile),
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
  const _Banner(
      {required this.icon, required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.07),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 10),
          Expanded(
              child: Text(text,
                  style: TextStyle(color: color, fontSize: 13))),
        ],
      ),
    );
  }
}
