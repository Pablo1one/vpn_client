import 'dart:ui' as ui;
import 'package:flutter/material.dart';

import 'world_map_data.dart';

/// Фоновая точечная карта мира. Масштабируется под размер (cover - заполняет
/// область, лишнее обрезается), тонируется переданным цветом. Не ловит клики.
class WorldMapBackground extends StatelessWidget {
  final Color color;
  final double opacity;
  const WorldMapBackground({super.key, required this.color, this.opacity = 0.14});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: SizedBox.expand(
        child: CustomPaint(
          painter: _WorldMapPainter(color.withOpacity(opacity)),
        ),
      ),
    );
  }
}

class _WorldMapPainter extends CustomPainter {
  final Color color;
  _WorldMapPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    // cover: грид заполняет всю область, выходящее за края обрезается
    final cell = (size.width / worldMapW > size.height / worldMapH)
        ? size.width / worldMapW
        : size.height / worldMapH;
    final ox = (size.width - worldMapW * cell) / 2;
    final oy = (size.height - worldMapH * cell) / 2;

    final points = <Offset>[];
    for (var gy = 0; gy < worldMapH; gy++) {
      final base = gy * worldMapW;
      for (var gx = 0; gx < worldMapW; gx++) {
        if (worldMapData.codeUnitAt(base + gx) == 0x31) {
          points.add(Offset(ox + (gx + 0.5) * cell, oy + (gy + 0.5) * cell));
        }
      }
    }
    final paint = Paint()
      ..color = color
      ..strokeCap = StrokeCap.round
      ..strokeWidth = cell * 0.68; // диаметр точки чуть меньше ячейки
    canvas.drawPoints(ui.PointMode.points, points, paint);
  }

  @override
  bool shouldRepaint(_WorldMapPainter old) => old.color != color;
}
