/// Round 26 multi-gateway field test (two gateways side by side):
///
/// * gateway names — the list showed 「GIOS-S80-G…」 twice; a gateway reads
///   「站 80 · 閘道器 2」 plus its MAC tail instead ([gatewayTitle]);
/// * another gateway is never a PTU — firmware before 1.7.38 listed a
///   neighbouring gateway's own Bluetooth advertisement (`GIOS-S20-GW01`,
///   number 0, strongest) as an unassigned PTU and, in direct mode,
///   connected to it ([isGatewayName], [splitGatewayRows]);
/// * test mode and a paused upload — an old gateway in test mode only
///   generates test data and never scans PTUs, one with a paused upload
///   sends heartbeats but no PTU data ([isTestMode], [uploadPausedProblem]).
///
/// Pure Dart so every rule can be unit-tested without widgets.
library;

/// `GIOS-S{site}-GW{nn}`: the gateway's Bluetooth advertising name.
final gatewayNamePattern = RegExp(
  r'^GIOS-S(\d+)-GW(\d+)',
  caseSensitive: false,
);

/// Site and gateway number in a gateway's advertising name; null when the
/// name does not follow `GIOS-S{site}-GW{nn}` or carries no identity yet
/// (site or gateway 0).
({int site, int gateway})? parseGatewayName(String? name) {
  final match = gatewayNamePattern.firstMatch(name?.trim() ?? '');
  if (match == null) return null;
  final site = int.tryParse(match.group(1)!);
  final gateway = int.tryParse(match.group(2)!);
  if (site == null || gateway == null || site <= 0 || gateway <= 0) {
    return null;
  }
  return (site: site, gateway: gateway);
}

/// 「站 80 · 閘道器 2」.
String gatewayIdText(int site, int gateway) => '站 $site · 閘道器 $gateway';

/// A gateway row's title: 「站 80 · 閘道器 2」 when the name parses, else the
/// full name (never cut).
String gatewayTitle(String name) {
  final id = parseGatewayName(name);
  return id == null ? name : gatewayIdText(id.site, id.gateway);
}

/// Last 4 hex digits of a MAC address (「70F2」); null when [id] is not a
/// 6-byte MAC (e.g. an iOS peripheral UUID).
String? macTail(String? id) {
  final raw = (id ?? '').trim();
  if (!RegExp(r'^[0-9a-fA-F]{2}([:-]?[0-9a-fA-F]{2}){5}$').hasMatch(raw)) {
    return null;
  }
  final hex = raw.replaceAll(RegExp('[^0-9a-fA-F]'), '');
  return hex.substring(8).toUpperCase();
}

/// 「MAC 後 4 碼 70F2」; null when [id] is not a MAC.
String? macTailText(String? id) {
  final tail = macTail(id);
  return tail == null ? null : 'MAC 後 4 碼 $tail';
}

/// The connected gateway in the page header: its configured identity
/// (get_config, which follows a site change at once) or else its name,
/// the MAC tail and the firmware.
String gatewayHeaderText({
  required String name,
  required String id,
  Map<String, dynamic> config = const {},
}) {
  final site = (config['site_id'] as num?)?.toInt() ?? 0;
  final gateway = (config['gateway_id'] as num?)?.toInt() ?? 0;
  final title = site > 0 && gateway > 0
      ? gatewayIdText(site, gateway)
      : gatewayTitle(name);
  final fw = config['fw_version']?.toString() ?? '';
  return [title, ?macTailText(id), if (fw.isNotEmpty) fw].join(' · ');
}

// ---- Another gateway is not a PTU ----

/// A Bluetooth name that belongs to a gateway, never a PTU: the gateway
/// naming rule `GIOS-S{site}-GW{nn}`, or any name starting with `GIOS-S`
/// (the prefix the APP's own gateway list uses; PTUs advertise
/// `GIOS0403ST`-style names).
bool isGatewayName(Object? name) {
  if (name is! String) return false;
  final text = name.trim();
  return gatewayNamePattern.hasMatch(text) ||
      text.toUpperCase().startsWith('GIOS-S');
}

/// 12 upper-case hex digits of a MAC, '' when it is not one.
String gatewayMacKey(Object? mac) {
  final hex = (mac?.toString() ?? '').replaceAll(RegExp('[^0-9a-fA-F]'), '');
  return hex.length == 12 ? hex.toUpperCase() : '';
}

/// PTU rows ([ptus]) and the rows that are gateways ([gateways]): named
/// like a gateway ([isGatewayName]) or with a MAC [isGatewayMac] knows.
({List<Map<String, dynamic>> ptus, List<Map<String, dynamic>> gateways})
splitGatewayRows(
  Iterable<Map<String, dynamic>> rows,
  bool Function(String mac) isGatewayMac,
) {
  final ptus = <Map<String, dynamic>>[];
  final gateways = <Map<String, dynamic>>[];
  for (final row in rows) {
    final mac = row['mac']?.toString() ?? '';
    if (isGatewayName(row['name']) || isGatewayMac(mac)) {
      gateways.add(row);
    } else {
      ptus.add(row);
    }
  }
  return (ptus: ptus, gateways: gateways);
}

