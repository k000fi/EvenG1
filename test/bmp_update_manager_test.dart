import 'dart:typed_data';

import 'package:crclib/catalog.dart';
import 'package:demo_ai_even/controllers/bmp_update_manager.dart';
import 'package:demo_ai_even/services/ble.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('chunks both arms and latches them in left-to-right order', () async {
    final sent = <({String lr, Uint8List data})>[];
    final requests = <({String lr, Uint8List data})>[];
    final manager = BmpUpdateManager(
      sendData: (data, {required lr}) async {
        sent.add((lr: lr, data: Uint8List.fromList(data)));
      },
      request: (data, {required lr, required timeoutMs}) async {
        requests.add((lr: lr, data: Uint8List.fromList(data)));
        final response = BleReceive();
        response.data = Uint8List.fromList(
            data[0] == 0x20 ? [0x20, 0xc9] : [0x16, 0, 0, 0, 0, 0xc9]);
        return response;
      },
    );
    final image = Uint8List.fromList(List.generate(9856, (i) => i & 0xff));

    final result = await manager.updateBmpBothArms(image);

    expect(result, (left: true, right: true));
    for (final lr in ['L', 'R']) {
      final packets = sent.where((packet) => packet.lr == lr).toList();
      expect(packets, hasLength(51));
      for (var index = 0; index < packets.length; index++) {
        final packet = packets[index].data;
        final start = index * 194;
        final end = start + 194 < image.length ? start + 194 : image.length;
        final payloadOffset = index == 0 ? 6 : 2;
        expect(packet[0], 0x15);
        expect(packet[1], index);
        if (index == 0) {
          expect(packet.sublist(0, payloadOffset), [
            0x15,
            0,
            0,
            0x1c,
            0,
            0,
          ]);
        }
        expect(packet.sublist(payloadOffset), image.sublist(start, end));
      }
    }
    expect(
      requests.map((request) => '${request.lr}:${request.data[0]}').toList(),
      ['L:32', 'R:32', 'L:22', 'R:22'],
    );
    expect(requests[0].data, [0x20, 0x0d, 0x0e]);

    final crc = Crc32Xz()
        .convert(Uint8List.fromList([0x00, 0x1c, 0x00, 0x00, ...image]))
        .toBigInt()
        .toInt();
    final expectedCrc = [
      0x16,
      crc >> 24 & 0xff,
      crc >> 16 & 0xff,
      crc >> 8 & 0xff,
      crc & 0xff,
    ];
    expect(requests[2].data, expectedCrc);
    expect(requests[3].data, expectedCrc);
    expect(BmpUpdateManager.isTransferring, isFalse);
  });

  test('rejects a truncated CRC acknowledgement', () async {
    final manager = BmpUpdateManager(
      sendData: (data, {required lr}) async {},
      request: (data, {required lr, required timeoutMs}) async {
        final response = BleReceive();
        response.data = Uint8List.fromList(
          data[0] == 0x20 ? [0x20, 0xc9] : [0x16],
        );
        return response;
      },
    );

    final result = await manager.updateBmp('L', Uint8List.fromList([0x42]));

    expect(result, isFalse);
    expect(BmpUpdateManager.isTransferring, isFalse);
  });

  test('refuses images that exceed the one-byte chunk index', () async {
    var sentCount = 0;
    final manager = BmpUpdateManager(
      sendData: (data, {required lr}) async => sentCount++,
      request: (data, {required lr, required timeoutMs}) async => BleReceive(),
    );

    final result = await manager.updateBmp('L', Uint8List(194 * 256 + 1));

    expect(result, isFalse);
    expect(sentCount, 0);
    expect(BmpUpdateManager.isTransferring, isFalse);
  });
}
