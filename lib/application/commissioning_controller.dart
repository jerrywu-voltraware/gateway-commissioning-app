import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/mqtt_target.dart';
import '../core/protocol.dart';
import '../data/ble_gateway_link.dart';
import '../data/contracts.dart';
import '../data/dashboard_api.dart';
import '../data/demo_system.dart';
import '../data/ptu_inventory.dart';
import 'verify_diagnosis.dart';

class DemoMode extends Notifier<bool> {
  @override
  bool build() => const bool.fromEnvironment('DEMO_MODE');
  void set(bool value) => state = value;
}

final demoProvider = NotifierProvider<DemoMode, bool>(DemoMode.new);
final demoSystemProvider = Provider((ref) => DemoSystem());
final linkProvider = Provider<GatewayLink>(
  (ref) => ref.watch(demoProvider)
      ? ref.watch(demoSystemProvider)
      : BleGatewayLink(),
);
final apiProvider = Provider<GatewayApi>(
  (ref) =>
      ref.watch(demoProvider) ? ref.watch(demoSystemProvider) : DashboardApi(),
);

class CommissionState {
  const CommissionState({
    this.step = 0,
    this.busy = false,
    this.message = '',
    this.error,
    this.seconds = 0,
    this.peers = const [],
    this.peer,
    this.config = const {},
    this.ptus = const [],
    this.selected = const {},
    this.results = const {},
    this.verified = false,
    this.report = '',
    this.online = false,
    this.missing = const [],
    this.uploadNotice = '',
  });
  final int step, seconds;
  final bool busy, verified, online;
  final String message, report;

  /// Outcome of the last upload-target switch or refresh (shown in its card).
  final String uploadNotice;
  final String? error;
  final List<GatewayPeer> peers;
  final GatewayPeer? peer;
  final Map<String, dynamic> config;
  final List<Map<String, dynamic>> ptus;
  final Set<String> selected;
  final Map<String, String> results;
  final List<String> missing;
  CommissionState copy({
    int? step,
    bool? busy,
    String? message,
    String? error,
    int? seconds,
    List<GatewayPeer>? peers,
    GatewayPeer? peer,
    Map<String, dynamic>? config,
    List<Map<String, dynamic>>? ptus,
    Set<String>? selected,
    Map<String, String>? results,
    bool? verified,
    String? report,
    bool? online,
    List<String>? missing,
    String? uploadNotice,
  }) => CommissionState(
    step: step ?? this.step,
    busy: busy ?? this.busy,
    message: message ?? this.message,
    error: error,
    seconds: seconds ?? this.seconds,
    peers: peers ?? this.peers,
    peer: peer ?? this.peer,
    config: config ?? this.config,
    ptus: ptus ?? this.ptus,
    selected: selected ?? this.selected,
    results: results ?? this.results,
    verified: verified ?? this.verified,
    report: report ?? this.report,
    online: online ?? this.online,
    missing: missing ?? this.missing,
    uploadNotice: uploadNotice ?? this.uploadNotice,
  );
}

final commissionProvider =
    NotifierProvider<CommissioningController, CommissionState>(
      CommissioningController.new,
    );

class CommissioningController extends Notifier<CommissionState> {
  late GatewayLink _link;
  late GatewayApi _api;
  Timer? _clock, _health;
  int _generation = 0;
  bool _provisioningMayBeActive = false;
  Future<bool>? _stopping;
  final Map<String, int> _restoredAssignments = {};
  String _backend = describeBackend(null);
  // Latest step-7 diagnosis, tagged with the generation that produced it.
  (int, String)? _diagnosis;
  bool _loggedIn = false,
      _lease = false,
      _foreground = true,
      _healthBusy = false;
  int get site => (state.config['site_id'] as num?)?.toInt() ?? 1;
  int get gateway => (state.config['gateway_id'] as num?)?.toInt() ?? 1;
  String get _path => '/api/gateways/$site/$gateway';
  @override
  CommissionState build() {
    _link = ref.watch(linkProvider);
    _api = ref.watch(apiProvider);
    ref.onDispose(() {
      _generation++;
      _clock?.cancel();
      _health?.cancel();
      unawaited(_link.disconnect());
    });
    return const CommissionState();
  }

  Future<void> _wait(int seconds, int generation) async {
    await Future<void>.delayed(
      _link.demo ? const Duration(milliseconds: 1) : Duration(seconds: seconds),
    );
    if (generation != _generation || !ref.mounted) {
      throw const GatewayFailure('cancelled');
    }
  }

  void _check(int generation) {
    if (generation != _generation || !ref.mounted) {
      throw const GatewayFailure('cancelled');
    }
  }

