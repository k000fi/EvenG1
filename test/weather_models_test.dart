import 'package:demo_ai_even/services/weather_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final fetched = DateTime(2026, 9, 28, 14, 5);

  group('WeatherNow.fromOpenMeteo', () {
    test('parses current conditions, range and sun times', () {
      final w = WeatherNow.fromOpenMeteo({
        'latitude': 48.2,
        'longitude': 16.38,
        'utc_offset_seconds': 7200,
        'timezone': 'Europe/Vienna',
        'current': {
          'time': '2026-09-28T14:00',
          'temperature_2m': 18.4,
          'weather_code': 3,
          'is_day': 1,
        },
        'daily': {
          'time': ['2026-09-28'],
          'temperature_2m_max': [21.0],
          'temperature_2m_min': [11.2],
          'sunrise': ['2026-09-28T06:52'],
          'sunset': ['2026-09-28T18:38'],
        },
      }, fetchedAt: fetched)!;
      expect(w.temperature, 18.4);
      expect(w.kind, WeatherKind.cloudy);
      expect(w.label, 'Bedeckt');
      expect(w.isDay, isTrue);
      expect(w.max, 21.0);
      expect(w.min, 11.2);
      expect(w.sunrise, '06:52');
      expect(w.sunset, '18:38');
      expect(w.utcOffsetSec, 7200);
    });

    test('tolerates a missing daily block', () {
      final w = WeatherNow.fromOpenMeteo({
        'current': {'temperature_2m': -3, 'weather_code': 71, 'is_day': 0},
      }, fetchedAt: fetched)!;
      expect(w.temperature, -3.0);
      expect(w.kind, WeatherKind.snow);
      expect(w.isDay, isFalse);
      expect(w.sunrise, isNull);
      expect(w.max, isNull);
    });

    test('rejects malformed payloads', () {
      expect(WeatherNow.fromOpenMeteo(null, fetchedAt: fetched), isNull);
      expect(WeatherNow.fromOpenMeteo({'current': 'x'}, fetchedAt: fetched), isNull);
      expect(
          WeatherNow.fromOpenMeteo({
            'current': {'temperature_2m': 'warm', 'weather_code': 1}
          }, fetchedAt: fetched),
          isNull);
    });

    test('round-trips through the cache format and goes stale after 6 h', () {
      final w = WeatherNow(
        temperature: 12.5,
        code: 61,
        isDay: true,
        utcOffsetSec: 3600,
        fetchedAt: fetched,
        sunset: '18:38',
      );
      final back = WeatherNow.fromJson(w.toJson())!;
      expect(back.temperature, 12.5);
      expect(back.kind, WeatherKind.rain);
      expect(back.sunset, '18:38');
      expect(back.fetchedAt, fetched);
      expect(back.isStale(fetched.add(const Duration(hours: 5))), isFalse);
      expect(back.isStale(fetched.add(const Duration(hours: 6))), isTrue);
    });
  });

  group('GeoPlace', () {
    test('parses geocoding results and skips broken entries', () {
      final places = GeoPlace.listFromGeocoding({
        'results': [
          {
            'name': 'Wien',
            'latitude': 48.20849,
            'longitude': 16.37208,
            'country': 'Österreich',
            'admin1': 'Wien',
          },
          {'name': 'kaputt'},
          {
            'name': 'Springfield',
            'latitude': 39.8,
            'longitude': -89.64,
            'country': 'Vereinigte Staaten',
            'admin1': 'Illinois',
          },
        ],
      });
      expect(places, hasLength(2));
      expect(places[0].label, 'Wien, Österreich'); // region == name is dropped
      expect(places[1].label, 'Springfield, Illinois, Vereinigte Staaten');
    });

    test('no results -> empty list', () {
      expect(GeoPlace.listFromGeocoding({'generationtime_ms': 0.2}), isEmpty);
      expect(GeoPlace.listFromGeocoding(null), isEmpty);
    });

    test('round-trips through the cache format', () {
      const p = GeoPlace(
          name: 'Wien', latitude: 48.2, longitude: 16.37, country: 'Österreich');
      final back = GeoPlace.fromJson(p.toJson())!;
      expect(back.label, 'Wien, Österreich');
      expect(back.latitude, 48.2);
    });
  });

  test('WMO codes map to the right icon family', () {
    expect(Wmo.kind(0), WeatherKind.clear);
    expect(Wmo.kind(2), WeatherKind.partly);
    expect(Wmo.kind(45), WeatherKind.fog);
    expect(Wmo.kind(53), WeatherKind.drizzle);
    expect(Wmo.kind(81), WeatherKind.rain);
    expect(Wmo.kind(86), WeatherKind.snow);
    expect(Wmo.kind(99), WeatherKind.thunder);
    expect(Wmo.label(0, isDay: false), 'Klar');
    expect(Wmo.label(0), 'Sonnig');
  });
}
