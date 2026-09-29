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

/// 1.0.0+12 (field: a gateway with an old test identity 80/2 left in its
/// NVS was listed as 「站 80 · 閘道器 2」 although the back office had no
/// 80/2): the title of a gateway known not to be configured — 「未配置閘道器
/// …3A00」 with its Wi-Fi MAC tail ([tail], as the list shows it), never a
/// station or number.
const unconfiguredGatewayText = '未配置閘道器';

/// 「未配置閘道器 …3A00」, or 「未配置閘道器」 without a MAC [tail].
String unconfiguredGatewayTitle(String? tail) => tail == null || tail.isEmpty
    ? unconfiguredGatewayText
    : '$unconfiguredGatewayText $tail';

/// 1.0.0+12: the advertising name carries the factory identity 1/1.
bool isFactoryGatewayName(String? name) {
  final id = parseGatewayName(name);
  return id != null && id.site == 1 && id.gateway == 1;
}

/// 1.0.0+12: the Wi-Fi MAC tail of [unconfiguredGatewayTitle] — 「…70F0」
/// ([gatewayWifiMac]); null when neither [uid] nor [bleId] is a MAC.
String? gatewayTailText({Object? uid, String? bleId}) {
  final wifi = gatewayWifiMac(uid: uid, bleId: bleId);
  return wifi == null ? null : '…${wifi.substring(8)}';
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

/// Round 28 (field: the list read 「MAC 後 4 碼 70F2」, the help panel and
/// the back office 「70F0」 for the same gateway): the gateway's Wi-Fi MAC
/// — the identity the back office shows (`gateway_uid`, heartbeats, the
/// rescue page) — derived from its Bluetooth MAC [bleId]. The firmware
/// uses the ESP32's four universal MAC addresses
/// (`CONFIG_ESP32_UNIVERSAL_MAC_ADDRESSES_FOUR`): Wi-Fi STA = the base MAC,
/// Bluetooth = the base MAC + 2 on its last byte. 12 upper-case hex digits;
/// null when [bleId] is not a MAC (e.g. an iOS peripheral UUID).
String? wifiMacFromBle(String? bleId) {
  if (macTail(bleId) == null) return null;
  final hex = bleId!.replaceAll(RegExp('[^0-9a-fA-F]'), '').toUpperCase();
  final last = (int.parse(hex.substring(10), radix: 16) - 2) & 0xFF;
  return '${hex.substring(0, 10)}${last.toRadixString(16).padLeft(2, '0').toUpperCase()}';
}

/// Round 28: the gateway's Wi-Fi MAC (12 upper-case hex digits) — [uid]
/// (`gateway_uid` read over Bluetooth, or remembered from an earlier
/// connect) when known, else derived from its Bluetooth MAC [bleId]
/// ([wifiMacFromBle]); null when neither is a MAC.
String? gatewayWifiMac({Object? uid, String? bleId}) {
  final known = gatewayMacKey(uid);
  return known.isNotEmpty ? known : wifiMacFromBle(bleId);
}

/// Round 28: the gateway's MAC tail as the back office shows it — its
/// Wi-Fi MAC ([gatewayWifiMac]) — with the Bluetooth tail the phone sees
/// in brackets when it differs: 「MAC 後 4 碼 70F0（藍牙 70F2）」 ([withBle]
/// false: the Wi-Fi tail only); null when neither [uid] nor [bleId] is a
/// MAC.
String? gatewayMacText({Object? uid, String? bleId, bool withBle = true}) {
  final wifi = gatewayWifiMac(uid: uid, bleId: bleId);
  if (wifi == null) return null;
  final ble = withBle ? macTail(bleId) : null;
  final tail = wifi.substring(8);
  return ble == null || ble == tail
      ? 'MAC 後 4 碼 $tail'
      : 'MAC 後 4 碼 $tail（藍牙 $ble）';
}

/// 1.0.0+8: the gateway list's short form — 「MAC …70F0」 (the Wi-Fi MAC's
/// last 4 digits, as the back office shows it); null when neither [uid]
/// nor [bleId] is a MAC.
String? gatewayMacTail({Object? uid, String? bleId}) {
  final wifi = gatewayWifiMac(uid: uid, bleId: bleId);
  return wifi == null ? null : 'MAC …${wifi.substring(8)}';
}

/// The connected gateway in the page header: its configured identity
/// (get_config, which follows a site change at once) or else its name,
/// the MAC tail and the firmware. Round 28: the Wi-Fi MAC tail
/// (`gateway_uid`, as the back office and the help panel show it —
/// [gatewayMacText]; the gateway list adds the Bluetooth tail).
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
  return [
    title,
    ?gatewayMacText(uid: config['gateway_uid'], bleId: id, withBle: false),
    if (fw.isNotEmpty) fw,
  ].join(' · ');
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
/// step 8's join_fleet resumes it), so that is not a problem
/// ([uploadHeldUntilJoin]).
bool uploadPausedProblem(Map<String, dynamic> config) =>
    config['fleet_joined'] == true && config['upload_paused'] == true;

/// Round 28 (field: pile B — a new identity, upload paused until
/// join_fleet — read 「✓ 資料上傳中」 at steps 5 and 6 although not one row
/// could be uploaded): a gateway not in service yet (`fleet_joined` false,
/// e.g. after set_site_identity or leave_fleet) whose upload is paused.
/// That is on purpose until the commissioning sends join_fleet, so it is
/// not a problem to fix here ([uploadPausedProblem] stays false) — but it
/// is never 「資料上傳中」 either: connected to the broker means heartbeats
/// only ([uploadHeldText], [uploadHeldStatus]).
bool uploadHeldUntilJoin(Map<String, dynamic> config) =>
    config['fleet_joined'] != true && config['upload_paused'] == true;

/// Round 28: the network check's upload line for [uploadHeldUntilJoin].
///
/// Round 30 (user rehearsal 09-27, E: 「✓ 已連上後台；PTU 資料上傳暫停中…」
/// — a ✓ beside 「暫停」 read as a fault; the installer waited 95 s and
/// asked for help): says the pause is normal and what to press.
const uploadHeldText = '後台連線正常。PTU 資料會在完成配置後自動開始上傳（目前暫停是正常的），APP 會自動繼續';

/// Round 30: 確認資料上傳's (controller step 3) retry, in the bottom bar.
/// 09-28: named after its action (no 「下一步：…」 labels).
const confirmOnlineLabel = '確認閘道器上線';

/// Round 28: the 「連線狀態」 gateway row for [uploadHeldUntilJoin].
const uploadHeldStatus = '✓ 已連上（完成配置後才上傳）';

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
