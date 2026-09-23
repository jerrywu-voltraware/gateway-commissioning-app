import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/gateway_net.dart';
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

/// Background polling of the gateway's upload (MQTT) state.
enum UploadWatch {
  /// Not polling (nothing pending, or no gateway connected).
  idle,

  /// Polling get_net_status until the gateway reports it is uploading.
  polling,

  /// Stopped after the time cap without the gateway connecting.
  gaveUp,

  /// Stopped because the BLE link to the gateway dropped.
  linkLost,
}

/// How often and how long the upload state is polled; injectable in tests.
class UploadWatchTiming {
  const UploadWatchTiming({
    this.interval = const Duration(seconds: 5),
    this.cap = const Duration(minutes: 2),
    this.slowAfter = const Duration(seconds: 30),
    this.confirmAfter = const Duration(seconds: 60),
    this.wifiGrace = const Duration(seconds: 20),
  });

  /// [slowAfter]: polling time without upload after which a guess about the
  /// cause (e.g. another subnet) may be shown.
  ///
  /// [confirmAfter]: the network check stops waiting for the upload and
  /// shows what to check instead.
  ///
  /// [wifiGrace]: after a connect or reboot, a gateway that has not joined
  /// its Wi-Fi yet is shown as 「正在連 Wi-Fi」 this long before it counts as
  /// a failure (unless it has been up for [wifiSettleSeconds]).
  final Duration interval, cap, slowAfter, confirmAfter, wifiGrace;
  int get maxTicks => (cap.inMilliseconds / interval.inMilliseconds).ceil();
  int get slowTicks =>
      (slowAfter.inMilliseconds / interval.inMilliseconds).ceil();
  int get lateTicks =>
      (confirmAfter.inMilliseconds / interval.inMilliseconds).ceil();
}

final uploadWatchTimingProvider = Provider<UploadWatchTiming>(
  (ref) => const UploadWatchTiming(),
);

/// Gateway network fields copied from get_net_status (firmware cmd_handler.c).
const gatewayNetKeys = ['wifi_state', 'ip', 'ssid', 'rssi', 'uptime_sec'];

/// 「沿用目前站點」 refused because the gateway cannot upload yet.
const reuseBlockedText =
    '「沿用目前站點」會直接驗證資料，但 Gateway 還沒連上 Wi-Fi 或還沒開始上傳資料。'
    '請先用「保留站點，重設 Wi-Fi」，或回到網路體檢確認。';

/// Station kept after a Wi-Fi change: the upload must work before step 6.
const uploadNotReadyText =
    '要等 Gateway 連上 Wi-Fi 並開始上傳資料，才能驗證資料。'
    '請等「確認資料上傳」出現 ✓，或再重設一次 Wi-Fi。';

/// Step 7 after a backend switch: the earlier result belongs to the old one.
const backendSwitchedDoneText = '已切換連線環境，資料要在新的環境重新確認。';

