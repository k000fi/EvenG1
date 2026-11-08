import 'package:flutter/material.dart';

import 'complications.dart';
import 'face_data.dart';
import 'face_format.dart';
import 'face_text.dart';
import 'glyphs.dart';

/// One complication position on a face.
class FaceSlot {
  /// Shown in the editor, e.g. "Oben links".
  final String label;
  final Rect rect;
  final ComplicationFamily family;
  final TextAlign align;
  final String defaultComplication;

  const FaceSlot({
    required this.label,
    required this.rect,
    required this.family,
    required this.defaultComplication,
    this.align = TextAlign.left,
  });
}

/// A watch face: a base (the time, drawn by the face itself) plus slots the
/// user fills with complications. All drawing is white on black in panel
/// coordinates (576 x 136); the renderer turns it into the 1-bit bitmap.
abstract class WatchFace {
  const WatchFace();

  String get id;
  String get name;
  String get description;
  List<FaceSlot> get slots;

  String contentKey(FaceData data) => Fmt.hhmm(data.now);

  void paintBase(Canvas c, FaceData d);
}

/// Paints [face] with [slotIds] (one complication id per slot).
void paintWatchFace(
    Canvas canvas, WatchFace face, List<String> slotIds, FaceData data) {
  face.paintBase(canvas, data);
  for (var i = 0; i < face.slots.length; i++) {
    final slot = face.slots[i];
    final complication = Complications.byId(slotIdAt(face, slotIds, i));
    ComplicationPainter.paint(
        canvas, slot.rect, slot.family, slot.align, complication.content(data));
  }
}

/// Changes exactly when the pixels of the face change: the minute (every face
/// shows the time) plus what each complication displays.
String faceContentKey(WatchFace face, List<String> slotIds, FaceData data) => [
      face.id,
  face.contentKey(data),
      for (var i = 0; i < face.slots.length; i++)
        _slotKey(Complications.byId(slotIdAt(face, slotIds, i)), data),
    ].join('|');

String _slotKey(Complication c, FaceData data) => '${c.id}:${c.contentKey(data)}';

String slotIdAt(WatchFace face, List<String> slotIds, int i) =>
    i < slotIds.length ? slotIds[i] : face.slots[i].defaultComplication;

// ------------------------------------------------------------------ faces

/// Big digital time with the date, four small complications in a grid -
/// watchOS "Modular".
class ModularFace extends WatchFace {
  const ModularFace();
  @override
  String get id => 'modular';
  @override
  String get name => 'Modular';
  @override
  String get description => 'Große Digitalzeit, Datum und vier Komplikationen';

  @override
  List<FaceSlot> get slots => const [
        FaceSlot(
            label: 'Oben links',
            rect: Rect.fromLTWH(254, 10, 150, 54),
            family: ComplicationFamily.small,
            defaultComplication: 'weather'),
        FaceSlot(
            label: 'Oben rechts',
            rect: Rect.fromLTWH(416, 10, 150, 54),
            family: ComplicationFamily.small,
            defaultComplication: 'moon'),
        FaceSlot(
            label: 'Unten links',
            rect: Rect.fromLTWH(254, 74, 150, 54),
            family: ComplicationFamily.small,
            defaultComplication: 'glasses'),
        FaceSlot(
            label: 'Unten rechts',
            rect: Rect.fromLTWH(416, 74, 150, 54),
            family: ComplicationFamily.small,
            defaultComplication: 'week'),
      ];

  @override
  void paintBase(Canvas c, FaceData d) {
    FaceText.paintDigits(c, Fmt.hhmm(d.now), const Rect.fromLTWH(12, 14, 228, 70));
    final date = FaceText.fit(Fmt.dayMonth(d.now),
        size: 24, weight: FontWeight.w500, maxWidth: 228, maxHeight: 30);
    date.paint(c, const Offset(14, 96));
  }
}

/// Analog dial in the middle, two complications on either side - watchOS
/// "Utility".
class UtilityFace extends WatchFace {
  const UtilityFace();
  @override
  String get id => 'utility';
  @override
  String get name => 'Utility';
  @override
  String get description => 'Analoges Zifferblatt, links und rechts je zwei Komplikationen';

  static const _center = Offset(288, 68);
  static const _radius = 62.0;

  @override
  List<FaceSlot> get slots => const [
        FaceSlot(
            label: 'Links oben',
            rect: Rect.fromLTWH(12, 12, 196, 54),
            family: ComplicationFamily.small,
            align: TextAlign.right,
            defaultComplication: 'date'),
        FaceSlot(
            label: 'Links unten',
            rect: Rect.fromLTWH(12, 72, 196, 54),
            family: ComplicationFamily.small,
            align: TextAlign.right,
            defaultComplication: 'glasses'),
        FaceSlot(
            label: 'Rechts oben',
            rect: Rect.fromLTWH(368, 12, 196, 54),
            family: ComplicationFamily.small,
            defaultComplication: 'weather'),
        FaceSlot(
            label: 'Rechts unten',
            rect: Rect.fromLTWH(368, 72, 196, 54),
            family: ComplicationFamily.small,
            defaultComplication: 'moon'),
      ];

