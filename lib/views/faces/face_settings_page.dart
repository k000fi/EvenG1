import 'dart:async';

import 'package:demo_ai_even/faces/complications.dart';
import 'package:demo_ai_even/faces/face_data.dart';
import 'package:demo_ai_even/faces/face_format.dart';
import 'package:demo_ai_even/faces/face_scheduler.dart';
import 'package:demo_ai_even/faces/watch_faces.dart';
import 'package:demo_ai_even/services/weather_models.dart';
import 'package:demo_ai_even/services/weather_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Waveguide green - the panel is a green monochrome micro-LED.
const Color kPanelGreen = Color(0xFF35E07F);
const Color kPanelBlack = Color(0xFF07120C);
const Color kDarkGreen = Color(0xFF14351F);
const double kRadius = 16;

/// Watch faces: pick a face, fill its complication slots, set the places
/// for weather and world clock.
class FaceSettingsPage extends StatefulWidget {
  const FaceSettingsPage({super.key});

  @override
  State<FaceSettingsPage> createState() => _FaceSettingsPageState();
}

class _FaceSettingsPageState extends State<FaceSettingsPage> {
  late final TextEditingController _textController;
  Timer? _previewTicker;
  Timer? _textDebounce;
  String? _pendingText;

  @override
  void initState() {
    super.initState();
    _textController =
        TextEditingController(text: FaceScheduler.get.customText.value);
    // the previews show the minute; everything else is reactive via Obx
    _previewTicker =
        Timer.periodic(const Duration(seconds: 10), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _previewTicker?.cancel();
    _textDebounce?.cancel();
    _commitText(); // do not drop what was typed right before leaving
    _textController.dispose();
    super.dispose();
  }

  /// Every change is persisted and may trigger a multi-second BMP push - so
  /// only commit once typing pauses.
  void _onTextChanged(String value) {
    _pendingText = value;
    _textDebounce?.cancel();
    _textDebounce = Timer(const Duration(milliseconds: 500), _commitText);
  }

  void _commitText() {
    final value = _pendingText;
    _pendingText = null;
    if (value != null) FaceScheduler.get.customText.value = value;
  }

  @override
  Widget build(BuildContext context) {
    final fs = FaceScheduler.get;
    return Scaffold(
      backgroundColor: const Color(0xFFF2F3F5),
      appBar: AppBar(
        title: const Text('Even Faces'),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          _masterSwitch(fs),
          const SizedBox(height: 12),
          _howItWorks(),
          const SizedBox(height: 20),
          _sectionLabel('Faces'),
          _gallery(fs),
          const SizedBox(height: 20),
          Obx(() => _sectionLabel('Komplikationen · ${fs.activeFace.name}')),
          _editor(fs),
          const SizedBox(height: 20),
          _sectionLabel('Wetter & Weltzeit'),
          _places(),
          const SizedBox(height: 20),
          _sectionLabel('Eigener Text'),
          _textCard(),
          const SizedBox(height: 20),
          _sectionLabel('Hintergrund'),
          _keepAliveCard(fs),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- pieces

  Widget _card({required Widget child, EdgeInsets? padding}) => Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(kRadius),
        ),
        padding: padding ?? const EdgeInsets.all(16),
        child: child,
      );

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Text(
          text.toUpperCase(),
          style: const TextStyle(
            fontSize: 12,
            letterSpacing: 0.8,
            fontWeight: FontWeight.w600,
            color: Colors.black54,
          ),
        ),
      );

  Widget _hint(String text) => Text(
        text,
        style: const TextStyle(fontSize: 12, height: 1.35, color: Colors.black54),
      );

  Widget _masterSwitch(FaceScheduler fs) => Obx(() {
        final on = fs.facesEnabled.value;
        return Container(
          decoration: BoxDecoration(
            color: on ? kDarkGreen : Colors.white,
            borderRadius: BorderRadius.circular(kRadius),
          ),
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          child: Row(
            children: [
              Icon(Icons.watch_outlined, color: on ? kPanelGreen : Colors.black38),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Faces aktiv',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: on ? Colors.white : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      on
                          ? 'Die Brille zeigt dein Watch-Face'
                          : 'Die Brille zeigt ihr eigenes Dashboard',
                      style: TextStyle(
                        fontSize: 12,
                        color: on ? Colors.white70 : Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: on,
                activeColor: kPanelGreen,
                onChanged: (v) => fs.facesEnabled.value = v,
              ),
            ],
          ),
        );
      });

  Widget _howItWorks() => _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.help_outline, size: 18, color: Colors.black54),
                SizedBox(width: 8),
                Text('So funktioniert es',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 12),
            _bullet(Icons.touch_app_outlined, 'Face wechseln',
                'Doppeltipp auf den rechten Bügel: nächstes Face. Doppeltipp links: vorheriges. Einfaches Tippen blättert weiter in Even AI.'),
            _bullet(Icons.dashboard_customize_outlined, 'Komplikationen',
                'Jedes Face hat Plätze für Komplikationen – Wetter, Mond, Akku, Weltzeit und mehr. Unten unter „Komplikationen" einen Platz antippen und belegen.'),
            _bullet(Icons.visibility_outlined, 'Nur beim Tragen',
                'Nimmst du die Brille ab, pausiert die Anzeige und spart Akku. Beim Aufsetzen ist das Face sofort wieder da.'),
            _bullet(Icons.speed_outlined, 'Minutentakt',
                'Ein Bild braucht rund eine Sekunde pro Bügel. Die Brille aktualisiert deshalb nur, wenn sich etwas ändert – spätestens jede Minute.'),
            _bullet(Icons.settings_suggest_outlined, 'Doppeltipp belegt?',
                'Öffnet die Brille bei Doppeltipp etwas anderes, stell in der Even-App die Doppeltipp-Geste auf „Keine".',
                last: true),
          ],
        ),
      );

  Widget _bullet(IconData icon, String title, String body, {bool last = false}) =>
      Padding(
        padding: EdgeInsets.only(bottom: last ? 0 : 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: const Color(0xFF1F9D57)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 13.5, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(body,
                      style: const TextStyle(
                          fontSize: 12.5, height: 1.35, color: Colors.black54)),
                ],
              ),
            ),
          ],
        ),
      );

  // --------------------------------------------------------------- gallery

  Widget _gallery(FaceScheduler fs) => SizedBox(
        height: 190,
        child: Obx(() {
          final data = fs.snapshot();
          final active = fs.activeFaceIndex.value;
          return ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: FaceScheduler.faces.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, i) {
              final face = FaceScheduler.faces[i];
              final isActive = i == active;
              return SizedBox(
                width: 272,
                child: Material(
                  color: isActive ? kDarkGreen : Colors.white,
                  borderRadius: BorderRadius.circular(kRadius),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(kRadius),
                    onTap: () => fs.selectFace(i),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          FacePreview(
                              face: face, slotIds: fs.slotsFor(face), data: data),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  face.name,
                                  style: TextStyle(
                                    fontSize: 15.5,
                                    fontWeight: FontWeight.w600,
                                    color: isActive ? Colors.white : Colors.black87,
                                  ),
                                ),
                              ),
                              if (isActive)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: kPanelGreen,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: const Text('Aktiv',
                                      style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: kDarkGreen)),
                                ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            face.description,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.3,
                              color: isActive ? Colors.white70 : Colors.black54,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        }),
      );

  // ---------------------------------------------------------------- editor

  Widget _editor(FaceScheduler fs) => _card(
        padding: const EdgeInsets.all(12),
        child: Obx(() {
          final face = fs.activeFace;
          final ids = fs.slotsFor(face);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FacePreview(
                  face: face, slotIds: ids, data: fs.snapshot(), showSlots: true),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: _hint('Genau dieses Bild geht an beide Gläser. '
                    'Die Umrisse zeigen die Plätze – sie sind nur hier zu sehen.'),
              ),
              const SizedBox(height: 8),
              for (var i = 0; i < face.slots.length; i++)
                _slotRow(fs, face, i, Complications.byId(ids[i])),
            ],
          );
        }),
      );

  Widget _slotRow(FaceScheduler fs, WatchFace face, int i, Complication c) =>
      InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _pickComplication(fs, face, i, c),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFFF0F1F3),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('${i + 1}',
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(face.slots[i].label,
                        style: const TextStyle(fontSize: 12, color: Colors.black54)),
                    const SizedBox(height: 1),
                    Text(c.name,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, size: 20, color: Colors.black26),
            ],
          ),
        ),
      );

  Future<void> _pickComplication(
      FaceScheduler fs, WatchFace face, int slot, Complication current) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.75),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: Text('${face.slots[slot].label} · ${face.name}',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600)),
              ),
              for (final c in Complications.all)
                ListTile(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  title: Text(c.name),
                  subtitle: Text(c.description),
                  trailing: c.id == current.id
                      ? const Icon(Icons.check_circle, color: Color(0xFF1F9D57))
                      : null,
                  onTap: () => Navigator.pop(context, c.id),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked != null) fs.setSlot(face, slot, picked);
  }

  // ---------------------------------------------------------------- places

  Widget _places() {
    final ws = WeatherService.get;
    return _card(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: Obx(() {
        final w = ws.weather.value;
        final error = ws.lastError.value;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _placeRow(
              icon: Icons.wb_sunny_outlined,
              title: 'Wetter-Ort',
              place: ws.place.value,
              trailing: ws.loading.value
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : (w != null
                      ? Text('${w.temperature.round()}° · ${Fmt.hhmm(w.fetchedAt)}',
                          style: const TextStyle(
                              fontSize: 12, color: Colors.black54))
                      : null),
              onTap: () => _pickPlace(world: false),
            ),
            const Divider(height: 1, indent: 52),
            _placeRow(
              icon: Icons.public,
              title: 'Weltzeit-Stadt',
              place: ws.worldPlace.value,
              onTap: () => _pickPlace(world: true),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
              child: error != null
                  ? Text(error,
                      style: const TextStyle(fontSize: 12, color: Colors.red))
                  : _hint('Suche nach Ortsnamen, keine Standortfreigabe nötig. '
                      'Daten von Open-Meteo, alle 30 Minuten aktualisiert.'),
            ),
          ],
        );
      }),
    );
  }

  Widget _placeRow({
    required IconData icon,
    required String title,
    required GeoPlace? place,
    required VoidCallback onTap,
    Widget? trailing,
  }) =>
      ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        leading: Icon(icon, color: const Color(0xFF1F9D57)),
        title: Text(title,
            style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
        subtitle: Text(place?.label ?? 'Nicht gewählt – antippen'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (trailing != null) trailing,
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, size: 20, color: Colors.black26),
          ],
        ),
        onTap: onTap,
      );

  Future<void> _pickPlace({required bool world}) async {
    final ws = WeatherService.get;
    final current = world ? ws.worldPlace.value : ws.place.value;
    final result = await showModalBottomSheet<_PlaceChoice>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => _PlaceSearchSheet(
        title: world ? 'Weltzeit-Stadt' : 'Wetter-Ort',
        current: current,
      ),
    );
    if (result == null) return;
    if (world) {
      await ws.setWorldPlace(result.place);
    } else {
      await ws.setPlace(result.place);
    }
  }

  // ------------------------------------------------------------ text, bg

  Widget _textCard() => _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _textController,
              maxLines: 3,
              onChanged: _onTextChanged,
              decoration: InputDecoration(
                hintText: 'Schreib etwas …',
                filled: true,
                fillColor: const Color(0xFFF4F5F7),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.all(14),
              ),
            ),
            const SizedBox(height: 8),
            _hint('Erscheint in der Komplikation „Eigener Text". Am besten '
                'lesbar im großen Platz des Kompakt-Faces.'),
          ],
        ),
      );

  Widget _keepAliveCard(FaceScheduler fs) => _card(
        child: Obx(() => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text('Im Hintergrund aktiv halten',
                          style: TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w600)),
                    ),
                    Switch(
                      value: fs.keepAliveEnabled.value,
                      activeColor: kPanelGreen,
                      onChanged: (v) => fs.keepAliveEnabled.value = v,
                    ),
                  ],
                ),
                _hint('Spielt eine lautlose Tonspur, damit iOS die App im '
                    'Hintergrund nicht beendet und die Faces weiterlaufen. '
                    'Kostet etwas Akku – zum Sparen ausschalten.'),
              ],
            )),
      );
}

