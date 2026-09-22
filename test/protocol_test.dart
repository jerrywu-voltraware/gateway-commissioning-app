import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:gateway_commissioning/core/protocol.dart';

void main() {
  test('byte framing retains split UTF8, quotes and multiple frames', () {
    final frames = JsonFrames();
    final message = {
      'req_id': 'one',
      'status': 'ok',
      'result': jsonEncode({'ssid': '測試}網路"'}),
    };
    final bytes = utf8.encode(jsonEncode(message));
    final all = <Map<String, dynamic>>[];
    for (final byte in bytes) {
      all.addAll(frames.add([byte]));
    }
    expect(all, [message]);
    expect(frames.add(utf8.encode('{}{}')).length, 2);
  });
  test('timeout reset discards a lost frame before the next reply', () {
    final frames = JsonFrames();
    expect(frames.add(utf8.encode('{"result":')), isEmpty);
    frames.clear();
    expect(
      frames.add(utf8.encode('{"req_id":"next"}')).single['req_id'],
      'next',
    );
  });
  test('legacy and next generation have separate profiles and deadlines', () {
    expect(profileFor('1.6.0'), ProtocolProfile.legacy);
    expect(profileFor('1.7.0'), ProtocolProfile.current);
    expect(commandTimeout('assign_device_id', {}).inSeconds, 30);
    expect(commandTimeout('scan_ble_discover', {'duration': 10}).inSeconds, 18);
  });
}
