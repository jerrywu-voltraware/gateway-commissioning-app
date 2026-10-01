import 'dart:async';

import '../core/mqtt_target.dart';
import '../core/identify.dart';
import '../core/protocol.dart';
import 'contracts.dart';

/// Compile-time production broker host reported by firmware 1.7.3.
const demoProductionMqttHost = '46.250.255.172';

class DemoSystem implements GatewayLink, GatewayApi, ForeignAcks {
  final config = <String, dynamic>{
    'fw_version': '1.7.3',
    'identify_supported': true,
    'site_id': 1,
    'gateway_id': 1,
    'gateway_uid': 'AABBCCDDEEFF',
    'otp_enabled': false,
    'max_connections': 3,
    'fleet_joined': false,
    'ble_enabled': true,
    // `upload_paused` unset: see [uploadPaused] (round 26).
    'mqtt_target': 'production',
    'mqtt_host': demoProductionMqttHost,
    'mqtt_port': defaultMqttPort,
    'wifi_ssid': 'Demo-2.4G',
    // Firmware 1.7.20 direct mode + PTU identify (remove to simulate older).
    'direct_autoconnect_supported': true,
    'identify_ptu_supported': true,
    'identify_ptu_protocol': 'a2_seconds',
    'auto_connect_min_rssi': -55,
    'direct_bind_mac': '',
  };

  /// Identify requests received (params as sent).
  final identifyRequests = <Map<String, dynamic>>[];

  final _foreign = StreamController<Map<String, dynamic>>.broadcast();

  @override
  Stream<Map<String, dynamic>> get foreignAcks => _foreign.stream;

  /// Round 19: an ack of a command this APP did not send, as the gateway
  /// relays it to the phone (see [ForeignAcks]).
  void relayForeignAck(Map<String, dynamic> ack) => _foreign.add(ack);

  /// Round 19: the back office's identify (sent over MQTT, dashboard
  /// pattern 0 / 3 s) as the gateway relays its ack to the phone:
  /// [confirm] as `ptu_confirm` (firmware 1.7.25+), the connected PTU's
  /// MAC / RSSI when there is one.
  void remoteIdentify({
    String reqId = '20260926-00007',
    String? confirm,
    int seconds = defaultIdentifySeconds,
  }) {
    final ptu = devices.where((d) => d['connected'] == true).firstOrNull;
    relayForeignAck({
      'gateway_led': 'ok',
      'duration_ms': seconds * 1000,
      if (confirm == null) ...{
        'identify_ptu_protocol': 'a2_seconds',
        'ptu_reply_expected': false,
      },
      'ptu_write': ptu == null ? 'not_connected' : 'ok',
      if (confirm != null) 'ptu_confirmed': ptu != null && confirm == 'ok',
      if (ptu != null && confirm != null) ...{
        'ptu_confirm': confirm,
        'ptu_confirm_ms': confirm == 'ok' ? 180 : 1505,
        'ptu_seq': 3,
      },
      if (ptu != null) 'mac': ptu['mac'],
      if (ptu != null) 'rssi': ptu['rssi'],
      'req_id': reqId,
      'status': 'ok',
    });
  }

  /// Round 18: firmware 1.7.25's `ptu_confirm` for a PTU identify (`ok`,
  /// `unsupported_pattern`, `timeout`); null uses the configured protocol.
  String? identifyPtuConfirm;

  /// Firmware 1.7.20 direct mode: `max_connections` 1 on a firmware that
  /// picks the PTU itself (cmd_contract.md §3A).
  bool get directMode =>
      config['direct_autoconnect_supported'] == true &&
      config['max_connections'] == 1;

  /// `select_reason` of the latest simulated collection window.
  String directReason = '';

  /// Round 19: firmware 1.7.27's `self_adv_rssi_med` / `self_adv_age_s`
  /// and `neighbors[]` in the direct report (false: older firmware).
  bool directNeighborsReport = false;

  /// Round 19: `self_adv_rssi_med` = the connected PTU's rssi + this (null:
  /// not heard, reported as null).
  int? selfAdvOffset = 0;

  /// Round 20: `self_adv_age_s` while connected (null: not reported) —
  /// the firmware freezes the median once connected, so it grows.
  num? selfAdvAgeS = 1;

