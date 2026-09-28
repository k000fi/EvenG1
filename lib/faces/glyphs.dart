import 'dart:math' as math;

import 'package:demo_ai_even/services/weather_models.dart';
import 'package:flutter/material.dart';

/// What a complication shows next to its value.
enum IconKind { weather, moon, battery, sunrise, sunset, globe, calendar, link, note }

class ComplicationIcon {
  final IconKind kind;
  final WeatherKind weather;
  final bool isDay;
  final double moonPhase;
  final int? percent;

  const ComplicationIcon(
    this.kind, {
    this.weather = WeatherKind.clear,
    this.isDay = true,
    this.moonPhase = 0,
    this.percent,
  });

  /// Everything that changes the drawn pixels.
  String get key =>
      '${kind.name}/${weather.name}/$isDay/${moonPhase.toStringAsFixed(2)}/$percent';
}

/// Vector glyphs for the panel. All strokes are at least 2 px so they survive
/// the 1-bit conversion; everything stays inside the box it is given.
class Glyphs {
  Glyphs._();

  static Paint stroke(double width) => Paint()
    ..color = Colors.white
    ..style = PaintingStyle.stroke
    ..strokeWidth = width
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  static Paint get fill => Paint()..color = Colors.white;
  static Paint get erase => Paint()..color = Colors.black;

  static double _w(Rect box) => math.max(2.0, box.shortestSide * 0.09);

  static void icon(Canvas c, ComplicationIcon icon, Rect box) {
    final b = Rect.fromCenter(
      center: box.center,
      width: box.shortestSide,
      height: box.shortestSide,
    );
    switch (icon.kind) {
      case IconKind.weather:
        weather(c, icon.weather, icon.isDay, b);
      case IconKind.moon:
        moon(c, b.center, b.width * 0.44, icon.moonPhase);
      case IconKind.battery:
        battery(c, b, icon.percent);
      case IconKind.sunrise:
        sunEvent(c, b, rise: true);
      case IconKind.sunset:
        sunEvent(c, b, rise: false);
      case IconKind.globe:
        globe(c, b.center, b.width * 0.42);
      case IconKind.calendar:
        calendar(c, b);
      case IconKind.link:
        link(c, b);
      case IconKind.note:
        note(c, b);
    }
  }

  // ------------------------------------------------------------- weather

  static void weather(Canvas c, WeatherKind kind, bool isDay, Rect b) {
    switch (kind) {
      case WeatherKind.clear:
        if (isDay) {
          sun(c, b.center, b.width * 0.46);
        } else {
          crescent(c, b.center, b.width * 0.38);
        }
      case WeatherKind.partly:
        final small = b.width * 0.30;
        final sunCenter = Offset(b.left + b.width * 0.36, b.top + b.height * 0.36);
        if (isDay) {
          sun(c, sunCenter, small);
        } else {
          crescent(c, sunCenter, small * 0.8);
        }
        cloud(c, Rect.fromLTRB(b.left + b.width * 0.18, b.top + b.height * 0.34,
            b.right, b.bottom - b.height * 0.06));
      case WeatherKind.cloudy:
        cloud(c, b.deflate(b.width * 0.02));
      case WeatherKind.fog:
        final p = stroke(_w(b));
        for (var i = 0; i < 4; i++) {
          final y = b.top + b.height * (0.2 + i * 0.2);
          final inset = b.width * (i.isEven ? 0.08 : 0.2);
          c.drawLine(Offset(b.left + inset, y), Offset(b.right - inset * 0.5, y), p);
        }
      case WeatherKind.drizzle:
      case WeatherKind.rain:
      case WeatherKind.snow:
      case WeatherKind.thunder:
        final top = Rect.fromLTRB(b.left, b.top, b.right, b.top + b.height * 0.66);
        cloud(c, top);
        _precipitation(c, kind, Rect.fromLTRB(b.left, top.bottom, b.right, b.bottom));
    }
  }

