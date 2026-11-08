import 'package:demo_ai_even/ble_manager.dart';
import 'package:demo_ai_even/faces/face_scheduler.dart';
import 'package:flutter/material.dart';

class MatrixPage extends StatefulWidget {
  const MatrixPage({super.key});

  @override
  State<MatrixPage> createState() => _MatrixPageState();
}

class _MatrixPageState extends State<MatrixPage> {
  late final int _previousFaceIndex;
  late final bool _previousFacesEnabled;
  bool _started = false;
  bool _animate = true;
  int _speed = 1;

  @override
  void initState() {
    super.initState();
    final scheduler = FaceScheduler.get;
    _previousFaceIndex = scheduler.activeFaceIndex.value;
    _previousFacesEnabled = scheduler.facesEnabled.value;
  }

  void _start() {
    if (!BleManager.get().isConnected) return;
    FaceScheduler.get.showMatrix(animate: _animate, speed: _speed);
    setState(() => _started = true);
  }

  void _stop() {
    if (!_started) return;
    FaceScheduler.get.restoreFace(
      index: _previousFaceIndex,
      enabled: _previousFacesEnabled,
    );
    setState(() => _started = false);
  }

  @override
  void dispose() {
    if (_started) {
      FaceScheduler.get.restoreFace(
        index: _previousFaceIndex,
        enabled: _previousFacesEnabled,
      );
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheduler = FaceScheduler.get;
    final connected = BleManager.get().isConnected;
    return Scaffold(
      backgroundColor: const Color(0xFFF2F3F5),
      appBar: AppBar(
        title: const Text('Matrix'),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFF07120C),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              children: [
                Icon(Icons.blur_on, color: Color(0xFF35E07F), size: 28),
                SizedBox(width: 14),
                Expanded(
                  child: Text(
                    'Zeichenregen',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            connected
                ? 'Bildwechsel können je nach Bluetooth-Verbindung einige Sekunden dauern.'
                : 'Verbinde zuerst die G1-Brille auf der Startseite.',
            style: const TextStyle(fontSize: 14, color: Colors.black54),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 52,
            child: FilledButton.icon(
              onPressed: !connected ? null : (_started ? _stop : _start),
              icon: Icon(_started ? Icons.stop : Icons.play_arrow),
              label: Text(_started ? 'Matrix beenden' : 'Matrix starten'),
            ),
          ),
          const SizedBox(height: 18),
          SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            title: const Text('Bewegung'),
            subtitle: Text(_animate ? 'Fallende Zeichen' : 'Standbild'),
            value: _animate,
            onChanged: (value) {
              setState(() => _animate = value);
              if (_started) scheduler.setMatrixAnimating(value);
            },
          ),
          const SizedBox(height: 12),
          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 10),
            child: Text(
              'TEMPO',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.black54,
              ),
            ),
          ),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 0, label: Text('Ruhig')),
              ButtonSegment(value: 1, label: Text('Normal')),
              ButtonSegment(value: 2, label: Text('Schnell')),
            ],
            selected: {_speed},
            onSelectionChanged: !_animate
                ? null
                : (selection) {
                    final value = selection.first;
                    setState(() => _speed = value);
                    if (_started) scheduler.setMatrixSpeed(value);
                  },
          ),
          const SizedBox(height: 10),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              'Die Tempostufe bestimmt die Bewegung zwischen den übertragenen Vollbildern. '
              '„Schnell“ kann sichtbare Sprünge verursachen.',
              style: TextStyle(fontSize: 12, height: 1.35, color: Colors.black54),
            ),
          ),
        ],
      ),
    );
  }
}