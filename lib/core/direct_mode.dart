/// Direct (one-to-one) mode as reported by firmware 1.7.20+: the gateway
/// picks the nearest PTU itself (RSSI threshold, optional MAC binding) and
/// reports `direct:{state, min_rssi, bound_mac, candidates}` in get_status /
/// get_ble_devices / the heartbeat. Older firmware sends none of this; every
/// helper here then returns null / false so the APP keeps its old behaviour.
library;

/// PTU number used for every direct-mode PTU (the firmware ignores the
/// number in direct mode; identity is the distance / bound MAC).
const directPtuId = 1;

/// `auto_connect_min_rssi` range and default (dBm).
const minDirectRssi = -100;
const maxDirectRssi = -20;
const defaultDirectRssi = -55;

/// get_config says the firmware selects the direct PTU by RSSI threshold.
bool directAutoConnectSupported(Map<String, dynamic> config) =>
    config['direct_autoconnect_supported'] == true;

/// get_config says identify can also blink the connected PTU.
bool identifyPtuSupported(Map<String, dynamic> config) =>
    config['identify_ptu_supported'] == true;

/// Saved threshold, clamped; the default when absent or malformed.
int directMinRssiOf(Map<String, dynamic> config) {
  final value = config['auto_connect_min_rssi'];
  if (value is! num) return defaultDirectRssi;
  return value.toInt().clamp(minDirectRssi, maxDirectRssi);
}

/// Bound PTU MAC, or null when unbound (`""` / absent).
String? directBoundMacOf(Map<String, dynamic> source) {
  final value = source['direct_bind_mac'] ?? source['bound_mac'];
  if (value is! String || value.trim().isEmpty) return null;
  return value.trim();
}

class DirectCandidate {
  const DirectCandidate(this.mac, this.rssiPeak, this.deviceNumber);
  final String mac;
  final int? rssiPeak;
  final int? deviceNumber;

  String get rssiText => rssiPeak == null ? 'RSSI —' : '峰值 $rssiPeak dBm';
}

enum DirectState {
  connected,
  noCandidate,
  scanning,
  boundMissing;

  static DirectState? parse(Object? value) => switch (value) {
    'connected' => DirectState.connected,
    'no_candidate' => DirectState.noCandidate,
    'scanning' => DirectState.scanning,
    'bound_missing' => DirectState.boundMissing,
    _ => null,
  };

  String get label => switch (this) {
    DirectState.connected => '已連上同樁 PTU',
    DirectState.noCandidate => '找不到夠近的 PTU',
    DirectState.scanning => '正在尋找同樁 PTU',
    DirectState.boundMissing => '已綁定的 PTU 不在場',
  };

  /// Field guidance; null when nothing needs doing.
  String? get hint => switch (this) {
    DirectState.noCandidate => '請靠近／確認同樁 PTU 已上電',
    DirectState.boundMissing => '已綁定的 PTU 不在場，請確認其電源；若已更換 PTU，請解除綁定',
    _ => null,
  };
}

/// Parsed `direct` object; null for firmware without it.
class DirectStatus {
  const DirectStatus({
    required this.state,
    this.minRssi,
    this.boundMac,
    this.candidates = const [],
  });
  final DirectState state;
  final int? minRssi;
  final String? boundMac;

  /// At most 5, as the firmware sends them (strongest first).
  final List<DirectCandidate> candidates;

  static DirectStatus? from(Object? source) {
    if (source is! Map) return null;
    final state = DirectState.parse(source['state']);
    if (state == null) return null;
    final rows = source['candidates'];
    return DirectStatus(
      state: state,
      minRssi: (source['min_rssi'] as num?)?.toInt(),
      boundMac: directBoundMacOf({'bound_mac': source['bound_mac']}),
      candidates: [
        if (rows is List)
          for (final row in rows.whereType<Map>().take(5))
            if (row['mac'] != null)
              DirectCandidate(
                row['mac'].toString(),
                (row['rssi_peak'] as num?)?.toInt(),
                (row['device_number'] as num?)?.toInt(),
              ),
      ],
    );
  }
}

/// identify on firmware 1.7.20+ when target=ptu itself fails outright
/// (no PTU connected): the APP falls back to blinking the gateway only.
const identifyNoPtuText = '閘道器雙閃 6 秒；閘道器尚未連上 PTU，PTU 不會閃燈。';

/// identify ack → text for the installer, when the PTU write itself
/// succeeded (`ptu_write` absent — bare/gateway-only ack — or `"ok"`).
/// [ptuConfirmed] false means the PTU accepted the write but could not
/// confirm it blinked.
String identifyAckText(Map<String, dynamic> ack) {
  final mac = ack['mac'];
  if (mac == null) return '請找出雙閃藍燈的閘道器，6 秒後會恢復原本燈號。';
  final rssi = ack['rssi'];
  final number = ack['device_number'];
  final seconds = ((ack['duration_ms'] as num?) ?? 6000) / 1000;
  final confirmed = ack['ptu_confirmed'] == true;
  final parts = [
    'PTU $mac',
    if (rssi is num) '$rssi dBm',
    if (number is num && number > 0) '#$number',
  ];
  return 'PTU 與閘道器正在閃燈（${confirmed ? 'PTU 已確認閃燈' : 'PTU 燈效需新版 PTU 韌體'}），'
      '閘道器雙閃 ${seconds.toStringAsFixed(0)} 秒（${parts.join(' · ')}）。';
}

/// identify ack (target both, firmware 1.7.20+) with the gateway LED lit
/// but the PTU write itself unsuccessful — `ptu_write` present and not
/// `"ok"` (e.g. `"not_connected"`, or a PTU error code). The firmware still
/// acks `status:ok` here (§ cmd_contract.md identify: "both 只有兩者都失敗才
/// fail"); this is not a failure the APP should resend or treat as a
/// dropped phone↔gateway link.
String identifyPtuFailedText(String reason) => '閘道器正在閃燈；尚未連上 PTU（$reason）。';
