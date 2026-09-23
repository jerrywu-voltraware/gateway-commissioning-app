import '../core/mqtt_target.dart';
import '../core/protocol.dart';
import 'contracts.dart';

/// Compile-time production broker host reported by firmware 1.7.3.
const demoProductionMqttHost = '46.250.255.172';

class DemoSystem implements GatewayLink, GatewayApi {
  final config = <String, dynamic>{
    'fw_version': '1.7.3',
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
  };
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

  /// MQTT state reported by get_net_status.
  bool mqttConnected = true;

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
  Future<void> connect(GatewayPeer peer) async {
    connects++;
    rebooting = false;
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
        config['wifi_ssid'] = params['ssid'];
        return {'message': 'wifi switching'};
      case 'get_status':
      case 'get_net_status':
        return {
          'wifi_state': 'got_ip',
          'ip': 'demo',
          'mqtt_connected': mqttConnected,
          'ntp_synced': true,
          'ssid': config['wifi_ssid'],
          'last_wifi_error': '',
          if (op == 'get_net_status')
            for (final key in ['mqtt_target', 'mqtt_host', 'mqtt_port'])
              if (config.containsKey(key)) key: config[key],
        };
      case 'set_mqtt_target':
        return _setMqttTarget(params);
      case 'scan_ble_discover':
      case 'get_ble_devices':
        return {'devices': devices.map(Map<String, dynamic>.of).toList()};
      case 'assign_device_id':
        devices.firstWhere((d) => d['mac'] == params['mac'])['device_number'] =
            params['new_id'];
        return {'success': true};
      case 'set_config':
        config.addAll(params);
        return {};
      case 'join_fleet':
        config['fleet_joined'] = true;
        config['upload_paused'] = false;
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
