import 'dart:async';
import 'dart:convert';

import 'package:demo_ai_even/ble_manager.dart';
import 'package:demo_ai_even/controllers/bmp_update_manager.dart';
import 'package:demo_ai_even/services/keepalive_service.dart';
import 'package:demo_ai_even/services/proto.dart';
import 'package:demo_ai_even/services/weather_service.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'complications.dart';
import 'face_data.dart';
import 'face_renderer.dart';
import 'watch_faces.dart';

/// Drives the watch faces on the glasses:
///
///   - renders the active face with its complications (576x136, 1-bit) and
///     pushes it to both arms through the ordered dual-arm BMP flow
///   - pushes only when the visible content changes (the minute, or what a
///     complication shows), checked once per second
///   - double tap left/right cycles the faces (wrap-around)
///   - pauses while the glasses are off the face (wear events)
///   - starts/stops the iOS silent-audio keep-alive
///
/// Settings, including which complication sits in which slot, persist via
/// SharedPreferences.
class FaceScheduler extends GetxService {
  FaceScheduler._();

  static FaceScheduler create() =>
      Get.put(FaceScheduler._(), permanent: true);
  static FaceScheduler get get => Get.find<FaceScheduler>();

  /// Face order for double-tap navigation.
  static const List<WatchFace> faces = [
    ModularFace(),
    UtilityFace(),
    CompactFace(),
    NumeralsFace(),
  ];

  /// Floor between two pushes, so the link gets breathing room.
  static const _minGap = Duration(seconds: 2);

  /// After a failed push, wait this long before trying again.
  static const _retryAfter = Duration(seconds: 10);

  final BmpUpdateManager _bmp = BmpUpdateManager();
  final FaceRenderer _renderer = FaceRenderer();

  // ---- settings (persisted) ----
  final RxBool facesEnabled = true.obs;
  final RxBool keepAliveEnabled = true.obs;
  final RxInt activeFaceIndex = 0.obs;
  final RxString customText = 'Hallo Even!'.obs;

  /// face id -> complication id per slot. Missing entries use the face's
  /// defaults.
  final RxMap<String, List<String>> slotConfig = <String, List<String>>{}.obs;

  // ---- runtime state ----
  final RxBool glassesWorn = true.obs;
  final RxBool pushing = false.obs;
  final RxInt linkCounter = 0.obs;
  final Rxn<DateTime> lastSuccessAt = Rxn<DateTime>();
  final Rxn<int> batteryL = Rxn<int>();
  final Rxn<int> batteryR = Rxn<int>();

  bool _connected = false;
  bool _initDone = false;
  Timer? _tick;
  String _pushedKey = '';
  DateTime _notBefore = DateTime.fromMillisecondsSinceEpoch(0);

  bool get connected => _connected;
  WatchFace get activeFace => faces[activeFaceIndex.value % faces.length];

  /// Complication ids for every slot of [face].
  List<String> slotsFor(WatchFace face) {
    final saved = slotConfig[face.id];
    return [
      for (var i = 0; i < face.slots.length; i++)
        (saved != null && i < saved.length && Complications.isKnown(saved[i]))
            ? saved[i]
            : face.slots[i].defaultComplication,
    ];
  }

  void setSlot(WatchFace face, int slot, String complicationId) {
    final ids = slotsFor(face)..[slot] = complicationId;
    slotConfig[face.id] = ids;
    _persist();
  }

  /// Everything the faces can show, right now.
  FaceData snapshot() {
    final ws = Get.isRegistered<WeatherService>() ? WeatherService.get : null;
    return FaceData(
      now: DateTime.now(),
      connected: _connected,
      glassesWorn: glassesWorn.value,
      lastSuccessAt: lastSuccessAt.value,
      batteryL: batteryL.value,
      batteryR: batteryR.value,
      customText: customText.value,
      weatherPlace: ws?.place.value?.name,
      weather: ws?.weather.value,
      worldPlace: ws?.worldPlace.value?.name,
      worldOffsetSec: ws?.worldOffsetSec.value,
    );
  }

