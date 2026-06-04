import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'log_service.dart';

enum VpnStatus { disconnected, connecting, connected, disconnecting, error }

abstract class VpnService {
  static const kAwgTunnelName = 'vpnclient_awg';

  Stream<VpnStatus> get statusStream;
  Future<void> connect(String singboxConfigJson,
      {List<String> excludedApps = const []});
  Future<void> connectProxy({
    String? singboxConfigJson,
    String? xrayConfigJson,
    String? tunConfigJson,
  });
  Future<void> connectAwg(String confContent);
  Future<void> disconnect();
  Future<void> cleanup();
  void dispose();

  factory VpnService.create() {
    if (Platform.isAndroid) return _MobileVpnService();
    if (Platform.isIOS) return _MobileVpnService();
    if (Platform.isWindows) return _WindowsVpnService();
    throw UnsupportedError('Unsupported platform: ${Platform.operatingSystem}');
  }
}

// мобильный (android + ios)
class _MobileVpnService implements VpnService {
  static const _method = MethodChannel('lightningmcqueen.proxy/vpn');
  static const _events = EventChannel('lightningmcqueen.proxy/vpn_events');

  final _controller = StreamController<VpnStatus>.broadcast();
  late final StreamSubscription _sub;

  _MobileVpnService() {
    _sub = _events.receiveBroadcastStream().listen(
      (event) => _controller.add(_parse(event as String)),
      onError: (_) => _controller.add(VpnStatus.error),
    );
  }

  VpnStatus _parse(String s) => switch (s) {
        'connected' => VpnStatus.connected,
        'connecting' => VpnStatus.connecting,
        'disconnecting' => VpnStatus.disconnecting,
        'disconnected' => VpnStatus.disconnected,
        _ => VpnStatus.error,
      };

  @override
  Stream<VpnStatus> get statusStream => _controller.stream;

  @override
  Future<void> connect(String config,
          {List<String> excludedApps = const []}) =>
      _method.invokeMethod(
          'connect', {'config': config, 'excludedApps': excludedApps});

  @override
  Future<void> connectProxy({
    String? singboxConfigJson,
    String? xrayConfigJson,
    String? tunConfigJson,
  }) =>
      throw UnsupportedError('Proxy mode not supported on mobile');

  @override
  Future<void> connectAwg(String confContent) =>
      throw UnsupportedError('AWG not yet supported on mobile');

  @override
  Future<void> disconnect() => _method.invokeMethod('disconnect');

  @override
  Future<void> cleanup() async {}

  @override
  void dispose() {
    _sub.cancel();
    _controller.close();
  }
}

// windows — прокси (xray или singbox) на порту 10808 плюс tun форвардер
class _WindowsVpnService implements VpnService {
  final _controller = StreamController<VpnStatus>.broadcast();

  Process? _process;         // tun singbox
  StreamSubscription? _outSub;
  StreamSubscription? _errSub;
  File? _configFile;

  Process? _proxyProcess;    // xray или singbox прокси
  File? _proxyConfigFile;

  bool _awgActive = false;
  static const _awgTunnelName = VpnService.kAwgTunnelName;
  static const _regPath =
      r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings';

  @override
  Stream<VpnStatus> get statusStream => _controller.stream;

  String get _binDir {
    final appDir = File(Platform.resolvedExecutable).parent.path;
    return '$appDir\\data\\flutter_assets\\assets\\bin';
  }

  String get _exePath => '$_binDir\\sing-box.exe';

  Future<void> _ensureWintun() async {
    final src = File('$_binDir\\wintun.dll');
    final dst = File('${File(_exePath).parent.path}\\wintun.dll');
    if (src.existsSync() && !dst.existsSync()) {
      await src.copy(dst.path);
    }
  }

  Future<void> _killProxy() async {
    final old = _proxyProcess;
    _proxyProcess = null;
    if (old != null) {
      old.kill(ProcessSignal.sigterm);
      await old.exitCode
          .timeout(const Duration(seconds: 3), onTimeout: () {
            old.kill();
            return -1;
          })
          .catchError((_) => -1);
    }
    try { await _proxyConfigFile?.delete(); } catch (_) {}
    _proxyConfigFile = null;
  }

