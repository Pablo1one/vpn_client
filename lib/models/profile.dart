import 'dart:math';

enum VpnProtocol { vless, wireguard, tuic, hysteria2, amnezia }

class VpnProfile {
  final String id;
  final String name;
  final VpnProtocol protocol;
  final Map<String, dynamic> config;
  final DateTime createdAt;
  final String? subscriptionUrl;

  const VpnProfile({
    required this.id,
    required this.name,
    required this.protocol,
    required this.config,
    required this.createdAt,
    this.subscriptionUrl,
  });

  VpnProfile copyWith({String? subscriptionUrl}) => VpnProfile(
        id: id,
        name: name,
        protocol: protocol,
        config: config,
        createdAt: createdAt,
        subscriptionUrl: subscriptionUrl ?? this.subscriptionUrl,
      );

  static String generateId() {
    final rng = Random.secure();
    final bytes = List.generate(16, (_) => rng.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final h = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'protocol': protocol.name,
        'config': config,
        'createdAt': createdAt.toIso8601String(),
        if (subscriptionUrl != null) 'subscriptionUrl': subscriptionUrl,
      };

  factory VpnProfile.fromJson(Map<String, dynamic> json) => VpnProfile(
        id: json['id'] as String,
        name: json['name'] as String,
        protocol: VpnProtocol.values.firstWhere(
          (e) => e.name == json['protocol'],
          orElse: () => VpnProtocol.vless,
        ),
        config: Map<String, dynamic>.from(json['config'] as Map),
        createdAt: DateTime.parse(json['createdAt'] as String),
        subscriptionUrl: json['subscriptionUrl'] as String?,
      );

  String get protocolLabel {
    if (protocol != VpnProtocol.vless) {
      return switch (protocol) {
        VpnProtocol.wireguard => 'WireGuard',
        VpnProtocol.tuic => 'TUIC',
        VpnProtocol.hysteria2 => 'Hysteria2',
        VpnProtocol.amnezia => 'AmneziaWG',
        _ => 'VLESS',
      };
    }
    final transport = config['transport'] as String? ?? 'tcp';
    final security = config['security'] as String? ?? 'none';
    final sec = switch (security) {
      'reality' => ' • Reality',
      'tls' => ' • TLS',
      _ => '',
    };
    final tr = switch (transport) {
      'ws' => 'WS',
      'grpc' => 'gRPC',
      'xhttp' => 'xHTTP',
      'httpupgrade' || 'http' => 'HTTP',
      _ => 'TCP',
    };
    return 'VLESS $tr$sec';
  }

  String get serverHost => switch (protocol) {
        VpnProtocol.vless ||
        VpnProtocol.tuic ||
        VpnProtocol.hysteria2 ||
        VpnProtocol.wireguard ||
        VpnProtocol.amnezia =>
          config['server'] as String? ?? '',
      };

  int get serverPort {
    final raw = config['port'];
    if (raw is int) return raw;
    if (raw is String) return int.tryParse(raw) ?? 443;
    return 443;
  }
}
