import 'dart:ui' show PictureRecorder;

import 'package:demo_ai_even/faces/complications.dart';
import 'package:demo_ai_even/faces/face_data.dart';
import 'package:demo_ai_even/faces/face_format.dart';
import 'package:demo_ai_even/faces/face_scheduler.dart';
import 'package:demo_ai_even/faces/face_text.dart';
import 'package:demo_ai_even/faces/watch_faces.dart';
import 'package:demo_ai_even/services/weather_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime(2026, 9, 28, 14, 5);
  final bare = FaceData(now: now);
  final full = FaceData(
    now: now,
    connected: true,
    lastSuccessAt: now,
    batteryL: 80,
    batteryR: 75,
    customText: 'Einkaufen: Milch, Brot, Äpfel\nZahnarzt um 16:30, danach Post',
    weatherPlace: 'Wien',
    weather: WeatherNow(
      temperature: 18.4,
      code: 2,
      isDay: true,
      max: 21,
      min: 11,
      sunrise: '06:52',
      sunset: '18:38',
      utcOffsetSec: now.timeZoneOffset.inSeconds,
      fetchedAt: now,
    ),
    worldPlace: 'New York',
    worldOffsetSec: -4 * 3600,
  );

  String value(String id, FaceData d) => Complications.byId(id).content(d).value;

  group('content', () {
    test('weather: asks for a place, then shows temperature', () {
      expect(value('weather', bare), 'Ort?');
      expect(value('weather', full), '18°');
      expect(Complications.byId('weather').content(full).label, 'Wien');
    });

    test('weather older than 6 h is not shown as current', () {
      final stale = FaceData(
        now: now,
        weatherPlace: 'Wien',
        weather: WeatherNow(
          temperature: 18,
          code: 0,
          isDay: true,
          utcOffsetSec: 0,
          fetchedAt: now.subtract(const Duration(hours: 7)),
        ),
      );
      expect(value('weather', stale), '—');
    });

    test('sun: next event at the place', () {
      final c = Complications.byId('sun').content(full); // 14:05 local
      expect(c.label, 'Untergang');
      expect(c.value, '18:38');
      expect(value('sun', bare), 'Ort?');
    });

    test('world clock converts through the fetched UTC offset', () {
      expect(value('world', bare), 'Stadt?');
      expect(value('world', full),
          Fmt.hhmm(now.toUtc().subtract(const Duration(hours: 4))));
    });

    test('glasses battery shows both arms', () {
      expect(value('glasses', bare), '—');
      expect(value('glasses', full), '80 · 75 %');
    });

    test('empty slot draws nothing', () {
      expect(Complications.byId('none').content(full).isEmpty, isTrue);
      expect(Complications.byId('does-not-exist').id, 'none');
    });

    test('link key ignores the last-frame time (no push loop)', () {
      final later = FaceData(
          now: now, connected: true, lastSuccessAt: now.add(const Duration(minutes: 1)));
      final link = Complications.byId('link');
      expect(link.contentKey(later), link.contentKey(full));
    });

    test('every complication builds content for sparse and full data', () {
      for (final c in Complications.all) {
        expect(() => c.content(bare), returnsNormally, reason: c.id);
        expect(c.contentKey(full), c.contentKey(full), reason: c.id);
        expect(c.name, isNotEmpty);
        expect(c.description, isNotEmpty);
      }
    });
  });

  group('painting', () {
    test('every complication in every slot of every face', () {
      for (final face in FaceScheduler.faces) {
        for (final c in Complications.all) {
          for (final data in [bare, full]) {
            final recorder = PictureRecorder();
            paintWatchFace(Canvas(recorder),
                face, List.filled(face.slots.length, c.id), data);
            recorder.endRecording().dispose();
          }
        }
      }
    });

    test('face ids are unique and every default complication exists', () {
      final ids = FaceScheduler.faces.map((f) => f.id).toSet();
      expect(ids, hasLength(FaceScheduler.faces.length));
      for (final f in FaceScheduler.faces) {
        for (final s in f.slots) {
          expect(Complications.isKnown(s.defaultComplication), isTrue,
              reason: '${f.id}/${s.label}');
          expect(s.rect.left, greaterThanOrEqualTo(0));
          expect(s.rect.right, lessThanOrEqualTo(kFaceWidth));
          expect(s.rect.bottom, lessThanOrEqualTo(kFaceHeight));
        }
      }
    });

    test('content key changes with the minute and with the data', () {
      const face = ModularFace();
      final ids = [for (final s in face.slots) s.defaultComplication];
      final k1 = faceContentKey(face, ids, full);
      expect(faceContentKey(face, ids, full), k1);
      final nextMinute = FaceData(
          now: now.add(const Duration(minutes: 1)),
          weatherPlace: full.weatherPlace,
          weather: full.weather,
          batteryL: 80,
          batteryR: 75);
      expect(faceContentKey(face, ids, nextMinute), isNot(k1));
      expect(faceContentKey(face, ['moon', 'moon', 'moon', 'moon'], full),
          isNot(k1));
    });
  });

  group('FaceText.fit', () {
    test('shrinks until the text fits, ellipsizes as a last resort', () {
      final tp = FaceText.fit('Sehr langer Ortsname mit vielen Wörtern',
          size: 30, maxWidth: 80, maxHeight: 20);
      expect(tp.width, lessThanOrEqualTo(80));
      expect(tp.height, lessThanOrEqualTo(20));
    });

    test('keeps the requested size when it already fits', () {
      final fitted = FaceText.fit('Hi', size: 20, maxWidth: 500);
      expect(fitted.height, FaceText.layout('Hi', size: 20).height);
    });
  });
}
