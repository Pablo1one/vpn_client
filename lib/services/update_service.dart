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
  static const _repo = 'Pablo1one/vpn_client';
  static const releasesUrl = 'https://github.com/$_repo/releases/latest';
  static const _apiUrl = 'https://api.github.com/repos/$_repo/releases/latest';

  Future<String> currentVersion() async {
    final info = await PackageInfo.fromPlatform();
    return info.version;
  }

  /// Returns [UpdateInfo] if a newer version is available, null otherwise.
  Future<UpdateInfo?> check() async {
    try {
      final current = await currentVersion();
      final resp = await http.get(
        Uri.parse(_apiUrl),
        headers: {'Accept': 'application/vnd.github.v3+json'},
      ).timeout(const Duration(seconds: 10));

      if (resp.statusCode != 200) return null;

      final json = jsonDecode(resp.body) as Map<String, dynamic>;
      final latest =
          (json['tag_name'] as String).replaceAll(RegExp(r'^v'), '');

      if (!_isNewer(latest, current)) return null;

      final assets = (json['assets'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      final asset = assets.firstWhere(
        (a) => Platform.isWindows
            ? (a['name'] as String).endsWith('.exe')
            : (a['name'] as String).endsWith('.apk'),
        orElse: () => {},
      );

      return UpdateInfo(
        version: latest,
        downloadUrl:
            (asset['browser_download_url'] as String?) ?? releasesUrl,
      );
    } catch (_) {
      return null;
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
