import 'dart:io';
import 'package:package_info_plus/package_info_plus.dart';

class EngineVersions {
  final String app;
  final String xray;
  final String singbox;
  final String amneziawg;
  final String wintun;

  const EngineVersions({
    required this.app,
    required this.xray,
    required this.singbox,
    required this.amneziawg,
    required this.wintun,
  });
}

/// Читает версии встроенных ядер (xray/sing-box — через `version`,
/// amneziawg/wintun — из ресурсов файла) для отображения в настройках.
class EngineVersionService {
  static const _dash = '—';

  String get _binDir {
    final appDir = File(Platform.resolvedExecutable).parent.path;
    return '$appDir\\data\\flutter_assets\\assets\\bin';
  }

  Future<EngineVersions> load() async {
    final app = await _appVersion();
    if (!Platform.isWindows) {
      return EngineVersions(
        app: app,
        xray: _dash,
        singbox: _dash,
        amneziawg: _dash,
        wintun: _dash,
      );
    }
    final results = await Future.wait([
      _cmdVersion('$_binDir\\xray.exe', RegExp(r'Xray\s+(\S+)')),
      _cmdVersion('$_binDir\\sing-box.exe', RegExp(r'version\s+(\S+)')),
      _fileVersions(),
    ]);
    final fileV = results[2] as Map<String, String>;
    return EngineVersions(
      app: app,
      xray: results[0] as String,
      singbox: results[1] as String,
      amneziawg: fileV['amneziawg'] ?? _dash,
      wintun: fileV['wintun'] ?? _dash,
    );
  }

  Future<String> _appVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return info.version;
    } catch (_) {
      return _dash;
    }
  }

  Future<String> _cmdVersion(String exe, RegExp re) async {
    try {
      if (!File(exe).existsSync()) return _dash;
      final r = await Process.run(exe, ['version'], runInShell: false)
          .timeout(const Duration(seconds: 5));
      final out = (r.stdout as String);
      final m = re.firstMatch(out);
      return m?.group(1) ?? _dash;
    } catch (_) {
      return _dash;
    }
  }

  // ProductVersion из ресурсов exe/dll (Go-бинари xray/sing-box его не заполняют,
  // поэтому для них используем `version`, а здесь — amneziawg и wintun).
  Future<Map<String, String>> _fileVersions() async {
    try {
      final script =
          r'$b="' + _binDir + r'";'
          r'"$((Get-Item "$b\amneziawg.exe" -EA SilentlyContinue).VersionInfo.ProductVersion)'
          r'|$((Get-Item "$b\wintun.dll" -EA SilentlyContinue).VersionInfo.ProductVersion)"';
      final r = await Process.run('powershell', ['-NoProfile', '-Command', script],
              runInShell: false)
          .timeout(const Duration(seconds: 5));
      final parts = (r.stdout as String).trim().split('|');
      return {
        'amneziawg': parts.isNotEmpty && parts[0].trim().isNotEmpty
            ? parts[0].trim()
            : _dash,
        'wintun': parts.length > 1 && parts[1].trim().isNotEmpty
            ? parts[1].trim()
            : _dash,
      };
    } catch (_) {
      return {};
    }
  }
}
