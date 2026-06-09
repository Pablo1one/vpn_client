import 'package:country_flags/country_flags.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/vpn_provider.dart';
import '../services/ip_check_service.dart';
import '../l10n/strings.dart';
import '../theme.dart';

// Проверка соединения: показывает реальный адрес выхода (ip/страна/провайдер) и
// сверяет страну с сервером. Запрос идёт через туннель.
class ConnCheckScreen extends StatefulWidget {
  const ConnCheckScreen({super.key});

  @override
  State<ConnCheckScreen> createState() => _ConnCheckScreenState();
}

class _ConnCheckScreenState extends State<ConnCheckScreen> {
  bool _loading = false;
  bool _failed = false;
  IpCheckResult? _res;

  Future<void> _run() async {
    setState(() {
      _loading = true;
      _failed = false;
      _res = null;
    });
    final r = await IpCheckService.check();
    if (!mounted) return;
    setState(() {
      _loading = false;
      _res = r;
      _failed = r == null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final vpn = context.watch<VpnProvider>();
    final s = L10n.of(context);
    final c = context.ac;

    final exitCc = _res?.countryCode.toUpperCase();

    return Scaffold(
      appBar: AppBar(title: Text(s.connCheck)),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Banner(
              c: c,
              icon: vpn.isConnected
                  ? Icons.lock_outline
                  : Icons.lock_open_outlined,
              color: vpn.isConnected ? c.primary : c.textMuted,
              text: vpn.isConnected
                  ? 'vpn подключён - ниже точка выхода трафика'
                  : 'vpn не подключён - это ваш реальный адрес',
            ),
            if (_res != null) ...[
              _row(c, 'ip', _res!.ip),
              const SizedBox(height: 12),
              Row(
                children: [
                  SizedBox(
                      width: 90,
                      child: Text('страна',
                          style: TextStyle(color: c.textMuted, fontSize: 13))),
                  if (exitCc != null && exitCc.length == 2) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: CountryFlag.fromCountryCode(exitCc,
                          width: 22, height: 15),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                      child: Text('${_res!.country} ($exitCc)',
                          style: const TextStyle(fontSize: 14))),
                ],
              ),
              const SizedBox(height: 12),
              _row(c, 'провайдер', _res!.org),
            ],
            if (_failed)
              _Banner(
                c: c,
                icon: Icons.error_outline,
                color: Theme.of(context).colorScheme.error,
                text: 'не удалось проверить (нет сети?)',
              ),
            const Spacer(),
            FilledButton.icon(
              onPressed: _loading ? null : _run,
              icon: _loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.travel_explore_outlined),
              label: Text(_loading ? '...' : s.connCheck),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(AppColors c, String label, String value) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
              width: 90,
              child:
                  Text(label, style: TextStyle(color: c.textMuted, fontSize: 13))),
          Expanded(
              child: SelectableText(value,
                  style: const TextStyle(fontSize: 14))),
        ],
      );
}

class _Banner extends StatelessWidget {
  final AppColors c;
  final IconData icon;
  final Color color;
  final String text;
  const _Banner(
      {required this.c,
      required this.icon,
      required this.color,
      required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
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
