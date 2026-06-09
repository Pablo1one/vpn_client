import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'log_service.dart';

enum VpnStatus { disconnected, connecting, connected, disconnecting, error }

abstract class VpnService {
  static const kAwgTunnelName = 'vpnclient_awg';

  Stream<VpnStatus> get statusStream;
  // вызывается когда дисконнект инициирован вне UI (кнопка «Отключить» в шторке
  // Android) - провайдер сбрасывает флаг авто-реконнекта, чтобы не переподключаться
  set onUserStop(void Function()? cb);
  Future<void> connect(String singboxConfigJson,
      {List<String> excludedApps = const [],
      String protocol = '',
      String country = ''});
  // единый движок (windows): один процесс sing-box-форка (tun+аутбаунд), как на Android
  Future<void> connectUnified(String singboxConfigJson);
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

// мобильный (ведроид + ios)
class _MobileVpnService implements VpnService {
  static const _method = MethodChannel('lightningmcqueen.proxy/vpn');
  static const _events = EventChannel('lightningmcqueen.proxy/vpn_events');

  final _controller = StreamController<VpnStatus>.broadcast();
  late final StreamSubscription _sub;

  @override
  void Function()? onUserStop;

  _MobileVpnService() {
    _sub = _events.receiveBroadcastStream().listen(
      (event) {
        final s = event as String;
        // пользовательская остановка из шторки - отдельное событие, не статус
        if (s == 'userstop') {
          onUserStop?.call();
          return;
        }
        _controller.add(_parse(s));
      },
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
          {List<String> excludedApps = const [],
          String protocol = '',
          String country = ''}) =>
      _method.invokeMethod('connect', {
        'config': config,
        'excludedApps': excludedApps,
        'protocol': protocol,
        'country': country,
      });

  @override
  Future<void> connectUnified(String c) =>
      throw UnsupportedError('unified engine только на windows');

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

// windows - прокси (xray или singbox) на порту 10808 плюс tun форвардер
class _WindowsVpnService implements VpnService {
  final _controller = StreamController<VpnStatus>.broadcast();

  @override
  void Function()? onUserStop; // на Windows нет нативной кнопки в шторке - не используется

  Process? _process;         // tun singbox
  StreamSubscription? _outSub;
  StreamSubscription? _errSub;
  File? _configFile;

  Process? _proxyProcess;    // xray или singbox прокси
  File? _proxyConfigFile;

  static const _awgTunnelName = VpnService.kAwgTunnelName;
  static const _regPath =
      r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings';

  @override
  Stream<VpnStatus> get statusStream => _controller.stream;

  // движок и wintun.dll лежат в {app}\bin (кладёт installer), а НЕ в flutter_assets -
  // иначе 43-мб singbox-uni.exe бандлится и в android apk (pubspec-ассеты идут на все платформы)
  String get _binDir {
    final appDir = File(Platform.resolvedExecutable).parent.path;
    return '$appDir\\bin';
  }

  String get _exePath => '$_binDir\\singbox-uni.exe';

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

  // sing-box не удаляет tun0 при падении - следующий запуск упадёт с "file already exists".
  // Условная чистка: если sing-box TUN нет (частый случай, особенно при коннекте awg) -
  // мгновенно выходим. Задержки только когда реально удаляли адаптер.
  static const _tunFilter = r'Get-NetAdapter -IncludeHidden | Where-Object {'
      r' ($_.Name -like "tun*" -or $_.InterfaceDescription -like "*Wintun*")'
      r' -and $_.Name -ne "' + _awgTunnelName + r'" }';

  Future<int> _tunAdapterCount() async {
    final r = await Process.run(
      'powershell',
      ['-NoProfile', '-NonInteractive', '-Command', '@($_tunFilter).Count'],
      runInShell: false,
    );
    return int.tryParse((r.stdout as String).trim()) ?? 0;
  }

  Future<void> _removeTunAdapter() async {
    if (await _tunAdapterCount() == 0) return; // нечего удалять - без задержек
    for (var i = 0; i < 10; i++) {
      await Process.run(
        'powershell',
        ['-NoProfile', '-NonInteractive', '-Command', '$_tunFilter | Remove-NetAdapter -Confirm:\$false -ErrorAction SilentlyContinue'],
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
    // ВАЖНО: отвязываем текущий процесс ДО taskkill. иначе его exitCode-хендлер
    // (см. _launchTunOnce) при kill'е эмитит disconnected посреди connect - кнопка
    // на миг становится серой. при неожиданном обрыве _process остаётся - там обрыв
    // ловится и идёт авто-реконнект.
    final old = _process;
    _process = null;
    await _outSub?.cancel();
    _outSub = null;
    await _errSub?.cancel();
    _errSub = null;

    // параллельно: singbox-uni - наш движок, остальные - возможный мусор от старых
    // версий (3-движковая до v1.0.16). несуществующие образы taskkill отдаёт быстро
    await Future.wait([
      Process.run('taskkill', ['/F', '/IM', 'singbox-uni.exe'], runInShell: false),
      Process.run('taskkill', ['/F', '/IM', 'sing-box.exe'], runInShell: false),
      Process.run('taskkill', ['/F', '/IM', 'xray.exe'], runInShell: false),
      Process.run('taskkill', ['/F', '/IM', 'amneziawg.exe'], runInShell: false),
    ]);
    // короткая пауза на завершение процессов; адаптер чистится условно
    await Future.delayed(const Duration(milliseconds: 400));
    await _removeTunAdapter();
    await _killProxy();
    if (old != null) {
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
    }
    try { await _configFile?.delete(); } catch (_) {}
    _configFile = null;
  }


  // Авто-ретрай старта TUN-форвардера (автоматизирует ручной reconnect).
  // ВАЖНО: убиваем только сам форвардер (_process), НЕ трогая прокси (_proxyProcess) -
  // для tuic/hysteria прокси тоже sing-box, и общий taskkill убил бы его.
  Future<void> _launchTun(String configJson, {String? exe}) async {
    const maxAttempts = 3;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        await _launchTunOnce(configJson, exe: exe);
        return;
      } catch (e) {
        // убиваем только зависший форвардер, прокси оставляем живым.
        // Чистим и на последней попытке - иначе остался бы работающий туннель
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

  Future<void> _launchTunOnce(String configJson, {String? exe}) async {
    _configFile = File(
      '${Directory.systemTemp.path}\\vpn_client_tun_${DateTime.now().millisecondsSinceEpoch}.json',
    );
    await _configFile!.writeAsString(configJson);

    _process = await Process.start(
      exe ?? _exePath,
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

    // последние строки лога - там фатальная ошибка (а не первые WARN/INFO)
    String tailLog() => allLines.isEmpty
        ? '(нет вывода)'
        : (allLines.length > 12
                ? allLines.sublist(allLines.length - 12)
                : allLines)
            .join('\n');

    // процесс умер (туннель упал позже) - сообщаем об отключении
    proc.exitCode.then((code) {
      exited = true;
      if (_process == proc) _controller.add(VpnStatus.disconnected);
    });

    // Готовность - по открытию clash_api (9090), а не по строке в логе:
    // парсинг лога давал ложные таймауты (туннель работал, а кнопка серела).
    // Холодный старт wintun - до ~25 с, потому бюджет ~30 с.
    for (var i = 0; i < 60; i++) {
      if (exited) {
        throw Exception('sing-box (TUN) завершился:\n${tailLog()}');
      }
      try {
        final s = await Socket.connect('127.0.0.1', 9090,
            timeout: const Duration(milliseconds: 300));
        await s.close();
        return; // sing-box поднял clash_api - точно готов
      } catch (_) {}
      await Future.delayed(const Duration(milliseconds: 500));
    }
    _controller.add(VpnStatus.error);
    throw Exception('sing-box не открыл clash_api за 30 с:\n${tailLog()}');
  }

  @override

  @override
  Future<void> connect(String configJson,
      {List<String> excludedApps = const [],
      String protocol = '',
      String country = ''}) async {
    _controller.add(VpnStatus.connecting);
    try {
      final exe = File(_exePath);
      if (!exe.existsSync()) {
        throw Exception('sing-box.exe не найден\nОжидается: ${exe.path}');
      }
      await _ensureWintun();
      await _killExistingProcess();
      await _launchTun(configJson);
      _controller.add(VpnStatus.connected);
    } catch (e) {
      _controller.add(VpnStatus.error);
      rethrow;
    }
  }

  // единый движок: один процесс sing-box-форка (singbox-uni.exe), tun+аутбаунд
  // в одном конфиге (как на Android). Заменяет xray+sing-box двухпроцессную схему.
  @override
  Future<void> connectUnified(String configJson) async {
    _controller.add(VpnStatus.connecting);
    // тайминг по фазам - чтобы видеть где уходит время на коннекте
    final sw = Stopwatch()..start();
    void lap(String phase) {
      LogService().add('[connect] $phase: ${sw.elapsedMilliseconds}ms');
      sw.reset();
    }
    try {
      final uni = File('$_binDir\\singbox-uni.exe');
      if (!uni.existsSync()) {
        throw Exception('singbox-uni.exe не найден\nОжидается: ${uni.path}');
      }
      await _ensureWintun();
      // _uninstallAwgTunnel убран из горячего пути: awg теперь unified (нативной
      // службы нет), а остаточную от старой версии чистит cleanup() при старте
      await _killExistingProcess();
      lap('killExisting+removeAdapter');
      await _launchTun(configJson, exe: uni.path);
      lap('launchTun (wintun+движок до готовности)');
      _controller.add(VpnStatus.connected);
    } catch (e) {
      _controller.add(VpnStatus.error);
      rethrow;
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
    await Process.run('taskkill', ['/F', '/IM', 'singbox-uni.exe'], runInShell: false);
    await Process.run('taskkill', ['/F', '/IM', 'sing-box.exe'], runInShell: false);
  }

  @override
  Future<void> disconnect() async {
    _controller.add(VpnStatus.disconnecting);
    await _killExistingProcess();
    await _clearSystemProxy();
    _controller.add(VpnStatus.disconnected);
  }

  @override
  void dispose() {
    _proxyProcess?.kill();
    _process?.kill();
    _controller.close();
  }
}
