import 'dart:math' as math;

/// German date/time formatting and small calendar/astronomy helpers shared by
/// the faces and complications. Pure Dart - unit-tested without Flutter.
class Fmt {
  Fmt._();

  static String two(int v) => v.toString().padLeft(2, '0');

  static String hhmm(DateTime d) => '${two(d.hour)}:${two(d.minute)}';

  /// Index = DateTime.weekday - 1 (Monday first).
  static const weekdaysShort = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];
  static const weekdaysLong = [
    'Montag', 'Dienstag', 'Mittwoch', 'Donnerstag', 'Freitag', 'Samstag',
    'Sonntag', //
  ];
  static const monthsShort = [
    'Jan', 'Feb', 'Mär', 'Apr', 'Mai', 'Jun', 'Jul', 'Aug', 'Sep', 'Okt',
    'Nov', 'Dez', //
  ];
  static const monthsLong = [
    'Jänner', 'Februar', 'März', 'April', 'Mai', 'Juni', 'Juli', 'August',
    'September', 'Oktober', 'November', 'Dezember', //
  ];

  static String weekdayShort(DateTime d) => weekdaysShort[d.weekday - 1];
  static String weekdayLong(DateTime d) => weekdaysLong[d.weekday - 1];

  /// "Do, 24.09."
  static String shortDate(DateTime d) =>
      '${weekdayShort(d)}, ${two(d.day)}.${two(d.month)}.';

  /// "Mo 28. Sep"
  static String dayMonth(DateTime d) =>
      '${weekdayShort(d)} ${d.day}. ${monthsShort[d.month - 1]}';

  /// "Montag, 28. September"
  static String longDate(DateTime d) =>
      '${weekdayLong(d)}, ${d.day}. ${monthsLong[d.month - 1]}';

  /// ISO 8601 week number (weeks start Monday, week 1 holds the first
  /// Thursday). Computed on UTC dates so DST days do not skew the count.
  static int isoWeek(DateTime d) {
    final date = DateTime.utc(d.year, d.month, d.day);
    final thursday = date.add(Duration(days: DateTime.thursday - d.weekday));
    final firstJan = DateTime.utc(thursday.year, 1, 1);
    return thursday.difference(firstJan).inDays ~/ 7 + 1;
  }

  static int dayOfYear(DateTime d) =>
      DateTime.utc(d.year, d.month, d.day)
          .difference(DateTime.utc(d.year, 1, 1))
          .inDays +
      1;

  static int daysInYear(int year) =>
      DateTime.utc(year + 1, 1, 1).difference(DateTime.utc(year, 1, 1)).inDays;

  /// "heute" / "morgen" / "in 5 Tagen"
  static String inDays(int n) => n <= 0
      ? 'heute'
      : n == 1
          ? 'morgen'
          : 'in $n Tagen';

  /// Signed hour offset, e.g. "+6 h", "−1 h", "+5:30 h", "±0 h".
  static String hourOffset(int seconds) {
    if (seconds == 0) return '±0 h';
    final sign = seconds > 0 ? '+' : '−';
    final abs = seconds.abs();
    final h = abs ~/ 3600;
    final m = (abs % 3600) ~/ 60;
    return m == 0 ? '$sign$h h' : '$sign$h:${two(m)} h';
  }
}

/// Moon phase from the mean synodic month, anchored on the new moon of
/// 2000-01-06 18:14 UTC. Good to well under a day - plenty for a watch face.
class MoonPhase {
  static const double synodicMonth = 29.530588853;
  static final DateTime _referenceNewMoon = DateTime.utc(2000, 1, 6, 18, 14);

  /// 0 = new, 0.25 = first quarter, 0.5 = full, 0.75 = last quarter.
  final double phase;

  const MoonPhase(this.phase);

  factory MoonPhase.at(DateTime t) {
    final days =
        t.toUtc().difference(_referenceNewMoon).inSeconds / Duration.secondsPerDay;
    var age = days % synodicMonth;
    if (age < 0) age += synodicMonth;
    return MoonPhase(age / synodicMonth);
  }

  /// Illuminated fraction of the disc, 0..1.
  double get illumination => (1 - math.cos(2 * math.pi * phase)) / 2;

  bool get waxing => phase < 0.5;

  int get daysToFull =>
      (((phase < 0.5 ? 0.5 : 1.5) - phase) * synodicMonth).round();

  int get daysToNew => ((1 - phase) * synodicMonth).round();

  String get name {
    if (phase < 0.03 || phase >= 0.97) return 'Neumond';
    if (phase < 0.22) return 'Zunehmende Sichel';
    if (phase < 0.28) return 'Erstes Viertel';
    if (phase < 0.47) return 'Zunehmender Mond';
    if (phase < 0.53) return 'Vollmond';
    if (phase < 0.72) return 'Abnehmender Mond';
    if (phase < 0.78) return 'Letztes Viertel';
    return 'Abnehmende Sichel';
  }

  /// Short form for the small complication's label line.
  String get shortName {
    if (phase < 0.03 || phase >= 0.97) return 'Neumond';
    if (phase < 0.22) return 'Zunehmend';
    if (phase < 0.28) return 'Erstes Viertel';
    if (phase < 0.47) return 'Zunehmend';
    if (phase < 0.53) return 'Vollmond';
    if (phase < 0.72) return 'Abnehmend';
    if (phase < 0.78) return 'Letztes Viertel';
    return 'Abnehmend';
  }
}
