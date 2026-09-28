import 'package:demo_ai_even/faces/face_scheduler.dart';
import 'package:demo_ai_even/faces/watch_faces.dart';
import 'package:demo_ai_even/services/keepalive_service.dart';
import 'package:demo_ai_even/services/weather_service.dart';
import 'package:demo_ai_even/views/faces/face_settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    Get.reset();
    KeepAliveService.create();
    WeatherService.create();
    FaceScheduler.create();
  });

  tearDown(() => Get.reset());

  Future<void> pumpPage(WidgetTester tester) async {
    // The page is a lazy ListView: on the default 800x600 view the lower
    // cards are never built and the finders below would miss them. Resize the
    // view itself (not just the render surface) so MediaQuery - which sizes
    // the bottom sheets - agrees.
    tester.view.physicalSize = const Size(1200, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: FaceSettingsPage()));
  }

  Future<void> unmount(WidgetTester tester) =>
      // cancels the preview ticker's periodic Timer
      tester.pumpWidget(const SizedBox.shrink());

  testWidgets('face settings page renders (smoke)', (tester) async {
    await pumpPage(tester);

    expect(find.text('Even Faces'), findsOneWidget);
    expect(find.text('Faces aktiv'), findsOneWidget);
    expect(find.text('So funktioniert es'), findsOneWidget);
    for (final face in FaceScheduler.faces) {
      expect(find.text(face.name), findsOneWidget, reason: face.id);
      expect(find.text(face.description), findsOneWidget, reason: face.id);
    }
    // the editor lists the active face's slots
    for (final slot in FaceScheduler.faces.first.slots) {
      expect(find.text(slot.label), findsOneWidget, reason: slot.label);
    }
    expect(find.text('Wetter-Ort'), findsOneWidget);
    expect(find.text('Weltzeit-Stadt'), findsOneWidget);

    await tester.pump(const Duration(seconds: 11));
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets('tapping a face card activates it', (tester) async {
    await pumpPage(tester);
    final fs = FaceScheduler.get;
    expect(fs.activeFaceIndex.value, 0);

    await tester.tap(find.text('Utility'));
    await tester.pumpAndSettle();

    expect(fs.activeFaceIndex.value, 1);
    expect(find.text('KOMPLIKATIONEN · UTILITY'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('a slot can be filled from the complication picker',
      (tester) async {
    await pumpPage(tester);
    final fs = FaceScheduler.get;
    const face = ModularFace();
    expect(fs.slotsFor(face).first, 'weather');

    await tester.tap(find.text(face.slots.first.label));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Weltzeit').last);
    await tester.pumpAndSettle();

    expect(fs.slotsFor(face).first, 'world');
    await unmount(tester);
  });
}
