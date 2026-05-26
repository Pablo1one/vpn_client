import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/vpn_provider.dart';
import '../services/vpn_service.dart';
import '../l10n/strings.dart';
import '../theme.dart';

class CdnScreen extends StatelessWidget {
  const CdnScreen({super.key});

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
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
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
              if (vpn.error != null && !busy) ...[
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
              const SizedBox(height: 32),
              TextButton(
                onPressed: busy || connected ? null : vpn.resetWarp,
                child: Text(
                  s.cdnReset,
                  style: TextStyle(
                    fontSize: 12,
                    color: busy || connected
                        ? c.textMuted
                        : c.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
