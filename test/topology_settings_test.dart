// 2026-09: 一對一（直連）模式的使用者決策 —「確認『是這台』後預設把 PTU 綁定到
// 閘道器」。`TopologySettingsState.directBindOnConfirm` 的類別預設改為 true
// （韌體本身仍預設 off，是 APP 主動選擇綁定）。這裡只測偏好本身的載入／保存；
// 「確認後真的會送 direct_bind_mac」由 round15_direct_flow_test.dart 的
// commissioning 流程測試覆蓋。
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gateway_commissioning/application/topology_settings.dart';

void main() {
  test('fresh install (no saved preference): directBindOnConfirm defaults to '
      'true', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(topologyProvider.notifier).ready;
    expect(container.read(topologyProvider).directBindOnConfirm, isTrue);
    expect(container.read(topologyProvider).loaded, isTrue);
  });

  test('an install that already saved the setting off keeps it off (the new '
      'default never overrides a saved preference)', () async {
    SharedPreferences.setMockInitialValues({'direct_bind_on_confirm': false});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(topologyProvider.notifier).ready;
    expect(container.read(topologyProvider).directBindOnConfirm, isFalse);
  });

  test('an install that already saved the setting on keeps it on', () async {
    SharedPreferences.setMockInitialValues({'direct_bind_on_confirm': true});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(topologyProvider.notifier).ready;
    expect(container.read(topologyProvider).directBindOnConfirm, isTrue);
  });

  test('setDirectBindOnConfirm(false) persists across a later load (app '
      'restart)', () async {
    SharedPreferences.setMockInitialValues({});
    final first = ProviderContainer();
    addTearDown(first.dispose);
    final topo = first.read(topologyProvider.notifier);
    await topo.ready;
    expect(first.read(topologyProvider).directBindOnConfirm, isTrue);
    await topo.setDirectBindOnConfirm(false);
    expect(first.read(topologyProvider).directBindOnConfirm, isFalse);

    // A fresh container reading the same (mocked) SharedPreferences store,
    // as after the app restarts.
    final reopened = ProviderContainer();
    addTearDown(reopened.dispose);
    await reopened.read(topologyProvider.notifier).ready;
    expect(reopened.read(topologyProvider).directBindOnConfirm, isFalse);
  });
}
