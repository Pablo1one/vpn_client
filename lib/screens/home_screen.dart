import 'package:country_flags/country_flags.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/vpn_provider.dart';
import '../providers/language_provider.dart';
import '../services/speed_service.dart';
import '../services/vpn_service.dart';
import '../utils/config_builder.dart';
import '../l10n/strings.dart';
import '../theme.dart';
import '../widgets/world_map_painter.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final vpn = context.watch<VpnProvider>();
    context.watch<LanguageProvider>();
    final s = L10n.of(context);

    final c = context.ac;
    return Scaffold(
      appBar: AppBar(title: Text(s.vpnTab)),
      body: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: WorldMapPainter(
                landColor: c.primary.withOpacity(0.055),
                gridColor: c.borderFaint,
              ),
            ),
          ),
          Center(
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
            const SizedBox(height: 16),
            _ConnectionTimer(connectedAt: vpn.connectedAt),
            const SizedBox(height: 10),
            _SpeedWidget(stream: vpn.speedStream, visible: vpn.isConnected),
            const SizedBox(height: 14),
            _ProfileLabel(
              name: vpn.activeProfile?.name,
              countryCode: vpn.activeCountryCode,
            ),
            const SizedBox(height: 5),
            SizedBox(
              height: 18,
              child: vpn.activeProfile != null
                  ? Text(
                      vpn.activeProfile!.protocolLabel,
                      style: TextStyle(
                          fontSize: 12,
                          color: context.ac.textSecondary),
                    )
                  : null,
            ),
            const SizedBox(height: 8),
            _RoutingBadge(vpn: vpn),
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
        ],
      ),
    );
  }
}

// ── Status badge ──────────────────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  final VpnStatus status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final s = L10n.of(context);
    final c = context.ac;
    final (label, color) = switch (status) {
      VpnStatus.connected    => (s.connected, c.primary),
      VpnStatus.connecting   => (s.connecting, c.primary),
      VpnStatus.disconnecting => (s.disconnecting, c.primary),
      VpnStatus.error        => (s.error, Theme.of(context).colorScheme.error),
      _                      => (s.disconnected, c.textMuted),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8, height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Text(label,
            style: TextStyle(
                color: color,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
                fontSize: 13)),
      ],
    );
  }
}

// ── Connect button ────────────────────────────────────────────────────────────

class _ConnectButton extends StatefulWidget {
  final VpnStatus status;
  final bool hasProfile;
  final VoidCallback? onTap;

  const _ConnectButton({
    required this.status,
    required this.hasProfile,
    this.onTap,
  });

  @override
  State<_ConnectButton> createState() => _ConnectButtonState();
}

