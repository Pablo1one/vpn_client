import 'dart:io';
import 'log_service.dart';

// kill switch через брандмауэр windows. когда включён - весь исходящий трафик
// запрещён, кроме туннеля, ip сервера, локалки и loopback. если туннель падает -
// блокировка остаётся и трафик не утекает (в отличие от strict_route, он слетает
// вместе с процесом sing-box)
class KillSwitchService {
  static const _group = 'LightningMcQueen-KillSwitch';
  bool _active = false;
  bool get active => _active;

  /// Включает блокировку. [tunAlias] — имя туннельного адаптера
  /// (`tun0` для sing-box, `vpnclient_awg` для AmneziaWG).
  Future<void> apply({
    required String serverHost,
    required String tunAlias,
  }) async {
    if (!Platform.isWindows) return;
    final ips = await _resolve(serverHost);

    // разрешения добавляем до смены дефолта на block, иначе будет окошко
    // где заблокировано вобще всё
    final cmds = <String>[
      'Remove-NetFirewallRule -Group "$_group" -ErrorAction SilentlyContinue',
      _allow('LMQ Loopback', '-RemoteAddress 127.0.0.0/8'),
      _allow('LMQ LAN', '-RemoteAddress LocalSubnet'),
      _allow('LMQ Tunnel', '-InterfaceAlias "$tunAlias"'),
    ];
    for (var i = 0; i < ips.length; i++) {
      cmds.add(_allow('LMQ Server $i', '-RemoteAddress ${ips[i]}'));
    }
    // дефолт — блокировать исходящее (разрешения выше работают как исключения)
    cmds.add('Set-NetFirewallProfile -All -DefaultOutboundAction Block');

    await _runPs(cmds.join('; '));
    _active = true;
    LogService().add(
        '[killswitch] брандмауэр включён (сервер ${ips.join(", ")}, адаптер $tunAlias)');
  }

  /// Снимает блокировку и возвращает исходящий трафик к разрешённому по умолчанию.
  Future<void> remove() async {
    if (!Platform.isWindows) return;
    await _runPs(
      'Set-NetFirewallProfile -All -DefaultOutboundAction Allow; '
      'Remove-NetFirewallRule -Group "$_group" -ErrorAction SilentlyContinue',
    );
    if (_active) LogService().add('[killswitch] брандмауэр выключен');
    _active = false;
  }

  String _allow(String name, String filter) =>
      'New-NetFirewallRule -DisplayName "$name" -Group "$_group" '
      '-Direction Outbound $filter -Action Allow -Profile Any | Out-Null';

  Future<List<String>> _resolve(String host) async {
    final isV4 = RegExp(r'^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$').hasMatch(host);
    if (isV4) return [host];
    try {
      final addrs =
          await InternetAddress.lookup(host).timeout(const Duration(seconds: 5));
      final ips = addrs
          .where((a) => a.type == InternetAddressType.IPv4)
          .map((a) => a.address)
          .toSet()
          .toList();
      return ips.isEmpty ? [host] : ips;
    } catch (_) {
      return [host];
    }
  }

  Future<void> _runPs(String script) async {
    try {
      await Process.run(
        'powershell',
        ['-NoProfile', '-NonInteractive', '-Command', script],
        runInShell: false,
      );
    } catch (e) {
      LogService().add('[killswitch] ошибка брандмауэра: $e');
    }
  }
}
