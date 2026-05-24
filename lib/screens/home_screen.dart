import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/vpn_provider.dart';
import '../providers/language_provider.dart';
import '../services/vpn_service.dart';
import '../utils/config_builder.dart';
import '../l10n/strings.dart';
import '../theme.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final vpn = context.watch<VpnProvider>();
    // Listen to language changes to rebuild labels
    context.watch<LanguageProvider>();
    final s = L10n.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(s.vpnTab)),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _StatusBadge(status: vpn.status),
            const SizedBox(height: 56),
            _ConnectButton(
              status: vpn.status,
              hasProfile: vpn.activeProfile != null,
              onTap: vpn.isBusy
                  ? null
                  : vpn.isConnected
                      ? vpn.disconnect
                      : vpn.connect,
            ),
            const SizedBox(height: 40),
            _ProfileLabel(name: vpn.activeProfile?.name),
            const SizedBox(height: 6),
            if (vpn.activeProfile != null)
              Text(
                vpn.activeProfile!.protocolLabel,
                style: const TextStyle(
                    fontSize: 12, color: Color(0xFF4A5A6A)),
              ),
            const SizedBox(height: 8),
            _RoutingBadge(vpn: vpn),
            if (vpn.error != null) ...[
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
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
          ],
        ),
      ),
    );
  }
}

// ── Status badge ─────────────────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  final VpnStatus status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final s = L10n.of(context);
    final (label, color) = switch (status) {
      VpnStatus.connected => (s.connected, AppTheme.cyan),
      VpnStatus.connecting => (s.connecting, const Color(0xFFFFB300)),
      VpnStatus.disconnecting => (s.disconnecting, const Color(0xFFFFB300)),
      VpnStatus.error => (s.error, const Color(0xFFFF4560)),
      _ => (s.disconnected, const Color(0xFF3A4A5A)),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
              color: color,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
              fontSize: 13),
        ),
      ],
    );
  }
}

// ── Connect button ────────────────────────────────────────────────────────────

class _ConnectButton extends StatelessWidget {
  final VpnStatus status;
  final bool hasProfile;
  final VoidCallback? onTap;

  const _ConnectButton({
    required this.status,
    required this.hasProfile,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final connected = status == VpnStatus.connected;
    final busy =
        status == VpnStatus.connecting || status == VpnStatus.disconnecting;
    final active = hasProfile && !busy;

    final color = connected
        ? AppTheme.cyan
        : active
            ? const Color(0xFF3A5060)
            : const Color(0xFF1E2535);

    return GestureDetector(
      onTap: active ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 350),
        width: 168,
        height: 168,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withOpacity(connected ? 0.12 : 0.06),
          border: Border.all(
            color: color.withOpacity(active ? 0.9 : 0.3),
            width: 2,
          ),
          boxShadow: connected
              ? [
                  BoxShadow(
                    color: AppTheme.cyan.withOpacity(0.25),
                    blurRadius: 32,
                    spreadRadius: 4,
                  )
                ]
              : null,
        ),
        child: busy
            ? Center(
                child: CircularProgressIndicator(
                  color: const Color(0xFFFFB300),
                  strokeWidth: 2.5,
                ),
              )
            : Icon(
                Icons.power_settings_new_rounded,
                size: 68,
                color: color.withOpacity(active ? 1 : 0.35),
              ),
      ),
    );
  }
}

// ── Profile label ─────────────────────────────────────────────────────────────

class _ProfileLabel extends StatelessWidget {
  final String? name;
  const _ProfileLabel({this.name});

  @override
  Widget build(BuildContext context) {
    final s = L10n.of(context);
    return Text(
      name ?? s.noProfile,
      style: TextStyle(
        fontSize: 15,
        fontWeight: name != null ? FontWeight.w500 : FontWeight.normal,
        color: name != null
            ? const Color(0xFFB0C4D8)
            : const Color(0xFF3A4A5A),
      ),
    );
  }
}

// ── Routing mode badge ────────────────────────────────────────────────────────

class _RoutingBadge extends StatelessWidget {
  final VpnProvider vpn;
  const _RoutingBadge({required this.vpn});

  @override
  Widget build(BuildContext context) {
    final s = L10n.of(context);
    final label = switch (vpn.routingMode) {
      RoutingMode.fullVpn => s.routingFull,
      RoutingMode.russiaBypass => s.routingRussia,
      RoutingMode.custom => s.routingCustom,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.cyan.withOpacity(0.06),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.cyan.withOpacity(0.18)),
      ),
      child: Text(
        label,
        style: const TextStyle(
            fontSize: 11,
            color: AppTheme.cyan,
            letterSpacing: 0.3),
      ),
    );
  }
}
