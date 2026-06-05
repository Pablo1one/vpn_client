import 'dart:convert';
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
  SubUserInfo? _batchInfo;
  bool _loading = false;

  String? _pickedFileName;
  String? _pickedFileContent;

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
      _batchInfo = result.subInfo;
      _error = result.error;
      _loading = false;
    });
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null) {
      _clearFile();
      _ctrl.text = data!.text!;
      _onChanged(data.text!);
    }
  }

  Future<void> _pickFile() async {
    // на Android/iOS у .conf нет MIME-типа → FileType.custom не открывает пикер;
    // берём любой файл и валидируем по содержимому. withData — чтобы читать bytes
    // (на Android путь часто content:// с null path)
    final mobile = Platform.isAndroid || Platform.isIOS;
    final result = await FilePicker.platform.pickFiles(
      type: mobile ? FileType.any : FileType.custom,
      allowedExtensions: mobile ? null : ['conf'],
      allowMultiple: false,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    try {
      final content = file.bytes != null
          ? utf8.decode(file.bytes!, allowMalformed: true)
          : (file.path != null ? await File(file.path!).readAsString() : null);
      if (content == null) {
        setState(() => _error = 'Не удалось прочитать файл');
        return;
      }
      _ctrl.clear();
      setState(() {
        _pickedFileName = file.name;
        _pickedFileContent = content;
        _error = null;
        _parsed = null;
        _batch = null;
        _loading = false;
      });
      _onChanged(content);
    } catch (e) {
      setState(() => _error = 'Ошибка чтения файла: $e');
    }
  }

  void _clearFile() {
    setState(() {
      _pickedFileName = null;
      _pickedFileContent = null;
      _parsed = null;
      _batch = null;
      _error = null;
    });
  }

  Future<void> _import() async {
    final vpn = context.read<VpnProvider>();
    final s = L10n.of(context);
    String? msg;
    if (_batch != null) {
      final added = await vpn.addProfiles(_batch!);
      final url = _batch!.isNotEmpty ? _batch!.first.subscriptionUrl : null;
      if (url != null && _batchInfo != null) {
        await vpn.setSubInfo(url, _batchInfo!);
      }
      if (added == 0) {
        msg = s.keyAlreadyExists;
      } else if (added < _batch!.length) {
        msg = s.duplicatesSkipped;
      }
    } else if (_parsed != null) {
      final ok = await vpn.addProfile(_parsed!);
      if (!ok) msg = s.keyAlreadyExists;
    } else {
      return;
    }
    if (!mounted) return;
    if (msg != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    context.watch<LanguageProvider>();
    final s = L10n.of(context);
    final c = context.ac;
    final colors = Theme.of(context).colorScheme;
    final canImport =
        _parsed != null || (_batch != null && _batch!.isNotEmpty);

    return Scaffold(
      appBar: AppBar(title: Text(s.importProfile)),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_pickedFileName != null)
              _FileChip(name: _pickedFileName!, onClear: _clearFile)
            else
              TextField(
                controller: _ctrl,
                maxLines: 1,
                style: const TextStyle(fontSize: 14),
                decoration: InputDecoration(
                  hintText: s.importHint,
                  hintStyle: TextStyle(fontSize: 13, color: c.textMuted),
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: Icon(Icons.content_paste_rounded,
                            color: c.primary),
                        tooltip: s.pasteBtn,
                        onPressed: _paste,
                      ),
                      IconButton(
                        icon: Icon(Icons.folder_open_outlined,
                            color: c.primary),
                        tooltip: s.openFile,
                        onPressed: _pickFile,
                      ),
                    ],
                  ),
                ),
                onChanged: _onChanged,
              ),
            if (_pickedFileName == null) ...[
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  icon: const Icon(Icons.folder_open_outlined, size: 16),
                  label: Text(s.openFile,
                      style: const TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(
                    foregroundColor: c.primary,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  onPressed: _pickFile,
                ),
              ),
            ],
            const SizedBox(height: 12),
            if (_loading)
              _Banner(
                icon: Icons.cloud_download_outlined,
                color: c.primary,
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
                color: c.primary,
                text: '${_parsed!.name}  •  ${_parsed!.protocolLabel}',
              ),
            if (_batch != null && _batch!.isNotEmpty)
              _Banner(
                icon: Icons.check_circle_outline,
                color: c.primary,
                text: s.foundProfiles(_batch!.length),
              ),
            const Spacer(),
            FilledButton.icon(
              onPressed: canImport ? _import : null,
              icon: const Icon(Icons.save_outlined),
              label: Text(_batch != null ? s.importAll : s.saveProfile),
            ),
          ],
        ),
      ),
    );
  }
}

class _FileChip extends StatelessWidget {
  final String name;
  final VoidCallback onClear;
  const _FileChip({required this.name, required this.onClear});

  @override
  Widget build(BuildContext context) {
    final c = context.ac;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: c.primary.withOpacity(0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.primary.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.insert_drive_file_outlined, size: 18, color: c.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              name,
              style: TextStyle(
                  fontSize: 14,
                  color: c.primary,
                  fontWeight: FontWeight.w500),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            icon: Icon(Icons.close, size: 18, color: c.primary),
            onPressed: onClear,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
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
              child: Text(text, style: TextStyle(color: color, fontSize: 13))),
        ],
      ),
    );
  }
}