  /// Round 19: every neighbour's `samples` / `age_s` (MAC → value;
  /// default 8 readings, heard 2 s ago).
  final neighborSamples = <String, int>{};
  final neighborAges = <String, num>{};

  /// Round 17: get_status reads left that report `scanning` (no pick)
  /// after a `disconnect_device` — the new collection window is still
  /// open (firmware: CLOSE_EVT resumes the scan, the window takes ≥ 3 s).
  int directGapReads = 0;

  static String _macKey(Object? mac) =>
      (mac?.toString() ?? '').toLowerCase().replaceAll(RegExp('[^0-9a-f]'), '');

  /// Simulated direct-mode pick after a BLE restart (set_config of
  /// max_connections / threshold / binding) or while nothing is connected:
  /// only the bound MAC when bound, else the strongest at or above the
  /// threshold; a runner-up within 6 dB is `ambiguous` (the strongest is
  /// still connected, as after two ambiguous windows).
  void directReselect() {
    if (!directMode) return;
    for (final d in devices) {
      d['connected'] = false;
      d['notify_enabled'] = false;
    }
    final min = (config['auto_connect_min_rssi'] as num?)?.toInt() ?? -55;
    final bound = _macKey(config['direct_bind_mac']);
    Map<String, dynamic>? pick;
    if (bound.isNotEmpty) {
      pick = devices.where((d) => _macKey(d['mac']) == bound).firstOrNull;
      directReason = pick == null ? 'bound_missing' : 'ok';
    } else {
      final sorted = List.of(devices)
        ..sort((a, b) => (b['rssi'] as num).compareTo(a['rssi'] as num));
      final best = sorted.firstOrNull;
      if (best == null || (best['rssi'] as num) < min) {
        directReason = 'none';
      } else {
        pick = best;
        final second = sorted.length > 1 ? sorted[1] : null;
        directReason =
            second != null &&
                (best['rssi'] as num) - (second['rssi'] as num) < 6
            ? 'ambiguous'
            : 'ok';
      }
    }
    if (pick != null) {
      pick['connected'] = true;
      pick['notify_enabled'] = true;
    }
  }

  /// `direct` object as firmware 1.7.20 reports it; null for older firmware
  /// (no `direct_autoconnect_supported`), `state:"off"` in star mode.
  Map<String, dynamic>? directStatus() {
    if (config['direct_autoconnect_supported'] != true) return null;
    final min = (config['auto_connect_min_rssi'] as num?)?.toInt() ?? -55;
    final bound = config['direct_bind_mac']?.toString() ?? '';
    if (!directMode) {
      return {
        'active': false,
        'state': 'off',
        'min_rssi': min,
        'bound_mac': bound,
        'select_reason': '',
        'candidates': const [],
      };
    }
    if (directGapReads > 0) {
      directGapReads--;
      return {
        'active': true,
        'state': 'scanning',
        'min_rssi': min,
        'bound_mac': bound,
        'select_reason': directReason,
        'candidates': const [],
      };
    }
    // The gateway keeps scanning while nothing (or not the bound PTU) is
    // connected.
    var linked = devices.where((d) => d['connected'] == true).firstOrNull;
    if (linked == null ||
        (bound.isNotEmpty && _macKey(linked['mac']) != _macKey(bound))) {
      directReselect();
      linked = devices.where((d) => d['connected'] == true).firstOrNull;
    }
    final candidates = devices.where((d) => (d['rssi'] as num) >= -100).toList()
      ..sort((a, b) => (b['rssi'] as num).compareTo(a['rssi'] as num));
    final String state;
    if (linked != null) {
      state = 'connected';
    } else if (directReason == 'bound_missing') {
      state = 'bound_missing';
    } else if (directReason == 'none') {
      state = 'no_candidate';
    } else {
      state = 'scanning';
    }
    return {
      'active': true,
      'state': state,
      'min_rssi': min,
      'bound_mac': bound,
      'select_reason': directReason,
      if (linked != null) 'ptu_mac': linked['mac'],
      if (linked != null) 'ptu_rssi': linked['rssi'],
      if (linked != null) 'ptu_device_number': linked['device_number'],
      if (directNeighborsReport) ...{
        'self_adv_rssi_med': linked == null || selfAdvOffset == null
            ? null
            : (linked['rssi'] as num) + selfAdvOffset!,
        'self_adv_age_s': linked == null ? null : selfAdvAgeS,
        'neighbors': [
          if (linked != null)
            for (final d in candidates)
              if (d != linked)
                {
                  'mac': d['mac'],
                  'rssi_peak': d['rssi'],
                  'rssi_last': (d['rssi'] as num) - 2,
                  'rssi_med': (d['rssi'] as num) - 3,
                  'samples': neighborSamples[d['mac']] ?? 8,
                  'age_s': neighborAges[d['mac']] ?? 2,
                },
        ],
      },
      'candidates': [
        for (final d in candidates.take(5))
          {
            'mac': d['mac'],
            'rssi_peak': d['rssi'],
            'rssi_last': d['rssi'],
            'count': 3,
            'device_number': d['device_number'],
            // Firmware 1.7.40: the window median the unbound pick compares
            // with min_rssi, and the verdict.
            'rssi_med': d['rssi'],
            'reason': (d['rssi'] as num) >= min
                ? 'ok'
                : 'below_threshold_median',
          },
      ],
    };
  }

