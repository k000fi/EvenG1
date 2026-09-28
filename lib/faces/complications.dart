import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'face_data.dart';
import 'face_format.dart';
import 'face_text.dart';
import 'glyphs.dart';

/// watchOS-style complication families, adapted to the 576 x 136 panel.
enum ComplicationFamily {
  /// ~150-200 x 50-56: small caps label over a big value, optional icon.
  small,

  /// ~400 x 120: title row plus up to three lines.
  large,
}

/// What a complication shows. Small slots use [label]/[value]/[icon], large
/// slots use [title]/[lines]/[icon].
class ComplicationContent {
  final String label;
  final String value;
  final String title;
  final List<String> lines;
  final ComplicationIcon? icon;

  /// Large slot: wrap [lines] as one paragraph (free text) instead of one
  /// line each.
  final bool wrapBody;

  const ComplicationContent({
    this.label = '',
    this.value = '',
    this.title = '',
    this.lines = const [],
    this.icon,
    this.wrapBody = false,
  });

  static const empty = ComplicationContent();

  bool get isEmpty =>
      label.isEmpty && value.isEmpty && title.isEmpty && lines.isEmpty && icon == null;

  /// Everything that changes the drawn pixels - the face pump only pushes a
  /// new frame when this changes.
  String get key =>
      [label, value, title, lines.join('\u0002'), icon?.key ?? ''].join('\u0001');
}

abstract class Complication {
  const Complication();

  String get id;
  String get name;
  String get description;

  ComplicationContent content(FaceData d);

  String contentKey(FaceData d) => content(d).key;
}

/// All complications, in the order the picker lists them.
class Complications {
  Complications._();

  static const List<Complication> all = [
    NoComplication(),
    DateComplication(),
    TimeComplication(),
    WeekComplication(),
    WeatherComplication(),
    SunComplication(),
    MoonComplication(),
    GlassesBatteryComplication(),
    WorldClockComplication(),
    NoteComplication(),
    LinkComplication(),
  ];

  static Complication byId(String id) =>
      all.firstWhere((c) => c.id == id, orElse: () => const NoComplication());

  static bool isKnown(String id) => all.any((c) => c.id == id);
}

// ----------------------------------------------------------------- layout

/// Lays a [ComplicationContent] out inside a slot. Clipped to the slot, so a
/// complication can never bleed into its neighbours.
class ComplicationPainter {
  ComplicationPainter._();

  static void paint(Canvas c, Rect r, ComplicationFamily family, TextAlign align,
      ComplicationContent k) {
    if (k.isEmpty) return;
    c.save();
    c.clipRect(r);
    if (family == ComplicationFamily.small) {
      _small(c, r, align, k);
    } else {
      _large(c, r, k);
    }
    c.restore();
  }

  static void _small(Canvas c, Rect r, TextAlign align, ComplicationContent k) {
    final labelH = r.height * 0.34;
    final label = FaceText.fit(k.label.toUpperCase(),
        size: 14, minSize: 11, maxWidth: r.width, maxHeight: labelH, letterSpacing: 1.1);
    label.paint(c, Offset(FaceText.alignX(r, label.width, align), r.top));

    final valueTop = r.top + labelH;
    final valueH = r.bottom - valueTop;
    final icon = k.icon;
    final iconSize = icon == null ? 0.0 : math.min(valueH, 30.0);
    final gap = icon == null ? 0.0 : 7.0;
    // Below ~20 px a value is unreadable on the panel - cut it with "…"
    // instead, as watchOS does.
    final value = FaceText.fit(k.value,
        size: 30,
        minSize: 20,
        weight: FontWeight.w700,
        tabular: true,
        maxWidth: r.width - iconSize - gap,
        maxHeight: valueH);
    final rowW = iconSize + gap + value.width;
    final x = FaceText.alignX(r, rowW, align);
    if (icon != null) {
      Glyphs.icon(c, icon,
          Rect.fromLTWH(x, valueTop + (valueH - iconSize) / 2, iconSize, iconSize));
    }
    value.paint(c, Offset(x + iconSize + gap, valueTop + (valueH - value.height) / 2));
  }