  @override
  void paintBase(Canvas c, FaceData d) =>
      Glyphs.analogDial(c, _center, _radius, d.now);
}

/// Small analog dial next to one large complication - watchOS
/// "Modular Compact".
class CompactFace extends WatchFace {
  const CompactFace();
  @override
  String get id => 'compact';
  @override
  String get name => 'Kompakt';
  @override
  String get description => 'Kleines Zifferblatt und eine große Komplikation';

  @override
  List<FaceSlot> get slots => const [
        FaceSlot(
            label: 'Groß',
            rect: Rect.fromLTWH(156, 10, 410, 118),
            family: ComplicationFamily.large,
            defaultComplication: 'weather'),
      ];

  @override
  void paintBase(Canvas c, FaceData d) =>
      Glyphs.analogDial(c, const Offset(72, 68), 60, d.now);
}

/// Huge numerals, two complications on the right - watchOS "Numerals".
class NumeralsFace extends WatchFace {
  const NumeralsFace();
  @override
  String get id => 'numerals';
  @override
  String get name => 'Numerals';
  @override
  String get description => 'Riesige Ziffern und zwei Komplikationen';

  @override
  List<FaceSlot> get slots => const [
        FaceSlot(
            label: 'Rechts oben',
            rect: Rect.fromLTWH(392, 14, 174, 52),
            family: ComplicationFamily.small,
            align: TextAlign.right,
            defaultComplication: 'date'),
        FaceSlot(
            label: 'Rechts unten',
            rect: Rect.fromLTWH(392, 72, 174, 52),
            family: ComplicationFamily.small,
            align: TextAlign.right,
            defaultComplication: 'glasses'),
      ];

  @override
  void paintBase(Canvas c, FaceData d) {
    FaceText.paintDigits(c, Fmt.hhmm(d.now), const Rect.fromLTWH(10, 16, 372, 104),
        weight: FontWeight.w800, letterSpacing: -2);
  }
}

/// A monochrome falling-glyph pattern rendered into the G1's full-screen BMP.
class MatrixFace extends WatchFace {
  const MatrixFace();

  static const _glyphs = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ';
  static const _columns = 48;
  static const _columnWidth = kFaceWidth / _columns;
  static const _fontSize = 11.0;
  static const _lineHeight = 12.0;
  static const _trailRows = 9;

  @override
  String get id => 'matrix';
  @override
  String get name => 'Matrix';
  @override
  String get description => 'Fallende Zeichen auf dunklem Hintergrund';
  @override
  List<FaceSlot> get slots => const [];

  @override
  String contentKey(FaceData data) => data.matrixFrame?.toString() ?? 'static';

  @override
  void paintBase(Canvas canvas, FaceData data) {
    final frame = data.matrixFrame ?? 0;
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(
      0, 0, kFaceWidth.toDouble(), kFaceHeight.toDouble()));

    for (var column = 0; column < _columns; column++) {
      final seed = _seed(column);
      final trailLength = 4 + seed % (_trailRows - 3);
      final cycle = kFaceHeight ~/ _lineHeight + trailLength;
      final headRow = (seed + frame) % cycle;
      final startY = (headRow - trailLength) * _lineHeight;
      final glyphRun = StringBuffer();
      for (var row = 0; row < trailLength; row++) {
        final charIndex = (seed + frame + row * 17) % _glyphs.length;
        glyphRun.writeln(_glyphs[charIndex]);
      }

      final painter = TextPainter(
        text: TextSpan(
          text: glyphRun.toString(),
          style: const TextStyle(
            color: Color(0xFFB8B8B8),
            fontFamily: 'monospace',
            fontSize: _fontSize,
            height: _lineHeight / _fontSize,
          ),
          children: [
            TextSpan(
              text: _glyphs[(seed + frame + trailLength * 17) % _glyphs.length],
              style: const TextStyle(color: Colors.white),
            ),
          ],
        ),
        textDirection: TextDirection.ltr,
        maxLines: trailLength + 1,
      )..layout(maxWidth: _columnWidth);
      painter.paint(canvas, Offset(column * _columnWidth, startY));
      painter.dispose();
    }

    canvas.restore();
  }

  static int _seed(int column) {
    var value = column * 1103515245 + 12345;
    value = (value ^ (value >> 16)) & 0x7fffffff;
    return value;
  }
}
