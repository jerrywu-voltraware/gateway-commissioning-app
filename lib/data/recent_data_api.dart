/// 09-28 〔查看最近資料〕: the done page lets the installer confirm that the
/// back office receives this gateway's data without opening the dashboard
/// or typing a key — the APP's own (low-privilege) session asks the
/// read-only endpoint `GET /api/app/recent/{site}/{gateway}?limit=N`.
///
/// Contract (dashboard-api, fields fixed):
/// ```
/// {"site_id":80,"gateway_id":1,"count":2,
///  "items":[{"ts":"2026-09-28T13:00:00.123+08:00","seq":123,"device_id":1,
///            "ptu_mac":"90:5F:E8:9A:96:00","ptu_state":"POWER_TRANSFER",
///            "input_mv":5000,"input_ma":120,"bus_mv":4980,"temp_c":31}]}
/// ```
/// `count` 0 = nothing received yet; a non-2xx answer or no connection is
/// a [GatewayFailure] from [GatewayApi.request].
library;

import '../core/protocol.dart';
import 'contracts.dart';

/// How many rows the page asks for.
const recentDataLimit = 20;

/// One row of the recent data of a gateway.
class RecentItem {
  const RecentItem({
    required this.ts,
    this.seq,
    this.deviceId,
    this.ptuMac = '',
    this.ptuState = '',
    this.inputMv,
    this.inputMa,
    this.busMv,
    this.tempC,
  });

  /// Local time ([DateTime.parse] then [DateTime.toLocal]); null when the
  /// backend sent no parsable `ts`.
  final DateTime? ts;
  final int? seq, deviceId;
  final String ptuMac, ptuState;
  final num? inputMv, inputMa, busMv, tempC;

  /// The PTU's last 4 hex digits (`90:5F:E8:9A:96:00` → `9600`; widget
  /// keys).
  String get ptuTail => ptuMacTail(ptuMac);

  /// The PTU's last 3 groups (`90:5F:E8:9A:96:00` → `9A:96:00`; what the
  /// installer sees, 1.0.0+5).
  String get ptuShort => ptuMacShort(ptuMac);

  /// The PTU's whole MAC as `AA:BB:CC:DD:EE:FF` (empty when none).
  String get ptuMacText => ptuMacFull(ptuMac);

  /// `input_mv` in volts with two decimals, or `--`.
  String get inputVoltsText =>
      inputMv == null ? '--' : (inputMv! / 1000).toStringAsFixed(2);

  static RecentItem fromJson(Map<String, dynamic> json) => RecentItem(
    ts: parseRecentTs(json['ts']),
    seq: (json['seq'] as num?)?.toInt(),
    deviceId: (json['device_id'] as num?)?.toInt(),
    ptuMac: json['ptu_mac']?.toString() ?? '',
    ptuState: json['ptu_state']?.toString() ?? '',
    inputMv: json['input_mv'] as num?,
    inputMa: json['input_ma'] as num?,
    busMv: json['bus_mv'] as num?,
    tempC: json['temp_c'] as num?,
  );
}

/// The answer of the recent-data endpoint.
class RecentData {
  const RecentData({
    required this.siteId,
    required this.gatewayId,
    required this.count,
    required this.items,
    this.serverOffset,
  });

  final int siteId, gatewayId;

  /// 1.0.0+10: the back office's clock minus the phone's, from its answer's
  /// `Date` header ([ServerClock]); null when unknown (the phone's clock
  /// is used).
  final Duration? serverOffset;

  /// Rows the backend has (`count`); 0 = nothing received yet.
  final int count;
  final List<RecentItem> items;

  bool get isEmpty => count == 0 || items.isEmpty;

  /// The newest row's time (the list is newest first; any order accepted).
  DateTime? get latest {
    DateTime? best;
    for (final item in items) {
      final ts = item.ts;
      if (ts != null && (best == null || ts.isAfter(best))) best = ts;
    }
    return best;
  }

