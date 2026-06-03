import 'dart:io';
import 'log_service.dart';

/// Чистит «чужие» маршруты в обход VPN — подсети, направленные на шлюз
/// локальной сети (их добавляют split-tunnel других VPN, напр. AmneziaVPN,
/// командой `route add <subnet> <gateway> -p`). Тысячи таких маршрутов
/// специфичнее дефолта туннеля и уводят трафик мимо VPN.
///
/// Удаляются ТОЛЬКО не-дефолтные подсети (`< /32`), указывающие на шлюз(ы)
/// из дефолтного маршрута — из активного и постоянного хранилищ. Дефолт
/// `0.0.0.0/0`, локальная сеть (on-link) и host-маршруты `/32` (в т.ч. наш
/// маршрут до сервера) не трогаются.
class RouteCleanupService {
  /// Возвращает число удалённых маршрутов (из активной таблицы).
  Future<int> cleanBypassRoutes() async {
    if (!Platform.isWindows) return 0;
    const script = r'''
$gw = (Get-NetRoute -AddressFamily IPv4 -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue).NextHop |
      Where-Object { $_ -and $_ -ne '0.0.0.0' } | Select-Object -Unique
if (-not $gw) { '0'; exit }
$f = { ($gw -contains $_.NextHop) -and ($_.DestinationPrefix -ne '0.0.0.0/0') -and ([int]($_.DestinationPrefix.Split('/')[1]) -lt 32) }
$active = @(Get-NetRoute -AddressFamily IPv4 -PolicyStore ActiveStore -ErrorAction SilentlyContinue | Where-Object $f)
$n = $active.Count
if ($n -gt 0) { $active | Remove-NetRoute -Confirm:$false -ErrorAction SilentlyContinue }
Get-NetRoute -AddressFamily IPv4 -PolicyStore PersistentStore -ErrorAction SilentlyContinue |
  Where-Object $f | Remove-NetRoute -PolicyStore PersistentStore -Confirm:$false -ErrorAction SilentlyContinue
$n
''';
    try {
      final r = await Process.run(
        'powershell',
        ['-NoProfile', '-NonInteractive', '-Command', script],
        runInShell: false,
      );
      final out = (r.stdout as String).trim();
      final n = int.tryParse(out.split('\n').last.trim()) ?? 0;
      if (n > 0) {
        LogService().add('[routes] удалено маршрутов в обход VPN: $n');
      }
      return n;
    } catch (e) {
      LogService().add('[routes] ошибка очистки маршрутов: $e');
      return 0;
    }
  }
}
