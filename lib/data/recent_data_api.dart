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

  /// The PTU's last 4 hex digits (`90:5F:E8:9A:96:00` → `9600`).
  String get ptuTail => ptuMacTail(ptuMac);

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
  });

  final int siteId, gatewayId;

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
  return RecentData.fromJson(json, site: site, gateway: gateway);
}

/// Words for a failed fetch: the failure's own text, or a generic one.
String recentDataErrorText(Object error) => switch (error) {
  GatewayFailure(code: 'authentication') =>
    'APP 尚未登入後台，請回到完成頁按「登入並確認資料」後再試。',
  GatewayFailure f => f.message,
  _ => '無法取得最近資料：$error',
};