  final devices = List.generate(
    3,
    (i) => <String, dynamic>{
      'mac': 'AA:BB:CC:00:00:0${i + 1}',
      'rssi': -40 - i * 9,
      'device_number': 0,
      'connected': false,
      'notify_enabled': false,
      'zombie': false,
      'last_data_age_sec': 0,
    },
  );
  bool monitored = true;
  int tick = 0;

  /// MQTT state reported by get_net_status (only while the Wi-Fi works).
  bool mqttConnected = true;

  /// Wi-Fi state reported by get_net_status, as in firmware cmd_handler.c:
  /// `got_ip`, `connecting` or `disconnected`.
  String wifiState = 'got_ip';

  /// While [wifiState] is `connecting`: reads of get_net_status left before
  /// the simulated gateway joins its Wi-Fi (a gateway that just booted).
  int connectingReads = 3;

  /// get_net_status `uptime_sec`; reset by a simulated reboot.
  int uptimeSec = 3600;

  /// get_net_status `ip` while the Wi-Fi works.
  String ip = 'demo';

  /// Networks set_wifi cannot join (out of range, wrong password or
  /// 5 GHz): the firmware keeps the old Wi-Fi and reports last_wifi_error.
  final unreachableSsids = <String>{};
  String lastWifiError = '';

  /// NVS boot counter (firmware 1.7.6 `boot_count`, get_config and
  /// get_net_status); null leaves it out, as older firmware does.
  int? bootCount;

  /// get_net_status `reset_reason` of the current boot (with [bootCount]).
  String resetReason = 'poweron';

  /// The gateway restarts on its own ([reason], e.g. `ble_stack_stuck`):
  /// counted, uptime from zero. The link drop itself is up to the caller.
  void simulateRestart(String reason) {
    bootCount = (bootCount ?? 0) + 1;
    resetReason = reason;
    uptimeSec = 5;
  }

  /// Simulates the Wi-Fi the gateway finds after a (re)boot.
  void simulateWifi(String state) {
    wifiState = state;
    connectingReads = 3;
    uptimeSec = state == 'connecting' ? 5 : 3600;
  }

  /// Set after a set_mqtt_target change: the simulated gateway reboots and
  /// answers nothing until the APP reconnects.
  bool rebooting = false;
  int connects = 0;

  /// 1.0.0+22 (select_then_identify): the gateway the simulated link is
  /// connected to (null after a disconnect) and how many disconnects there
  /// were — the list keeps the selected gateway's link, and its bulb and
  /// 〔連線到 …〕 must not connect again.
  String? linkedPeer;
  int linkDisconnects = 0;
  final targetRequests = <Map<String, dynamic>>[];
  @override
  bool get demo => true;
  @override
  Future<void> prepare() async {}
  @override
  Future<void> disconnect() async {
    linkDisconnects++;
    linkedPeer = null;
  }

  @override
  Future<List<GatewayPeer>> scan() async => [
    const GatewayPeer('demo-gateway', 'GIOS-S1-GW01', -42),
  ];
  @override
  Future<void> connect(
    GatewayPeer peer, {
    void Function(String stage)? onStage,
  }) async {
    onStage?.call('正在連線閘道器');
    connects++;
    linkedPeer = peer.id;
    if (rebooting) {
      // Booted again: the Wi-Fi is joined from scratch.
      uptimeSec = 5;
      lastWifiError = '';
      if (bootCount != null) {
        bootCount = bootCount! + 1;
        resetReason = 'sw';
      }
    }
    rebooting = false;
  }