  /// A tolerant parse: `count` falls back to the number of items, rows
  /// without a `ts` are kept (shown as `--:--:--`).
  static RecentData fromJson(
    Map<String, dynamic> json, {
    int site = 0,
    int gateway = 0,
    Duration? serverOffset,
  }) {
    final raw = json['items'];
    final items = raw is List
        ? raw
              .whereType<Map>()
              .map((e) => RecentItem.fromJson(Map<String, dynamic>.from(e)))
              .toList()
        : const <RecentItem>[];
    return RecentData(
      siteId: (json['site_id'] as num?)?.toInt() ?? site,
      gatewayId: (json['gateway_id'] as num?)?.toInt() ?? gateway,
      count: (json['count'] as num?)?.toInt() ?? items.length,
      items: items,
      serverOffset: serverOffset,
    );
  }
}

/// `ts` as local time; null when it is not an ISO-8601 string.
DateTime? parseRecentTs(Object? ts) {
  if (ts is! String || ts.isEmpty) return null;
  try {
    return DateTime.parse(ts).toLocal();
  } on FormatException {
    return null;
  }
}

/// The last 4 hex digits of a MAC (separators ignored), upper case.
String ptuMacTail(String mac) {
  final hex = mac.replaceAll(RegExp(r'[^0-9A-Fa-f]'), '').toUpperCase();
  return hex.length <= 4 ? hex : hex.substring(hex.length - 4);
}

/// The hex digits of a MAC, upper case, no separators.
String _macHex(String mac) =>
    mac.replaceAll(RegExp(r'[^0-9A-Fa-f]'), '').toUpperCase();

/// The last 3 groups of a MAC with colons (`90:5F:E8:9A:96:00` →
/// `9A:96:00`; `905fe89a9600` too). Fewer than 6 hex digits: all of
/// them, grouped from the right; empty for none.
String ptuMacShort(String mac) {
  final hex = _macHex(mac);
  final tail = hex.length <= 6 ? hex : hex.substring(hex.length - 6);
  return _grouped(tail);
}

/// The whole MAC with colons (`905fe89a9600` → `90:5F:E8:9A:96:00`).
String ptuMacFull(String mac) => _grouped(_macHex(mac));

String _grouped(String hex) {
  final groups = <String>[];
  var end = hex.length;
  while (end > 0) {
    final start = end - 2 < 0 ? 0 : end - 2;
    groups.insert(0, hex.substring(start, end));
    end = start;
  }
  return groups.join(':');
}

/// `HH:mm:ss` of a local time; `--:--:--` for none.
String recentClockText(DateTime? ts) {
  if (ts == null) return '--:--:--';
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(ts.hour)}:${two(ts.minute)}:${two(ts.second)}';
}

/// 「最近一筆 N 秒前・共 count 筆」 (a future time counts as 0 seconds).
String recentSummaryText(RecentData data, DateTime now) {
  final latest = data.latest;
  final age = latest == null ? null : now.difference(latest).inSeconds;
  final ago = age == null ? '時間不明' : '${age < 0 ? 0 : age} 秒前';
  return '最近一筆 $ago・共 ${data.count} 筆';
}

/// The endpoint path for one gateway.
String recentDataPath(int site, int gateway, {int limit = recentDataLimit}) =>
    '/api/app/recent/$site/$gateway?limit=$limit';

/// The recent data of [site]/[gateway] through the APP's session.
/// Throws the [GatewayFailure] of [GatewayApi.request] (no session,
/// network, HTTP) — the page turns it into words with
/// [GatewayFailure.message].
Future<RecentData> fetchRecentData(
  GatewayApi api, {
  required int site,
  required int gateway,
  int limit = recentDataLimit,
}) async {
  final json = await api.request(
    'GET',
    recentDataPath(site, gateway, limit: limit),
  );
  // 1.0.0+10: the back office's clock as its answer's `Date` said.
  final offset = api is ServerClock
      ? (api as ServerClock).serverClockOffset
      : null;
  return RecentData.fromJson(
    json,
    site: site,
    gateway: gateway,
    serverOffset: offset,
  );
}

/// Words for a failed fetch: 「連不上後台（原因）」. 1.0.0+7: the pages log
/// in by themselves ([AppSession]), so a refused login is a reason like
/// any other — nobody is sent back to the done page any more.
String recentDataErrorText(Object error) =>
    '連不上後台（${recentDataErrorReason(error)}）';

/// The reason inside [recentDataErrorText].
String recentDataErrorReason(Object error) => switch (error) {
  GatewayFailure(code: 'authentication') => '後台拒絕此 APP 的登入憑證，請聯絡管理員更新 APP',
  GatewayFailure f => f.message,
  _ => '$error',
};