// ------------------------------------------------------------ place search

/// Result of the place sheet; `place == null` means "remove".
class _PlaceChoice {
  final GeoPlace? place;
  const _PlaceChoice(this.place);
}

class _PlaceSearchSheet extends StatefulWidget {
  final String title;
  final GeoPlace? current;

  const _PlaceSearchSheet({required this.title, required this.current});

  @override
  State<_PlaceSearchSheet> createState() => _PlaceSearchSheetState();
}

class _PlaceSearchSheetState extends State<_PlaceSearchSheet> {
  Timer? _debounce;
  List<GeoPlace> _results = const [];
  bool _loading = false;
  String? _error;
  String _query = '';

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged(String q) {
    _query = q;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () => _search(q));
  }

  Future<void> _search(String q) async {
    if (q.trim().length < 2) {
      setState(() => _results = const []);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await WeatherService.get.search(q);
      if (!mounted || q != _query) return;
      setState(() => _results = r);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Suche fehlgeschlagen – Internetverbindung prüfen');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.6,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
                child: Text(widget.title,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600)),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  autofocus: true,
                  onChanged: _onChanged,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'Stadt suchen, z. B. Wien',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _loading
                        ? const Padding(
                            padding: EdgeInsets.all(14),
                            child: SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2)),
                          )
                        : null,
                    filled: true,
                    fillColor: const Color(0xFFF4F5F7),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                  child: Text(_error!,
                      style: const TextStyle(fontSize: 12, color: Colors.red)),
                ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(8),
                  children: [
                    for (final p in _results)
                      ListTile(
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        leading: const Icon(Icons.place_outlined),
                        title: Text(p.name),
                        subtitle: Text(p.label),
                        onTap: () => Navigator.pop(context, _PlaceChoice(p)),
                      ),
                    if (widget.current != null)
                      ListTile(
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        leading: const Icon(Icons.close, color: Colors.red),
                        title: Text('„${widget.current!.name}" entfernen',
                            style: const TextStyle(color: Colors.red)),
                        onTap: () =>
                            Navigator.pop(context, const _PlaceChoice(null)),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- preview

/// The exact face canvas the glasses get, scaled down and tinted green.
class FacePreview extends StatelessWidget {
  final WatchFace face;
  final List<String> slotIds;
  final FaceData data;

  /// Outline the complication slots (editor only - never sent to the glasses).
  final bool showSlots;

  const FacePreview({
    super.key,
    required this.face,
    required this.slotIds,
    required this.data,
    this.showSlots = false,
  });

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          return ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Container(
              color: kPanelBlack,
              width: w,
              height: w * kFaceHeight / kFaceWidth,
              child: ColorFiltered(
                colorFilter: const ColorFilter.matrix(<double>[
                  0, 0, 0, 0, 0, //
                  0.30, 0.59, 0.11, 0, 0, //
                  0.10, 0.20, 0.04, 0, 0, //
                  0, 0, 0, 1, 0, //
                ]),
                child: CustomPaint(
                    painter: _PreviewPainter(face, slotIds, data, showSlots)),
              ),
            ),
          );
        },
      );
}

class _PreviewPainter extends CustomPainter {
  final WatchFace face;
  final List<String> slotIds;
  final FaceData data;
  final bool showSlots;

  _PreviewPainter(this.face, this.slotIds, this.data, this.showSlots);

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / kFaceWidth;
    canvas.save();
    canvas.scale(scale, scale);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, kFaceWidth.toDouble(), kFaceHeight.toDouble()),
      Paint()..color = Colors.black,
    );
    paintWatchFace(canvas, face, slotIds, data);
    if (showSlots) {
      final outline = Paint()
        ..color = const Color(0x66FFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5 / scale;
      for (final slot in face.slots) {
        canvas.drawRRect(
            RRect.fromRectAndRadius(slot.rect.inflate(3), const Radius.circular(6)),
            outline);
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PreviewPainter old) => true;
}
