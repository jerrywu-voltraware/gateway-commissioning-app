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
  connecting,
  noCandidate,
  scanning,
  boundMissing;

  /// `off` (star mode) and unknown values are null: nothing to show.
  static DirectState? parse(Object? value) => switch (value) {
    'connected' => DirectState.connected,
    'connecting' => DirectState.connecting,
    'no_candidate' => DirectState.noCandidate,
    'scanning' => DirectState.scanning,
    'bound_missing' => DirectState.boundMissing,
    _ => null,
  };

  /// Round 14: 「已連上同樁 PTU」 claimed more than the gateway knows (an
  /// ambiguous pick is only the strongest); the installer confirms with
  /// 「辨識此樁」.
  String get label => switch (this) {
    DirectState.connected => '已連上 PTU',
    DirectState.connecting => '正在連線 PTU',
    DirectState.noCandidate => '找不到夠近的 PTU',
    DirectState.scanning => '正在尋找最近的 PTU',
    DirectState.boundMissing => '已綁定的 PTU 不在場',
  };

  /// Field guidance; null when nothing needs doing.
  String? get hint => switch (this) {
    DirectState.noCandidate => '請靠近／確認同樁 PTU 已上電',
    DirectState.boundMissing => '已綁定的 PTU 不在場，請確認其電源；若已更換 PTU，請解除綁定',
    _ => null,
  };
}

/// Parsed `direct` object; null for firmware without it (or star mode,
/// `state:"off"`).
class DirectStatus {
  const DirectStatus({
    required this.state,
    this.minRssi,
    this.boundMac,
    this.selectReason = '',
    this.ptuMac,
    this.ptuRssi,
    this.ptuDeviceNumber,
    this.candidates = const [],
  });
  final DirectState state;
  final int? minRssi;
  final String? boundMac;

  /// Latest collection window: `ok` / `ambiguous` / `none` /
  /// `bound_missing`, `""` before the first window (cmd_contract.md §3A).
  /// `connected` + `ambiguous` = the gateway could not tell and took the
  /// strongest — not a clear pick.
  final String selectReason;

  /// The PTU the gateway is connected to (firmware 1.7.20 `ptu_mac`,
  /// `ptu_rssi`, `ptu_device_number`); null while not connected.
  final String? ptuMac;
  final int? ptuRssi;
  final int? ptuDeviceNumber;

  /// At most 5, as the firmware sends them (strongest first).
  final List<DirectCandidate> candidates;

  /// The gateway's own pick: connected and naming the PTU.
  String? get pickedMac =>
      state == DirectState.connected && ptuMac != null ? ptuMac : null;

  /// Signals too close to tell apart: the installer must confirm the pick
  /// with 「辨識此樁」 (not shown for a PTU the gateway is bound to).
  bool get ambiguous =>
      selectReason == 'ambiguous' &&
      !(boundMac != null && ptuMac != null && _same(boundMac!, ptuMac!));

  static bool _same(String a, String b) =>
      a.toLowerCase().replaceAll(RegExp('[^0-9a-f]'), '') ==
      b.toLowerCase().replaceAll(RegExp('[^0-9a-f]'), '');

  /// Why the gateway picked [pickedMac], for the installer; null when there
  /// is nothing useful to say.
  String? get reasonText {
    if (pickedMac == null) return null;
    if (boundMac != null && _same(boundMac!, pickedMac!)) {
      return '已綁定這台，閘道器只連它';
    }
    return switch (selectReason) {
      'ok' => '門檻內訊號明顯最強',
      'ambiguous' => '附近訊號相近，閘道器暫選最強的一台',
      _ => null,
    };
  }

  static DirectStatus? from(Object? source) {
    if (source is! Map) return null;
    final state = DirectState.parse(source['state']);
    if (state == null) return null;
    final rows = source['candidates'];
    final ptuMac = source['ptu_mac'];
    return DirectStatus(
      state: state,
      minRssi: (source['min_rssi'] as num?)?.toInt(),
      boundMac: directBoundMacOf({'bound_mac': source['bound_mac']}),
      selectReason: source['select_reason']?.toString() ?? '',
      ptuMac: ptuMac is String && ptuMac.trim().isNotEmpty
          ? ptuMac.trim()
          : null,
      ptuRssi: (source['ptu_rssi'] as num?)?.toInt(),
      ptuDeviceNumber: (source['ptu_device_number'] as num?)?.toInt(),
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

/// Step 7 direct flow: shown when the gateway's pick is ambiguous.
const directAmbiguousText = '附近有訊號相近的 PTU，請按「辨識此樁」確認是否為眼前這台';

/// Beside 「辨識此樁」 right after the tap, before the ack.
const identifySentText = '已送出，請看樁上燈號';

/// Beside 「辨識此樁」 once the gateway acked. [ack] is the identify ack.
String identifyNoteText(Map<String, dynamic> ack) {
  final ptuWrite = ack['ptu_write'];
  if (ptuWrite != null && ptuWrite != 'ok') {
    return '已送出：只有閘道器在閃燈，PTU 未收到（$ptuWrite）';
  }
  final mac = ack['mac'];
  if (mac == null) return '$identifySentText（閘道器雙閃 6 秒）';
  final rssi = ack['rssi'];
  return '$identifySentText（PTU $mac${rssi is num ? ' · $rssi dBm' : ''}）';
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
