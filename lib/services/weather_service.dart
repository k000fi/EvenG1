import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'weather_models.dart';

/// Feeds the weather, sun and world-clock complications.
///
/// The places are picked by name through Open-Meteo's geocoding search, so
/// no location permission is needed. Data refreshes every 30 minutes; the
/// last good result is cached so faces still have something after a restart
/// without network.
class WeatherService extends GetxService {
  WeatherService._();

  static WeatherService create() =>
      Get.put(WeatherService._(), permanent: true);
  static WeatherService get get => Get.find<WeatherService>();

  static const refreshEvery = Duration(minutes: 30);

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
  ));

  /// Weather + sun complications.
  final Rxn<GeoPlace> place = Rxn<GeoPlace>();

  /// World-clock complication.
  final Rxn<GeoPlace> worldPlace = Rxn<GeoPlace>();

  final Rxn<WeatherNow> weather = Rxn<WeatherNow>();

  /// UTC offset of [worldPlace] - fetched rather than computed, so DST is
  /// always right without shipping a time-zone database.
  final Rxn<int> worldOffsetSec = Rxn<int>();

  final RxBool loading = false.obs;
  final Rxn<String> lastError = Rxn<String>();

  Timer? _timer;
  bool _initDone = false;

  Future<void> init() async {
    if (_initDone) return;
    _initDone = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      place.value = GeoPlace.fromJson(_decode(prefs.getString('weather.place')));
      worldPlace.value =
          GeoPlace.fromJson(_decode(prefs.getString('weather.worldPlace')));
      weather.value = WeatherNow.fromJson(_decode(prefs.getString('weather.last')));
      worldOffsetSec.value = prefs.getInt('weather.worldOffset');
    } catch (e) {
      print('WeatherService init failed: $e');
    }
    _timer = Timer.periodic(refreshEvery, (_) => refresh());
    unawaited(refresh());
  }

  static Object? _decode(String? s) {
    if (s == null) return null;
    try {
      return jsonDecode(s);
    } catch (_) {
      return null;
    }
  }

  Future<List<GeoPlace>> search(String query) async {
    final q = query.trim();
    if (q.length < 2) return const [];
    final res = await _dio.get(
      'https://geocoding-api.open-meteo.com/v1/search',
      queryParameters: {'name': q, 'count': 8, 'language': 'de', 'format': 'json'},
    );
    return GeoPlace.listFromGeocoding(res.data);
  }

  Future<void> setPlace(GeoPlace? p) async {
    place.value = p;
    weather.value = null;
    await _persist();
    await refresh();
  }

  Future<void> setWorldPlace(GeoPlace? p) async {
    worldPlace.value = p;
    worldOffsetSec.value = null;
    await _persist();
    await refresh();
  }

  Future<void> refresh() async {
    if (loading.value) return;
    loading.value = true;
    try {
      final p = place.value;
      if (p != null) {
        final json = await _forecast(p, full: true);
        final w = WeatherNow.fromOpenMeteo(json, fetchedAt: DateTime.now());
        if (w != null) weather.value = w;
      }
      final wp = worldPlace.value;
      if (wp != null) {
        final json = await _forecast(wp, full: false);
        final offset = json is Map ? json['utc_offset_seconds'] : null;
        if (offset is num) worldOffsetSec.value = offset.toInt();
      }
      lastError.value = null;
      await _persist();
    } catch (e) {
      lastError.value = 'Keine Verbindung zum Wetterdienst';
      print('WeatherService refresh failed: $e');
    } finally {
      loading.value = false;
    }
  }

  Future<Object?> _forecast(GeoPlace p, {required bool full}) async {
    final res = await _dio.get(
      'https://api.open-meteo.com/v1/forecast',
      queryParameters: {
        'latitude': p.latitude,
        'longitude': p.longitude,
        'timezone': 'auto',
        'forecast_days': 1,
        'current': full ? 'temperature_2m,weather_code,is_day' : 'temperature_2m',
        if (full) 'daily': 'temperature_2m_max,temperature_2m_min,sunrise,sunset',
      },
    );
    return res.data;
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      Future<void> put(String key, Object? value) => value == null
          ? prefs.remove(key)
          : prefs.setString(key, jsonEncode(value));
      await Future.wait([
        put('weather.place', place.value?.toJson()),
        put('weather.worldPlace', worldPlace.value?.toJson()),
        put('weather.last', weather.value?.toJson()),
        worldOffsetSec.value == null
            ? prefs.remove('weather.worldOffset')
            : prefs.setInt('weather.worldOffset', worldOffsetSec.value!),
      ]);
    } catch (e) {
      print('WeatherService persist failed: $e');
    }
  }

  @override
  void onClose() {
    _timer?.cancel();
    _dio.close();
    super.onClose();
  }
}
