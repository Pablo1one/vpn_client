import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/vpn_provider.dart';
import '../services/vpn_service.dart';
import '../services/warp_service.dart';
import '../l10n/strings.dart';
import '../theme.dart';

class CdnScreen extends StatefulWidget {
  const CdnScreen({super.key});

  @override
  State<CdnScreen> createState() => _CdnScreenState();
}

class _CdnScreenState extends State<CdnScreen> {
  bool _showManual = false;
  final _ctrl = TextEditingController();
  String? _manualError;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _saveManual(VpnProvider vpn) async {
    setState(() => _manualError = null);
    try {
      await WarpService.saveManual(_ctrl.text.trim());
      if (mounted) setState(() => _showManual = false);
    } catch (e) {
      setState(() => _manualError = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final vpn = context.watch<VpnProvider>();
    final s = L10n.of(context);
    final c = context.ac;

    final connected = vpn.warpActive && vpn.isConnected;
    final busy = vpn.warpActive && vpn.isBusy;

    return Scaffold(
      appBar: AppBar(title: Text(s.cdnTitle)),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: c.primary.withOpacity(0.1),
                  border: Border.all(
                    color: c.primary.withOpacity(connected ? 0.8 : 0.3),
                    width: 2,
                  ),
                ),
                child: Icon(
                  Icons.cloud_rounded,
                  size: 40,
                  color: c.primary.withOpacity(connected ? 1.0 : 0.4),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                s.cdnTitle,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: c.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                s.cdnDesc,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: c.textSecondary, height: 1.5),
              ),
              const SizedBox(height: 32),
              if (busy)
                Column(
                  children: [
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: c.primary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      vpn.status == VpnStatus.connecting
                          ? s.cdnRegistering
                          : s.disconnecting,
                      style: TextStyle(fontSize: 13, color: c.textSecondary),
                    ),
                  ],
                )
              else
                FilledButton(
                  onPressed: connected ? vpn.disconnect : vpn.connectWarp,
                  style: FilledButton.styleFrom(
                    backgroundColor: connected ? c.secondary : c.primary,
                    minimumSize: const Size(160, 44),
                  ),
                  child: Text(
                    connected ? s.cdnDisconnect : s.cdnConnect,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              if (vpn.error != null && !busy && vpn.warpActive == false) ...[
                const SizedBox(height: 20),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    vpn.error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 12,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
              const SizedBox(height: 24),
              // ── Ручной ввод конфига ────────────────────────────────────────
              if (!connected && !busy) ...[
                Divider(color: c.border),
                const SizedBox(height: 8),
                InkWell(
                  onTap: () => setState(() {
                    _showManual = !_showManual;
                    _manualError = null;
                  }),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _showManual
                              ? Icons.keyboard_arrow_up_rounded
                              : Icons.keyboard_arrow_down_rounded,
                          size: 18,
                          color: c.textSecondary,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          s.cdnManual,
                          style: TextStyle(fontSize: 12, color: c.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_showManual) ...[
                  const SizedBox(height: 12),
                  Text(
                    s.cdnManualDesc,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11, color: c.textMuted, height: 1.5),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _ctrl,
                    maxLines: 10,
                    style: TextStyle(fontSize: 11, fontFamily: 'monospace', color: c.textPrimary),
                    decoration: InputDecoration(
                      hintText: '[Interface]\nPrivateKey = …\nAddress = …\n\n[Peer]\nPublicKey = …\nEndpoint = …',
                      hintStyle: TextStyle(fontSize: 11, color: c.textMuted),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: c.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: c.border),
                      ),
                      contentPadding: const EdgeInsets.all(12),
                    ),
                  ),
                  if (_manualError != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _manualError!,
                      style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.error),
                    ),
                  ],
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: _ctrl.text.trim().isEmpty ? null : () => _saveManual(vpn),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(140, 40),
                    ),
                    child: Text(s.cdnSaveConfig),
                  ),
                ],
                const SizedBox(height: 16),
                TextButton(
                  onPressed: vpn.resetWarp,
                  child: Text(
                    s.cdnReset,
                    style: TextStyle(fontSize: 12, color: c.textSecondary),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