  static void _large(Canvas c, Rect r, ComplicationContent k) {
    const headerH = 24.0;
    var x = r.left;
    final icon = k.icon;
    if (icon != null) {
      Glyphs.icon(c, icon, Rect.fromLTWH(r.left, r.top, headerH, headerH));
      x += headerH + 8;
    }
    final title = FaceText.fit(k.title.toUpperCase(),
        size: 15, maxWidth: r.right - x, maxHeight: headerH, letterSpacing: 1.3);
    title.paint(c, Offset(x, r.top + (headerH - title.height) / 2));

    final bodyTop = r.top + headerH + 6;
    final bodyH = r.bottom - bodyTop;
    if (k.lines.isEmpty) return;

    if (k.wrapBody) {
      FaceText.fitParagraph(k.lines.join('\n'),
              size: 26, maxWidth: r.width, maxHeight: bodyH)
          .paint(c, Offset(r.left, bodyTop));
      return;
    }

    // first line is the headline, the rest are details
    final weights = [for (var i = 0; i < k.lines.length; i++) i == 0 ? 1.4 : 1.0];
    final total = weights.reduce((a, b) => a + b);
    var y = bodyTop;
    for (var i = 0; i < k.lines.length; i++) {
      final rowH = bodyH * weights[i] / total;
      final tp = FaceText.fit(k.lines[i],
          size: rowH * 0.8,
          weight: i == 0 ? FontWeight.w700 : FontWeight.w500,
          tabular: true,
          maxWidth: r.width,
          maxHeight: rowH);
      tp.paint(c, Offset(r.left, y + (rowH - tp.height) / 2));
      y += rowH;
    }
  }
}

// ---------------------------------------------------------- complications

class NoComplication extends Complication {
  const NoComplication();
  @override
  String get id => 'none';
  @override
  String get name => 'Leer';
  @override
  String get description => 'Slot bleibt frei';
  @override
  ComplicationContent content(FaceData d) => ComplicationContent.empty;
}

class DateComplication extends Complication {
  const DateComplication();
  @override
  String get id => 'date';
  @override
  String get name => 'Datum';
  @override
  String get description => 'Wochentag und Datum';
  @override
  ComplicationContent content(FaceData d) {
    final n = d.now;
    return ComplicationContent(
      label: Fmt.weekdayLong(n),
      value: '${n.day}. ${Fmt.monthsShort[n.month - 1]}',
      title: 'Datum',
      lines: [
        Fmt.longDate(n),
        '${n.year} · KW ${Fmt.isoWeek(n)} · Tag ${Fmt.dayOfYear(n)}',
      ],
    );
  }
}

class TimeComplication extends Complication {
  const TimeComplication();
  @override
  String get id => 'time';
  @override
  String get name => 'Uhrzeit';
  @override
  String get description => 'Digitale Uhrzeit, praktisch neben dem Zifferblatt';
  @override
  ComplicationContent content(FaceData d) => ComplicationContent(
        label: 'Uhrzeit',
        value: Fmt.hhmm(d.now),
        title: 'Uhrzeit',
        lines: [Fmt.hhmm(d.now), Fmt.longDate(d.now)],
      );
}

class WeekComplication extends Complication {
  const WeekComplication();
  @override
  String get id => 'week';
  @override
  String get name => 'Kalenderwoche';
  @override
  String get description => 'ISO-Kalenderwoche und Tag im Jahr';
  @override
  ComplicationContent content(FaceData d) {
    final n = d.now;
    final day = Fmt.dayOfYear(n);
    final left = Fmt.daysInYear(n.year) - day;
    return ComplicationContent(
      label: 'Woche',
      value: 'KW ${Fmt.isoWeek(n)}',
      title: 'Kalenderwoche',
      icon: const ComplicationIcon(IconKind.calendar),
      lines: ['KW ${Fmt.isoWeek(n)}', 'Tag $day · noch $left Tage im Jahr'],
    );
  }
}