/// Step 6 after a backend switch.
const backendSwitchedVerifyText = '已切換連線環境，請按「開始資料驗證」重新確認。';

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
    this.loggedIn = false,
    this.net = const {},
    this.uploadWatch = UploadWatch.idle,
    this.uploadSlow = false,
    this.uploadLate = false,
    this.checkPassed = false,
    this.wifiGraceOver = false,
    this.offline = false,
  });
  final int step, seconds;
  final bool busy, verified, online;
  final String message, report;

  /// Logged in to the backend currently selected (reset on a switch).
  final bool loggedIn;

  /// Gateway network status (wifi_state / ip / ssid / rssi / uptime_sec)
  /// last read.
  final Map<String, dynamic> net;
  final UploadWatch uploadWatch;

  /// Still polling after [UploadWatchTiming.slowAfter] without upload.
  final bool uploadSlow;

  /// Polled for [UploadWatchTiming.confirmAfter] without upload.
  final bool uploadLate;

  /// Step 2: the network check (網路體檢 → 對準上傳目標 → 確認資料上傳)
  /// shown right after connecting has been passed or skipped, so the station
  /// choice or the identity/Wi-Fi form is shown. False again after a Wi-Fi
  /// change that keeps the station, whose upload is confirmed before step 6.
  final bool checkPassed;

  /// The Wi-Fi grace period after a connect or reboot is over.
  final bool wifiGraceOver;

  /// Started with 「先離線配置，稍後驗證資料」 (no backend login).
  final bool offline;

  /// Gateway Wi-Fi as the network check judges it.
  WifiVerdict get wifi => wifiVerdictOf(
    net,
    configSsid: config['wifi_ssid'],
    settled:
        wifiGraceOver ||
        uploadWatch == UploadWatch.gaveUp ||
        uploadWatch == UploadWatch.linkLost,
  );

  /// The firmware answers get_net_status (1.7+); older ones cannot be checked.
  bool get netCheckSupported =>
      profileFor(config['fw_version']?.toString() ?? '') ==
      ProtocolProfile.current;

  /// The gateway has Wi-Fi and uploads, so its data can be verified now
  /// (「沿用目前站點」, or the station kept after a Wi-Fi change). Always true
  /// for firmware that cannot report it: the data verification decides.
  bool get networkReady =>
      !netCheckSupported ||
      (wifi == WifiVerdict.ok && config['mqtt_connected'] == true);

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
    bool? loggedIn,
    Map<String, dynamic>? net,
    UploadWatch? uploadWatch,
    bool? uploadSlow,
    bool? uploadLate,
    bool? checkPassed,
    bool? wifiGraceOver,
    bool? offline,
  }) => CommissionState(
    loggedIn: loggedIn ?? this.loggedIn,
    net: net ?? this.net,
    uploadWatch: uploadWatch ?? this.uploadWatch,
    uploadSlow: uploadSlow ?? this.uploadSlow,
    uploadLate: uploadLate ?? this.uploadLate,
    checkPassed: checkPassed ?? this.checkPassed,
    wifiGraceOver: wifiGraceOver ?? this.wifiGraceOver,
    offline: offline ?? this.offline,
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
  late UploadWatchTiming _timing;
  Timer? _poll, _grace;
  int _pollTicks = 0;
  bool _pollInFlight = false;

  /// Base URL of the backend the login (if any) belongs to.
  String? _loginBase;

  @override
  CommissionState build() {
    _link = ref.watch(linkProvider);
    _api = ref.watch(apiProvider);
    _timing = ref.read(uploadWatchTimingProvider);
    ref.onDispose(() {
      _generation++;
      _clock?.cancel();
      _health?.cancel();
      _poll?.cancel();
      _grace?.cancel();
      unawaited(_link.disconnect());
    });
    return const CommissionState();
  }

  /// Starts the Wi-Fi grace period: right after a connect or a reboot the
  /// gateway may still be joining its Wi-Fi.
  void _startWifiGrace() {
    _grace?.cancel();
    if (!ref.mounted) return;
    if (state.wifiGraceOver) {
      state = state.copy(wifiGraceOver: false, error: state.error);
    }
    _grace = Timer(_timing.wifiGrace, () {
      if (ref.mounted) {
        state = state.copy(wifiGraceOver: true, error: state.error);
      }
    });
  }

  void _setLoggedIn(bool value, [String? base]) {
    _loggedIn = value;
    if (value) _loginBase = base?.trim();
    if (ref.mounted && state.loggedIn != value) {
      state = state.copy(loggedIn: value, error: state.error);
    }
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
    // Only the verify loop's own end or this overall timeout may be explained
    // by the data diagnosis; a BLE/HTTP command timeout keeps its own text.
    bool timedOut = false;
    try {
      await action(generation).timeout(
        Duration(seconds: timeout),
        onTimeout: () {
          if (generation == _generation) _generation++;
          timedOut = true;
          throw const GatewayFailure('timeout');
        },
      );
      _check(generation);
      await _save();
    } catch (error) {
      if (error is GatewayFailure && error.code == 'authentication') {
        _setLoggedIn(false);
      }
      final safe = await _safeStop();
      final failure = error is GatewayFailure
          ? error
          : GatewayFailure.unexpected(error);
      final diagnosis = _diagnosis;
      final detailed =
          diagnosis != null &&
          diagnosis.$1 == generation &&
          ((failure.code == 'timeout' && timedOut) ||
              failure.code == 'incomplete');
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
          _setLoggedIn(true, base);
        }
        state = state.copy(
          step: 1,
          offline: offline,
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
  Future<void> connect(GatewayPeer peer) async {
    if (state.busy) return;
    _stopWatch(UploadWatch.idle);
    state = state.copy(
      net: const {},
      checkPassed: false,
      uploadLate: false,
      error: state.error,
    );
    await _connect(peer);
    if (ref.mounted &&
        state.step == 2 &&
        state.error == null &&
        identical(state.peer, peer)) {
      _startWifiGrace();
    }
    _watchUploadIfPending();
  }

  /// get_net_status for the network check; null when the firmware cannot
  /// answer it (before 1.7) or is not ready yet (polling reads it later).
  Future<Map<String, dynamic>?> _readNet(
    int generation,
    Map<String, dynamic> config,
  ) async {
    if (profileFor(config['fw_version']?.toString() ?? '') !=
        ProtocolProfile.current) {
      return null;
    }
    try {
      return await _command(generation, 'get_net_status');
    } catch (_) {
      _check(generation);
      return null;
    }
  }

  /// get_config plus what get_net_status says about the upload (MQTT).
  static Map<String, dynamic> _withUpload(
    Map<String, dynamic> config,
    Map<String, dynamic>? net,
  ) => {
    ...config,
    if (net != null)
      for (final key in mqttStatusKeys)
        if (net.containsKey(key)) key: net[key],
  };

  static Map<String, dynamic> _netFields(Map<String, dynamic>? net) => {
    if (net != null)
      for (final key in gatewayNetKeys)
        if (net.containsKey(key)) key: net[key],
  };

  Future<void> _connect(GatewayPeer peer) =>
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
        // 網路體檢: the gateway's own Wi-Fi and upload state.
        final net = await _readNet(generation, config);
        if (config['fleet_joined'] == true) {
          final existing = await _command(generation, 'get_ble_devices');
          final devices = (existing['devices'] as List? ?? [])
              .map((d) => Map<String, dynamic>.from(d as Map))
              .toList();
          state = state.copy(
            step: 2,
            peer: peer,
            config: {..._withUpload(config, net), 'choose_station': true},
            net: _netFields(net),
            checkPassed: false,
            ptus: devices,
            selected: devices.map((d) => d['mac'].toString()).toSet(),
            message: '已連線，此閘道器已有站點設定。先做網路體檢，再選擇沿用或設定新站。',
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
          config: _withUpload(config, net),
          net: _netFields(net),
          checkPassed: false,
          message: '已連線。先做網路體檢，再設定身份與 Wi-Fi。',
          uploadNotice: '',
        );
      });

  // ---- 網路體檢 (step 2 before the station choice) ----

  bool get _atCheck => !state.busy && state.step == 2 && !state.checkPassed;

  /// Leaves the network check: to the station choice, the identity/Wi-Fi
  /// form (new gateway), or, after a Wi-Fi change that keeps the station, to
  /// the data verification. [skip] continues although the check has not
  /// passed; that is never allowed when the next page verifies data.
  void passNetworkCheck({bool skip = false}) {
    if (!_atCheck) return;
    if (state.config['wifi_only'] == true) {
      if (!state.networkReady) {
        state = state.copy(error: uploadNotReadyText);
        return;
      }
      state = state.copy(
        step: 6,
        checkPassed: true,
        results: {},
        verified: false,
        report: '',
        message: 'Wi-Fi 已更新，資料也開始上傳了，站點與 PTU 設定保留。可接著驗證資料。',
      );
      return;
    }
    final station = state.config['choose_station'] == true;
    final String message;
    if (station) {
      message = skip ? '網路體檢未通過：可重設 Wi-Fi 或設定新站點；沿用要等網路正常。' : '網路體檢通過，請選擇站點。';
    } else {
      message = skip ? '網路體檢未通過，仍可設定新站點；之後會再確認資料上傳。' : '網路體檢通過，請設定身份與 Wi-Fi。';
    }
    state = state.copy(checkPassed: true, message: message);
  }

  /// 「重設 Wi-Fi」 from the network check. A station that is set up keeps
  /// its site / gateway numbers and PTUs (Wi-Fi only); a new gateway gets the
  /// identity + Wi-Fi form.
  ///
  /// [target]: the upload target must change too. It is sent FIRST, without
  /// waiting for the upload: set_mqtt_target always reboots, and the boot
  /// reads the Wi-Fi from NVS, while set_wifi reconnects in place without a
  /// reboot. So target-then-Wi-Fi costs one reboot and the gateway starts
  /// uploading to the right place as soon as the new Wi-Fi works; the other
  /// order would also reboot once but first upload to the old place.
  Future<void> startWifiFix({MqttTarget? target}) async {
    if (!_atCheck) return;
    if (target != null) {
      await switchUploadTarget(target, waitUpload: false);
      // Reconnect or read-back failed: stay on the check with its message.
      if (!ref.mounted || state.error != null || state.step != 2) return;
    }
    if (!_atCheck) return;
    final station = state.config['fleet_joined'] == true;
    state = state.copy(
      checkPassed: true,
      config: {
        ...state.config,
        'choose_station': false,
        'new_station': false,
        'wifi_only': station,
      },
      results: {},
      verified: false,
      report: '',
      message: station
          ? '保留目前站點與 PTU，只重設 Wi-Fi。請選 2.4 GHz 的 Wi-Fi。'
          : '請設定身份與 Wi-Fi（Gateway 只能用 2.4 GHz）。',
    );
  }

  /// Back to the network check from the station choice or a Wi-Fi form.
  /// A station gets its PTU selection back (only a new station clears it).
  void backToNetworkCheck() {
    if (state.busy || state.step != 2 || !state.checkPassed) return;
    final station = state.config['fleet_joined'] == true;
    state = state.copy(
      checkPassed: false,
      config: {
        ...state.config,
        'choose_station': station,
        'new_station': false,
        'wifi_only': false,
      },
      selected: station
          ? state.ptus.map((d) => d['mac'].toString()).toSet()
          : null,
      message: '網路體檢：確認 Gateway 的 Wi-Fi 與資料上傳。',
    );
    _watchUploadIfPending();
  }

  /// From the upload re-check after a Wi-Fi change back to the station choice.
  void backToStationChoice() {
    if (!_atCheck || state.config['fleet_joined'] != true) return;
    state = state.copy(
      checkPassed: true,
      config: {
        ...state.config,
        'choose_station': true,
        'new_station': false,
        'wifi_only': false,
      },
      message: '請選擇站點。沿用要等 Gateway 開始上傳資料。',
    );
  }

  void chooseStation({required bool newStation, bool wifiOnly = false}) {
    if (state.busy || state.config['choose_station'] != true) return;
    // 沿用 goes straight to the data verification, which cannot pass while
    // the gateway has no Wi-Fi or no upload.
    if (!newStation && !wifiOnly && !state.networkReady) {
      state = state.copy(error: reuseBlockedText);
      return;
    }
    state = state.copy(
      step: newStation || wifiOnly ? 2 : 6,
      checkPassed: true,
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
  ) async {
    await _configureWifi(newSite, newGateway, ssid, password);
    _watchUploadIfPending();
  }

  Future<void> _configureWifi(
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
    // Once sent, even a lost ACK may mean the network has changed. Do not
    // retain a successful check from the previous Wi-Fi while reading back.
    state = state.copy(
      config: {...state.config}..remove('mqtt_connected'),
      net: const {},
      uploadLate: false,
    );
    _startWifiGrace();
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
      _absorbTarget(net);
      if (current) _absorbNet(net);
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
        if (current) _absorbNet(net);
        connected = true;
        break;
      }
    }
    if (!connected) throw const GatewayFailure('wifi_failed');
    // The MQTT client reconnects over the new Wi-Fi: an earlier
    // mqtt_connected no longer applies until it is read again.
    state = state.copy(
      config: {...state.config, 'wifi_ssid': ssid}..remove('mqtt_connected'),
      uploadLate: false,
    );
    if (wifiOnly) {
      // The station is kept and the next page verifies data, so the upload
      // is confirmed first (網路體檢 → 確認資料上傳).
      state = state.copy(
        checkPassed: false,
        message: 'Wi-Fi 已更新，站點與 PTU 設定保留。接著確認資料有上傳。',
      );
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

  /// [base] / [environment] are the APP backend URL and selector value; when
  /// given, a known upload-target mismatch fails fast instead of waiting 90 s.
  ///
  /// [password] logs in again when the backend was switched since the last
  /// login (or the flow started offline); empty keeps the old skip behaviour.
  Future<void> online({
    bool skip = false,
    String? base,
    String? environment,
    String? password,
  }) => _run('確認閘道器持續上線', 90, (generation) async {
    if (!skip && !_loggedIn && base != null && (password ?? '').isNotEmpty) {
      _backend = describeBackend(Uri.tryParse(base.trim()));
      await _api.login(base.trim(), password!);
      _check(generation);
      _setLoggedIn(true, base);
    }
    if (skip || !_loggedIn) {
      state = state.copy(step: 4, message: '後端尚未確認；完成配置後仍需驗證');
      return;
    }
    if (base != null) _checkUploadTarget(base, environment);
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
        state = state.copy(
          step: 4,
          online: true,
          message: '閘道器持續上線，可搜尋 PTU',
          // Heartbeats reached this backend, so the gateway is uploading.
          config: reportsMqttTarget(state.config)
              ? {...state.config, 'mqtt_connected': true}
              : null,
        );
        _stopWatch(UploadWatch.idle);
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
    final wanted = _checkUploadTarget(base, environment);
    final running = parseMqttTarget(state.config);
    // Why a gateway can be missing from this backend, from what the APP knows.
    final cause = missingGatewayCause(
      running: running,
      wanted: wanted,
      mqttConnected: state.config['mqtt_connected'],
    );
    if (!_loggedIn) {
      await _api.login(base, password);
      _check(generation);
      _setLoggedIn(true, base);
    }
    try {
      // Renew the lease for every verification attempt; a cached flag may have expired.
      await _request(generation, 'PATCH', '$_path/bot-monitor', {
        'enabled': false,
        'ttl_minutes': 30,
      });
      _lease = true;
    } on GatewayFailure catch (error) {
      if (error.gatewayNotFound) throw error.withCause(cause);
      rethrow;
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
          cause: cause,
        ),
      );
      state = state.copy(message: '連續資料驗證 $consecutive / 3');
      if (consecutive >= 3) {
        await _request(generation, 'PATCH', '$_path/bot-monitor', {
          'enabled': true,
        });
        _lease = false;
        _reportBody =
            '${_link.demo ? "模擬安裝報告（非實機驗證）" : "安裝報告"}\n站點 $site / 閘道器 $gateway\n${state.ptus.map((p) => "#${p['device_number']}  ${p['mac']}").join('\n')}\n驗證時間：${DateTime.now().toIso8601String()}\n驗證後端：$_backend\n每台連續三次資料更新通過';
        state = state.copy(
          step: 7,
          verified: true,
          online: true,
          report: _report(),
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
    state = state.copy(
      config: {...state.config, ...update},
      error: state.error,
    );
  }

  /// Fails fast when the gateway is known to upload elsewhere than the APP
  /// backend ([base] / [environment]): the data can never arrive, so waiting
  /// the full window only hides why. Returns the wanted target (null = unknown).
  MqttTarget? _checkUploadTarget(String base, String? environment) {
    final wanted = desiredUploadTarget(environment ?? 'custom', base).target;
    final running = parseMqttTarget(state.config);
    if (wanted != null && running != null && !running.sameAs(wanted)) {
      throw GatewayFailure.targetMismatch(
        gatewayTarget: running.plainLabel,
        appTarget: wanted.plainLabel,
      );
    }
    return wanted;
  }

  /// The APP backend was switched to [base]. A login belongs to the old
  /// backend, so every later backend call logs in again first. A monitoring
  /// lease on the old backend is not handed back here (a fire-and-forget
  /// request could race a new login's key); it expires by its TTL or is
  /// returned by 「結束並重新選擇閘道器」. The running step is not touched.
  ///
  /// On step 6/7 the shown result (verification error, 「開通驗證通過」,
  /// data health) came from the old backend, so it is cleared.
  void backendChanged(String base) {
    final next = base.trim();
    if (_loginBase == next && _loggedIn) return;
    if (!state.busy) _backend = describeBackend(Uri.tryParse(next));
    _setLoggedIn(false);
    if (!ref.mounted || state.busy) return;
    if (state.step == 7) {
      state = state.copy(online: false, message: backendSwitchedDoneText);
    } else if (state.step == 6) {
      state = state.copy(message: backendSwitchedVerifyText);
    }
  }

  /// Logs in to [base] outside a step (after switching environments).
  Future<void> login(String base, String password) =>
      _sideTask('登入後端', 30, (generation) async {
        await _api.login(base.trim(), password);
        _check(generation);
        _backend = describeBackend(Uri.tryParse(base.trim()));
        _setLoggedIn(true, base);
      });

  // ---- Background upload-state polling ----

  bool get _canWatch =>
      ref.mounted &&
      state.peer != null &&
      state.step >= 2 &&
      state.netCheckSupported;

  /// Starts (or restarts) polling when the gateway's upload is not yet
  /// confirmed; called after a connect, Wi-Fi change, switch or refresh.
  void _watchUploadIfPending() {
    if (!_canWatch || state.networkReady) {
      if (ref.mounted && state.uploadWatch == UploadWatch.polling) {
        _stopWatch(UploadWatch.idle);
      }
      return;
    }
    _poll?.cancel();
    _pollTicks = 0;
    state = state.copy(
      uploadWatch: UploadWatch.polling,
      uploadSlow: false,
      uploadLate: false,
      error: state.error,
    );
    _poll = Timer.periodic(_timing.interval, (_) => unawaited(_pollTick()));
    Timer.run(() => unawaited(_pollTick(count: false)));
  }

  void _stopWatch(UploadWatch reason) {
    _poll?.cancel();
    _poll = null;
    final clearLate = reason == UploadWatch.idle && state.uploadLate;
    if (ref.mounted &&
        (state.uploadWatch != reason || state.uploadSlow || clearLate)) {
      state = state.copy(
        uploadWatch: reason,
        uploadSlow: false,
        uploadLate: clearLate ? false : null,
        error: state.error,
      );
    }
  }

  /// One poll: only while no step or command runs on the BLE link.
  Future<void> _pollTick({bool count = true}) async {
    if (!ref.mounted || _poll == null) return;
    if (!_canWatch) return _stopWatch(UploadWatch.idle);
    if (state.networkReady) {
      return _stopWatch(UploadWatch.idle);
    }
    // Time spent under a running step (or in the background) does not count.
    if (state.busy || _pollInFlight || !_foreground) return;
    if (count) _pollTicks++;
    if (_pollTicks > _timing.maxTicks) return _stopWatch(UploadWatch.gaveUp);
    if (!state.uploadSlow && _pollTicks >= _timing.slowTicks) {
      state = state.copy(uploadSlow: true, error: state.error);
    }
    if (!state.uploadLate && _pollTicks >= _timing.lateTicks) {
      state = state.copy(uploadLate: true, error: state.error);
    }
    _pollInFlight = true;
    final generation = _generation;
    try {
      final net = await _link.command('get_net_status');
      if (generation != _generation || !ref.mounted || state.busy) return;
      if (_poll == null) return;
      _absorbTarget(net);
      _absorbNet(net);
      if (state.networkReady) {
        _stopWatch(UploadWatch.idle);
      }
    } on GatewayFailure catch (error) {
      if (generation != _generation || !ref.mounted || _poll == null) return;
      if (error.code == 'disconnected' || error.code == 'not_connected') {
        _stopWatch(UploadWatch.linkLost);
      }
      // busy / not_ready / timeout: skip this round.
    } catch (_) {
      // Unexpected; try again next round.
    } finally {
      _pollInFlight = false;
    }
  }

  /// Copies the gateway's own network fields (get_net_status only).
  void _absorbNet(Map<String, dynamic> source) {
    final update = {
      for (final key in gatewayNetKeys)
        if (source.containsKey(key)) key: source[key],
    };
    if (update.isEmpty) return;
    state = state.copy(net: {...state.net, ...update}, error: state.error);
  }

  /// Install report text (set on step 7); empty before the first pass.
  String _reportBody = '';
  String _report() => '$_reportBody\n${reportTargetText(state.config)}';

  /// Keeps the step-7 report's upload-target lines in sync after a switch.
  void _refreshReport() {
    if (state.step == 7 && _reportBody.isNotEmpty) {
      state = state.copy(report: _report(), error: state.error);
    }
  }

  /// Runs a gateway-side task that must not replace the step's guidance
  /// text, whether it succeeds or fails (a cancel sets its own message).
  Future<void> _sideTask(
    String label,
    int timeout,
    Future<void> Function(int) action,
  ) async {
    final resume = state.message;
    await _run(label, timeout, action);
    if (!ref.mounted) return;
    if (state.message == label) {
      state = state.copy(message: resume, error: state.error);
    }
    _refreshReport();
  }

  String get _uploadText => state.config['mqtt_connected'] == true
      ? 'Gateway 已開始上傳資料。'
      : 'Gateway 正在連線，APP 會自動確認（最多約 2 分鐘）。';

  /// Re-reads the running upload target and upload state.
  Future<void> refreshUploadTarget() async {
    await _sideTask('重新讀取 Gateway 狀態', 20, (generation) async {
      final net = await _command(generation, 'get_net_status');
      _absorbTarget(net);
      _absorbNet(net);
      final target = parseMqttTarget(state.config);
      state = state.copy(
        uploadNotice: target == null ? '' : '已重新讀取。$_uploadText',
      );
    });
    _watchUploadIfPending();
  }

  /// Sends `set_mqtt_target`; on a change the gateway reboots, so reconnect to
  /// the same gateway and confirm the running target by reading it back.
  ///
  /// [waitUpload]: after reading the target back, briefly wait for the
  /// upload to start. False when the Wi-Fi is changed next anyway (the
  /// upload cannot start before), so no time is spent waiting for it.
  Future<void> switchUploadTarget(
    MqttTarget wanted, {
    bool waitUpload = true,
  }) async {
    await _switchUploadTarget(wanted, waitUpload);
    _watchUploadIfPending();
  }

  Future<void> _switchUploadTarget(
    MqttTarget wanted,
    bool waitUpload,
  ) => _sideTask('正在把 Gateway 切到${wanted.plainLabel}（會重新開機，約 1 分鐘）', 120, (
    generation,
  ) async {
    final peer = state.peer;
    if (peer == null) throw const GatewayFailure('disconnected');
    if (!reportsMqttTarget(state.config)) {
      throw GatewayFailure(
        'target_unsupported',
        detail: state.config['fw_version']?.toString(),
      );
    }
    SetTargetAck? ack;
    for (int attempt = 0; ; attempt++) {
      try {
        ack = parseSetTargetAck(
          await _command(generation, 'set_mqtt_target', wanted.params),
        );
      } on GatewayFailure catch (error) {
        if (error.fromGateway) throw GatewayFailure.uploadTarget(error.code);
        if (error.code == 'not_connected' && attempt == 0) {
          // The link had already dropped, so nothing reached the gateway:
          // reconnect, then send the command once more.
          await _relink(generation, peer);
          continue;
        }
        // ACK lost: the gateway may already be rebooting. Reconnect and
        // read back instead of guessing.
        if (error.code != 'disconnected' && error.code != 'timeout') rethrow;
      }
      break;
    }
    if (ack != null && !ack.changed) {
      final status = await _command(generation, 'get_net_status');
      _absorbTarget(status);
      _absorbNet(status);
      final now = parseMqttTarget(state.config) ?? ack.target;
      if (!now.sameAs(wanted)) {
        throw GatewayFailure.targetReadback(
          actual: now.plainLabel,
          wanted: wanted.plainLabel,
        );
      }
      state = state.copy(
        uploadNotice:
            '不用切換：Gateway 本來就送到${now.plainLabel}（沒有重新開機）。$_uploadText',
      );
      return;
    }
    // Changed (or outcome unknown): the old MQTT state no longer applies.
    // The firmware commits the target to NVS before a changed:true ACK, so
    // the gateway boots with it even if the reconnect below fails; with no
    // ACK the running target is unknown until it is read back.
    final config = {...state.config}..remove('mqtt_connected');
    if (ack != null) {
      config.addAll(ack.target.fields);
    } else {
      config
        ..['mqtt_target'] = unconfirmedMqttTarget
        ..remove('mqtt_host')
        ..remove('mqtt_port');
    }
    state = state.copy(config: config, net: const {}, uploadNotice: '');
    await _reconnectAfterReboot(generation, peer, ack?.rebootInMs ?? 1500);
    // Rebooted: the Wi-Fi is joined again from scratch.
    _startWifiGrace();
    final confirmed = await _readBackTarget(generation, wanted, waitUpload);
    state = state.copy(
      uploadNotice:
          '已把 Gateway 切到${confirmed.plainLabel}，Gateway 已重新開機並重新連上。'
          '${waitUpload ? _uploadText : '接著設定 Wi-Fi。'}',
    );
  });

  /// Reconnects a link that dropped while idle (no reboot involved).
  Future<void> _relink(int generation, GatewayPeer peer) async {
    await _link.disconnect();
    _check(generation);
    try {
      await _link.connect(peer).timeout(const Duration(seconds: 20));
    } on GatewayFailure {
      rethrow;
    } catch (_) {
      await _link.disconnect();
      _check(generation);
      throw const GatewayFailure('disconnected');
    }
    _check(generation);
    await _command(generation, 'ping');
  }

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
  /// it is used meanwhile. Polls briefly for mqtt_connected unless
  /// [waitUpload] is false.
  Future<MqttTarget> _readBackTarget(
    int generation,
    MqttTarget wanted,
    bool waitUpload,
  ) async {
    const transient = ['not_ready', 'busy', 'timeout'];
    MqttTarget? seen;
    for (int attempt = 0; attempt < 10; attempt++) {
      if (attempt > 0) await _wait(3, generation);
      Map<String, dynamic> status;
      bool fromNet = true;
      try {
        status = await _command(generation, 'get_net_status');
      } on GatewayFailure catch (error) {
        if (!transient.contains(error.code)) rethrow;
        try {
          status = await _command(generation, 'get_config');
          fromNet = false;
        } on GatewayFailure catch (error) {
          if (!transient.contains(error.code)) rethrow;
          continue;
        }
      }
      _absorbTarget(status);
      if (fromNet) _absorbNet(status);
      final target = parseMqttTarget(status);
      if (target == null || !target.sameAs(wanted)) {
        throw GatewayFailure.targetReadback(
          actual: target?.plainLabel ?? '（未回報）',
          wanted: wanted.plainLabel,
        );
      }
      seen = target;
      if (!waitUpload || status['mqtt_connected'] == true) break;
    }
    if (seen == null) {
      throw GatewayFailure.targetReadback(
        actual: '（無法讀取）',
        wanted: wanted.plainLabel,
      );
    }
    return seen;
  }

  void setForeground(bool value) => _foreground = value;
  Future<void> refreshHealth() async {
    if (!_foreground || _healthBusy || state.busy || !_loggedIn) return;
    _healthBusy = true;
    final loginBase = _loginBase;
    // A switch of backend while the request runs makes its answer stale.
    bool stale() => !_loggedIn || _loginBase != loginBase;
    try {
      final latest = await _api.request(
        'GET',
        '/api/latest?site_id=$site&gateway_id=$gateway',
      );
      if (stale()) return;
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
      if (ref.mounted && !stale()) {
        state = state.copy(online: false, message: '無法確認最新資料，請檢查網路');
      }
    } finally {
      _healthBusy = false;
    }
  }

  /// [base] / [password] log in first when the backend was switched since
  /// the last login (step 7 offers the password field for that).
  Future<void> repair({String? base, String? password}) => _run('重新連接閘道器', 60, (
    generation,
  ) async {
    if (!_loggedIn && base != null && (password ?? '').isNotEmpty) {
      _backend = describeBackend(Uri.tryParse(base.trim()));
      await _api.login(base.trim(), password!);
      _check(generation);
      _setLoggedIn(true, base);
    }
    // After an environment switch the old login must not reach the new
    // site.
    if (!_loggedIn) throw const GatewayFailure('authentication');
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
    _grace?.cancel();
    _stopWatch(UploadWatch.idle);
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
        net: const {},
        checkPassed: false,
        wifiGraceOver: false,
        error: safe ? null : '尚未確認安全停止，請重新連線核對。',
        message: '已取消。請重新連線核對進度；未成功恢復的監控會話最晚於到期時恢復。',
      );
    }
  }
}
