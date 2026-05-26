import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/vpn_provider.dart';
import '../providers/language_provider.dart';
import '../services/speed_service.dart';
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
            const SizedBox(height: 40),
            _ConnectButton(
              status: vpn.status,
              hasProfile: vpn.activeProfile != null,
              onTap: vpn.isBusy
                  ? null
                  : vpn.isConnected
                      ? vpn.disconnect
                      : vpn.connect,
            ),
            const SizedBox(height: 20),
            _ConnectionTimer(connectedAt: vpn.connectedAt),
            const SizedBox(height: 12),
            _SpeedWidget(stream: vpn.speedStream, visible: vpn.isConnected),
            const SizedBox(height: 12),
            _ProfileLabel(
              name: vpn.activeProfile?.name,
              countryCode: vpn.activeCountryCode,
            ),
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
        ? AppTheme.purple
        : active
            ? const Color(0xFF3A5060)
            : const Color(0xFF1E2535);

    final button = AnimatedContainer(
      duration: const Duration(milliseconds: 350),
      width: 168,
      height: 168,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withOpacity(connected ? 0.10 : 0.06),
        border: Border.all(
          color: color.withOpacity(active ? 0.85 : 0.25),
          width: connected ? 2.5 : 2,
        ),
        boxShadow: connected
            ? [
                BoxShadow(
                  color: AppTheme.purple.withOpacity(0.35),
                  blurRadius: 44,
                  spreadRadius: 6,
                ),
                BoxShadow(
                  color: AppTheme.purple.withOpacity(0.15),
                  blurRadius: 80,
                  spreadRadius: 16,
                ),
              ]
            : null,
      ),
      child: Icon(
        Icons.power_settings_new_rounded,
        size: 68,
        color: color.withOpacity(active ? 1 : 0.3),
      ),
    );

    return GestureDetector(
      onTap: active ? onTap : null,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (busy)
            const SizedBox(
              width: 186,
              height: 186,
              child: CircularProgressIndicator(
                color: AppTheme.cyan,
                strokeWidth: 3,
              ),
            ),
          button,
        ],
      ),
    );
  }
}

// ── Profile label ─────────────────────────────────────────────────────────────

class _ProfileLabel extends StatelessWidget {
  final String? name;
  final String? countryCode;
  const _ProfileLabel({this.name, this.countryCode});

  static String? _flag(String? cc) {
    if (cc == null || cc.length != 2) return null;
    return cc.toUpperCase().runes
        .map((r) => String.fromCharCode(0x1F1E0 + r - 65))
        .join();
  }

  @override
  Widget build(BuildContext context) {
    final s = L10n.of(context);
    final flag = _flag(countryCode);
    final displayName = name != null && flag != null
        ? '$flag  $name'
        : name ?? s.noProfile;
    return Text(
      displayName,
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

// ── Connection timer ──────────────────────────────────────────────────────────

class _ConnectionTimer extends StatelessWidget {
  final DateTime? connectedAt;
  const _ConnectionTimer({this.connectedAt});

  @override
  Widget build(BuildContext context) {
    if (connectedAt == null) return const SizedBox(height: 28);
    return StreamBuilder<int>(
      stream: Stream.periodic(const Duration(seconds: 1), (i) => i),
      builder: (_, __) {
        final elapsed = DateTime.now().difference(connectedAt!);
        final h = elapsed.inHours;
        final m = (elapsed.inMinutes % 60).toString().padLeft(2, '0');
        final s = (elapsed.inSeconds % 60).toString().padLeft(2, '0');
        final label = h > 0 ? '${h.toString().padLeft(2, '0')}:$m:$s' : '$m:$s';
        return Text(
          label,
          style: const TextStyle(
            color: AppTheme.purple,
            fontSize: 22,
            fontWeight: FontWeight.w700,
            fontFamily: 'monospace',
            letterSpacing: 3,
          ),
        );
      },
    );
  }
}

// ── Speed / ping widget ───────────────────────────────────────────────────────

class _SpeedWidget extends StatelessWidget {
  final Stream<SpeedData> stream;
  final bool visible;
  const _SpeedWidget({required this.stream, required this.visible});

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox(height: 24);
    return StreamBuilder<SpeedData>(
      stream: stream,
      builder: (_, snap) {
        final data = snap.data ?? SpeedData.empty;
        return AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: const Duration(milliseconds: 400),
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF1E1E38)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _Stat(
                  icon: Icons.arrow_upward_rounded,
                  value: SpeedService.formatSpeed(data.uploadBps),
                  color: const Color(0xFFFFB300),
                ),
                const SizedBox(width: 20),
                _Stat(
                  icon: Icons.arrow_downward_rounded,
                  value: SpeedService.formatSpeed(data.downloadBps),
                  color: AppTheme.cyan,
                ),
                if (data.pingMs >= 0) ...[
                  const SizedBox(width: 20),
                  _Stat(
                    icon: Icons.network_ping_rounded,
                    value: '${data.pingMs} ms',
                    color: AppTheme.purple,
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Stat extends StatelessWidget {
  final IconData icon;
  final String value;
  final Color color;
  const _Stat({required this.icon, required this.value, required this.color});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color.withOpacity(0.85)),
          const SizedBox(width: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              color: color,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
          ),
        ],
      );
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
