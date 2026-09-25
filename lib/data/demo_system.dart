import '../core/mqtt_target.dart';
import '../core/protocol.dart';
import 'contracts.dart';

/// Compile-time production broker host reported by firmware 1.7.3.
const demoProductionMqttHost = '46.250.255.172';

class DemoSystem implements GatewayLink, GatewayApi {
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
    'upload_paused': true,
    'mqtt_target': 'production',
    'mqtt_host': demoProductionMqttHost,
    'mqtt_port': defaultMqttPort,
    'wifi_ssid': 'Demo-2.4G',
    // Firmware 1.7.20 direct mode + PTU identify (remove to simulate older).
    'direct_autoconnect_supported': true,
    'identify_ptu_supported': true,
    'auto_connect_min_rssi': -55,
    'direct_bind_mac': '',
  };

  /// Identify requests received (params as sent).
  final identifyRequests = <Map<String, dynamic>>[];

  /// Firmware 1.7.20 direct mode: `max_connections` 1 on a firmware that
  /// picks the PTU itself (cmd_contract.md §3A).
  bool get directMode =>
      config['direct_autoconnect_supported'] == true &&
      config['max_connections'] == 1;

  /// `select_reason` of the latest simulated collection window.
  String directReason = '';

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
      'candidates': [
        for (final d in candidates.take(5))
          {
            'mac': d['mac'],
            'rssi_peak': d['rssi'],
            'rssi_last': d['rssi'],
            'count': 3,
            'device_number': d['device_number'],
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
  final targetRequests = <Map<String, dynamic>>[];
  @override
  bool get demo => true;
  @override
  Future<void> prepare() async {}
  @override
  Future<void> disconnect() async {}
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
    if (rebooting) {
      // Booted again: the Wi-Fi is joined from scratch.
      uptimeSec = 5;
      lastWifiError = '';
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
        return Map.of(config);
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
        if (config['identify_ptu_supported'] != true) {
          return {'duration_ms': 6000};
        }
        final target = params['target'] ?? 'both';
        if (target == 'gateway') return {'duration_ms': 6000};
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
          'duration_ms': 6000,
          'ptu_write': ptuWrite,
          'ptu_confirmed': false,
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
      case 'set_data_upload':
        config['upload_paused'] = params['enabled'] != true;
        return {};
      case 'check_db_upload':
        return {'db_ok': true};
      default:
        return {};
    }
  }

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
    if (path.contains('/api/latest')) {
      return {
        'items': devices
            .where((d) => d['connected'] == true)
            .map(
              (d) => {
                'device_id': d['device_number'],
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
