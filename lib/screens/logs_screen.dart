import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers/language_provider.dart';
import '../services/log_service.dart';
import '../l10n/strings.dart';
import '../theme.dart';

class LogsScreen extends StatefulWidget {
  const LogsScreen({super.key});

  @override
  State<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends State<LogsScreen> {
  final _log = LogService();
  late List<String> _lines;
  final _scroll = ScrollController();
  late final StreamSubscription _sub;

  @override
  void initState() {
    super.initState();
    _lines = _log.lines.toList();
    _sub = _log.stream.listen((lines) {
      if (!mounted) return;
      setState(() => _lines = lines.toList());
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.animateTo(
            _scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 100),
            curve: Curves.easeOut,
          );
        }
      });
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients && _scroll.position.maxScrollExtent > 0) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  @override
  void dispose() {
    _sub.cancel();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    context.watch<LanguageProvider>();
    final s = L10n.of(context);
    final c = context.ac;

    return Scaffold(
      appBar: AppBar(
        title: Text(s.logsTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy_outlined, size: 20),
            tooltip: s.copyLogs,
            onPressed: _lines.isEmpty
                ? null
                : () {
                    Clipboard.setData(ClipboardData(text: _lines.join('\n')));
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(s.logsCopied),
                      duration: const Duration(seconds: 2),
                    ));
                  },
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 20),
            tooltip: s.clearLogs,
            onPressed: () => _log.clear(),
          ),
        ],
      ),
      body: _lines.isEmpty
          ? Center(
              child: Text(
                s.noLogs,
                style: TextStyle(color: c.textMuted),
              ),
            )
          : ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
              itemCount: _lines.length,
              itemBuilder: (_, i) => Text(
                _lines[i],
                style: TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                  color: c.textSecondary,
                  height: 1.6,
                ),
              ),
            ),
    );
  }
}