  Map<String, dynamic> _netStatus(String op) {
    if (wifiState == 'connecting' && --connectingReads <= 0) {
      wifiState = 'got_ip';
    }
    final online = wifiState == 'got_ip';
    return {
      'wifi_state': wifiState,
      'ip': online ? ip : '',
      'rssi': online ? -55 : 0,
      'mqtt_connected': online && mqttConnected,
      'ntp_synced': true,
      'ssid': config['wifi_ssid'],
      'uptime_sec': uptimeSec,
      'last_wifi_error': lastWifiError,
      if (op == 'get_net_status')
        for (final key in ['mqtt_target', 'mqtt_host', 'mqtt_port'])
          if (config.containsKey(key)) key: config[key],
      if (op == 'get_net_status' && bootCount != null) ...{
        'boot_count': bootCount,
        'reset_reason': resetReason,
      },
    };
  }

  @override
  Future<void> login(String base, String password) async {}
  @override
  Future<Map<String, dynamic>> command(
    String op, [
    Map<String, dynamic> params = const {},
  ]) async {
    if (rebooting) throw const GatewayFailure('disconnected');
    switch (op) {
      case 'get_config':
        return {
          ...config,
          'upload_paused': uploadPaused,
          'boot_count': ?bootCount,
        };
      case 'set_mode':
        // Firmware: same mode → no reboot; else ACK, NVS, reboot.
        final mode = params['mode'];
        if (mode != 'test' && mode != 'normal') {
          throw const GatewayFailure.gateway(
            'unknown mode (use "test" or "normal")',
          );
        }
        if ((config['mode'] ?? 'normal') == mode) {
          return {'message': 'already in $mode mode, no change'};
        }
        config['mode'] = mode;
        rebooting = true;
        return {'message': 'mode switching to $mode, rebooting...'};
      case 'set_site_identity':
        config.addAll(params);
        return {'message': 'rebooting'};
      case 'set_wifi':
        // Reconnects in place (no reboot); a failure keeps the old Wi-Fi.
        if (unreachableSsids.contains(params['ssid'])) {
          lastWifiError = 'ESP_ERR_TIMEOUT';
        } else {
          lastWifiError = '';
          config['wifi_ssid'] = params['ssid'];
          wifiState = 'got_ip';
        }
        return {'message': 'wifi switching to ${params['ssid']}'};
      case 'get_status':
        return {..._netStatus(op), 'direct': ?directStatus()};
      case 'get_net_status':
        return _netStatus(op);
      case 'set_mqtt_target':
        return _setMqttTarget(params);
      case 'identify':
        identifyRequests.add(Map.of(params));
        // Pre-PTU firmware: bare identify, fixed IDENTIFY_DEFAULT_MS (6 s),
        // and the same fallback when duration_ms is omitted. Not the APP's
        // own default (defaultIdentifySeconds).
        if (config['identify_ptu_supported'] != true) {
          return {'duration_ms': 6000};
        }
        final target = params['target'] ?? 'both';
        final durationMs = params['duration_ms'] ?? 6000;
        if (durationMs is! int || durationMs < 0 || durationMs > 255000) {
          throw const GatewayFailure.gateway('invalid duration_ms');
        }
        final seconds = (durationMs / 1000).ceil();
        if (target == 'gateway') {
          return {
            'target': target,
            'gateway_led': 'ok',
            'duration_ms': seconds * 1000,
            'identify_ptu_protocol': 'a2_seconds',
          };
        }
        // Firmware 1.7.20: target=ptu fails outright when the PTU side
        // can't be written (not_connected/ambiguous_target/write_failed).
        // target=both (the default, and the only target the APP's own UI
        // sends) never fails just because the PTU side did: it still acks
        // ok and blinks the gateway LED, reporting the PTU outcome via
        // `ptu_write` instead (cmd_contract.md identify: "both 只有兩者都
        // 失敗才 fail"). `mac`/`rssi`/`device_number` are only present when
        // the write actually succeeded.
        final linked = devices.where((d) => d['connected'] == true).toList();
        String ptuWrite;
        Map<String, dynamic>? ptu;
        if (linked.isEmpty) {
          ptuWrite = 'not_connected';
        } else if (linked.length > 1 && params['mac'] == null) {
          ptuWrite = 'ambiguous_target';
        } else {
          ptu = linked.firstWhere(
            (d) => params['mac'] == null || d['mac'] == params['mac'],
            orElse: () => throw const GatewayFailure.gateway('not_connected'),
          );
          ptuWrite = 'ok';
        }
        if (target == 'ptu' && ptuWrite != 'ok') {
          throw GatewayFailure.gateway(ptuWrite);
        }
        return {
          'target': target,
          'duration_ms': seconds * 1000,
          if (target != 'ptu') 'gateway_led': 'ok',
          'ptu_write': ptuWrite,
          if (identifyPtuConfirm == null &&
              config['identify_ptu_protocol'] == 'a2_seconds') ...{
            'identify_ptu_protocol': 'a2_seconds',
            'ptu_reply_expected': false,
          },
          if (identifyPtuConfirm != null)
            'ptu_confirmed': ptu != null && identifyPtuConfirm == 'ok',
          if (ptu != null && identifyPtuConfirm != null) ...{
            'ptu_confirm': identifyPtuConfirm,
            'ptu_confirm_ms': identifyPtuConfirm == 'ok' ? 180 : 1500,
          },
          if (ptu != null) 'mac': ptu['mac'],
          if (ptu != null) 'rssi': ptu['rssi'],
          if (ptu != null) 'device_number': ptu['device_number'],
        };
      case 'scan_ble_discover':
        return {'devices': devices.map(Map<String, dynamic>.of).toList()};
      case 'get_ble_devices':
        // Note: unlike get_status, get_ble_devices does NOT carry `direct`
        // (cmd_contract.md identify section); only get_status does.
        return {'devices': devices.map(Map<String, dynamic>.of).toList()};
      case 'assign_device_id':
        devices.firstWhere((d) => d['mac'] == params['mac'])['device_number'] =
            params['new_id'];
        return {'success': true};
      case 'set_config':
        const selection = [
          'max_connections',
          'auto_connect_min_rssi',
          'direct_bind_mac',
        ];
        final before = [for (final k in selection) config[k]];
        config.addAll(params);
        final after = [for (final k in selection) config[k]];
        // Firmware 1.7.20: a selection-affecting change restarts BLE and,
        // in direct mode, picks again.
        if (directMode &&
            [
              for (var i = 0; i < before.length; i++) before[i] != after[i],
            ].any((changed) => changed)) {
          directReselect();
        }
        return {};
      case 'join_fleet':
        config['fleet_joined'] = true;
        config['upload_paused'] = false;
        if (directMode) {
          // Direct mode: the gateway keeps its own pick (numbers ignored).
          if (!devices.any((d) => d['connected'] == true)) directReselect();
          return {};
        }
        for (final d in devices) {
          if ((d['device_number'] as int) > 0) {
            d['connected'] = true;
            d['notify_enabled'] = true;
          }
        }
        return {};
      case 'set_ble_enabled':
        config['ble_enabled'] = params['enabled'];
        return {};
      case 'disconnect_device':
        final target = devices
            .where(
              (d) =>
                  d['connected'] == true &&
                  _macKey(d['mac']) == _macKey(params['mac']),
            )
            .firstOrNull;
        if (target == null) {
          throw const GatewayFailure.gateway('device not connected');
        }
        target['connected'] = false;
        target['notify_enabled'] = false;
        // Direct mode: the scan resumes and a new window picks again.
        if (directMode) directGapReads = 1;
        return {'mac': params['mac'], 'success': true};
      case 'set_data_upload':
        config['upload_paused'] = params['enabled'] != true;
        return {'upload_enabled': params['enabled'] == true};
      case 'check_db_upload':
        return {'db_ok': true};
      default:
        return {};
    }
  }