  static void _precipitation(Canvas c, WeatherKind kind, Rect r) {
    final p = stroke(math.max(2.0, r.height * 0.18));
    final xs = [0.3, 0.52, 0.74].map((f) => r.left + r.width * f).toList();
    switch (kind) {
      case WeatherKind.drizzle:
        for (final x in xs) {
          c.drawCircle(Offset(x, r.center.dy), p.strokeWidth * 0.7, fill);
        }
      case WeatherKind.rain:
        for (final x in xs) {
          c.drawLine(Offset(x + r.height * 0.18, r.top + r.height * 0.15),
              Offset(x - r.height * 0.18, r.bottom - r.height * 0.1), p);
        }
      case WeatherKind.snow:
        for (final x in xs) {
          final s = r.height * 0.26;
          final o = Offset(x, r.center.dy);
          c.drawLine(o.translate(-s, 0), o.translate(s, 0), p);
          c.drawLine(o.translate(0, -s), o.translate(0, s), p);
        }
      case WeatherKind.thunder:
        final x = r.center.dx;
        final bolt = Path()
          ..moveTo(x + r.width * 0.06, r.top)
          ..lineTo(x - r.width * 0.10, r.center.dy + r.height * 0.05)
          ..lineTo(x + r.width * 0.02, r.center.dy + r.height * 0.05)
          ..lineTo(x - r.width * 0.06, r.bottom)
          ..lineTo(x + r.width * 0.12, r.center.dy - r.height * 0.1)
          ..lineTo(x, r.center.dy - r.height * 0.1)
          ..close();
        c.drawPath(bolt, fill);
      default:
        break;
    }
  }

  static void sun(Canvas c, Offset center, double r) {
    final w = math.max(2.0, r * 0.18);
    c.drawCircle(center, r * 0.42, fill);
    final p = stroke(w);
    for (var i = 0; i < 8; i++) {
      final a = i * math.pi / 4;
      final d = Offset(math.cos(a), math.sin(a));
      c.drawLine(center + d * (r * 0.64), center + d * (r - w / 2), p);
    }
  }

  static void crescent(Canvas c, Offset center, double r) {
    final path = Path.combine(
      PathOperation.difference,
      Path()..addOval(Rect.fromCircle(center: center, radius: r)),
      Path()
        ..addOval(Rect.fromCircle(
            center: center.translate(r * 0.55, -r * 0.35), radius: r * 0.85)),
    );
    c.drawPath(path, fill);
  }

  /// Cloud outline filling [r]; the inside is erased first so a cloud drawn
  /// over a sun hides it.
  static void cloud(Canvas c, Rect r) {
    final w = r.width, h = r.height;
    final shape = Path.combine(
      PathOperation.union,
      Path.combine(
        PathOperation.union,
        Path()
          ..addRRect(RRect.fromRectAndRadius(
              Rect.fromLTRB(r.left + w * 0.06, r.top + h * 0.48,
                  r.right - w * 0.06, r.bottom - h * 0.06),
              Radius.circular(h * 0.23))),
        Path()
          ..addOval(Rect.fromCircle(
              center: Offset(r.left + w * 0.34, r.top + h * 0.56),
              radius: h * 0.24)),
      ),
      Path()
        ..addOval(Rect.fromCircle(
            center: Offset(r.left + w * 0.58, r.top + h * 0.44),
            radius: h * 0.34)),
    );
    c.drawPath(shape, erase);
    c.drawPath(shape, stroke(math.max(2.0, h * 0.09)));
  }

  // ----------------------------------------------------------------- moon

  /// Moon disc for [phase] (0 new, 0.5 full): outline plus the lit part,
  /// lit on the right while waxing (northern hemisphere view).
  static void moon(Canvas c, Offset center, double r, double phase) {
    c.drawCircle(center, r, stroke(math.max(2.0, r * 0.12)));
    final waxing = phase < 0.5;
    final k = math.cos(2 * math.pi * phase); // 1 new .. -1 full
    if (k > 0.97) return; // new moon: outline only

    c.save();
    if (!waxing) {
      c.translate(center.dx, center.dy);
      c.scale(-1, 1);
      c.translate(-center.dx, -center.dy);
    }
    final top = Offset(center.dx, center.dy - r);
    final bottom = Offset(center.dx, center.dy + r);
    final lit = Path()
      ..moveTo(top.dx, top.dy)
      ..arcToPoint(bottom, radius: Radius.circular(r), clockwise: true)
      ..arcToPoint(top,
          radius: Radius.elliptical(math.max(0.5, k.abs() * r), r),
          clockwise: k < 0)
      ..close();
    c.drawPath(lit, fill);
    c.restore();
  }

  // -------------------------------------------------------------- misc

  static void battery(Canvas c, Rect b, int? percent) {
    final w = _w(b);
    final body = Rect.fromLTWH(b.left + w / 2, b.top + b.height * 0.26,
        b.width * 0.82 - w, b.height * 0.48);
    c.drawRRect(RRect.fromRectAndRadius(body, Radius.circular(w * 1.2)), stroke(w));
    c.drawRect(
      Rect.fromLTWH(body.right + w * 0.6, body.center.dy - body.height * 0.2,
          b.width * 0.08, body.height * 0.4),
      fill,
    );
    if (percent != null && percent > 0) {
      final inner = body.deflate(w * 1.4);
      c.drawRect(
        Rect.fromLTWH(inner.left, inner.top,
            inner.width * (percent.clamp(0, 100) / 100), inner.height),
        fill,
      );
    }
  }