class WeatherComplication extends Complication {
  const WeatherComplication();
  @override
  String get id => 'weather';
  @override
  String get name => 'Wetter';
  @override
  String get description => 'Temperatur und Wetterlage am gewählten Ort';
  @override
  ComplicationContent content(FaceData d) {
    final place = d.weatherPlace;
    if (place == null) {
      return const ComplicationContent(
        label: 'Wetter',
        value: 'Ort?',
        title: 'Wetter',
        lines: ['Ort wählen', 'In der App unter „Wetter & Weltzeit"'],
      );
    }
    final w = d.currentWeather;
    if (w == null) {
      return ComplicationContent(
        label: place,
        value: '—',
        title: 'Wetter · $place',
        lines: const ['Noch keine Daten', 'Wird alle 30 Minuten geladen'],
      );
    }
    final icon = ComplicationIcon(IconKind.weather, weather: w.kind, isDay: w.isDay);
    return ComplicationContent(
      label: place,
      value: _deg(w.temperature),
      icon: icon,
      title: 'Wetter · $place',
      lines: [
        '${_deg(w.temperature)}  ${w.label}',
        if (w.max != null && w.min != null) 'H ${_deg(w.max!)}   T ${_deg(w.min!)}',
      ],
    );
  }
}

String _deg(double t) => '${t.round()}°';

class SunComplication extends Complication {
  const SunComplication();
  @override
  String get id => 'sun';
  @override
  String get name => 'Sonne';
  @override
  String get description => 'Nächster Sonnenauf- oder -untergang am Wetter-Ort';
  @override
  ComplicationContent content(FaceData d) {
    final place = d.weatherPlace;
    final w = d.currentWeather;
    if (place == null || w == null || w.sunrise == null || w.sunset == null) {
      return ComplicationContent(
        label: 'Sonne',
        value: place == null ? 'Ort?' : '—',
        title: 'Sonne',
        lines: [place == null ? 'Ort wählen' : 'Noch keine Daten'],
      );
    }
    final local = d.now.toUtc().add(Duration(seconds: w.utcOffsetSec));
    final nowMin = local.hour * 60 + local.minute;
    int minutes(String hhmm) =>
        int.parse(hhmm.substring(0, 2)) * 60 + int.parse(hhmm.substring(3, 5));
    final beforeSunset = nowMin < minutes(w.sunset!);
    final nextIsRise = nowMin < minutes(w.sunrise!) || !beforeSunset;
    return ComplicationContent(
      label: nextIsRise ? 'Aufgang' : 'Untergang',
      value: nextIsRise ? w.sunrise! : w.sunset!,
      icon: ComplicationIcon(nextIsRise ? IconKind.sunrise : IconKind.sunset),
      title: 'Sonne · $place',
      lines: ['Aufgang ${w.sunrise}', 'Untergang ${w.sunset}'],
    );
  }
}

class MoonComplication extends Complication {
  const MoonComplication();
  @override
  String get id => 'moon';
  @override
  String get name => 'Mond';
  @override
  String get description => 'Mondphase und Beleuchtung';
  @override
  ComplicationContent content(FaceData d) {
    final m = MoonPhase.at(d.now);
    final pct = '${(m.illumination * 100).round()} %';
    final icon = ComplicationIcon(IconKind.moon, moonPhase: m.phase);
    return ComplicationContent(
      label: m.shortName,
      value: pct,
      icon: icon,
      title: 'Mond',
      lines: [
        m.name,
        '$pct beleuchtet',
        m.waxing
            ? 'Vollmond ${Fmt.inDays(m.daysToFull)}'
            : 'Neumond ${Fmt.inDays(m.daysToNew)}',
      ],
    );
  }
}

