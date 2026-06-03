import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

class UpdateInfo {
  final String version;
  final String downloadUrl;
  const UpdateInfo({required this.version, required this.downloadUrl});
}

class UpdateService {
  // публичный репозиторий только с релизами (инсталлеры) — код приватный, а
  // GitHub API /releases/latest у приватного репо без токена отдаёт 404
  static const _repo = 'Pablo1one/vpn_client_releases';
  static const releasesUrl = 'https://github.com/$_repo/releases/latest';
  static const _apiUrl = 'https://api.github.com/repos/$_repo/releases/latest';

  Future<String> currentVersion() async {
    final info = await PackageInfo.fromPlatform();
    return info.version;
  }

  /// Returns [UpdateInfo] if a newer version is available, null if up to date.
  /// Бросает исключение при сбое проверки (нет сети, приватный репо, нет релизов → 404).
  Future<UpdateInfo?> check() async {
    final current = await currentVersion();
    final resp = await http.get(
      Uri.parse(_apiUrl),
      headers: {'Accept': 'application/vnd.github.v3+json'},
    ).timeout(const Duration(seconds: 10));

    if (resp.statusCode != 200) {
      throw Exception('GitHub API: HTTP ${resp.statusCode}');
    }

    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    final latest = (json['tag_name'] as String).replaceAll(RegExp(r'^v'), '');

    if (!_isNewer(latest, current)) return null;

    final assets =
        (json['assets'] as List<dynamic>).cast<Map<String, dynamic>>();
    final asset = assets.firstWhere(
      (a) => Platform.isWindows
          ? (a['name'] as String).endsWith('.exe')
          : (a['name'] as String).endsWith('.apk'),
      orElse: () => {},
    );

    return UpdateInfo(
      version: latest,
      downloadUrl: (asset['browser_download_url'] as String?) ?? releasesUrl,
    );
  }

  /// Скачивает инсталлятор во временную папку и запускает его, затем закрывает
  /// приложение (чтобы инсталлятор смог перезаписать файлы). Только Windows.
  /// [onProgress] — доля загрузки 0..1 (если сервер отдал Content-Length).
  Future<void> downloadAndRun(
    UpdateInfo info, {
    void Function(double progress)? onProgress,
  }) async {
    if (!Platform.isWindows) {
      throw Exception('Авто-установка поддерживается только на Windows');
    }
    final client = http.Client();
    try {
      final req = http.Request('GET', Uri.parse(info.downloadUrl));
      final resp = await client.send(req).timeout(const Duration(minutes: 5));
      if (resp.statusCode != 200) {
        throw Exception('Загрузка: HTTP ${resp.statusCode}');
      }
      final total = resp.contentLength ?? 0;
      final file = File(
          '${Directory.systemTemp.path}\\LightningMcQueen-Setup-${info.version}.exe');
      final sink = file.openWrite();
      var received = 0;
      await for (final chunk in resp.stream) {
        received += chunk.length;
        sink.add(chunk);
        if (total > 0 && onProgress != null) onProgress(received / total);
      }
      await sink.flush();
      await sink.close();

      // запускаем инсталлятор отдельным процессом (он сам поднимет UAC) и выходим
      await Process.start(file.path, const [],
          mode: ProcessStartMode.detached);
      await Future.delayed(const Duration(milliseconds: 600));
      exit(0);
    } finally {
      client.close();
    }
  }

  static bool _isNewer(String a, String b) {
    List<int> parse(String v) =>
        v.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    final av = parse(a), bv = parse(b);
    for (var i = 0; i < 3; i++) {
      final ai = i < av.length ? av[i] : 0;
      final bi = i < bv.length ? bv[i] : 0;
      if (ai > bi) return true;
      if (ai < bi) return false;
    }
    return false;
  }
}