  /// Loads persisted settings, wires observers, starts if already connected.
  /// Call once at app startup.
  Future<void> init() async {
    if (_initDone) return;
    _initDone = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      facesEnabled.value = prefs.getBool('faces.enabled') ?? true;
      keepAliveEnabled.value = prefs.getBool('faces.keepalive') ?? true;
      activeFaceIndex.value = (prefs.getInt('faces.active') ?? 0) % faces.length;
      customText.value = prefs.getString('faces.text') ?? 'Hallo Even!';
      final raw = prefs.getString('faces.slots');
      if (raw != null) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          slotConfig.assignAll({
            for (final e in decoded.entries)
              if (e.key is String && e.value is List)
                e.key as String: [for (final v in e.value as List) '$v'],
          });
        }
      }
    } catch (e) {
      print('FaceScheduler init failed: $e');
    }

    facesEnabled.listen((_) {
      _persist();
      _onEnabledChanged();
    });
    keepAliveEnabled.listen((_) {
      _persist();
      _syncKeepAlive();
    });
    activeFaceIndex.listen((_) => _persist());
    customText.listen((_) => _persist());

    if (BleManager.get().isConnected) {
      onConnected();
    }
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await Future.wait([
        prefs.setBool('faces.enabled', facesEnabled.value),
        prefs.setBool('faces.keepalive', keepAliveEnabled.value),
        prefs.setInt('faces.active', activeFaceIndex.value),
        prefs.setString('faces.text', customText.value),
        prefs.setString('faces.slots', jsonEncode(slotConfig)),
      ]);
    } catch (e) {
      print('FaceScheduler persist failed: $e');
    }
  }

  void _onEnabledChanged() {
    if (facesEnabled.value) {
      forceRefresh();
    } else if (_connected) {
      // free the glasses so the user does not get stuck on a stale face
      exitToDashboard();
    }
    _syncKeepAlive();
  }

  // ------------------------------------------------------- connection events

  void onConnected() {
    if (_connected) return;
    _connected = true;
    _pushedKey = '';
    _notBefore = DateTime.fromMillisecondsSinceEpoch(0);
    // The pump runs for the whole connection and checks every condition
    // itself - no code path can leave the faces without a ticker.
    _tick?.cancel();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
    _syncKeepAlive();
  }

  void onDisconnected() {
    if (!_connected) return;
    _connected = false;
    _tick?.cancel();
    _tick = null;
    lastSuccessAt.value = null;
    _syncKeepAlive();
  }

  // ----------------------------------------------------- wear + battery data

  /// 0xF5 06 = worn / 07 = removed. While not worn nothing is pushed
  /// (battery saver); putting the glasses on shows the current face again.
  void onWearChanged(bool worn) {
    if (glassesWorn.value == worn) return;
    glassesWorn.value = worn;
    if (worn) forceRefresh();
  }

  /// Battery percent per side from the 0x2C report (also pushed unsolicited).
  void onBattery(String lr, int percent) {
    if (percent < 0 || percent > 100) return;
    if (lr == 'L') {
      batteryL.value = percent;
    } else if (lr == 'R') {
      batteryR.value = percent;
    }
  }

  // ------------------------------------------------------------- navigation

  void nextFace() => selectFace(activeFaceIndex.value + 1);
  void prevFace() => selectFace(activeFaceIndex.value - 1);

  /// Selects a face (double tap on the glasses or the settings screen) and
  /// shows it right away.
  void selectFace(int index) {
    activeFaceIndex.value =
        ((index % faces.length) + faces.length) % faces.length;
    forceRefresh();
  }

  /// Re-sends the active face even if nothing changed - e.g. after the
  /// firmware drew its own screen over it.
  void forceRefresh() {
    _pushedKey = '';
    _notBefore = DateTime.fromMillisecondsSinceEpoch(0);
    unawaited(pushActiveFace());
  }

  // ------------------------------------------------------------------ pump

  bool get _canPush =>
      _connected &&
      facesEnabled.value &&
      glassesWorn.value &&
      !pushing.value &&
      !BmpUpdateManager.isTransferring;

  void _onTick() {
    if (!_canPush || DateTime.now().isBefore(_notBefore)) return;
    final face = activeFace;
    final key = faceContentKey(face, slotsFor(face), snapshot());
    if (key != _pushedKey) {
      unawaited(pushActiveFace());
    }
  }

  /// Renders the active face and pushes it to both arms. If exactly one arm
  /// drops out, that arm is re-sent once - otherwise the halves would show
  /// different frames until the next change.
  Future<void> pushActiveFace() async {
    if (!_canPush) return;
    pushing.value = true;
    var ok = false;
    try {
      final face = activeFace;
      final slots = slotsFor(face);
      final data = snapshot();
      final key = faceContentKey(face, slots, data);
      final bmp = await _renderer.renderBmp(face, slots, data);

      var res = await _bmp.updateBmpBothArms(bmp);
      if (res.left != res.right) {
        final lr = res.left ? 'R' : 'L';
        print('FaceScheduler: $lr dropped out, re-sending that arm');
        final retry = await _bmp.updateBmp(lr, bmp);
        res = (left: res.left || retry, right: res.right || retry);
      }
      ok = res.left && res.right;
      if (ok) {
        _pushedKey = key;
        linkCounter.value++;
        lastSuccessAt.value = DateTime.now();
      } else {
        print('FaceScheduler: push failed (L=${res.left}, R=${res.right})');
      }
    } catch (e) {
      print('FaceScheduler push failed: $e');
    } finally {
      _notBefore = DateTime.now().add(ok ? _minGap : _retryAfter);
      pushing.value = false;
    }
  }

  /// 0x18: tell the glasses to go back to their dashboard.
  Future<void> exitToDashboard() async {
    if (!_connected) return;
    try {
      await Proto.exit();
    } catch (e) {
      print('FaceScheduler exitToDashboard failed: $e');
    }
  }

  // -------------------------------------------------------------- keep-alive

  void _syncKeepAlive() {
    final shouldRun =
        facesEnabled.value && _connected && keepAliveEnabled.value;
    if (Get.isRegistered<KeepAliveService>()) {
      KeepAliveService.get.set(shouldRun);
    }
  }

  @override
  void onClose() {
    _tick?.cancel();
    _tick = null;
    if (Get.isRegistered<KeepAliveService>()) {
      KeepAliveService.get.stop();
    }
    super.onClose();
  }
}
