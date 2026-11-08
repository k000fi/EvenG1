import 'dart:ui' show ImageByteFormat, PictureRecorder;

import 'package:demo_ai_even/faces/face_data.dart';
import 'package:demo_ai_even/faces/watch_faces.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

/// Turns a [WatchFace] + its complications + [FaceData] into the exact byte
/// stream the G1 firmware expects for a 0x15 BMP transfer:
///
///   1. paint the face into a 576 x 136 canvas (white on black)
///   2. rasterize to RGBA
///   3. threshold to 1 bit (1 = pixel ON = green), or use ordered dithering
///      for the Matrix face's darker trails.
///   4. pack to a 9856-byte BMP: 64-byte header (byte-identical to
///      assets/images/image_2.bmp) + 9792 bottom-up rows of 72 bytes,
///      MSB-first, **inverted** (see [encodeBmp]).
///
/// Steps 3 and 4 are pure Dart and fully unit-testable; step 2 uses the
/// Flutter software rasterizer (also available in flutter_test).
class FaceRenderer {
  static const int width = kFaceWidth;
  static const int height = kFaceHeight;
  static const int rowBytes = (width + 7) ~/ 8; // 72
  static const int pixelBytes = rowBytes * height; // 9792
  static const int bmpBytes = 64 + pixelBytes; // 9856

  /// Cached 64-byte BMP header, byte-identical to the working template.
  Uint8List? _header;

  Future<Uint8List> header() async {
    _header ??= await _loadHeader();
    return _header!;
  }

  Future<Uint8List> _loadHeader() async {
    final bytes = await rootBundle.load('assets/images/image_2.bmp');
    final h = bytes.buffer.asUint8List(bytes.offsetInBytes, 64);
    if (h.length != 64) {
      throw StateError('image_2.bmp header must be 64 bytes, got ${h.length}');
    }
    return Uint8List.fromList(h);
  }

  /// Renders [face] with its complications to a 1-bit row-major bitmap
  /// (width*height bytes, 1 = ON). Row 0 is the top of the picture.
  Future<Uint8List> renderBits(
          WatchFace face, List<String> slotIds, FaceData data) =>
      rasterize(
        (canvas) => paintWatchFace(canvas, face, slotIds, data),
        orderedDither: face is MatrixFace,
      );

  /// Full pipeline: face -> 9856-byte BMP file bytes.
  Future<Uint8List> renderBmp(
      WatchFace face, List<String> slotIds, FaceData data) async {
    final bits = await renderBits(face, slotIds, data);
    return encodeBmp(bits, header: await header());
  }

  /// Runs [paint] on a black 576 x 136 canvas and returns the 1-bit result.
  static Future<Uint8List> rasterize(
    void Function(Canvas canvas) paint, {
    bool orderedDither = false,
  }) async {
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
      Rect.fromLTWH(0.0, 0.0, width.toDouble(), height.toDouble()),
      Paint()..color = const Color(0xFF000000),
    );
    paint(canvas);
    final picture = recorder.endRecording();
    final image = await picture.toImage(width, height);
    final byteData = await image.toByteData(format: ImageByteFormat.rawRgba);
    image.dispose();
    picture.dispose();
    if (byteData == null) {
      throw StateError('toByteData returned null');
    }
    final rgba = byteData.buffer.asUint8List(byteData.offsetInBytes);
    return orderedDither
        ? _orderedDither(rgba, width, height)
        : threshold(rgba, width, height);
  }

  static const _bayer4 = [
    [0, 8, 2, 10],
    [12, 4, 14, 6],
    [3, 11, 1, 9],
    [15, 7, 13, 5],
  ];

  static Uint8List _orderedDither(Uint8List rgba, int w, int h) {
    final bits = Uint8List(w * h);
    for (var row = 0; row < h; row++) {
      if (row == 0 || row == h - 1) continue;
      for (var column = 0; column < w; column++) {
        final rgbaOffset = 4 * (row * w + column);
        final brightness =
            rgba[rgbaOffset] + rgba[rgbaOffset + 1] + rgba[rgbaOffset + 2];
        final rank = _bayer4[row % 4][column % 4];
        final cutoff = 3 * (rank * 16 + 8);
        if (brightness >= cutoff) bits[row * w + column] = 1;
      }
    }
    return bits;
  }

  /// RGBA -> 1 bit (row-major): a pixel is ON when its mean channel value is
  /// at least [level].
  static Uint8List threshold(Uint8List rgba, int w, int h, {int level = 128}) {
    final n = w * h;
    final bits = Uint8List(n);
    for (var i = 0; i < n; i++) {
      final r = 4 * i;
      if (rgba[r] + rgba[r + 1] + rgba[r + 2] >= 3 * level) bits[i] = 1;
    }
    return bits;
  }

  /// Packs 1-bit row-major (top-down, 1=ON) pixels into BMP file bytes:
  /// [header] + 9792 bytes, bottom-up, 72 bytes/row, MSB-first.
  ///
  /// **The bit sense is inverted.** The colour table of the template header
  /// (bytes 54..61 of assets/images/image_2.bmp) is
  /// `index 0 = ff ff ff` (white -> lit green) and `index 1 = 00 00 00`
  /// (black -> dark), so a *set* bit is a DARK pixel. The template's own
  /// payload agrees: 71 % of its bytes are 0xFF, i.e. unlit background.
  /// We therefore start from all-ones and clear the bits that light up.
  static Uint8List encodeBmp(Uint8List bits, {required Uint8List header}) {
    assert(
        bits.length == width * height, 'bits must be ${width * height} bytes');
    assert(header.length == 64, 'header must be 64 bytes');

    final px = Uint8List(pixelBytes)..fillRange(0, pixelBytes, 0xFF);
    for (var y = 0; y < height; y++) {
      final imageRow = y; // 0 = top
      final fileRow = height - 1 - y; // BMP is bottom-up
      for (var x = 0; x < width; x++) {
        if (bits[imageRow * width + x] == 1) {
          final idx = fileRow * rowBytes + (x ~/ 8);
          px[idx] = px[idx] & ~(0x80 >> (x % 8)) & 0xFF;
        }
      }
    }

    final out = Uint8List(bmpBytes);
    out.setRange(0, 64, header);
    out.setRange(64, bmpBytes, px);
    return out;
  }
}