  /// Round 26: `upload_paused` as get_config reports it — set explicitly
  /// (set_data_upload, join_fleet, a test), or else paused until the
  /// gateway is in service (a new gateway uploads nothing before
  /// join_fleet; a gateway in service uploads).
  bool get uploadPaused =>
      config['upload_paused'] as bool? ?? config['fleet_joined'] != true;

  /// Mirrors cmd_exec_set_mqtt_target in firmware 1.7.3.
  Map<String, dynamic> _setMqttTarget(Map<String, dynamic> params) {
    if (!config.containsKey('mqtt_target')) {
      throw const GatewayFailure.gateway('unknown op');
    }
    targetRequests.add(Map.of(params));
    final target = params['target'];
    if (target != 'production' && target != 'local') {
      throw const GatewayFailure.gateway('invalid_target');
    }
    var host = demoProductionMqttHost;
    var port = defaultMqttPort;
    if (target == 'local') {
      final h = params['host'];
      if (h is! String || !isPrivateIpv4Literal(h)) {
        throw const GatewayFailure.gateway('invalid_host');
      }
      host = h;
      if (params.containsKey('port')) {
        final p = params['port'];
        if (p is! int || p < 1 || p > 65535) {
          throw const GatewayFailure.gateway('invalid_port');
        }
        port = p;
      }
    }
    final changed =
        target != config['mqtt_target'] ||
        (target == 'local' &&
            (host != config['mqtt_host'] || port != config['mqtt_port']));
    if (changed) {
      config.addAll({
        'mqtt_target': target,
        'mqtt_host': host,
        'mqtt_port': port,
      });
      rebooting = true;
    }
    return {
      'mqtt_target': target,
      'mqtt_host': host,
      'mqtt_port': port,
      'changed': changed,
      'reboot_in_ms': changed ? 1500 : 0,
    };
  }

