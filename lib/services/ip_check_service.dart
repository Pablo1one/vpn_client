import 'dart:convert';
import 'package:http/http.dart' as http;

class IpCheckResult {
  final String ip;
  final String countryCode; // XX (для флага)
  final String country;     // полное имя страны
  final String org;         // isp / провайдер выхода

  const IpCheckResult({
    required this.ip,
    required this.countryCode,
    required this.country,
    required this.org,
  });
}

// Проверка адреса выхода. Запрос идёт ЧЕРЕЗ туннель (трафик приложения захвачен
// vpn), поэтому показывает реальную точку выхода - сервер или warp.
class IpCheckService {
  static Future<IpCheckResult?> check() async {
    // основной: ip-api.com - один запрос, отдаёт ip+страну+isp
    try {
      final r = await http
          .get(Uri.parse(
              'http://ip-api.com/json/?fields=status,country,countryCode,isp,query'))
          .timeout(const Duration(seconds: 8));
      if (r.statusCode == 200) {
        final j = jsonDecode(r.body) as Map<String, dynamic>;
        if (j['status'] == 'success') {
          return IpCheckResult(
            ip: '${j['query'] ?? ''}',
            countryCode: '${j['countryCode'] ?? ''}',
            country: '${j['country'] ?? ''}',
            org: '${j['isp'] ?? ''}',
          );
        }
      }
    } catch (_) {}
    // фолбэк: ipinfo.io (https)
    try {
      final r = await http
          .get(Uri.parse('https://ipinfo.io/json'))
          .timeout(const Duration(seconds: 8));
      if (r.statusCode == 200) {
        final j = jsonDecode(r.body) as Map<String, dynamic>;
        return IpCheckResult(
          ip: '${j['ip'] ?? ''}',
          countryCode: '${j['country'] ?? ''}',
          country: '${j['country'] ?? ''}',
          org: '${j['org'] ?? ''}',
        );
      }
    } catch (_) {}
    return null;
  }
}