  static void sunEvent(Canvas c, Rect b, {required bool rise}) {
    final w = _w(b);
    final horizon = b.top + b.height * 0.72;
    final p = stroke(w);
    c.drawLine(Offset(b.left + w, horizon), Offset(b.right - w, horizon), p);
    final r = b.width * 0.26;
    c.drawArc(Rect.fromCircle(center: Offset(b.center.dx, horizon), radius: r),
        math.pi, math.pi, false, p);
    // arrow above the sun: up for sunrise, down for sunset
    final x = b.center.dx;
    final y0 = b.top + w, y1 = horizon - r - w * 1.5;
    c.drawLine(Offset(x, y0), Offset(x, y1), p);
    final tip = rise ? y0 : y1;
    final dir = rise ? 1 : -1;
    final a = b.width * 0.12;
    c.drawLine(Offset(x, tip), Offset(x - a, tip + a * dir), p);
    c.drawLine(Offset(x, tip), Offset(x + a, tip + a * dir), p);
  }

  static void globe(Canvas c, Offset center, double r) {
    final p = stroke(math.max(2.0, r * 0.13));
    c.drawCircle(center, r, p);
    c.drawOval(Rect.fromCenter(center: center, width: r, height: r * 2), p);
    c.drawLine(center.translate(-r, 0), center.translate(r, 0), p);
  }

  static void calendar(Canvas c, Rect b) {
    final w = _w(b);
    final body = Rect.fromLTRB(b.left + b.width * 0.12, b.top + b.height * 0.2,
        b.right - b.width * 0.12, b.bottom - b.height * 0.1);
    c.drawRRect(RRect.fromRectAndRadius(body, Radius.circular(w)), stroke(w));
    c.drawRect(Rect.fromLTWH(body.left, body.top, body.width, body.height * 0.28), fill);
    final p = stroke(w);
    for (final f in [0.3, 0.7]) {
      final x = body.left + body.width * f;
      c.drawLine(Offset(x, b.top + w / 2), Offset(x, body.top + w), p);
    }
  }

  static void link(Canvas c, Rect b) {
    final w = _w(b);
    final p = stroke(w);
    c.save();
    c.translate(b.center.dx, b.center.dy);
    c.rotate(-math.pi / 4);
    final lw = b.width * 0.44, lh = b.height * 0.28;
    c.drawRRect(
        RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(-lw * 0.35, 0), width: lw, height: lh),
            Radius.circular(lh / 2)),
        p);
    c.drawRRect(
        RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(lw * 0.35, 0), width: lw, height: lh),
            Radius.circular(lh / 2)),
        p);
    c.restore();
  }

  static void note(Canvas c, Rect b) {
    final w = _w(b);
    final body = Rect.fromLTRB(b.left + w, b.top + b.height * 0.14,
        b.right - w, b.bottom - b.height * 0.3);
    c.drawRRect(RRect.fromRectAndRadius(body, Radius.circular(w * 2)), stroke(w));
    final tail = Path()
      ..moveTo(body.left + body.width * 0.24, body.bottom - w / 2)
      ..lineTo(body.left + body.width * 0.18, b.bottom - w)
      ..lineTo(body.left + body.width * 0.46, body.bottom - w / 2)
      ..close();
    c.drawPath(tail, fill);
  }

  // ---------------------------------------------------------- analog dial

  /// Watch dial: 12 hour ticks (long at 12/3/6/9), hour and minute hand.
  /// Minute precision - the panel cannot refresh fast enough for a second
  /// hand.
  static void analogDial(Canvas c, Offset center, double r, DateTime t) {
    for (var i = 0; i < 12; i++) {
      final a = i * math.pi / 6;
      final d = Offset(math.sin(a), -math.cos(a));
      final major = i % 3 == 0;
      c.drawLine(center + d * (r * (major ? 0.76 : 0.86)), center + d * (r - 2),
          stroke(major ? 4 : 2.4));
    }
    final minuteAngle = t.minute / 60 * 2 * math.pi;
    final hourAngle = ((t.hour % 12) + t.minute / 60) / 12 * 2 * math.pi;
    Offset hand(double a, double len) =>
        center + Offset(math.sin(a), -math.cos(a)) * len;
    c.drawLine(center, hand(hourAngle, r * 0.5), stroke(6));
    c.drawLine(center, hand(minuteAngle, r * 0.8), stroke(4));
    c.drawCircle(center, 5, fill);
    c.drawCircle(center, 2, erase);
  }
}
