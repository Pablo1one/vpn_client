import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/vpn_provider.dart';
import '../services/vpn_service.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final vpn = context.watch<VpnProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('VPN')),
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
            const SizedBox(height: 8),
            if (vpn.activeProfile != null)
              Text(
                vpn.activeProfile!.protocolLabel,
                style:
                    const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            if (vpn.error != null) ...[
              const SizedBox(height: 20),
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

class _StatusBadge extends StatelessWidget {
  final VpnStatus status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      VpnStatus.connected => ('Connected', const Color(0xFF00E676)),
      VpnStatus.connecting => ('Connecting...', const Color(0xFFFFB300)),
      VpnStatus.disconnecting => ('Disconnecting...', const Color(0xFFFFB300)),
      VpnStatus.error => ('Error', const Color(0xFFFF5252)),
      _ => ('Disconnected', Colors.grey),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Text(label,
            style: TextStyle(
                color: color,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5)),
      ],
    );
  }
}

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
    final busy = status == VpnStatus.connecting ||
        status == VpnStatus.disconnecting;
    final active = hasProfile && !busy;

    final color = connected
        ? const Color(0xFF00E676)
        : active
            ? Colors.grey.shade400
            : Colors.grey.shade700;

    return GestureDetector(
      onTap: active ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: 164,
        height: 164,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withOpacity(connected ? 0.15 : 0.08),
          border: Border.all(
            color: color.withOpacity(active ? 1 : 0.4),
            width: 2.5,
          ),
        ),
        child: busy
            ? Center(
                child: CircularProgressIndicator(
                  color: const Color(0xFFFFB300),
                  strokeWidth: 2,
                ),
              )
            : Icon(
                Icons.power_settings_new_rounded,
                size: 68,
                color: color.withOpacity(active ? 1 : 0.4),
              ),
      ),
    );
  }
}

class _ProfileLabel extends StatelessWidget {
  final String? name;
  const _ProfileLabel({this.name});

  @override
  Widget build(BuildContext context) {
    return Text(
      name ?? 'No profile selected',
      style: TextStyle(
        fontSize: 15,
        fontWeight: name != null ? FontWeight.w500 : FontWeight.normal,
        color: name != null ? Colors.white70 : Colors.grey.shade600,
      ),
    );
  }
}