class GlassesBatteryComplication extends Complication {
  const GlassesBatteryComplication();
  @override
  String get id => 'glasses';
  @override
  String get name => 'Brillen-Akku';
  @override
  String get description => 'Akkustand beider Bügel';
  @override
  ComplicationContent content(FaceData d) {
    final l = d.batteryL, r = d.batteryR;
    final known = [l, r].whereType<int>();
    final low = known.isEmpty ? null : known.reduce(math.min);
    String pct(int? v) => v == null ? '–' : '$v';
    return ComplicationContent(
      label: 'Brille',
      value: known.isEmpty ? '—' : '${pct(l)} · ${pct(r)} %',
      icon: ComplicationIcon(IconKind.battery, percent: low),
      title: 'Brillen-Akku',
      lines: ['Links ${pct(l)} %', 'Rechts ${pct(r)} %'],
    );
  }
}

class WorldClockComplication extends Complication {
  const WorldClockComplication();
  @override
  String get id => 'world';
  @override
  String get name => 'Weltzeit';
  @override
  String get description => 'Uhrzeit in einer zweiten Stadt';
  @override
  ComplicationContent content(FaceData d) {
    final city = d.worldPlace;
    if (city == null) {
      return const ComplicationContent(
        label: 'Weltzeit',
        value: 'Stadt?',
        title: 'Weltzeit',
        lines: ['Stadt wählen', 'In der App unter „Wetter & Weltzeit"'],
      );
    }
    final offset = d.worldOffsetSec;
    if (offset == null) {
      return ComplicationContent(
        label: city,
        value: '—',
        title: 'Weltzeit · $city',
        lines: const ['Noch keine Daten'],
      );
    }
    final there = d.now.toUtc().add(Duration(seconds: offset));
    final diff = offset - d.now.timeZoneOffset.inSeconds;
    final dayShift = DateTime.utc(there.year, there.month, there.day)
        .difference(DateTime.utc(d.now.year, d.now.month, d.now.day))
        .inDays;
    final day = dayShift == 0 ? 'heute' : (dayShift > 0 ? 'morgen' : 'gestern');
    return ComplicationContent(
      label: city,
      value: Fmt.hhmm(there),
      icon: const ComplicationIcon(IconKind.globe),
      title: 'Weltzeit',
      lines: ['$city  ${Fmt.hhmm(there)}', '${Fmt.hourOffset(diff)} · $day'],
    );
  }
}

class NoteComplication extends Complication {
  const NoteComplication();
  @override
  String get id => 'text';
  @override
  String get name => 'Eigener Text';
  @override
  String get description => 'Dein Text aus der App, groß am besten lesbar';
  @override
  ComplicationContent content(FaceData d) {
    final text = d.customText.trim();
    return ComplicationContent(
      label: 'Notiz',
      value: text.isEmpty ? '—' : text.split('\n').first,
      icon: const ComplicationIcon(IconKind.note),
      title: 'Notiz',
      lines: [text.isEmpty ? '(leer)' : text],
      wrapBody: true,
    );
  }
}

class LinkComplication extends Complication {
  const LinkComplication();
  @override
  String get id => 'link';
  @override
  String get name => 'Verbindung';
  @override
  String get description => 'Diagnose: Verbindung, letztes Bild, Tragen';

  @override
  ComplicationContent content(FaceData d) => ComplicationContent(
        label: 'Verbindung',
        value: d.connected ? 'OK' : 'Aus',
        icon: const ComplicationIcon(IconKind.link),
        title: 'Verbindung',
        lines: [
          d.connected ? 'Verbunden' : 'Getrennt',
          d.lastSuccessAt == null
              ? 'Noch kein Bild'
              : 'Letztes Bild ${Fmt.hhmm(d.lastSuccessAt!)}',
          d.glassesWorn ? 'Brille getragen' : 'Brille abgesetzt',
        ],
      );

  /// The "last frame" time changes with every push - leaving it out of the
  /// key keeps a successful push from immediately triggering the next one.
  @override
  String contentKey(FaceData d) =>
      '${d.connected}/${d.glassesWorn}/${d.lastSuccessAt == null}';
}