  String _mac(dynamic value) =>
      value.toString().replaceAll(':', '').toUpperCase();

  Future<Map<String, dynamic>> _command(
    int generation,
    String op, [
    Map<String, dynamic> params = const {},
  ]) async {
    _check(generation);
    if (sensitiveOps.contains(op) && state.config['otp_enabled'] == true) {
      throw const GatewayFailure('otp_enabled');
    }
    final result = await _link.command(op, params);
    _check(generation);
    return result;
  }

  Future<Map<String, dynamic>> _request(
    int generation,
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    _check(generation);
    final result = await _api.request(method, path, body);
    if (generation != _generation &&
        path.endsWith('/bot-monitor') &&
        body?['enabled'] == false) {
      try {
        await _api.request('PATCH', path, {'enabled': true});
      } catch (_) {}
    }
    _check(generation);
    return result;
  }

  Future<bool> _safeStop() async {
    if (!_provisioningMayBeActive) return true;
    if (_stopping != null) return _stopping!;
    final future = () async {
      try {
        await _link.command('set_ble_enabled', {'enabled': false});
        await _link.command('set_data_upload', {'enabled': false});
        final config = await _link.command('get_config');
        final safe =
            config['ble_enabled'] == false && config['upload_paused'] == true;
        if (safe) _provisioningMayBeActive = false;
        return safe;
      } catch (_) {
        return false;
      }
    }();
    _stopping = future;
    try {
      return await future;
    } finally {
      _stopping = null;
    }
  }