class _ConnectButtonState extends State<_ConnectButton>
    with TickerProviderStateMixin {
  late final AnimationController _spin;
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _spin = AnimationController(vsync: this,
        duration: const Duration(milliseconds: 1400));
    _pulse = AnimationController(vsync: this,
        duration: const Duration(milliseconds: 900));
    _updateAnimation();
  }

  @override
  void didUpdateWidget(_ConnectButton old) {
    super.didUpdateWidget(old);
    _updateAnimation();
  }

  bool get _busy =>
      widget.status == VpnStatus.connecting ||
      widget.status == VpnStatus.disconnecting;

  void _updateAnimation() {
    if (_busy) {
      if (!_spin.isAnimating) _spin.repeat();
      if (!_pulse.isAnimating) _pulse.repeat(reverse: true);
    } else {
      _spin.stop(); _spin.value = 0;
      _pulse.stop(); _pulse.value = 0;
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ac;
    final connected = widget.status == VpnStatus.connected;
    final busy = _busy;
    final active = widget.hasProfile && !busy;

    final btnColor = connected
        ? c.secondary
        : active
            ? c.btnActive
            : c.btnInactive;

    final button = AnimatedContainer(
      duration: const Duration(milliseconds: 350),
      width: 168, height: 168,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: btnColor.withOpacity(connected ? 0.12 : 0.07),
        border: Border.all(
          color: btnColor.withOpacity(active ? 0.85 : 0.25),
          width: connected ? 2.5 : 2,
        ),
        boxShadow: connected
            ? [
                BoxShadow(
                  color: c.secondary.withOpacity(0.65),
                  blurRadius: 20,
                  spreadRadius: 4,
                ),
                BoxShadow(
                  color: c.secondary.withOpacity(0.38),
                  blurRadius: 55,
                  spreadRadius: 14,
                ),
                BoxShadow(
                  color: c.secondary.withOpacity(0.16),
                  blurRadius: 100,
                  spreadRadius: 28,
                ),
              ]
            : null,
      ),
      child: Icon(
        Icons.power_settings_new_rounded,
        size: 68,
        color: btnColor.withOpacity(active ? 1 : 0.3),
      ),
    );

    return MouseRegion(
      cursor: active ? SystemMouseCursors.click : MouseCursor.defer,
      child: GestureDetector(
        onTap: active ? widget.onTap : null,
        child: SizedBox(
          width: 220,
          height: 220,
          child: AnimatedBuilder(
            animation: Listenable.merge([_spin, _pulse]),
            builder: (_, __) => Stack(
              alignment: Alignment.center,
              children: [
                if (busy) ...[
                  SizedBox(
                    width: 200 + _pulse.value * 14,
                    height: 200 + _pulse.value * 14,
                    child: CircularProgressIndicator(
                      value: null,
                      color: c.primary.withOpacity(0.15 + _pulse.value * 0.18),
                      strokeWidth: 1.5,
                    ),
                  ),
                  Transform.rotate(
                    angle: _spin.value * 6.2832,
                    child: SizedBox(
                      width: 188, height: 188,
                      child: CustomPaint(painter: _ArcPainter(c.primary)),
                    ),
                  ),
                ],
                button,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ArcPainter extends CustomPainter {
  final Color color;
  const _ArcPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(3, 3, size.width - 6, size.height - 6);
    canvas.drawArc(
      rect, -1.57, 4.71, false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0
        ..strokeCap = StrokeCap.round
        ..shader = SweepGradient(
          colors: [color.withOpacity(0), color],
          startAngle: 0,
          endAngle: 4.71,
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_ArcPainter old) => old.color != color;
}

// ── Profile label ─────────────────────────────────────────────────────────────

class _ProfileLabel extends StatelessWidget {
  final String? name;
  final String? countryCode;
  const _ProfileLabel({this.name, this.countryCode});

  @override
  Widget build(BuildContext context) {
    final c = context.ac;
    final s = L10n.of(context);
    if (name == null) {
      return SizedBox(
        height: 24,
        child: Text(s.noProfile,
            style: TextStyle(fontSize: 15, color: c.textMuted)),
      );
    }
    final cc = countryCode?.toUpperCase();
    return SizedBox(
      height: 24,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (cc != null && cc.length == 2) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: CountryFlag.fromCountryCode(cc, width: 24, height: 16),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Text(
              name!,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: c.textPrimary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
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
    return SizedBox(
      height: 30,
      child: AnimatedOpacity(
        opacity: connectedAt != null ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 300),
        child: StreamBuilder<int>(
          stream: Stream.periodic(const Duration(seconds: 1), (i) => i),
          builder: (_, __) {
            final elapsed = connectedAt != null
                ? DateTime.now().difference(connectedAt!)
                : Duration.zero;
            final h = elapsed.inHours;
            final m = (elapsed.inMinutes % 60).toString().padLeft(2, '0');
            final s = (elapsed.inSeconds % 60).toString().padLeft(2, '0');
            final label =
                h > 0 ? '${h.toString().padLeft(2, '0')}:$m:$s' : '$m:$s';
            return Text(
              label,
              style: TextStyle(
                color: context.ac.secondary,
                fontSize: 22,
                fontWeight: FontWeight.w700,
                fontFamily: 'monospace',
                letterSpacing: 3,
              ),
            );
          },
        ),
      ),
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
    final c = context.ac;
    return AnimatedOpacity(
      opacity: visible ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 400),
      child: StreamBuilder<SpeedData>(
        stream: stream,
        builder: (_, snap) {
          final data = snap.data ?? SpeedData.empty;
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: c.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _Stat(
                  icon: Icons.arrow_upward_rounded,
                  value: SpeedService.formatSpeed(data.uploadBps),
                  color: c.upload,
                ),
                const SizedBox(width: 20),
                _Stat(
                  icon: Icons.arrow_downward_rounded,
                  value: SpeedService.formatSpeed(data.downloadBps),
                  color: c.primary,
                ),
                if (data.pingMs >= 0) ...[
                  const SizedBox(width: 20),
                  _Stat(
                    icon: Icons.network_ping_rounded,
                    value: '${data.pingMs} ms',
                    color: c.secondary,
                  ),
                ],
              ],
            ),
          );
        },
      ),
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
          Text(value,
              style: TextStyle(
                fontSize: 13,
                color: color,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
              )),
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
    final c = context.ac;
    final label = switch (vpn.routingMode) {
      RoutingMode.fullVpn      => s.routingFull,
      RoutingMode.russiaBypass => s.routingRussia,
      RoutingMode.custom       => s.routingCustom,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: c.primary.withOpacity(0.07),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.primary.withOpacity(0.2)),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 11, color: c.primary, letterSpacing: 0.3)),
    );
  }
}
