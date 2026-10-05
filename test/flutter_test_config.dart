// 所有測試共用的設定（flutter_test 會自動找到這個檔）。
//
// 首頁 NextActionGuide 的提示閃爍（_HintPulse）是無限重複動畫，會讓
// pumpAndSettle 一直等不到靜止而逾時。測試一律關掉它；APP 本身不受影響。
// 見 docs/i18n.md §8.5。
import 'dart:async';

import 'package:gateway_commissioning/presentation/next_action_guide.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  debugDisableHintPulse = true;
  await testMain();
}
