import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Color, Paint, Rect;

import 'package:demo_ai_even/faces/face_data.dart';
import 'package:demo_ai_even/faces/face_renderer.dart';
import 'package:demo_ai_even/faces/face_scheduler.dart';
import 'package:demo_ai_even/faces/watch_faces.dart';
import 'package:flutter_test/flutter_test.dart';

/// Renderer tests for pixel thresholding, ordered dithering, and the 9856-byte
/// BMP packing that the G1 firmware expects (64-byte template header + 9792 px,
/// bottom-up, MSB-first, 72 bytes/row).
void main() {
  const int w = 576;
  const int h = 136;
  const int rowBytes = 72;

  /// Decode the px region of a rendered file back to logical bits (top-down,
  /// 1 = lit). The file stores them inverted - see FaceRenderer.encodeBmp.
  List<int> decodePxBits(Uint8List file) {
    final out = <int>[];
    for (var y = 0; y < h; y++) {
      final fileRow = h - 1 - y;
      final row = file.sublist(
        64 + fileRow * rowBytes,
        64 + (fileRow + 1) * rowBytes,
      );
      for (var x = 0; x < w; x++) {
        out.add(1 - ((row[x ~/ 8] >> (7 - x % 8)) & 1));
      }
    }
    return out;
  }

  group('threshold', () {
    Uint8List gray(int v) {
      final rgba = Uint8List(4 * w * h);
      for (var i = 0; i < w * h; i++) {
        rgba[4 * i] = rgba[4 * i + 1] = rgba[4 * i + 2] = v;
        rgba[4 * i + 3] = 255;
      }
      return rgba;
    }

    test('black stays off, white turns on', () {
      expect(FaceRenderer.threshold(gray(0), w, h).toSet(), {0});
      expect(FaceRenderer.threshold(gray(255), w, h).toSet(), {1});
    });

    test('cuts at mid gray - no dithering noise', () {
      expect(FaceRenderer.threshold(gray(127), w, h).toSet(), {0});
      expect(FaceRenderer.threshold(gray(128), w, h).toSet(), {1});
    });

    test('uses the mean of the colour channels', () {
      final rgba = Uint8List(4 * w * h);
      rgba[0] = 255; // pure red pixel: mean 85 -> off
      rgba[4] = rgba[5] = 255; // yellow: mean 170 -> on
      final bits = FaceRenderer.threshold(rgba, w, h);
      expect(bits[0], 0);
      expect(bits[1], 1);
    });
  });

  group('encodeBmp', () {
    final header = Uint8List.fromList(List.filled(64, 0xAB));

    test('keeps the header and packs corners bottom-up MSB-first', () {
      final bits = Uint8List(w * h);
      bits[0] = 1; // top-left
      bits[w - 1] = 1; // top-right
      bits[(h - 1) * w] = 1; // bottom-left
      bits[h * w - 1] = 1; // bottom-right

      final file = FaceRenderer.encodeBmp(bits, header: header);
      expect(file.length, 64 + rowBytes * h); // 9856
      for (var i = 0; i < 64; i++) {
        expect(file[i], 0xAB, reason: 'header byte $i');
      }
      // a lit pixel CLEARS its bit (inverted palette)
      // top row of the image = LAST file row
      expect(file[64 + (h - 1) * rowBytes] & 0x80, 0x00);
      expect(file[64 + (h - 1) * rowBytes + rowBytes - 1] & 0x01, 0x00);
      // bottom row of the image = FIRST file row
      expect(file[64] & 0x80, 0x00);
      expect(file[64 + rowBytes - 1] & 0x01, 0x00);
      // and nothing else is set
      expect(
        decodePxBits(file),
        [
          for (var i = 0; i < w * h; i++)
            (i == 0 || i == w - 1 || i == (h - 1) * w || i == h * w - 1) ? 1 : 0
        ],
      );
    });

    test('all-on bits -> every px byte is 0x00 (inverted)', () {
      final bits = Uint8List(w * h)..fillRange(0, w * h, 1);
      final file = FaceRenderer.encodeBmp(bits, header: header);
      for (var i = 64; i < file.length; i++) {
        expect(file[i], 0x00, reason: 'px byte $i');
      }
    });

    test('all-off bits -> every px byte is 0xFF, like the template', () {
      final file = FaceRenderer.encodeBmp(Uint8List(w * h), header: header);
      for (var i = 64; i < file.length; i++) {
        expect(file[i], 0xFF, reason: 'px byte $i');
      }
    });

    test('round-trips an arbitrary pattern', () {
      final bits = Uint8List(w * h);
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          bits[y * w + x] = (x * 7 + y * 13) % 3 == 0 ? 1 : 0;
        }
      }
      final file = FaceRenderer.encodeBmp(bits, header: header);
      expect(decodePxBits(file), [for (final b in bits) b]);
    });
  });

  group('watch faces', () {
    testWidgets('ordered dithering represents mid gray with half coverage',
        (tester) async {
      final bits = await tester.runAsync(
        () => FaceRenderer.rasterize(
          (canvas) => canvas.drawRect(
            const Rect.fromLTWH(10, 10, 4, 4),
            Paint()..color = const Color(0xFF808080),
          ),
          orderedDither: true,
        ),
      );

      expect(bits, isNotNull);
      var litPixels = 0;
      for (var row = 10; row < 14; row++) {
        for (var column = 10; column < 14; column++) {
          if (bits![row * FaceRenderer.width + column] == 1) litPixels++;
        }
      }
      expect(litPixels, 8);
    });

    testWidgets('matrix face has a stable static frame and moving frames',
        (tester) async {
      const face = MatrixFace();
      final staticData = FaceData(now: DateTime(2026, 9, 28, 14, 5));
      final first = await tester.runAsync(
        () => FaceRenderer().renderBits(face, const [], staticData),
      );
      final repeated = await tester.runAsync(
        () => FaceRenderer().renderBits(face, const [], staticData),
      );
      final nextFrame = await tester.runAsync(
        () => FaceRenderer().renderBits(
          face,
          const [],
          FaceData(now: staticData.now, matrixFrame: 1),
        ),
      );

      expect(first, hasLength(w * h));
      expect(repeated, first);
      expect(nextFrame, hasLength(w * h));
      final staticBits = first!;
      expect(nextFrame!.toList(), isNot(staticBits.toList()));
      expect(staticBits.contains(1), isTrue);
      expect(staticBits.contains(0), isTrue);
    });

    testWidgets('matrix trails use fewer lit pixels than hard thresholding',
        (tester) async {
      const face = MatrixFace();
      final data = FaceData(now: DateTime(2026, 9, 28, 14, 5));
      final dithered = await tester.runAsync(
        () => FaceRenderer().renderBits(face, const [], data),
      );
      final thresholded = await tester.runAsync(
        () => FaceRenderer.rasterize(
          (canvas) => paintWatchFace(canvas, face, const [], data),
        ),
      );

      expect(dithered, isNotNull);
      expect(thresholded, isNotNull);
      final ditheredLit = dithered!.where((pixel) => pixel == 1).length;
      final thresholdedLit = thresholded!.where((pixel) => pixel == 1).length;
      expect(ditheredLit, lessThan(thresholdedLit));
    });

    testWidgets('matrix renders a complete G1 BMP', (tester) async {
      final bmp = await tester.runAsync(
        () => FaceRenderer().renderBmp(
          const MatrixFace(),
          const [],
          FaceData(
            now: DateTime(2026, 9, 28, 14, 5),
            matrixFrame: 42,
          ),
        ),
      );

      expect(bmp, hasLength(FaceRenderer.bmpBytes));
      expect(bmp!.sublist(0, 2), [0x42, 0x4d]);
      expect(bmp.sublist(0, 64), await FaceRenderer().header());
      final bits = decodePxBits(bmp);
      expect(bits.contains(1), isTrue);
      expect(bits.contains(0), isTrue);
      for (final y in [0, h - 1]) {
        for (var x = 0; x < w; x++) {
          expect(bits[y * w + x], 0, reason: 'pixel ($x,$y)');
        }
      }
    });

    test('matrix content key changes only for animated frames', () {
      const face = MatrixFace();
      final firstTime = FaceData(now: DateTime(2026, 9, 28, 14, 5));
      final laterTime = FaceData(now: DateTime(2026, 9, 28, 14, 6));
      expect(faceContentKey(face, const [], firstTime),
          faceContentKey(face, const [], laterTime));
      expect(
        faceContentKey(face, const [],
            FaceData(now: DateTime(2026, 9, 28, 14, 5), matrixFrame: 1)),
        isNot(faceContentKey(face, const [], firstTime)),
      );
    });

    testWidgets('every face renders inside the panel', (tester) async {
      final data = FaceData(
        now: DateTime(2026, 9, 28, 14, 5),
        connected: true,
        batteryL: 80,
        batteryR: 75,
        customText: 'Hallo Even!',
      );
      for (final face in FaceScheduler.faces) {
        final slots = [for (final s in face.slots) s.defaultComplication];
        // picture.toImage() completes on a real engine callback, which the
        // fake async zone of testWidgets never delivers - hence runAsync.
        final bits = await tester.runAsync(
          () => FaceRenderer().renderBits(face, slots, data),
        );
        expect(bits, isNotNull, reason: face.id);
        expect(bits!.contains(1), isTrue, reason: '${face.id} drew nothing');
        // the layouts keep a margin: outermost rows stay dark
        for (final y in [0, h - 1]) {
          for (var x = 0; x < w; x++) {
            expect(bits[y * w + x], 0, reason: '${face.id}: pixel ($x,$y)');
          }
        }
      }
    });
  });

  group('template header (golden)', () {
    test('colour table maps a set bit to black (dark pixel)', () {
      final template = File('assets/images/image_2.bmp').readAsBytesSync();
      // BMP colour table for 1 bpp, BGRA per entry, at offset 54.
      expect(template.sublist(54, 58), [0xFF, 0xFF, 0xFF, 0x00],
          reason: 'index 0 must be white = lit');
      expect(template.sublist(58, 62), [0x00, 0x00, 0x00, 0x00],
          reason: 'index 1 must be black = dark');
      // ... which is why encodeBmp inverts: an unlit frame matches the
      // template's own mostly-0xFF background.
      final unlit = FaceRenderer.encodeBmp(
        Uint8List(w * h),
        header: Uint8List.fromList(template.sublist(0, 64)),
      );
      expect(unlit[64], 0xFF);
    });

    testWidgets('matches the shipped image_2.bmp', (tester) async {
      final f = File('assets/images/image_2.bmp');
      expect(f.existsSync(), isTrue,
          reason: 'flutter test runs with the project root as cwd');
      final template = f.readAsBytesSync();
      expect(template.length, 9856);
      expect(template[0], 0x42); // 'B'
      expect(template[1], 0x4D); // 'M'

      final viaBundle = await FaceRenderer().header();
      expect(viaBundle.length, 64);
      expect(viaBundle, template.sublist(0, 64));
    });
  });
}