/// The gateway's direct-mode report (`get_status.direct`) without other
/// gateways: candidates and neighbours that are gateways are dropped, and
/// a pick that is a gateway reads as no pick (`no_candidate`, no `ptu_*`),
/// so it is never shown or confirmed as this pile's PTU. [dropped] lists
/// the gateway MACs removed; [pickedGateway] is the gateway the report
/// named as its pick (null: none).
({Map<String, dynamic> direct, List<String> dropped, String? pickedGateway})
directWithoutGateways(
  Map<String, dynamic> direct,
  bool Function(String mac) isGatewayMac,
) {
  final dropped = <String>[];
  List<dynamic>? clean(Object? rows) {
    if (rows is! List) return null;
    final kept = <dynamic>[];
    for (final row in rows) {
      final mac = row is Map ? row['mac']?.toString() ?? '' : '';
      if (mac.isNotEmpty && isGatewayMac(mac)) {
        dropped.add(mac);
      } else {
        kept.add(row);
      }
    }
    return kept;
  }

  final out = Map<String, dynamic>.of(direct);
  final candidates = clean(direct['candidates']);
  if (candidates != null) out['candidates'] = candidates;
  final neighbors = clean(direct['neighbors']);
  if (neighbors != null) out['neighbors'] = neighbors;
  final picked = direct['ptu_mac'];
  String? pickedGateway;
  if (picked is String && picked.trim().isNotEmpty && isGatewayMac(picked)) {
    pickedGateway = picked.trim();
    dropped.add(pickedGateway);
    out
      ..remove('ptu_mac')
      ..remove('ptu_rssi')
      ..remove('ptu_device_number');
    if (out['state'] == 'connected' || out['state'] == 'connecting') {
      out['state'] = 'no_candidate';
    }
  }
  return (direct: out, dropped: dropped, pickedGateway: pickedGateway);
}

const _directGatewayPickHead = '閘道器連到的是附近另一台閘道器';

/// Yellow direct-mode notice: the gateway connected another gateway.
String directGatewayPickText(String mac) =>
    '$_directGatewayPickHead（$mac），不是 PTU，APP 不會把它當成 PTU。'
    '請按「不是這台？」改選同樁的 PTU，或靠近同樁 PTU 後按「重新搜尋」。';

/// [text] is a [directGatewayPickText] (for any MAC).
bool isDirectGatewayPickText(String text) =>
    text.startsWith(_directGatewayPickHead);

// ---- Test mode and a paused upload (get_config `mode` / `upload_paused`) ----

/// get_config / get_ble_devices `mode` is `test`: the firmware only
/// generates test data and never scans or connects PTUs.
bool isTestMode(Map<String, dynamic> source) =>
    source['mode']?.toString().trim().toLowerCase() == 'test';

/// A gateway already in service (fleet_joined) whose upload is paused:
/// heartbeats still reach the back office, PTU data does not. A gateway
/// not in service yet is paused on purpose (set_site_identity pauses it;
/// step 8's join_fleet resumes it), so that is not a problem.
bool uploadPausedProblem(Map<String, dynamic> config) =>
    config['fleet_joined'] == true && config['upload_paused'] == true;

/// Test-mode card and the error that replaces 「PTU 沒有回應」 in test mode.
const testModeText = '這台閘道器處於測試模式（只產生測試資料、不會連 PTU），配置前需切回正常模式。';

/// Under [testModeText]: what the switch does.
const testModeActionHint = '切回後閘道器會重新開機（約 1 分鐘），APP 會自動重新連線並繼續。';

/// The button of the test-mode card.
const leaveTestModeLabel = '切回正常模式';

/// Busy text while switching.
const leavingTestModeText = '正在把閘道器切回正常模式（會重新開機，約 1 分鐘）';

/// After the switch.
const leftTestModeText = '閘道器已切回正常模式並重新連上，可以繼續配置。';

/// Network check / status panel line in test mode.
const testModeUploadText = '閘道器在測試模式：只上傳測試資料，不會上傳 PTU 資料。';

/// Upload paused: the network check line and the card.
const uploadPausedText = '閘道器已連上後台，但資料上傳已暫停：PTU 資料不會送出。請按「恢復上傳」。';

/// 連線狀態 panel hints (short: the card above says the whole thing).
const testModeStatusHint = '閘道器在測試模式（只產生測試資料），請按「$leaveTestModeLabel」。';
const uploadPausedStatusHint = '閘道器的資料上傳已暫停，PTU 資料不會送出；請按「$resumeUploadLabel」。';

/// The button that sends set_data_upload enabled.
const resumeUploadLabel = '恢復上傳';

/// Busy text while resuming.
const resumingUploadText = '正在恢復資料上傳';

/// After a resume the gateway confirmed.
const uploadResumedText = '已恢復資料上傳，閘道器開始送出 PTU 資料。';
