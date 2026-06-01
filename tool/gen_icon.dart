// Run from project root: dart run tool/gen_icon.dart
// Generates windows/runner/resources/app_icon.ico with a lightning bolt.

import 'dart:io';
import 'dart:typed_data';

void main() {
  const sizes = [16, 32, 48, 64, 128, 256];
  final ico = _buildIco([for (final s in sizes) (s, _renderBolt(s))]);
  File('windows/runner/resources/app_icon.ico').writeAsBytesSync(ico);
  // превью для визуальной проверки
  File('tool/icon_preview.png').writeAsBytesSync(_encodePng(256, _renderBolt(256)));
  print('app_icon.ico written (${sizes.join(", ")} px) + tool/icon_preview.png');
}

// ── Минимальный PNG-энкодер (RGBA, deflate stored) ───────────────────────────

Uint8List _encodePng(int size, Uint32List argb) {
  final raw = BytesBuilder();
  for (var y = 0; y < size; y++) {
    raw.addByte(0); // filter: none
    for (var x = 0; x < size; x++) {
      final p = argb[y * size + x];
      raw.addByte((p >> 16) & 0xFF); // R
      raw.addByte((p >> 8) & 0xFF);  // G
      raw.addByte(p & 0xFF);         // B
      raw.addByte((p >> 24) & 0xFF); // A
    }
  }
  final rawData = raw.toBytes();

  final out = BytesBuilder();
  out.add([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]); // signature

  // IHDR
  final ihdr = ByteData(13);
  ihdr.setUint32(0, size); ihdr.setUint32(4, size);
  ihdr.setUint8(8, 8);  // bit depth
  ihdr.setUint8(9, 6);  // RGBA
  _chunk(out, 'IHDR', ihdr.buffer.asUint8List());

  // IDAT: zlib (header + stored deflate + adler32)
  final z = BytesBuilder();
  z.add([0x78, 0x01]); // zlib header
  var off = 0;
  while (off < rawData.length) {
    final n = (rawData.length - off).clamp(0, 65535);
    final last = off + n >= rawData.length;
    z.addByte(last ? 1 : 0);
    z.add([n & 0xFF, (n >> 8) & 0xFF, (~n) & 0xFF, ((~n) >> 8) & 0xFF]);
    z.add(rawData.sublist(off, off + n));
    off += n;
  }
  final adler = _adler32(rawData);
  z.add([(adler >> 24) & 0xFF, (adler >> 16) & 0xFF, (adler >> 8) & 0xFF, adler & 0xFF]);
  _chunk(out, 'IDAT', z.toBytes());

  _chunk(out, 'IEND', Uint8List(0));
  return out.toBytes();
}

void _chunk(BytesBuilder out, String type, Uint8List data) {
  final len = ByteData(4)..setUint32(0, data.length);
  out.add(len.buffer.asUint8List());
  final typeBytes = Uint8List.fromList(type.codeUnits);
  out.add(typeBytes);
  out.add(data);
  final crcData = BytesBuilder()..add(typeBytes)..add(data);
  final crc = ByteData(4)..setUint32(0, _crc32(crcData.toBytes()));
  out.add(crc.buffer.asUint8List());
}

int _adler32(Uint8List d) {
  var a = 1, b = 0;
  for (final byte in d) {
    a = (a + byte) % 65521;
    b = (b + a) % 65521;
  }
  return (b << 16) | a;
}

int _crc32(Uint8List d) {
  var crc = 0xFFFFFFFF;
  for (final byte in d) {
    crc ^= byte;
    for (var i = 0; i < 8; i++) {
      crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1;
    }
  }
  return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}

// ── Polygon definition ────────────────────────────────────────────────────────

// Горизонтальная молния (стиль Lightning McQueen): болт с ОСТРЫМИ концами.
// Вертикальный острый болт (13,0)(3,14)(10,14)(11,24)(21,10)(14,10),
// повёрнут на 90° по часовой: (x,y)->(24-y, x). Острые торцы слева и справа.
const _vx = [24/24, 10/24, 10/24,  0/24, 14/24, 14/24];
const _vy = [13/24,  3/24, 10/24, 11/24, 21/24, 14/24];

// ── Scanline polygon fill ──────────────────────────────────────────────────────

Uint32List _renderBolt(int size) {
  final px = Uint32List(size * size); // ARGB, transparent by default
  const black  = 0xFF101010; // обводка
  const red    = 0xFFE01600; // контур McQueen
  const yellow = 0xFFFFCC00; // заливка

  // три концентрических слоя (от центра): чёрный → красный → жёлтый
  _fillScaled(px, size, 0.96, black);
  _fillScaled(px, size, 0.86, red);
  _fillScaled(px, size, 0.74, yellow);
  return px;
}

// центроид нормализованного полигона
double get _cx => _vx.reduce((a, b) => a + b) / _vx.length;
double get _cy => _vy.reduce((a, b) => a + b) / _vy.length;

void _fillScaled(Uint32List px, int size, double scale, int color) {
  for (var y = 0; y < size; y++) {
    for (final x in _scanAt(y + 0.5, size, scale)) {
      px[y * size + x] = color;
    }
  }
}

// заливка полигона на скан-линии y; полигон масштабируется от центроида на scale
Iterable<int> _scanAt(double y, int size, double scale) sync* {
  final cx = _cx, cy = _cy;
  final n = _vx.length;
  final xs = <double>[];
  for (var i = 0; i < n; i++) {
    final j = (i + 1) % n;
    final y0 = (cy + (_vy[i] - cy) * scale) * size;
    final y1 = (cy + (_vy[j] - cy) * scale) * size;
    final x0 = (cx + (_vx[i] - cx) * scale) * size;
    final x1 = (cx + (_vx[j] - cx) * scale) * size;
    if ((y0 < y && y <= y1) || (y1 < y && y <= y0)) {
      xs.add(x0 + (y - y0) / (y1 - y0) * (x1 - x0));
    }
  }
  if (xs.length < 2) return;
  xs.sort();
  for (var k = 0; k + 1 < xs.length; k += 2) {
    final xStart = xs[k].ceil().clamp(0, size - 1);
    final xEnd = xs[k + 1].floor().clamp(0, size - 1);
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
