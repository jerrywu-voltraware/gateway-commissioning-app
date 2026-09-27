import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/gateway_topology.dart';

/// 開發期開關：閘道器拓撲（直連／星狀）與星狀模式的每台 PTU 數。
/// Release 前會再加密碼鎖；本次只做開關本身。
class TopologySettingsState {
  const TopologySettingsState({
    this.topology = GatewayTopology.star,
    this.starCount = defaultStarPtuCount,
    this.directBindOnConfirm = true,
    this.loaded = false,
  });
  final GatewayTopology topology;
  final int starCount;

  /// Direct mode (firmware 1.7.20+): 「是這台，開始監控」 also binds the
  /// gateway to that PTU's MAC (`direct_bind_mac`), so it never connects a
  /// neighbouring pile's PTU later. On by default since 2026-09: once the
  /// installer confirms 「是這台」 the identity is settled, so the gateway
  /// should stay with that PTU (the firmware itself still defaults this
  /// off — the APP opts in). Turning it off lets the gateway free-roam
  /// again: if this pile's PTU is powered off, it may pick up a
  /// neighbouring pile's PTU instead.
  final bool directBindOnConfirm;

  /// Saved values have been read from SharedPreferences.
  final bool loaded;

  /// 這次配置流程要達成的 PTU 目標台數（直連固定 1）。
  int get targetCount => topology.targetCount(starCount);

  TopologySettingsState copy({
    GatewayTopology? topology,
    int? starCount,
    bool? directBindOnConfirm,
    bool? loaded,
  }) => TopologySettingsState(
    topology: topology ?? this.topology,
    starCount: starCount ?? this.starCount,
    directBindOnConfirm: directBindOnConfirm ?? this.directBindOnConfirm,
    loaded: loaded ?? this.loaded,
  );
}

final topologyProvider =
    NotifierProvider<TopologySettingsController, TopologySettingsState>(
      TopologySettingsController.new,
    );

class TopologySettingsController extends Notifier<TopologySettingsState> {
  static const _topologyKey = 'gateway_topology';
  static const _starCountKey = 'gateway_star_ptu_count';
  static const _bindKey = 'direct_bind_on_confirm';

  /// Completes once the saved values are loaded.
  Future<void> ready = Future.value();

  @override
  TopologySettingsState build() {
    ready = _load();
    return const TopologySettingsState();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!ref.mounted) return;
    final saved = prefs.getString(_topologyKey);
    final topology = GatewayTopology.values
        .where((t) => t.name == saved)
        .firstOrNull;
    final savedCount = prefs.getInt(_starCountKey);
    state = state.copy(
      topology: topology ?? state.topology,
      starCount: savedCount == null
          ? state.starCount
          : savedCount.clamp(minStarPtuCount, maxStarPtuCount),
      directBindOnConfirm: prefs.getBool(_bindKey) ?? state.directBindOnConfirm,
      loaded: true,
    );
  }

  Future<void> setTopology(GatewayTopology value) async {
    state = state.copy(topology: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_topologyKey, value.name);
  }

  Future<void> setDirectBindOnConfirm(bool value) async {
    state = state.copy(directBindOnConfirm: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_bindKey, value);
  }

  Future<void> setStarCount(int value) async {
    final clamped = value.clamp(minStarPtuCount, maxStarPtuCount);
    state = state.copy(starCount: clamped);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_starCountKey, clamped);
  }
}
