/// Generates assets/data/allowed_ips_bypass.txt —
/// the complement of Russian IP space used as AllowedIPs
/// in WireGuard Russia-bypass mode.
///
/// Run: dart run scripts/gen_bypass_ips.dart
import 'dart:io';

void main() {
  final input = File('assets/data/iplist_ru.txt');
  final ruCidrs = input
      .readAsLinesSync()
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty && !l.startsWith('#'))
      .toList();

  print('Loaded ${ruCidrs.length} Russian CIDRs');

  final result = invertIpv4(ruCidrs);
  print('Computed ${result.length} AllowedIPs blocks');

  final out = File('assets/data/allowed_ips_bypass.txt');
  out.writeAsStringSync('# Auto-generated — run scripts/gen_bypass_ips.dart to update\n');
  out.writeAsStringSync(result.join('\n'), mode: FileMode.append);
  out.writeAsStringSync('\n', mode: FileMode.append);
  print('Written to ${out.path}');
}

// ── CIDR inversion ──────────────────────────────────────────────────────────

List<String> invertIpv4(List<String> excludeCidrs) {
  final excluded = <_Block>[];
  for (final s in excludeCidrs) {
    final b = _parse(s.trim());
    if (b != null) excluded.add(b);
  }
  var allowed = [const _Block(0, 0)];
  for (var i = 0; i < excluded.length; i++) {
    if (i % 500 == 0) stderr.write('\r  processing ${i + 1}/${excluded.length}...');
    final ex = excluded[i];
    final next = <_Block>[];
    for (final block in allowed) {
      next.addAll(_subtract(block, ex));
    }
    allowed = next;
  }
  stderr.writeln('\r  done.                    ');
  return allowed.map((b) => b.toCidr()).toList();
}

_Block? _parse(String cidr) {
  try {
    final slash = cidr.indexOf('/');
    if (slash < 0) return null;
    final prefix = int.parse(cidr.substring(slash + 1));
    final parts = cidr.substring(0, slash).split('.');
    if (parts.length != 4 || prefix < 0 || prefix > 32) return null;
    final ip = (int.parse(parts[0]) << 24) |
        (int.parse(parts[1]) << 16) |
        (int.parse(parts[2]) << 8) |
        int.parse(parts[3]);
    return _Block(ip & _mask(prefix), prefix);
  } catch (_) {
    return null;
  }
}

List<_Block> _subtract(_Block block, _Block ex) {
  if (!_overlaps(block, ex)) return [block];
  if (_contains(ex, block)) return [];
  final result = <_Block>[];
  for (final half in block.halves()) {
    result.addAll(_subtract(half, ex));
  }
  return result;
}

bool _overlaps(_Block a, _Block b) => _contains(a, b) || _contains(b, a);

bool _contains(_Block outer, _Block inner) {
  if (outer.prefix > inner.prefix) return false;
  final m = _mask(outer.prefix);
  return (inner.ip & m) == outer.ip;
}

int _mask(int prefix) {
  if (prefix == 0) return 0;
  if (prefix >= 32) return 0xFFFFFFFF;
  return (~((1 << (32 - prefix)) - 1)) & 0xFFFFFFFF;
}

class _Block {
  final int ip;
  final int prefix;
  const _Block(this.ip, this.prefix);

  List<_Block> halves() {
    final halfSize = 1 << (31 - prefix);
    return [_Block(ip, prefix + 1), _Block(ip | halfSize, prefix + 1)];
  }

  String toCidr() =>
      '${(ip >> 24) & 0xFF}.${(ip >> 16) & 0xFF}.${(ip >> 8) & 0xFF}.${ip & 0xFF}/$prefix';
}