  // sing-box не удаляет tun0 при падении — следующий запуск упадёт с "file already exists".
  // Условная чистка: если sing-box TUN нет (частый случай, особенно при коннекте AWG) —
  // мгновенно выходим. Задержки только когда реально удаляли адаптер.
  static const _tunFilter = r'Get-NetAdapter -IncludeHidden | Where-Object {'
      r' ($_.Name -like "tun*" -or $_.InterfaceDescription -like "*Wintun*")'
      r' -and $_.Name -ne "' + _awgTunnelName + r'" }';

  Future<int> _tunAdapterCount() async {
    final r = await Process.run(
      'powershell', ['-Command', '@($_tunFilter).Count'],
      runInShell: false,
    );
    return int.tryParse((r.stdout as String).trim()) ?? 0;
  }

  Future<void> _removeTunAdapter() async {
    if (await _tunAdapterCount() == 0) return; // нечего удалять — без задержек
    for (var i = 0; i < 10; i++) {
      await Process.run(
        'powershell',
        ['-Command', '$_tunFilter | Remove-NetAdapter -Confirm:\$false -ErrorAction SilentlyContinue'],
        runInShell: false,
      );
      await Process.run(
        'netsh', ['interface', 'delete', 'interface', 'tun0'],
        runInShell: false,
      );
      if (await _tunAdapterCount() == 0) break;
      await Future.delayed(const Duration(milliseconds: 400));
    }
    // ждём пока драйвер WinTun освободит адаптер (только если удаляли)
    await Future.delayed(const Duration(milliseconds: 900));
  }

  Future<void> _killExistingProcess() async {
    await Process.run('taskkill', ['/F', '/IM', 'sing-box.exe'], runInShell: false);
    await Process.run('taskkill', ['/F', '/IM', 'xray.exe'], runInShell: false);
    await Process.run('taskkill', ['/F', '/IM', 'amneziawg.exe'], runInShell: false);
    // короткая пауза на завершение процессов; адаптер чистится условно
    await Future.delayed(const Duration(milliseconds: 400));
    await _removeTunAdapter();

    await _killProxy();
    if (_process == null) {
      return;
    }
    await _outSub?.cancel();
    _outSub = null;
    await _errSub?.cancel();
    _errSub = null;
    final old = _process!;
    _process = null;
    old.kill(ProcessSignal.sigterm);
    await old.exitCode
        .timeout(
          const Duration(seconds: 3),
          onTimeout: () {
            old.kill();
            return -1;
          },
        )
        .catchError((_) => -1);
    try { await _configFile?.delete(); } catch (_) {}
    _configFile = null;
  }

  Future<void> _startProxy(String configJson, {required bool isXray}) async {
    final exePath = isXray ? '$_binDir\\xray.exe' : _exePath;
    final exe = File(exePath);
    if (!exe.existsSync()) {
      throw Exception(
        '${isXray ? "xray" : "sing-box"}.exe не найден\nОжидается: $exePath',
      );
    }

    _proxyConfigFile = File(
      '${Directory.systemTemp.path}\\vpn_client_proxy_${DateTime.now().millisecondsSinceEpoch}.json',
    );
    await _proxyConfigFile!.writeAsString(configJson);

    _proxyProcess = await Process.start(
      exe.path,
      ['run', '-c', _proxyConfigFile!.path],
      runInShell: false,
    );
    final proc = _proxyProcess!;
    final errLines = <String>[];
    bool exited = false;

    proc.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((l) {
      errLines.add(l);
      LogService().add('[proxy] $l');
    });
    proc.stderr.transform(utf8.decoder).transform(const LineSplitter()).listen((l) {
      errLines.add(l);
      LogService().add('[proxy] $l');
    });
    proc.exitCode.then((_) => exited = true);

    // ждём открытия порта 10808 до 8 с
    for (var i = 0; i < 16; i++) {
      await Future.delayed(const Duration(milliseconds: 500));
      if (exited) {
        final log = errLines.isNotEmpty ? errLines.take(10).join('\n') : '(нет вывода)';
        throw Exception(
          '${isXray ? "xray" : "sing-box"} завершился до открытия порта:\n$log',
        );
      }
      try {
        final s = await Socket.connect('127.0.0.1', 10808,
            timeout: const Duration(milliseconds: 300));
        await s.close();
        return;
      } catch (_) {}
    }
    final log = errLines.isNotEmpty ? errLines.take(10).join('\n') : '(нет вывода)';
    throw Exception(
      '${isXray ? "xray" : "sing-box"} не открыл порт 10808 за 8 с:\n$log',
    );
  }

