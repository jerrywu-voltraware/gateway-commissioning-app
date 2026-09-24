import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/gateway_topology.dart';

/// 開發期開關：閘道器拓撲（直連／星狀）與星狀模式的每台 PTU 數。
/// Release 前會再加密碼鎖；本次只做開關本身。
class TopologySettingsState {
  const TopologySettingsState({
    this.topology = GatewayTopology.star,
    this.starCount = defaultStarPtuCount,
    this.loaded = false,
  });
  final GatewayTopology topology;
  final int starCount;

  /// Saved values have been read from SharedPreferences.
  final bool loaded;

  /// 這次配置流程要達成的 PTU 目標台數（直連固定 1）。
  int get targetCount => topology.targetCount(starCount);

  TopologySettingsState copy({
    GatewayTopology? topology,
    int? starCount,
    bool? loaded,
  }) => TopologySettingsState(
    topology: topology ?? this.topology,
    starCount: starCount ?? this.starCount,
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
      loaded: true,
    );
  }

  Future<void> setTopology(GatewayTopology value) async {
    state = state.copy(topology: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_topologyKey, value.name);
  }

  Future<void> setStarCount(int value) async {
    final clamped = value.clamp(minStarPtuCount, maxStarPtuCount);
    state = state.copy(starCount: clamped);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_starCountKey, clamped);
  }
}
