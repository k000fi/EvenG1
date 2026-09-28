/// Data models for the weather and world-clock complications, parsed from the
/// Open-Meteo APIs (https://open-meteo.com - free, no API key). Pure Dart so
/// the parsing is unit-testable.
library;

/// A place picked through the geocoding search.
class GeoPlace {
  final String name;
  final String? region;
  final String? country;
  final double latitude;
  final double longitude;

  const GeoPlace({
    required this.name,
    required this.latitude,
    required this.longitude,
    this.region,
    this.country,
  });

  /// "Wien, Österreich" / "Springfield, Illinois, USA"
  String get label => [
        name,
        if (region != null && region!.isNotEmpty && region != name) region!,
        if (country != null && country!.isNotEmpty) country!,
      ].join(', ');

  Map<String, dynamic> toJson() => {
        'name': name,
        'region': region,
        'country': country,
        'latitude': latitude,
        'longitude': longitude,
      };

  static GeoPlace? fromJson(Object? json) {
    if (json is! Map) return null;
    final name = json['name'];
    final lat = json['latitude'];
    final lon = json['longitude'];
    if (name is! String || lat is! num || lon is! num) return null;
    return GeoPlace(
      name: name,
      latitude: lat.toDouble(),
      longitude: lon.toDouble(),
      region: (json['region'] as String?) ?? (json['admin1'] as String?),
      country: json['country'] as String?,
    );
  }

  /// Parses `https://geocoding-api.open-meteo.com/v1/search` results.
  static List<GeoPlace> listFromGeocoding(Object? json) {
    if (json is! Map || json['results'] is! List) return const [];
    return [
      for (final r in json['results'] as List)
        if (fromJson(r) case final GeoPlace p) p,
    ];
  }
}

/// Coarse weather categories - one icon each.
enum WeatherKind { clear, partly, cloudy, fog, drizzle, rain, snow, thunder }

/// WMO weather interpretation codes as used by Open-Meteo.
class Wmo {
  Wmo._();

  static WeatherKind kind(int code) {
    if (code == 0) return WeatherKind.clear;
    if (code <= 2) return WeatherKind.partly;
    if (code == 3) return WeatherKind.cloudy;
    if (code == 45 || code == 48) return WeatherKind.fog;
    if (code >= 51 && code <= 57) return WeatherKind.drizzle;
    if ((code >= 61 && code <= 67) || (code >= 80 && code <= 82)) {
      return WeatherKind.rain;
    }
    if ((code >= 71 && code <= 77) || code == 85 || code == 86) {
      return WeatherKind.snow;
    }
    if (code >= 95) return WeatherKind.thunder;
    return WeatherKind.cloudy;
  }

  static String label(int code, {bool isDay = true}) => switch (code) {
        0 => isDay ? 'Sonnig' : 'Klar',
        1 => 'Überwiegend klar',
        2 => 'Teils bewölkt',
        3 => 'Bedeckt',
        45 => 'Nebel',
        48 => 'Reifnebel',
        51 => 'Leichter Niesel',
        53 => 'Niesel',
        55 => 'Starker Niesel',
        56 || 57 => 'Gefrierender Niesel',
        61 => 'Leichter Regen',
        63 => 'Regen',
        65 => 'Starker Regen',
        66 || 67 => 'Gefrierender Regen',
        71 => 'Leichter Schnee',
        73 => 'Schnee',
        75 => 'Starker Schnee',
        77 => 'Schneegriesel',
        80 => 'Leichte Schauer',
        81 => 'Schauer',
        82 => 'Starke Schauer',
        85 || 86 => 'Schneeschauer',
        95 => 'Gewitter',
        96 || 99 => 'Gewitter mit Hagel',
        _ => 'Wetter',
      };
}

/// Current conditions plus today's range and sun times at the weather place.
class WeatherNow {
  final double temperature;
  final int code;
  final bool isDay;
  final double? max;
  final double? min;

  /// "HH:MM", local time at the place.
  final String? sunrise;
  final String? sunset;

  /// UTC offset of the place, so "now" can be compared with the sun times.
  final int utcOffsetSec;
  final DateTime fetchedAt;

  const WeatherNow({
    required this.temperature,
    required this.code,
    required this.isDay,
    required this.utcOffsetSec,
    required this.fetchedAt,
    this.max,
    this.min,
    this.sunrise,
    this.sunset,
  });

  WeatherKind get kind => Wmo.kind(code);
  String get label => Wmo.label(code, isDay: isDay);

  /// Older data is shown as missing rather than as if it were current.
  bool isStale(DateTime now) => now.difference(fetchedAt).inHours >= 6;

  /// Parses `https://api.open-meteo.com/v1/forecast` with
  /// `current=temperature_2m,weather_code,is_day`,
  /// `daily=temperature_2m_max,temperature_2m_min,sunrise,sunset` and
  /// `timezone=auto`.
  static WeatherNow? fromOpenMeteo(Object? json, {required DateTime fetchedAt}) {
    if (json is! Map) return null;
    final cur = json['current'];
    if (cur is! Map) return null;
    final t = cur['temperature_2m'];
    final c = cur['weather_code'];
    if (t is! num || c is! num) return null;
    final daily = json['daily'] is Map ? json['daily'] as Map : const {};

    double? first(String key) {
      final v = daily[key];
      return (v is List && v.isNotEmpty && v.first is num)
          ? (v.first as num).toDouble()
          : null;
    }

    String? clock(String key) {
      final v = daily[key];
      if (v is! List || v.isEmpty || v.first is! String) return null;
      final s = v.first as String; // "2026-09-28T06:52"
      final i = s.indexOf('T');
      return (i >= 0 && s.length >= i + 6) ? s.substring(i + 1, i + 6) : null;
    }

    final offset = json['utc_offset_seconds'];
    return WeatherNow(
      temperature: t.toDouble(),
      code: c.toInt(),
      isDay: cur['is_day'] == 1,
      max: first('temperature_2m_max'),
      min: first('temperature_2m_min'),
      sunrise: clock('sunrise'),
      sunset: clock('sunset'),
      utcOffsetSec: offset is num ? offset.toInt() : 0,
      fetchedAt: fetchedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'temperature': temperature,
        'code': code,
        'isDay': isDay,
        'max': max,
        'min': min,
        'sunrise': sunrise,
        'sunset': sunset,
        'utcOffsetSec': utcOffsetSec,
        'fetchedAt': fetchedAt.toIso8601String(),
      };

  static WeatherNow? fromJson(Object? json) {
    if (json is! Map) return null;
    final t = json['temperature'];
    final c = json['code'];
    final at = DateTime.tryParse(json['fetchedAt'] as String? ?? '');
    if (t is! num || c is! num || at == null) return null;
    return WeatherNow(
      temperature: t.toDouble(),
      code: c.toInt(),
      isDay: json['isDay'] == true,
      max: (json['max'] as num?)?.toDouble(),
      min: (json['min'] as num?)?.toDouble(),
      sunrise: json['sunrise'] as String?,
      sunset: json['sunset'] as String?,
      utcOffsetSec: (json['utcOffsetSec'] as num?)?.toInt() ?? 0,
      fetchedAt: at,
    );
  }
}