  // Авто-ретрай старта TUN-форвардера (автоматизирует ручной reconnect).
  // ВАЖНО: убиваем только сам форвардер (_process), НЕ трогая прокси (_proxyProcess) —
  // для tuic/hysteria прокси тоже sing-box, и общий taskkill убил бы его.
  Future<void> _launchTun(String configJson) async {
    const maxAttempts = 3;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        await _launchTunOnce(configJson);
        return;
      } catch (e) {
        // убиваем только зависший форвардер, прокси оставляем живым.
        // Чистим и на последней попытке — иначе остался бы работающий туннель
        // с error-статусом (серая кнопка при живом коннекте).
        try { _process?.kill(ProcessSignal.sigterm); } catch (_) {}
        try { _process?.kill(); } catch (_) {}
        await _outSub?.cancel(); _outSub = null;
        await _errSub?.cancel(); _errSub = null;
        _process = null;
        if (attempt == maxAttempts - 1) rethrow;
        LogService().add('[tun] старт не удался — чистка и ретрай #${attempt + 1}');
        await Future.delayed(const Duration(milliseconds: 600));
        await _removeTunAdapter();
      }
    }
  }

  Future<void> _launchTunOnce(String configJson) async {
    _configFile = File(
      '${Directory.systemTemp.path}\\vpn_client_tun_${DateTime.now().millisecondsSinceEpoch}.json',
    );
    await _configFile!.writeAsString(configJson);

    _process = await Process.start(
      _exePath,
      ['run', '-c', _configFile!.path],
      runInShell: false,
    );
    final proc = _process!;

    final allLines = <String>[];
    bool exited = false;

    void log(String line) {
      if (line.isEmpty) return;
      allLines.add(line.trim());
      LogService().add('[tun] $line');
    }

    _outSub = proc.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(log);
    _errSub = proc.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(log);

    // последние строки лога — там фатальная ошибка (а не первые WARN/INFO)
    String tailLog() => allLines.isEmpty
        ? '(нет вывода)'
        : (allLines.length > 12
                ? allLines.sublist(allLines.length - 12)
                : allLines)
            .join('\n');

    // процесс умер (туннель упал позже) → сообщаем об отключении
    proc.exitCode.then((code) {
      exited = true;
      if (_process == proc) _controller.add(VpnStatus.disconnected);
    });

    // Готовность — по открытию clash_api (9090), а не по строке в логе:
    // парсинг лога давал ложные таймауты (туннель работал, а кнопка серела).
    // Холодный старт wintun — до ~25 с, потому бюджет ~30 с.
    for (var i = 0; i < 60; i++) {
      if (exited) {
        throw Exception('sing-box (TUN) завершился:\n${tailLog()}');
      }
      try {
        final s = await Socket.connect('127.0.0.1', 9090,
            timeout: const Duration(milliseconds: 300));
        await s.close();
        return; // sing-box поднял clash_api → точно готов
      } catch (_) {}
      await Future.delayed(const Duration(milliseconds: 500));
    }
    _controller.add(VpnStatus.error);
    throw Exception('sing-box не открыл clash_api за 30 с:\n${tailLog()}');
  }

  @override
  Future<void> connectProxy({
    String? singboxConfigJson,
    String? xrayConfigJson,
    String? tunConfigJson,
  }) async {
    _controller.add(VpnStatus.connecting);
    try {
      await _ensureWintun();
      await _uninstallAwgTunnel();
      await _killExistingProcess();

      if (xrayConfigJson != null) {
        await _startProxy(xrayConfigJson, isXray: true);
      } else if (singboxConfigJson != null) {
        await _startProxy(singboxConfigJson, isXray: false);
      } else {
        throw ArgumentError('singboxConfigJson or xrayConfigJson required');
      }

      if (tunConfigJson != null) {
        await _launchTun(tunConfigJson);
      }

      _controller.add(VpnStatus.connected);
    } catch (e) {
      _controller.add(VpnStatus.error);
      rethrow;
    }
  }

  @override
  Future<void> connect(String configJson,
      {List<String> excludedApps = const []}) async {
    _controller.add(VpnStatus.connecting);
    try {
      final exe = File(_exePath);
      if (!exe.existsSync()) {
        throw Exception('sing-box.exe не найден\nОжидается: ${exe.path}');
      }
      await _ensureWintun();
      await _uninstallAwgTunnel();
      await _killExistingProcess();
      await _launchTun(configJson);
      _controller.add(VpnStatus.connected);
    } catch (e) {
      _controller.add(VpnStatus.error);
      rethrow;
    }
  }

  @override
  Future<void> connectAwg(String confContent) async {
    _controller.add(VpnStatus.connecting);
    try {
      final awgExe = File('$_binDir\\amneziawg.exe');
      if (!awgExe.existsSync()) {
        throw Exception('amneziawg.exe не найден\nОжидается: ${awgExe.path}');
      }

      // Убиваем только TUN (sing-box/xray) — amneziawg не трогаем,
      // иначе Windows Service Manager получает process в FAILED-состоянии
      // и последующий uninstall/install может сломаться
      await Process.run('taskkill', ['/F', '/IM', 'sing-box.exe'], runInShell: false);
      await Process.run('taskkill', ['/F', '/IM', 'xray.exe'], runInShell: false);
      await Future.delayed(const Duration(milliseconds: 300));
      await _removeTunAdapter();
      await _killProxy();
      await _outSub?.cancel(); _outSub = null;
      await _errSub?.cancel(); _errSub = null;
      if (_process != null) {
        final old = _process!;
        _process = null;
        old.kill(ProcessSignal.sigterm);
        await old.exitCode
            .timeout(const Duration(seconds: 3),
                onTimeout: () { old.kill(); return -1; })
            .catchError((_) => -1);
      }
      try { await _configFile?.delete(); } catch (_) {}
      _configFile = null;

      await _uninstallAwgTunnel();

      final confFile = File('${Directory.systemTemp.path}\\$_awgTunnelName.conf');
      await confFile.writeAsString(confContent);

      // Установка с авто-ретраем: при "already installed" принудительно сносим службу и повторяем
      ProcessResult result = await Process.run(
        awgExe.path, ['/installtunnelservice', confFile.path], runInShell: false,
      );
      for (var attempt = 0; attempt < 2 && result.exitCode != 0; attempt++) {
        await _forceRemoveAwgService();
        result = await Process.run(
          awgExe.path, ['/installtunnelservice', confFile.path], runInShell: false,
        );
      }

      if (result.exitCode != 0) {
        throw Exception(
          'amneziawg: ошибка установки туннеля (код ${result.exitCode}): ${result.stderr}',
        );
      }

      await _waitForAwgHandshake();
      // LSO-disable убран: под корректным MTU он душил upload (AmneziaVPN его не делает)
      // await _disableAwgOffload();
      // Байпас-роут отключён для теста: wireguard-windows сам добавляет
      // endpoint-exclusion при AllowedIPs=0/0; ручной /32 может конфликтовать
      // await _ensureBypassRoute(confContent);
      _awgActive = true;
      _controller.add(VpnStatus.connected);
    } catch (e) {
      _controller.add(VpnStatus.error);
      rethrow;
    }
  }

  // Добавляет /32-маршрут для IP сервера через физический интерфейс.
  // /installtunnelservice не добавляет bypass-маршрут сам — без него
  // зашифрованные AWG UDP-пакеты уходят обратно в туннель (петля) → upload ≈ 0.
  Future<void> _ensureBypassRoute(String confContent) async {
    final match = RegExp(
      r'^Endpoint\s*=\s*([^\s:]+):\d+',
      multiLine: true,
      caseSensitive: false,
    ).firstMatch(confContent);
    if (match == null) return;

    final host = match.group(1)!.trim();
    String? serverIp;
    if (RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(host)) {
      serverIp = host;
    } else {
      try {
        final addrs = await InternetAddress.lookup(host)
            .timeout(const Duration(seconds: 5));
        serverIp = addrs
            .where((a) => a.type == InternetAddressType.IPv4)
            .map((a) => a.address)
            .firstOrNull;
      } catch (_) {}
    }
    if (serverIp == null) return;

    // Ищем дефолтный шлюз на физическом интерфейсе (не AWG)
    final gwResult = await Process.run(
      'powershell',
      [
        '-Command',
        r'$r = Get-NetRoute -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue'
            ' | Where-Object { \$_.InterfaceAlias -ne "$_awgTunnelName" }'
            r' | Sort-Object RouteMetric | Select-Object -First 1;'
            r' if ($r) { "$($r.NextHop)|$($r.InterfaceIndex)" }',
      ],
      runInShell: false,
    );
    final gwLine = (gwResult.stdout as String).trim();
    if (!gwLine.contains('|')) return;

    final gateway = gwLine.split('|')[0].trim();
    final ifIndex = gwLine.split('|')[1].trim();
    if (gateway.isEmpty || gateway == '0.0.0.0' || ifIndex.isEmpty) return;

    await Process.run(
      'powershell',
      [
        '-Command',
        'New-NetRoute -DestinationPrefix "$serverIp/32"'
            ' -InterfaceIndex $ifIndex -NextHop "$gateway"'
            ' -RouteMetric 1 -ErrorAction SilentlyContinue',
      ],
      runInShell: false,
    );
    LogService().add('[awg] bypass route: $serverIp/32 → $gateway (if$ifIndex)');
  }

  Future<void> _disableAwgOffload() async {
    try {
      await Process.run(
        'powershell',
        [
          '-Command',
          'Disable-NetAdapterLso -Name "$_awgTunnelName" -ErrorAction SilentlyContinue',
        ],
        runInShell: false,
      );
      LogService().add('[awg] LSO/checksum offload disabled');
    } catch (_) {}
  }

  Future<void> _waitForAwgHandshake() async {
    final awgCtl = File('$_binDir\\awg.exe');
    if (!awgCtl.existsSync()) {
      await Future.delayed(const Duration(seconds: 10));
      return;
    }
    const maxAttempts = 60;
    for (var i = 0; i < maxAttempts; i++) {
      await Future.delayed(const Duration(milliseconds: 500));
      final r = await Process.run(
        awgCtl.path,
        ['show', _awgTunnelName],
        runInShell: false,
      );
      if ((r.stdout as String).contains('latest handshake:')) return;
    }
    throw Exception(
      'Туннель установлен, но сервер не отвечает.\n'
      'Проверьте ключ или доступность сервера.',
    );
  }

  Future<bool> _awgServiceExists() async {
    // amneziawg.exe создаёт службу с именем AmneziaWGTunnel$<name>
    final r = await Process.run(
      'sc.exe', ['query', 'AmneziaWGTunnel\$$_awgTunnelName'],
      runInShell: false,
    );
    // exit 0 = служба есть; 1060 = нет такой службы
    return r.exitCode == 0;
  }

  Future<void> _uninstallAwgTunnel() async {
    _awgActive = false;
    if (!await _awgServiceExists()) return; // нечего удалять — мгновенно
    final awgExe = '$_binDir\\amneziawg.exe';
    await Process.run(awgExe, ['/uninstalltunnelservice', _awgTunnelName],
        runInShell: false);
    // дожидаемся исчезновения службы; если за ~3с не ушла — принудительно
    for (var i = 0; i < 10; i++) {
      await Future.delayed(const Duration(milliseconds: 300));
      if (!await _awgServiceExists()) return;
    }
    await _forceRemoveAwgService();
  }

  // Принудительный снос службы туннеля через SCM (когда /uninstalltunnelservice не справился)
  Future<void> _forceRemoveAwgService() async {
    final svc = 'AmneziaWGTunnel\$$_awgTunnelName';
    await Process.run('taskkill', ['/F', '/IM', 'amneziawg.exe'], runInShell: false);
    await Process.run('sc.exe', ['stop', svc], runInShell: false);
    await Process.run('sc.exe', ['delete', svc], runInShell: false);
    for (var i = 0; i < 15; i++) {
      await Future.delayed(const Duration(milliseconds: 300));
      if (!await _awgServiceExists()) return;
    }
  }

  Future<void> _clearSystemProxy() async {
    await Process.run('reg', [
      'add', _regPath, '/v', 'ProxyEnable', '/t', 'REG_DWORD', '/d', '0', '/f',
    ]);
  }

  @override
  Future<void> cleanup() async {
    await _clearSystemProxy();
    await Process.run('taskkill', ['/F', '/IM', 'sing-box.exe'], runInShell: false);
    await Process.run('taskkill', ['/F', '/IM', 'xray.exe'], runInShell: false);
    await _uninstallAwgTunnel();
  }

  @override
  Future<void> disconnect() async {
    _controller.add(VpnStatus.disconnecting);
    if (_awgActive) {
      await _uninstallAwgTunnel();
    } else {
      await _killExistingProcess();
    }
    await _clearSystemProxy();
    _controller.add(VpnStatus.disconnected);
  }

  @override
  void dispose() {
    if (_awgActive) _uninstallAwgTunnel();
    _proxyProcess?.kill();
    _process?.kill();
    _controller.close();
  }
}
