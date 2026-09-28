import 'package:demo_ai_even/faces/face_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Fmt', () {
    test('hhmm pads with zeros', () {
      expect(Fmt.hhmm(DateTime(2026, 9, 24, 8, 5)), '08:05');
      expect(Fmt.hhmm(DateTime(2026, 12, 31, 23, 59)), '23:59');
    });

    test('German weekdays and dates', () {
      // 2026-09-24 is a Thursday, 2026-10-04 a Sunday
      expect(Fmt.shortDate(DateTime(2026, 9, 24)), 'Do, 24.09.');
      expect(Fmt.shortDate(DateTime(2026, 10, 4)), 'So, 04.10.');
      expect(Fmt.dayMonth(DateTime(2026, 9, 28)), 'Mo 28. Sep');
      expect(Fmt.longDate(DateTime(2026, 9, 28)), 'Montag, 28. September');
    });

    test('ISO week', () {
      expect(Fmt.isoWeek(DateTime(2026, 1, 1)), 1); // a Thursday
      expect(Fmt.isoWeek(DateTime(2025, 12, 29)), 1); // Monday of that week
      expect(Fmt.isoWeek(DateTime(2026, 9, 28)), 40);
      expect(Fmt.isoWeek(DateTime(2027, 1, 1)), 53); // 2026 has 53 weeks
      expect(Fmt.isoWeek(DateTime(2027, 1, 4)), 1);
    });

    test('day of year', () {
      expect(Fmt.dayOfYear(DateTime(2026, 1, 1)), 1);
      expect(Fmt.dayOfYear(DateTime(2026, 9, 28)), 271);
      expect(Fmt.dayOfYear(DateTime(2024, 12, 31)), 366);
      expect(Fmt.daysInYear(2024), 366);
      expect(Fmt.daysInYear(2026), 365);
    });

    test('relative days and hour offsets', () {
      expect(Fmt.inDays(0), 'heute');
      expect(Fmt.inDays(1), 'morgen');
      expect(Fmt.inDays(5), 'in 5 Tagen');
      expect(Fmt.hourOffset(0), '±0 h');
      expect(Fmt.hourOffset(-6 * 3600), '−6 h');
      expect(Fmt.hourOffset(3 * 3600 + 1800), '+3:30 h');
    });
  });

  group('MoonPhase', () {
    test('new moon of 2026-02-17 (annular eclipse)', () {
      final m = MoonPhase.at(DateTime.utc(2026, 2, 17, 12, 1));
      expect(m.illumination, lessThan(0.05));
      expect(m.name, 'Neumond');
    });

    test('full moon of 2026-03-03 (total lunar eclipse)', () {
      final m = MoonPhase.at(DateTime.utc(2026, 3, 3, 11, 38));
      expect(m.illumination, greaterThan(0.95));
      expect(m.name, 'Vollmond');
    });

    test('waxing a week after new moon, full moon about a week away', () {
      final m = MoonPhase.at(DateTime.utc(2026, 2, 24, 12));
      expect(m.waxing, isTrue);
      expect(m.daysToFull, inInclusiveRange(6, 8));
    });

    test('phase stays in 0..1 for dates before the reference', () {
      final m = MoonPhase.at(DateTime.utc(1990, 5, 1));
      expect(m.phase, inInclusiveRange(0.0, 1.0));
    });
  });
}
