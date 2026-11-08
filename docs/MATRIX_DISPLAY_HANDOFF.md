# Matrix Display: Handoff and Device Test

This document records the Linux preparation and the remaining Mac/iPhone/G1
work. The goal is to resume from the current `matrix-display` branch without
repeating the software checks.

## Current Status

- The Matrix effect is a `WatchFace` and uses the existing face scheduler and
  BMP transfer flow.
- The G1 panel is 576 x 136 pixels and monochrome. The Matrix trails use a
  4 x 4 ordered Bayer pattern to simulate darker shades spatially; the bright
  heads remain bright. This is not true grayscale or continuous animation.
- The scheduler selects frames at nominal intervals of 4, 2, or 1 seconds.
  These are not guaranteed display rates: a full image must be transferred
  before the scheduler's additional minimum delay can elapse.
- Flutter 3.47.9 / Dart 3.13.7 were used on Linux Mint 22.3.
- `flutter test`: all 51 tests passed.
- `flutter build linux --debug`: succeeded; output is under
  `build/linux/x64/debug/bundle/`.
- `git diff --check`: clean. Targeted analysis of the files changed for this
  work found no issues. Workspace-wide analysis still reports informational
  lint hints in other files, mostly diagnostic `print` calls and naming/style
  conventions.

## Linux Coverage

The renderer tests in `test/face_renderer_test.dart` verify the Matrix output,
spatial gray coverage, BMP header, full 9856-byte image, and panel margins.

`BmpUpdateManager` in `lib/controllers/bmp_update_manager.dart` accepts
optional send/request callbacks. Production callers keep using the normal
parameterless constructor; tests can inject a fake transport. The tests in
`test/bmp_update_manager_test.dart` verify:

- A 9856-byte image is split into 51 chunks per arm, including the final short
  chunk.
- Chunk 0 contains the destination address; later chunks have sequential
  one-byte indices.
- Bulk chunks go to both arms, then END acknowledgements and CRC commands are
  issued in the required L-then-R order.
- CRC includes the storage address and full image, sent big-endian.
- A truncated CRC acknowledgement is rejected, and an image requiring more
  than 256 chunks is refused before sending.

These are protocol/software tests only. Linux has no implementation of the
app's `method.bluetooth` CoreBluetooth channel and cannot verify real G1 BLE.

## Remaining iOS Risks

Review in `ios/Runner/BluetoothManager.swift` before or during the first device
run:

1. `glassesConnected` is currently emitted after both peripherals connect, but
   before service/characteristic discovery and notification setup necessarily
   finish. Dart may start session requests while a write characteristic is not
   ready.
2. Writes use `withoutResponse`. The current code does not check the negotiated
   maximum write length or gate writes on `canSendWriteWithoutResponse`.
   A full-frame transfer sends 200 bytes for chunk 0 and 196 bytes for later
   chunks. The existing delay alone does not prove that CoreBluetooth queued
   every write.
3. Background execution and the silent-audio keep-alive need real-device
   validation; iOS does not guarantee indefinite background execution.

Do not treat community protocol notes in `docs/G1_PROTOCOL_REFERENCE.md` as an
official Even Realities specification. Verify response layouts against device
logs and actual glasses.

## Minimal Mac Setup

On a Mac with Xcode and the iPhone 13 connected:

```bash
flutter doctor -v
flutter pub get
flutter test
flutter build ios --debug --no-codesign
```

Then open `ios/Runner.xcworkspace` in Xcode, select the iPhone 13, configure
Personal Team signing, and run the app on the phone. A simulator is not a
substitute for the G1 BLE check.

## iPhone 13 + G1 Checklist

Record the iOS version, Xcode version, glasses firmware, and results below.

1. Connect both arms and confirm the app does not start session traffic before
   both GATT write/notify characteristics are ready.
2. Record `maximumWriteValueLength(for: .withoutResponse)` for each arm. It
   must accommodate the 200-byte first packet and 196-byte later packets, or
   the native write path must be adapted before relying on image transfer.
3. Show a static face first. Confirm 51 data packets per arm, END success
   (`0xC9`), CRC success (`0xC9`), and matching left/right display.
4. Start Matrix in static, calm, normal, and fast modes. Record transfer
   start-to-start time and whether every displayed frame is complete and in
   sync. The fastest nominal setting may skip frames.
5. Run for 10-15 minutes; test disconnect/reconnect, app backgrounding, screen
   lock, and return to foreground. Note dropped writes, timeouts, battery
   impact, and whether the face resumes correctly.
6. Adjust the trail density only after viewing the spatial dither on the real
   green display.

## Results To Fill In

| Check | Result |
| --- | --- |
| iOS / Xcode / glasses firmware | Pending |
| Maximum no-response write size, left / right | Pending |
| Static frame: END and CRC, both arms | Pending |
| Matrix observed frame interval by speed | Pending |
| Left/right synchronization and dropped writes | Pending |
| Background, screen lock, reconnect | Pending |

Acceptance: static and animated images transfer without malformed or missing
chunks; both arms acknowledge and display the same frame; actual update cadence
is documented honestly. Do not promise continuous film-speed animation.