  @override
  Future<Map<String, dynamic>> request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    // 1.0.0+19: the back office's upload policy (the done page's 「目前每
    // 5 秒」). Before [tick] so the simulated upload times stay as before.
    if (path == '/api/upload-policy') {
      return {
        'upload_interval_ms': 5000,
        'updated_by': 'seed',
        'range': {'min_ms': 1000, 'max_ms': 20000},
      };
    }
    // 1.0.0+20: the back office's build-mode fallback (sent; before [tick]
    // as well). 1.0.0+21: the simulated gateway applies it at once, so the
    // APP's get_config read-back confirms it (the demo's check as before).
    if (path.startsWith('/api/app/build-mode/')) {
      config.addAll({'ds_enabled': true, 'ds_min_ms': 1000, 'ds_max_ms': 1000});
      return {'sent': true, 'req_id': 'demo-build-mode'};
    }
    tick++;
    if (path.contains('bot-monitor')) {
      monitored = body?['enabled'] == true;
      return {'success': true};
    }
    if (path.contains('check-identity')) {
      if (!RegExp(r'^/api/gateways/\d+/\d+/check-identity$').hasMatch(path)) {
        throw StateError('Invalid identity route');
      }
      return {'exists': false, 'last_seen_mac': null};
    }
    if (path.contains('verify-installation')) return {'all_ok': true};
    if (path.contains('fleet-status')) {
      return {
        'mqtt_connected': true,
        'gateways': [
          {
            ...config,
            'online': true,
            'mqtt_connected': true,
            'last_heartbeat': 'demo-$tick',
            'bot_monitor': monitored,
          },
        ],
      };
    }
    if (path.startsWith('/api/app/recent/')) {
      // 09-28 〔查看最近資料〕: one row per connected PTU, newest first.
      final ptus = devices.where((d) => d['connected'] == true).toList();
      final base = DateTime.now();
      return {
        'site_id': config['site_id'],
        'gateway_id': config['gateway_id'],
        'count': ptus.length,
        'items': [
          for (final (i, d) in ptus.indexed)
            {
              'ts': base.subtract(Duration(seconds: 3 + i)).toIso8601String(),
              'seq': tick + i,
              'device_id': d['device_number'],
              'ptu_mac': d['mac'],
              'ptu_state': 'POWER_TRANSFER',
              'input_mv': 5000,
              'input_ma': 120,
              'bus_mv': 4980,
              'temp_c': 31,
            },
        ],
        // 1.0.0+20: the interval the page's limits follow.
        'upload_interval_ms': 5000,
      };
    }
    if (path.contains('/api/latest')) {
      return {
        'items': devices
            .where((d) => d['connected'] == true)
            .map(
              (d) => {
                'device_id': d['device_number'],
                'ptu': {'ptu_mac_addr': d['mac']},
                'online': true,
                'lag_seconds': 0,
                'error_num': 0,
                'ts': DateTime(
                  2030,
                ).add(Duration(seconds: tick)).toIso8601String(),
              },
            )
            .toList(),
      };
    }
    return {'success': true};
  }
}
