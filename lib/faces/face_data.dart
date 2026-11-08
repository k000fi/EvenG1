import 'package:demo_ai_even/services/weather_models.dart';

/// The G1 panel: 576 x 136, 1 bit per pixel.
const int kFaceWidth = 576;
const int kFaceHeight = 136;

/// Snapshot of everything a face or complication may draw. Built once per
/// render so a frame is internally consistent.
class FaceData {
  final DateTime now;
  final bool connected;
  final bool glassesWorn;
  final DateTime? lastSuccessAt;
  final int? batteryL; // 0..100, null = unknown
  final int? batteryR;
  final String customText;
  final int? matrixFrame;

  /// Weather place name; null = not configured.
  final String? weatherPlace;
  final WeatherNow? weather;

  /// World-clock city name; null = not configured.
  final String? worldPlace;
  final int? worldOffsetSec;

  const FaceData({
    required this.now,
    this.connected = false,
    this.glassesWorn = true,
    this.lastSuccessAt,
    this.batteryL,
    this.batteryR,
    this.customText = '',
    this.matrixFrame,
    this.weatherPlace,
    this.weather,
    this.worldPlace,
    this.worldOffsetSec,
  });

  /// Weather that is fresh enough to show as current.
  WeatherNow? get currentWeather {
    final w = weather;
    return (w == null || w.isStale(now)) ? null : w;
  }
}
