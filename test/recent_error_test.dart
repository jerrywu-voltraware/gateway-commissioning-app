import 'package:flutter_test/flutter_test.dart';
import 'package:gateway_commissioning/presentation/recent_error.dart';
import 'package:gateway_commissioning/l10n/l10n.dart';
import 'support/l10n.dart';

void main() {
  test('firmware code table and notification severity', () {
    useLanguage(AppLanguage.zh);
    final expected = <int, String>{
      0: '無錯誤',
      1: 'PTU PA 過溫',
      2: 'PTU DCDC 過溫',
      3: 'PTU IC 過溫',
      16: 'PTU Iin 電流過流',
      17: 'PTU IBUS 電流過流',
      18: 'PTU I1 電流過流',
      19: 'PTU I3 電流過流',
      32: 'PTU I1/I3 相位異常',
      48: 'PTU 通訊錯誤',
      64: 'PTU Timeset 失敗',
      160: 'PRU 過壓',
      161: 'PRU 過流',
      162: 'PRU 過溫',
      163: 'PRU 已充滿',
      176: 'PTU Low Power 卡住',
      177: 'PTU Power Transfer 卡住',
      178: '充電完成',
      179: '重新啟動充電',
    };
    for (final e in expected.entries) {
      expect(
        recentErrorText(e.key),
        '${e.value} (0x${e.key.toRadixString(16).toUpperCase().padLeft(2, '0')})',
      );
      expect(recentErrorIsFault(e.key), ![0, 163, 178, 179].contains(e.key));
    }
    expect(recentErrorText(255), '未知錯誤 (0xFF)');
    expect(recentErrorIsFault(255), isTrue);
    expect(recentErrorText(null), '--');
    expect(recentErrorIsFault(null), isFalse);
  });
  test('English code descriptions', () {
    useLanguage(AppLanguage.en);
    expect(recentErrorText(1), 'PTU PA overtemperature (0x01)');
    expect(recentErrorText(178), 'Charging complete (0xB2)');
    expect(recentErrorText(255), 'Unknown error (0xFF)');
  });
}