  Future<void> _run(
    String label,
    int timeout,
    Future<void> Function(int) action,
  ) async {
    if (state.busy) return;
    final generation = ++_generation;
    _diagnosis = null;
    state = state.copy(busy: true, message: label, seconds: timeout);
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (ref.mounted && state.seconds > 0) {
        state = state.copy(seconds: state.seconds - 1);
      }
    });
    try {
      await action(generation).timeout(
        Duration(seconds: timeout),
        onTimeout: () {
          if (generation == _generation) _generation++;
          throw const GatewayFailure('timeout');
        },
      );
      _check(generation);
      await _save();
    } catch (error) {
      if (error is GatewayFailure && error.code == 'authentication') {
        _loggedIn = false;
      }
      final safe = await _safeStop();
      final failure = error is GatewayFailure
          ? error
          : GatewayFailure.unexpected(error);
      final diagnosis = _diagnosis;
      final detailed =
          diagnosis != null &&
          diagnosis.$1 == generation &&
          (failure.code == 'timeout' || failure.code == 'incomplete');
      if (ref.mounted) {
        state = state.copy(
          error: !safe
              ? '尚未確認安全停止，請重新連線關閉監控並核對設定。'
              : detailed
              ? '資料驗證未通過：\n${diagnosis.$2}'
              : failure.message,
        );
      }
    } finally {
      _clock?.cancel();
      if (ref.mounted) {
        state = state.copy(busy: false, seconds: 0, error: state.error);
      }
    }
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _link.demo ? 'demo_progress' : 'progress',
      jsonEncode({
        'step': state.step,
        'site': site,
        'gateway': gateway,
        'peer': state.peer?.id,
        'assignments': state.ptus
            .map((p) => {'mac': p['mac'], 'id': p['device_number']})
            .toList(),
      }),
    );
  }

  Future<void> restore() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_link.demo ? 'demo_progress' : 'progress');
    if (value != null && ref.mounted) {
      Map data;
      try {
        data = jsonDecode(value) as Map;
      } catch (_) {
        return;
      }
      for (final p in (data['assignments'] as List? ?? [])) {
        if (p['mac'] is String && p['id'] is int) {
          _restoredAssignments[p['mac']] = p['id'];
        }
      }
      state = state.copy(
        config: {'site_id': data['site'], 'gateway_id': data['gateway']},
        message: '已保留先前進度，請重新連線以核對裝置現況。',
      );
    }
  }

  Future<void> prepare(String base, String password, {bool offline = false}) =>
      _run('檢查藍牙與後端連線', 30, (generation) async {
        await _link.prepare();
        _check(generation);
        _backend = describeBackend(Uri.tryParse(base.trim()));
        if (!offline) {
          await _api.login(base, password);
          _check(generation);
          _loggedIn = true;
        }
        state = state.copy(
          step: 1,
          message: offline ? '離線模式：最後仍需登入驗證資料' : '準備完成',
        );
      });
  Future<void> scan() => _run('搜尋附近的閘道器', 30, (generation) async {
    final peers = await _link.scan();
    _check(generation);
    state = state.copy(
      peers: peers,
      message: peers.isEmpty ? '未找到閘道器，請靠近並確認電源後重掃。' : '請選擇要開通的閘道器',
    );
  });
  Future<void> connect(GatewayPeer peer) =>
      _run('連線並讀取閘道器設定', 120, (generation) async {
        await _link.connect(peer);
        _check(generation);
        for (int attempt = 0; ; attempt++) {
          try {
            await _command(generation, 'ping');
            break;
          } catch (_) {
            if (attempt == 4) rethrow;
            await _wait(3, generation);
          }
        }
        final config = await _command(generation, 'get_config');
        _check(generation);
        if (config['fleet_joined'] == true) {
          final existing = await _command(generation, 'get_ble_devices');
          final devices = (existing['devices'] as List? ?? [])
              .map((d) => Map<String, dynamic>.from(d as Map))
              .toList();
          state = state.copy(
            step: 2,
            peer: peer,
            config: {...config, 'choose_station': true},
            ptus: devices,
            selected: devices.map((d) => d['mac'].toString()).toSet(),
            message: '此閘道器已有站點設定，請選擇沿用或設定新站。',
            uploadNotice: '',
          );
          return;
        }
        if (_loggedIn && config['fleet_joined'] != true) {
          final discover = await _request(
            generation,
            'GET',
            '/api/gateways/discover',
          );
          final fleet = await _request(
            generation,
            'GET',
            '/api/gateways/fleet-status',
          );
          final occupied = <String>{};
          for (final row in [
            ...(discover['items'] as List? ?? []),
            ...(fleet['gateways'] as List? ?? []),
          ]) {
            final uid = row['mac'] ?? row['last_seen_mac'];
            if (uid == null || _mac(uid) != _mac(config['gateway_uid'])) {
              occupied.add('${row['site_id']}/${row['gateway_id']}');
            }
          }
          candidate:
          for (int s = 1; s <= 65535; s++) {
            for (int g = 1; g <= 6; g++) {
              if (occupied.contains('$s/$g')) continue;
              final identity = await _request(
                generation,
                'GET',
                '/api/gateways/$s/$g/check-identity',
              );
              if (identity['exists'] != true ||
                  (identity['last_seen_mac'] != null &&
                      _mac(identity['last_seen_mac']) ==
                          _mac(config['gateway_uid']))) {
                config['suggested_site_id'] = s;
                config['suggested_gateway_id'] = g;
                break candidate;
              }
            }
          }
        }
        state = state.copy(
          step: 2,
          peer: peer,
          config: config,
          message: '已連線，請設定身份與 WiFi',
          uploadNotice: '',
        );
      });
  void chooseStation({required bool newStation, bool wifiOnly = false}) {
    if (state.busy || state.config['choose_station'] != true) return;
    state = state.copy(
      step: newStation || wifiOnly ? 2 : 6,
      config: {
        ...state.config,
        'choose_station': false,
        'new_station': newStation,
        'wifi_only': wifiOnly && !newStation,
      },
      selected: newStation ? <String>{} : state.selected,
      results: {},
      verified: false,
      report: '',
      message: newStation
          ? '請輸入新的站點 ID 與 Wi-Fi；儲存後才會變更閘道器。'
          : wifiOnly
          ? '保留目前站點與 PTU，僅更新 Wi-Fi。'
          : '沿用目前站點，檢查資料是否正常上傳。',
    );
  }

  Future<void> configureWifi(
    int newSite,
    int newGateway,
    String ssid,
    String password,
  ) => _run('設定身份與 WiFi', 150, (generation) async {
    final wifiOnly = state.config['wifi_only'] == true;
    if (wifiOnly && (newSite != site || newGateway != gateway)) {
      throw const GatewayFailure('conflict');
    }
    if (state.config['new_station'] == true && newSite == site) {
      throw const GatewayFailure('new_site_required');
    }
    if (newSite < 1 ||
        newSite > 65535 ||
        newGateway < 1 ||
        newGateway > 6 ||
        utf8.encode(ssid).isEmpty ||
        utf8.encode(ssid).length > 32 ||
        utf8.encode(password).length < 8 ||
        utf8.encode(password).length > 63) {
      throw const GatewayFailure('wifi_failed');
    }
    if (state.config['otp_enabled'] == true) {
      throw const GatewayFailure('otp_enabled');
    }
    if (_loggedIn && !wifiOnly) {
      final check = await _request(
        generation,
        'GET',
        '/api/gateways/$newSite/$newGateway/check-identity',
      );
      if (check['exists'] == true &&
          (check['last_seen_mac'] == null ||
              _mac(check['last_seen_mac']) !=
                  _mac(state.config['gateway_uid']))) {
        throw const GatewayFailure('conflict');
      }
    }
    if (newSite != site || newGateway != gateway) {
      await _command(generation, 'set_site_identity', {
        'site_id': newSite,
        'gateway_id': newGateway,
      });
      await _wait(15, generation);
      await _link.connect(state.peer!);
      await _wait(3, generation);
      await _command(generation, 'ping');
      state = state.copy(config: await _command(generation, 'get_config'));
      if (site != newSite || gateway != newGateway) {
        throw const GatewayFailure('conflict');
      }
    }
    final wifiDeadline = Stopwatch()..start();
    await _command(generation, 'set_wifi', {
      'ssid': ssid,
      'password': password,
    });
    final current =
        profileFor(state.config['fw_version']?.toString() ?? '') ==
        ProtocolProfile.current;
    if (!current) await _wait(16, generation);
    bool connected = false;
    while (wifiDeadline.elapsed < const Duration(seconds: 60)) {
      try {
        await _wait(
          3,
          generation,
        ).timeout(const Duration(seconds: 60) - wifiDeadline.elapsed);
      } on TimeoutException {
        break;
      }
      final remaining = const Duration(seconds: 60) - wifiDeadline.elapsed;
      if (remaining <= Duration.zero) break;
      Map<String, dynamic> net;
      try {
        net = await _command(
          generation,
          current ? 'get_net_status' : 'get_status',
        ).timeout(remaining);
      } on GatewayFailure catch (error) {
        if (['busy', 'not_ready', 'timeout'].contains(error.code)) continue;
        rethrow;
      } on TimeoutException {
        break;
      }
      if ((net['last_wifi_error']?.toString() ?? '').isNotEmpty) {
        throw const GatewayFailure('wifi_failed');
      }
      if (current
          ? net['wifi_state'] == 'got_ip' &&
                (net['ip']?.toString() ?? '').isNotEmpty &&
                net['ssid'] == ssid
          : net['mqtt_connected'] == true) {
        if (!current) {
          final remainingRead =
              const Duration(seconds: 60) - wifiDeadline.elapsed;
          if (remainingRead <= Duration.zero) break;
          final readback = await _command(generation, 'get_config').timeout(
            remainingRead,
            onTimeout: () => throw const GatewayFailure('wifi_failed'),
          );
          if (readback['wifi_ssid'] != ssid) {
            throw const GatewayFailure('wifi_failed');
          }
        }
        // Keep the reported upload target; MQTT is still coming up here.
        _absorbTarget({...net}..remove('mqtt_connected'));
        connected = true;
        break;
      }
    }
    if (!connected) throw const GatewayFailure('wifi_failed');
    state = state.copy(config: {...state.config, 'wifi_ssid': ssid});
    if (wifiOnly) {
      state = state.copy(step: 6, message: 'Wi-Fi 已更新，站點與 PTU 設定保留。可接著驗證資料。');
      return;
    }
    if (_loggedIn) {
      await _request(
        generation,
        'POST',
        '$_path/reserve-identity?mac=${Uri.encodeComponent(state.config['gateway_uid']?.toString() ?? '')}',
      );
    }
    state = state.copy(step: 3, message: 'WiFi 已連線，下一步確認後端看得到閘道器');
  });
  Future<Map<String, dynamic>?> _fleet(int generation) async {
    final response = await _request(
      generation,
      'GET',
      '/api/gateways/fleet-status?site_id=$site',
    );
    for (final item in (response['gateways'] as List? ?? [])) {
      final row = Map<String, dynamic>.from(item as Map);
      if (row['site_id'] == site && row['gateway_id'] == gateway) {
        return {
          ...row,
          'mqtt_connected': row['mqtt_connected'] ?? response['mqtt_connected'],
        };
      }
    }
    return null;
  }

  Future<void> online({bool skip = false}) => _run('確認閘道器持續上線', 90, (
    generation,
  ) async {
    if (skip || !_loggedIn) {
      state = state.copy(step: 4, message: '後端尚未確認；完成配置後仍需驗證');
      return;
    }
    await _command(generation, 'heartbeat_boost', {'duration': 300});
    String? previous;
    for (int elapsed = 0; elapsed < 90; elapsed += 5) {
      final row = await _fleet(generation);
      _check(generation);
      final heartbeat = row?['last_heartbeat']?.toString();
      if (row?['online'] == true &&
          row?['mqtt_connected'] == true &&
          previous != null &&
          heartbeat != null &&
          heartbeat != previous) {
        await _request(generation, 'PATCH', '$_path/bot-monitor', {
          'enabled': false,
          'ttl_minutes': 30,
        });
        _lease = true;
        state = state.copy(step: 4, online: true, message: '閘道器持續上線，可搜尋 PTU');
        return;
      }
      previous = heartbeat;
      await _wait(5, generation);
    }
    throw const GatewayFailure('timeout');
  });
  Future<void> discover() => _run('搜尋周邊與已連線 PTU', 35, (generation) async {
    final response = await _command(generation, 'scan_ble_discover', {
      'duration': 10,
    });
    _check(generation);
    final connected = await _command(generation, 'get_ble_devices');
    final ptus = mergePtuInventory(
      response['devices'] as List? ?? [],
      connected['devices'] as List? ?? [],
    );
    for (final p in ptus) {
      if (p['device_number'] == 0 &&
          _restoredAssignments.containsKey(p['mac'])) {
        p['device_number'] = _restoredAssignments[p['mac']];
      }
    }
    final selected = ptus
        .where((p) {
          final id = (p['device_number'] as num?)?.toInt() ?? 0;
          return id == 0 || (id >= (gateway - 1) * 5 + 1 && id <= gateway * 5);
        })
        .take(5)
        .map((p) => p['mac'].toString())
        .toSet();
    state = state.copy(
      ptus: ptus,
      selected: selected,
      message: ptus.isEmpty
          ? const GatewayFailure('no_devices').message
          : '選擇要監控的 PTU，最多五台',
    );
  });
  void select(String mac, bool selected) {
    if (state.busy) return;
    final next = Set<String>.of(state.selected);
    if (selected && next.length < 5) {
      next.add(mac);
    } else if (!selected) {
      next.remove(mac);
    }
    state = state.copy(selected: next);
  }

  Future<void> configurePtus() => _run('逐台編號並開始監控', 240, (generation) async {
    final chosen = state.ptus
        .where((p) => state.selected.contains(p['mac']))
        .toList();
    if (chosen.isEmpty || chosen.length > 5) {
      throw const GatewayFailure('no_devices');
    }
    _provisioningMayBeActive = true;
    final results = <String, String>{};
    final used = state.ptus
        .where((p) => !state.selected.contains(p['mac']))
        .map((p) => (p['device_number'] as num?)?.toInt() ?? 0)
        .where((id) => id > 0)
        .toSet();
    state = state.copy(step: 5);
    for (final p in chosen) {
      _check(generation);
      final old = (p['device_number'] as num?)?.toInt() ?? 0;
      final first = (gateway - 1) * 5 + 1;
      final id = old >= first && old < first + 5 && !used.contains(old)
          ? old
          : List.generate(
              5,
              (i) => first + i,
            ).firstWhere((id) => !used.contains(id));
      used.add(id);
      results[p['mac'].toString()] = '正在指派 #$id';
      state = state.copy(results: Map.of(results));
      final result = await _command(generation, 'assign_device_id', {
        'mac': p['mac'],
        'new_id': id,
      });
      if (result['success'] != true) throw const GatewayFailure('incomplete');
      p['device_number'] = id;
      results[p['mac'].toString()] = '已指派 #$id，等待連線';
      state = state.copy(results: Map.of(results));
      await _save();
    }
    await _command(generation, 'set_config', {
      'max_connections': chosen.length,
    });
    await _command(generation, 'join_fleet');
    for (int elapsed = 0; elapsed < 90; elapsed += 5) {
      await _wait(5, generation);
      final response = await _command(generation, 'get_ble_devices');
      final actual = (response['devices'] as List? ?? [])
          .map((p) => Map<String, dynamic>.from(p as Map))
          .toList();
      final connected = actual
          .where(
            (p) =>
                state.selected.contains(p['mac']) &&
                p['connected'] == true &&
                p['notify_enabled'] == true &&
                p['zombie'] != true &&
                ((p['last_data_age_sec'] as num?) ?? 999) < 30,
          )
          .toList();
      if (connected.length == chosen.length) {
        final config = await _command(generation, 'get_config');
        if (config['max_connections'] != chosen.length) {
          throw const GatewayFailure('incomplete');
        }
        await _command(generation, 'check_db_upload');
        _provisioningMayBeActive = false;
        state = state.copy(
          step: 6,
          config: config,
          ptus: connected,
          results: {
            for (final p in connected)
              p['mac'].toString(): '已連線 #${p['device_number']}',
          },
          message: '配置完成，請驗證後端資料',
        );
        return;
      }
      if (elapsed >= 85) {
        // Never leave a target above actual connections after a failed installation.
        if (connected.isEmpty) {
          await _command(generation, 'set_ble_enabled', {'enabled': false});
          await _command(generation, 'set_data_upload', {'enabled': false});
        } else {
          await _command(generation, 'set_config', {
            'max_connections': connected.length,
          });
          final readback = await _command(generation, 'get_config');
          if (readback['max_connections'] != connected.length) {
            throw const GatewayFailure('incomplete');
          }
          _provisioningMayBeActive = false;
        }
        state = state.copy(
          step: 4,
          ptus: actual,
          missing: chosen
              .where((p) => !connected.any((c) => c['mac'] == p['mac']))
              .map((p) => p['mac'].toString())
              .toList(),
          message: connected.isEmpty
              ? '未連上任何 PTU，已停止監控以避免反覆重啟。'
              : '已調整為 ${connected.length} 台；請重新選擇已連線裝置或修復缺少的 PTU。',
        );
        throw const GatewayFailure('incomplete');
      }
    }
  });

  /// [environment] is the selector value (`production` / `local` / `custom`);
  /// when omitted the target is derived from [base] alone.
  Future<void> verify(
    String base,
    String password, {
    String? environment,
  }) => _run('確認每台 PTU 的資料持續進入後端', 180, (generation) async {
    _backend = describeBackend(Uri.tryParse(base.trim()));
    // Fail fast when the gateway is known to upload elsewhere: the data can
    // never reach this backend, so waiting the full window only hides why.
    final wanted = desiredUploadTarget(environment ?? 'custom', base).target;
    final running = parseMqttTarget(state.config);
    if (wanted != null && running != null && !running.sameAs(wanted)) {
      throw GatewayFailure.targetMismatch(
        gatewayTarget: running.label,
        appTarget: wanted.label,
      );
    }
    if (!_loggedIn) {
      await _api.login(base, password);
      _check(generation);
      _loggedIn = true;
    }
    {
      // Renew the lease for every verification attempt; a cached flag may have expired.
      await _request(generation, 'PATCH', '$_path/bot-monitor', {
        'enabled': false,
        'ttl_minutes': 30,
      });
      _lease = true;
    }
    int consecutive = 0;
    final previous = <int, DateTime>{};
    final chosen = state.ptus
        .where((p) => state.selected.contains(p['mac']))
        .toList();
    final ids = chosen
        .map((p) => (p['device_number'] as num?)?.toInt() ?? 0)
        .toSet();
    if (ids.isEmpty) throw const GatewayFailure('no_devices');
    final unnumbered = chosen
        .where((p) => ((p['device_number'] as num?)?.toInt() ?? 0) == 0)
        .map((p) => 'PTU ${p['mac']}：PTU 未取得裝置編號（device_number=0）')
        .toList();
    if (unnumbered.isNotEmpty) {
      // A PTU without a number can never pass; report it instead of waiting.
      _diagnosis = (generation, unnumbered.join('\n'));
      throw const GatewayFailure('incomplete');
    }
    for (int elapsed = 0; elapsed < 180; elapsed += 10) {
      final fleet = await _fleet(generation);
      if (fleet?['upload_paused'] == true) {
        await _command(generation, 'set_data_upload', {'enabled': true});
      }
      final install = await _request(
        generation,
        'GET',
        '$_path/verify-installation?threshold_minutes=2&device_ids=${ids.join(',')}',
      );
      final latest = await _request(
        generation,
        'GET',
        '/api/latest?site_id=$site&gateway_id=$gateway',
      );
      _check(generation);
      final rows = (latest['items'] as List? ?? [])
          .map((p) => Map<String, dynamic>.from(p as Map))
          .toList();
      final before = Map<int, DateTime>.of(previous);
      bool good = install['all_ok'] == true;
      for (final id in ids) {
        final found = rows.where((p) => p['device_id'] == id).toList();
        if (found.isEmpty) {
          good = false;
          continue;
        }
        final row = found.first;
        final stamp = DateTime.tryParse(row['ts']?.toString() ?? '');
        if (row['online'] != true ||
            ((row['lag_seconds'] as num?) ?? 999) >= 60 ||
            row['error_num'] != 0 ||
            stamp == null ||
            (previous[id] != null && !stamp.isAfter(previous[id]!))) {
          good = false;
        }
        if (stamp != null) previous[id] = stamp;
      }
      consecutive = good ? consecutive + 1 : 0;
      _diagnosis = (
        generation,
        verifyDiagnosis(
          ids: ids,
          install: install,
          rows: rows,
          fleet: fleet,
          previous: before,
          site: site,
          gateway: gateway,
          consecutive: consecutive,
          backend: _backend,
        ),
      );
      state = state.copy(message: '連續資料驗證 $consecutive / 3');
      if (consecutive >= 3) {
        await _request(generation, 'PATCH', '$_path/bot-monitor', {
          'enabled': true,
        });
        _lease = false;
        final report =
            '${_link.demo ? "模擬安裝報告（非實機驗證）" : "安裝報告"}\n站點 $site / 閘道器 $gateway\n${state.ptus.map((p) => "#${p['device_number']}  ${p['mac']}").join('\n')}\n驗證時間：${DateTime.now().toIso8601String()}\n每台連續三次資料更新通過';
        state = state.copy(
          step: 7,
          verified: true,
          online: true,
          report: report,
          message: '開通驗證通過，已恢復自動監控',
        );
        _health?.cancel();
        _health = Timer.periodic(
          const Duration(seconds: 15),
          (_) => unawaited(refreshHealth()),
        );
        return;
      }
      await _wait(10, generation);
    }
    throw const GatewayFailure('incomplete');
  });
  // ---- Gateway upload target (firmware 1.7.3, docs/mqtt_target.md) ----

  static const _reconnectBudget = Duration(seconds: 45);

  /// Copies mqtt_target / mqtt_host / mqtt_port (and mqtt_connected) from a
  /// get_net_status or get_config result into the gateway config.
  void _absorbTarget(Map<String, dynamic> source) {
    final update = {
      for (final key in mqttStatusKeys)
        if (source.containsKey(key)) key: source[key],
    };
    if (update.isEmpty) return;
    state = state.copy(config: {...state.config, ...update});
  }

  /// Runs a gateway-side task that must not replace the step's guidance text.
  Future<void> _sideTask(
    String label,
    int timeout,
    Future<void> Function(int) action,
  ) {
    final resume = state.message;
    return _run(label, timeout, (generation) async {
      await action(generation);
      state = state.copy(message: resume);
    });
  }

  String _mqttText(MqttTarget target) =>
      switch (state.config['mqtt_connected']) {
        true => 'MQTT 已連線。',
        false when target.isLocal =>
          'MQTT 尚未連線：請確認電腦防火牆已開放 TCP 8883、本地 MQTT broker 已啟動，'
              '且 broker 憑證包含 ${target.host}。可稍後按「重新讀取」確認。',
        false => 'MQTT 尚未連線：請確認現場網路可連到正式站。可稍後按「重新讀取」確認。',
        _ => 'MQTT 連線狀態尚未確認，可稍後按「重新讀取」。',
      };

  /// Re-reads the running upload target and MQTT state.
  Future<void> refreshUploadTarget() =>
      _sideTask('讀取 Gateway 上傳目標', 20, (generation) async {
        final net = await _command(generation, 'get_net_status');
        _absorbTarget(net);
        final target = parseMqttTarget(state.config);
        state = state.copy(
          uploadNotice: target == null ? '' : '已重新讀取。${_mqttText(target)}',
        );
      });

  /// Sends `set_mqtt_target`; on a change the gateway reboots, so reconnect to
  /// the same gateway and confirm the running target by reading it back.
  Future<void> switchUploadTarget(
    MqttTarget wanted,
  ) => _sideTask('切換 Gateway 上傳目標', 120, (generation) async {
    final peer = state.peer;
    if (peer == null) throw const GatewayFailure('disconnected');
    if (!reportsMqttTarget(state.config)) {
      throw GatewayFailure(
        'target_unsupported',
        detail: state.config['fw_version']?.toString(),
      );
    }
    SetTargetAck? ack;
    try {
      ack = parseSetTargetAck(
        await _command(generation, 'set_mqtt_target', wanted.params),
      );
    } on GatewayFailure catch (error) {
      if (error.fromGateway) throw GatewayFailure.uploadTarget(error.code);
      // ACK lost: the gateway may already be rebooting. Reconnect and
      // read back instead of guessing.
      if (error.code != 'disconnected' && error.code != 'timeout') rethrow;
    }
    if (ack != null && !ack.changed) {
      _absorbTarget(await _command(generation, 'get_net_status'));
      final now = parseMqttTarget(state.config) ?? ack.target;
      if (!now.sameAs(wanted)) {
        throw GatewayFailure.targetReadback(
          actual: now.label,
          wanted: wanted.label,
        );
      }
      state = state.copy(
        uploadNotice: '上傳目標未變更：Gateway 已是${now.label}，未重新開機。${_mqttText(now)}',
      );
      return;
    }
    // Changed (or outcome unknown): the old MQTT state no longer applies.
    state = state.copy(
      config: {...state.config}..remove('mqtt_connected'),
      uploadNotice: '',
    );
    await _reconnectAfterReboot(generation, peer, ack?.rebootInMs ?? 1500);
    final confirmed = await _readBackTarget(generation, wanted);
    state = state.copy(
      uploadNotice:
          '已切換到${confirmed.label}，Gateway 已重新開機並重新連線。${_mqttText(confirmed)}',
    );
  });

  Future<void> _reconnectAfterReboot(
    int generation,
    GatewayPeer peer,
    int rebootMs,
  ) async {
    await _link.disconnect();
    _check(generation);
    // The firmware restarts rebootMs after the ACK; advertising resumes a
    // couple of seconds later.
    await _wait(((rebootMs + 2500) / 1000).ceil(), generation);
    final deadline = Stopwatch()..start();
    for (int attempt = 0; ; attempt++) {
      try {
        final remaining = _reconnectBudget - deadline.elapsed;
        await _link
            .connect(peer)
            .timeout(
              remaining > const Duration(seconds: 5)
                  ? remaining
                  : const Duration(seconds: 5),
            );
        _check(generation);
        await _command(generation, 'ping');
        return;
      } on TimeoutException {
        await _link.disconnect();
      } catch (_) {
        // Retried below; cancellation is detected by _check.
      }
      _check(generation);
      if (attempt >= 14 || deadline.elapsed >= _reconnectBudget) {
        throw const GatewayFailure('target_reconnect');
      }
      await _wait(3, generation);
    }
  }

  /// Reads the running target after a reboot. get_net_status is refused with
  /// not_ready until boot finishes; get_config already reports the target, so
  /// it is used meanwhile. Polls briefly for mqtt_connected.
  Future<MqttTarget> _readBackTarget(int generation, MqttTarget wanted) async {
    const transient = ['not_ready', 'busy', 'timeout'];
    MqttTarget? seen;
    for (int attempt = 0; attempt < 10; attempt++) {
      if (attempt > 0) await _wait(3, generation);
      Map<String, dynamic> status;
      try {
        status = await _command(generation, 'get_net_status');
      } on GatewayFailure catch (error) {
        if (!transient.contains(error.code)) rethrow;
        try {
          status = await _command(generation, 'get_config');
        } on GatewayFailure catch (error) {
          if (!transient.contains(error.code)) rethrow;
          continue;
        }
      }
      _absorbTarget(status);
      final target = parseMqttTarget(status);
      if (target == null || !target.sameAs(wanted)) {
        throw GatewayFailure.targetReadback(
          actual: target?.label ?? '（未回報）',
          wanted: wanted.label,
        );
      }
      seen = target;
      if (status['mqtt_connected'] == true) break;
    }
    if (seen == null) {
      throw GatewayFailure.targetReadback(
        actual: '（無法讀取）',
        wanted: wanted.label,
      );
    }
    return seen;
  }

  void setForeground(bool value) => _foreground = value;
  Future<void> refreshHealth() async {
    if (!_foreground || _healthBusy || state.busy || !_loggedIn) return;
    _healthBusy = true;
    try {
      final latest = await _api.request(
        'GET',
        '/api/latest?site_id=$site&gateway_id=$gateway',
      );
      final rows = (latest['items'] as List? ?? []).cast<Map>();
      final expected = state.ptus.map((p) => p['device_number']).toSet();
      final complete =
          expected.isNotEmpty &&
          expected.every((id) => rows.any((r) => r['device_id'] == id));
      final fresh =
          complete &&
          rows.every((r) => ((r['lag_seconds'] as num?) ?? 999) < 30);
      final abnormal =
          !complete ||
          rows.any(
            (r) =>
                r['online'] != true ||
                ((r['error_num'] as num?) ?? 0) > 0 ||
                ((r['lag_seconds'] as num?) ?? 999) > 300,
          );
      if (ref.mounted) {
        state = state.copy(
          online: fresh,
          message: abnormal
              ? '資料有異常，請檢查 PTU 與網路。'
              : fresh
              ? '資料持續更新'
              : '資料暫未更新',
        );
      }
    } catch (_) {
      if (ref.mounted) {
        state = state.copy(online: false, message: '無法確認最新資料，請檢查網路');
      }
    } finally {
      _healthBusy = false;
    }
  }

  Future<void> repair() => _run('重新連接閘道器', 60, (generation) async {
    await _request(generation, 'POST', '$_path/commands', {
      'op': 'reconnect_ble',
      'params': {'target_mac': state.config['gateway_uid']},
      'ttl': 30,
    });
    state = state.copy(step: 3, verified: false, message: '已要求重新連線，請重新確認上線與資料');
  });
  Future<void> cancel() async {
    _generation++;
    _health?.cancel();
    final safe = await _safeStop();
    await _link.disconnect();
    if (_lease) {
      try {
        await _api.request('PATCH', '$_path/bot-monitor', {'enabled': true});
        _lease = false;
      } catch (_) {}
    }
    if (ref.mounted) {
      state = state.copy(
        step: 1,
        error: safe ? null : '尚未確認安全停止，請重新連線核對。',
        message: '已取消。請重新連線核對進度；未成功恢復的監控會話最晚於到期時恢復。',
      );
    }
  }
}
