import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

enum TrayIconVariant { none, connected, error }

class TrayIconPainter {
  static Future<String> buildAndSave(
      TrayIconVariant v, String dir) async {
    final path = '$dir/vpn_tray_${v.name}.ico';
    final bytes = await _generateIco(v);
    await File(path).writeAsBytes(bytes);
    return path;
  }

  static Future<Uint8List> _generateIco(TrayIconVariant v) async {
    const size = 32;
    final recorder = ui.PictureRecorder();
    final sz = size.toDouble();
    final canvas = ui.Canvas(
        recorder, ui.Rect.fromLTWH(0, 0, sz, sz));
    _paint(canvas, v, size.toDouble());
    final picture = recorder.endRecording();
    final img = await picture.toImage(size, size);
    final bd = await img.toByteData(format: ui.ImageByteFormat.png);
    img.dispose();
    return _pngToIco(bd!.buffer.asUint8List(), size, size);
  }

  static void _paint(ui.Canvas c, TrayIconVariant v, double s) {
    _drawBolt(c, s);
    if (v == TrayIconVariant.connected) _drawBars(c, s);
    if (v == TrayIconVariant.error) _drawRedX(c, s);
  }

  // ── Bolt ───────────────────────────────────────────────────────────────────

  static void _drawBolt(ui.Canvas c, double s) {
    // 8-point lightning bolt polygon (diagonal, top-right - bottom-left)
    // Vertices: A(22,2) B(12,2) C(6,16) D(14,16) E(8,30) F(18,30) G(26,16) H(18,16)
    final path = ui.Path()
      ..moveTo(s * 22 / 32, s * 2 / 32) // A
      ..lineTo(s * 12 / 32, s * 2 / 32) // B
      ..lineTo(s * 6 / 32, s * 16 / 32) // C
      ..lineTo(s * 14 / 32, s * 16 / 32) // D
      ..lineTo(s * 8 / 32, s * 30 / 32) // E
      ..lineTo(s * 18 / 32, s * 30 / 32) // F
      ..lineTo(s * 26 / 32, s * 16 / 32) // G
      ..lineTo(s * 18 / 32, s * 16 / 32) // H
      ..close();

    // Dark shadow so bolt is visible on any taskbar color
    c.drawPath(
      path,
      ui.Paint()
        ..color = const ui.Color(0xCC000000)
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = s * 0.18
        ..strokeJoin = ui.StrokeJoin.round,
    );
    c.drawPath(
      path,
      ui.Paint()
        ..color = const ui.Color(0xFFFFCC00)
        ..style = ui.PaintingStyle.fill,
    );
  }

  // ── Green signal bars (connected) ─────────────────────────────────────────

  static void _drawBars(ui.Canvas c, double s) {
    // Small dark background pill
    final bgR = ui.RRect.fromRectAndRadius(
      ui.Rect.fromLTWH(s * 0.56, s * 0.58, s * 0.42, s * 0.40),
      const ui.Radius.circular(3),
    );
    c.drawRRect(bgR,
        ui.Paint()..color = const ui.Color(0xDD0A0A1A));

    final bar = ui.Paint()
      ..color = const ui.Color(0xFF44DD66)
      ..style = ui.PaintingStyle.fill;

    final barW = s * 0.09;
    final gap = s * 0.045;
    final baseY = s * 0.95;
    final heights = [s * 0.12, s * 0.20, s * 0.30];
    var x = s * 0.61;
    for (final h in heights) {
      c.drawRRect(
        ui.RRect.fromRectAndRadius(
          ui.Rect.fromLTWH(x, baseY - h, barW, h),
          const ui.Radius.circular(1.5),
        ),
        bar,
      );
      x += barW + gap;
    }
  }

  // ── Red X (error / disconnected) ──────────────────────────────────────────

  static void _drawRedX(ui.Canvas c, double s) {
    final cx = s * 0.77;
    final cy = s * 0.77;
    final r = s * 0.20;

    c.drawCircle(cx == 0 ? ui.Offset.zero : ui.Offset(cx, cy), r,
        ui.Paint()..color = const ui.Color(0xFFCC1111));

    final line = ui.Paint()
      ..color = const ui.Color(0xFFFFFFFF)
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = s * 0.085
      ..strokeCap = ui.StrokeCap.round;
    final d = r * 0.55;
    c.drawLine(ui.Offset(cx - d, cy - d), ui.Offset(cx + d, cy + d), line);
    c.drawLine(ui.Offset(cx + d, cy - d), ui.Offset(cx - d, cy + d), line);
  }

  // ── PNG - ICO wrapper ─────────────────────────────────────────────────────

  static Uint8List _pngToIco(Uint8List png, int w, int h) {
    final hdr = ByteData(22);
    hdr.setUint16(0, 0, Endian.little);  // reserved
    hdr.setUint16(2, 1, Endian.little);  // type: icon
    hdr.setUint16(4, 1, Endian.little);  // count: 1
    hdr.setUint8(6, w > 255 ? 0 : w);
    hdr.setUint8(7, h > 255 ? 0 : h);
    hdr.setUint8(8, 0);
    hdr.setUint8(9, 0);
    hdr.setUint16(10, 1, Endian.little);
    hdr.setUint16(12, 32, Endian.little);
    hdr.setUint32(14, png.length, Endian.little);
    hdr.setUint32(18, 22, Endian.little); // offset = 6+16
    final out = Uint8List(22 + png.length);
    out.setRange(0, 22, hdr.buffer.asUint8List());
    out.setRange(22, 22 + png.length, png);
    return out;
  }
}
