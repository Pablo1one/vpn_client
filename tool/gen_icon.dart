// Run from project root: dart run tool/gen_icon.dart
// Generates windows/runner/resources/app_icon.ico with a lightning bolt.

import 'dart:io';
import 'dart:typed_data';

void main() {
  // Generate three sizes for best quality across Windows contexts
  final s16 = _renderBolt(16);
  final s32 = _renderBolt(32);
  final s48 = _renderBolt(48);

  final ico = _buildIco([
    (16, s16),
    (32, s32),
    (48, s48),
  ]);

  File('windows/runner/resources/app_icon.ico').writeAsBytesSync(ico);
  print('app_icon.ico written (16, 32, 48 px)');
}

// ── Polygon definition ────────────────────────────────────────────────────────

// Lightning bolt: 8-vertex polygon, scaled to [0,1]
// Upper segment slants from top-right to mid-left; lower from mid-right to bottom-left.
// This creates the classic Z / ⚡ shape.
const _vx = [22/32, 12/32,  6/32, 14/32,  8/32, 18/32, 26/32, 18/32];
const _vy = [ 2/32,  2/32, 16/32, 16/32, 30/32, 30/32, 16/32, 16/32];

// ── Scanline polygon fill ──────────────────────────────────────────────────────

Uint32List _renderBolt(int size) {
  final px = Uint32List(size * size); // ARGB, transparent by default
  const boltArgb  = 0xFFFFCC00; // yellow
  const dark = 0xFF333300;      // outline

  // Paint outline first (1px expanded fill in dark color)
  for (var y = 0; y < size; y++) {
    for (final x in _scanAt(y + 0.5, size, expand: 1.5)) {
      px[y * size + x] = dark;
    }
  }
  // Then fill with yellow
  for (var y = 0; y < size; y++) {
    for (final x in _scanAt(y + 0.5, size, expand: 0)) {
      px[y * size + x] = boltArgb;
    }
  }
  return px;
}

Iterable<int> _scanAt(double y, int size, {required double expand}) sync* {
  final n = _vx.length;
  final xs = <double>[];
  for (var i = 0; i < n; i++) {
    final j = (i + 1) % n;
    final y0 = _vy[i] * size, y1 = _vy[j] * size;
    final x0 = _vx[i] * size, x1 = _vx[j] * size;
    if ((y0 < y && y <= y1) || (y1 < y && y <= y0)) {
      xs.add(x0 + (y - y0) / (y1 - y0) * (x1 - x0));
    }
  }
  if (xs.length < 2) return;
  xs.sort();
  for (var k = 0; k + 1 < xs.length; k += 2) {
    final xStart = (xs[k] - expand).ceil().clamp(0, size - 1);
    final xEnd = (xs[k + 1] + expand).floor().clamp(0, size - 1);
    for (var x = xStart; x <= xEnd; x++) yield x;
  }
}

// ── ICO builder ────────────────────────────────────────────────────────────────

Uint8List _buildIco(List<(int size, Uint32List pixels)> images) {
  // Pre-compute each image's BMP payload
  final payloads = <Uint8List>[];
  for (final (size, pixels) in images) {
    payloads.add(_bmpPayload(size, pixels));
  }

  final count = images.length;
  // File layout: ICONDIR(6) + count*ICONDIRENTRY(16) + payloads
  final headerLen = 6 + count * 16;
  final totalLen = headerLen + payloads.fold<int>(0, (s, p) => s + p.length);
  final buf = ByteData(totalLen);
  var o = 0;

  // ICONDIR
  buf.setUint16(o, 0, Endian.little); o += 2; // reserved
  buf.setUint16(o, 1, Endian.little); o += 2; // type = icon
  buf.setUint16(o, count, Endian.little); o += 2;

  // ICONDIRENTRY records
  var dataOffset = headerLen;
  for (var i = 0; i < count; i++) {
    final size = images[i].$1;
    final len = payloads[i].length;
    buf.setUint8(o++, size > 255 ? 0 : size); // width (0 = 256)
    buf.setUint8(o++, size > 255 ? 0 : size); // height
    buf.setUint8(o++, 0); // color count (0 = >256 colors)
    buf.setUint8(o++, 0); // reserved
    buf.setUint16(o, 1, Endian.little); o += 2; // planes
    buf.setUint16(o, 32, Endian.little); o += 2; // bit count
    buf.setUint32(o, len, Endian.little); o += 4;
    buf.setUint32(o, dataOffset, Endian.little); o += 4;
    dataOffset += len;
  }

  // Pixel payloads
  final bytes = buf.buffer.asUint8List();
  for (final payload in payloads) {
    bytes.setRange(o, o + payload.length, payload);
    o += payload.length;
  }
  return bytes;
}

// Build a 32bpp BMP DIB (BITMAPINFOHEADER + XOR mask + AND mask)
// Stored bottom-to-top as required by ICO format.
Uint8List _bmpPayload(int size, Uint32List argbPixels) {
  const hdrSize = 40;
  final xorBytes = size * size * 4;
  final andRowStride = ((size + 31) ~/ 32) * 4; // dword-aligned
  final andBytes = size * andRowStride;
  final total = hdrSize + xorBytes + andBytes;

  final buf = ByteData(total);
  var o = 0;

  // BITMAPINFOHEADER
  buf.setUint32(o, hdrSize, Endian.little); o += 4;     // biSize
  buf.setInt32(o, size, Endian.little); o += 4;          // biWidth
  buf.setInt32(o, size * 2, Endian.little); o += 4;      // biHeight (doubled for ICO)
  buf.setUint16(o, 1, Endian.little); o += 2;            // biPlanes
  buf.setUint16(o, 32, Endian.little); o += 2;           // biBitCount
  buf.setUint32(o, 0, Endian.little); o += 4;            // biCompression (BI_RGB)
  buf.setUint32(o, xorBytes, Endian.little); o += 4;     // biSizeImage
  buf.setInt32(o, 0, Endian.little); o += 4;             // biXPelsPerMeter
  buf.setInt32(o, 0, Endian.little); o += 4;             // biYPelsPerMeter
  buf.setUint32(o, 0, Endian.little); o += 4;            // biClrUsed
  buf.setUint32(o, 0, Endian.little); o += 4;            // biClrImportant

  // XOR mask: 32bpp BGRA, bottom-to-top
  for (var y = size - 1; y >= 0; y--) {
    for (var x = 0; x < size; x++) {
      final argb = argbPixels[y * size + x];
      final a = (argb >> 24) & 0xFF;
      final r = (argb >> 16) & 0xFF;
      final g = (argb >> 8) & 0xFF;
      final b = argb & 0xFF;
      buf.setUint8(o++, b);
      buf.setUint8(o++, g);
      buf.setUint8(o++, r);
      buf.setUint8(o++, a);
    }
  }

  // AND mask: 1-bit per pixel, bottom-to-top; 0 = opaque, 1 = transparent
  // With 32bpp + alpha channel, all zeros means "let alpha handle it"
  for (var y = size - 1; y >= 0; y--) {
    var maskByte = 0;
    var bitPos = 7;
    var col = 0;
    for (var x = 0; x < andRowStride * 8; x++) {
      final transparent = col < size
          ? ((argbPixels[y * size + col] >> 24) & 0xFF) == 0
          : true;
      if (transparent) maskByte |= (1 << bitPos);
      bitPos--;
      col++;
      if (bitPos < 0) {
        buf.setUint8(o++, maskByte);
        maskByte = 0;
        bitPos = 7;
      }
    }
  }

  return buf.buffer.asUint8List();
}
