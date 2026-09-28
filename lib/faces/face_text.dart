import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Text helpers for the faces. Everything drawn on the panel goes through
/// [fit], which shrinks the font until the text fits its box - so layouts
/// hold with any system font (and with the square test font in CI).
class FaceText {
  FaceText._();

  static TextPainter layout(
    String text, {
    required double size,
    FontWeight weight = FontWeight.w600,
    double letterSpacing = 0,
    bool tabular = false,
    double maxWidth = double.infinity,
    int? maxLines,
    String? ellipsis,
    TextAlign align = TextAlign.left,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: Colors.white,
          fontSize: size,
          fontWeight: weight,
          letterSpacing: letterSpacing,
          fontFeatures: tabular ? const [FontFeature.tabularFigures()] : null,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: align,
      maxLines: maxLines,
      ellipsis: ellipsis,
    );
    tp.layout(maxWidth: maxWidth);
    return tp;
  }

  /// Single line, largest size <= [size] that fits [maxWidth] x [maxHeight].
  /// At [minSize] the text is ellipsized instead, so the result never
  /// exceeds [maxWidth].
  static TextPainter fit(
    String text, {
    required double size,
    required double maxWidth,
    double? maxHeight,
    double minSize = 9,
    FontWeight weight = FontWeight.w600,
    double letterSpacing = 0,
    bool tabular = false,
  }) {
    var s = size;
    while (true) {
      final tp = layout(
        text,
        size: s,
        weight: weight,
        letterSpacing: letterSpacing * s / size,
        tabular: tabular,
        maxWidth: maxWidth < 1 ? 1 : maxWidth,
        maxLines: 1,
        ellipsis: '…',
      );
      final fits = !tp.didExceedMaxLines &&
          (maxHeight == null || tp.height <= maxHeight);
      if (fits || s <= minSize) return tp;
      s = _shrink(s, minSize);
    }
  }

  /// Wrapped paragraph of at most [maxLines], shrunk until it fits
  /// [maxHeight].
  static TextPainter fitParagraph(
    String text, {
    required double size,
    required double maxWidth,
    required double maxHeight,
    int maxLines = 3,
    double minSize = 10,
    FontWeight weight = FontWeight.w500,
  }) {
    var s = size;
    while (true) {
      final tp = layout(
        text,
        size: s,
        weight: weight,
        maxWidth: maxWidth < 1 ? 1 : maxWidth,
        maxLines: maxLines,
        ellipsis: '…',
      );
      if (tp.height <= maxHeight || s <= minSize) return tp;
      s = _shrink(s, minSize);
    }
  }

  /// Paints [text] (digits and colons) as large as [box] allows, sized and
  /// centred by the digits' cap height instead of the line box - the line box
  /// carries ascender and descender space that digits never use, which made
  /// big clocks a third smaller than they could be. [capRatio] is the cap
  /// height as a fraction of the font size (~0.71 for SF and Roboto);
  /// [letterSpacing] is in percent of the font size.
  static void paintDigits(
    Canvas c,
    String text,
    Rect box, {
    FontWeight weight = FontWeight.w700,
    double letterSpacing = 0,
    double capRatio = 0.71,
    TextAlign align = TextAlign.left,
  }) {
    TextPainter lay(double s) => layout(text,
        size: s,
        weight: weight,
        letterSpacing: letterSpacing * s / 100,
        tabular: true,
        maxLines: 1);
    var s = box.height / capRatio;
    var tp = lay(s);
    while (tp.width > box.width && s > 8) {
      s = math.max(8, s * math.min(0.98, box.width / tp.width));
      tp = lay(s);
    }
    final baseline = tp.computeDistanceToActualBaseline(TextBaseline.alphabetic);
    final y = box.center.dy - baseline + s * capRatio / 2;
    tp.paint(c, Offset(alignX(box, tp.width, align), y));
  }

  /// Next size down: 8 % smaller, at least half a point, never below [min].
  static double _shrink(double s, double min) =>
      math.max(min, math.min(s * 0.92, s - 0.5));

  /// x for a box of [width] aligned inside [r].
  static double alignX(Rect r, double width, TextAlign align) =>
      switch (align) {
        TextAlign.right || TextAlign.end => r.right - width,
        TextAlign.center => r.center.dx - width / 2,
        _ => r.left,
      };
}
