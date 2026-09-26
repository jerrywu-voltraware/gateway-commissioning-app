/// Field rescue v1 (PLAN_2026-09-26_FIELD_RESCUE.md §2.4 `commands`, §2.5):
/// the last 30 commands the APP sent — BLE ops to the gateway and its own
/// backend requests — for the diagnostics package. Secrets are masked the
/// moment an entry is recorded; raw BLE frames and HTTP bodies are never
/// kept.
library;

import 'dart:convert';

/// Ring size (the contract's `commands` maxItems).
const journalCapacity = 30;

/// `commands[].result` is cut to this many characters.
const journalResultLimit = 300;

/// `commands[].error` is cut to this many characters.
const journalErrorLimit = 200;

/// Mask for a secret value.
const redactedValue = '***';

/// Keys whose values are secrets (§2.5; the backend applies the same rule).
final secretKeyPattern = RegExp(
  r'pass|pwd|secret|token|otp|api[_-]?key|authorization|cookie',
  caseSensitive: false,
);

/// Shortest string [scrubSecrets] replaces inside other text (a shorter one
/// would mask ordinary words and numbers).
const secretMinLength = 4;

/// A value under a secret key that is masked: a non-empty string, a number,
/// a non-empty map or list. A flag or null (e.g. `otp_enabled: false`) is a
/// state, not a secret — the backend's second pass uses the same rule, so
/// it finds nothing left to mask.
bool isSecretValue(Object? value) {
  if (value == null || value is bool) return false;
  if (value is String) return value.isNotEmpty && value != redactedValue;
  if (value is Map) return value.isNotEmpty;
  if (value is List) return value.isNotEmpty;
  return true;
}

/// [value] with every secret value ([isSecretValue]) under a
/// [secretKeyPattern] key replaced by [redactedValue], recursively. Other
/// values are kept as they are.
Object? redactKeys(Object? value) {
  if (value is Map) {
    return {
      for (final e in value.entries)
        e.key.toString():
            secretKeyPattern.hasMatch(e.key.toString()) &&
                isSecretValue(e.value)
            ? redactedValue
            : redactKeys(e.value),
    };
  }
  if (value is List) return [for (final v in value) redactKeys(v)];
  return value;
}

/// §2.5: the params of [op] as they may be stored — `set_wifi` keeps only
/// its `ssid` (the password becomes [redactedValue]); any secret key is
/// masked.
Map<String, dynamic> redactParams(String op, Map<String, dynamic> params) {
  if (op == 'set_wifi') {
    return {
      if (params.containsKey('ssid')) 'ssid': params['ssid'],
      if (params.containsKey('password')) 'password': redactedValue,
    };
  }
  return Map<String, dynamic>.from(redactKeys(params) as Map);
}

/// String values of [params] under secret keys (what [redactParams] hides):
/// remembered in memory so the same text is masked wherever else it shows.
Iterable<String> secretValues(String op, Map<String, dynamic> params) sync* {
  for (final e in params.entries) {
    final secret =
        (op == 'set_wifi' && e.key != 'ssid') ||
        secretKeyPattern.hasMatch(e.key);
    final value = e.value;
    if (secret && value is String && value.length >= secretMinLength) {
      yield value;
    }
  }
}

/// [value] with every occurrence of any of [secrets] inside its strings
/// replaced by [redactedValue], recursively.
Object? scrubSecrets(Object? value, Iterable<String> secrets) {
  final list = [
    for (final s in secrets)
      if (s.length >= secretMinLength) s,
  ];
  if (list.isEmpty) return value;
  Object? walk(Object? v) {
    if (v is String) {
      var out = v;
      for (final s in list) {
        if (out.contains(s)) out = out.replaceAll(s, redactedValue);
      }
      return out;
    }
    if (v is Map) {
      return {for (final e in v.entries) e.key.toString(): walk(e.value)};
    }
    if (v is List) return [for (final x in v) walk(x)];
    return v;
  }

  return walk(value);
}

String? _cut(String? text, int limit) {
  if (text == null) return null;
  final flat = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  return flat.length > limit ? '${flat.substring(0, limit - 1)}…' : flat;
}

/// `HH:mm:ss.SSS` of [time] (phone clock).
String journalTime(DateTime time) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(time.hour)}:${two(time.minute)}:${two(time.second)}'
      '.${time.millisecond.toString().padLeft(3, '0')}';
}

/// One `commands[]` item.
class JournalEntry {
  JournalEntry({
    required this.time,
    required this.channel,
    required this.op,
    required this.status,
    this.params,
    this.durMs,
    this.httpStatus,
    this.result,
    this.error,
  });

  final DateTime time;

  /// `ble` or `http`.
  final String channel;

  /// BLE op, or `METHOD /path` (no query).
  final String op;

  /// `ok` / `fail` / `timeout` / `error` / `busy_retry`.
  String status;
  final Map<String, dynamic>? params;
  int? durMs;
  final int? httpStatus;
  String? result;
  final String? error;

  /// Consecutive 'busy' answers merged into this entry.
  int busyCount = 0;

  Map<String, dynamic> toJson() => {
    't': journalTime(time),
    'ch': channel,
    'op': op,
    if (params != null) 'params': params,
    'status': status,
    if (durMs != null) 'dur_ms': durMs,
    if (channel == 'http') 'http_status': httpStatus,
    if (result != null) 'result': result,
    if (error != null) 'error': error,
  };
}

/// Ring buffer of the last [journalCapacity] commands.
class CommandJournal {
  CommandJournal({DateTime Function()? now}) : _now = now ?? DateTime.now;

  final DateTime Function() _now;
  final List<JournalEntry> _entries = [];
  final Set<String> _secrets = {};

  /// Secret values seen in params (memory only, never sent).
  Set<String> get secrets => Set.unmodifiable(_secrets);

  /// Remembers [value] as a secret (e.g. the backend password).
  void addSecret(String? value) {
    if (value != null && value.length >= secretMinLength) _secrets.add(value);
  }

  List<JournalEntry> get entries => List.unmodifiable(_entries);

  void _add(JournalEntry entry) {
    _entries.add(entry);
    if (_entries.length > journalCapacity) {
      _entries.removeRange(0, _entries.length - journalCapacity);
    }
  }

  String? _summary(Object? result) {
    if (result == null) return null;
    Object? masked = redactKeys(result);
    masked = scrubSecrets(masked, _secrets);
    final text = masked is String ? masked : _encode(masked);
    return _cut(text, journalResultLimit);
  }

  static String _encode(Object? value) {
    try {
      return jsonEncode(value);
    } catch (_) {
      return value.toString();
    }
  }

  /// A BLE command to the gateway. [status]: `ok`, `fail` (the gateway's
  /// fail ack), `timeout`, `error` (link / APP) or `busy` — consecutive
  /// busy answers to the same op become one `busy_retry` entry (×n).
  void ble(
    String op,
    Map<String, dynamic> params, {
    required String status,
    int? durMs,
    Object? result,
    Object? error,
  }) {
    _secrets.addAll(secretValues(op, params));
    if (status == 'busy') {
      final last = _entries.isEmpty ? null : _entries.last;
      if (last != null &&
          last.channel == 'ble' &&
          last.op == op &&
          last.status == 'busy_retry') {
        last.busyCount++;
        last.durMs = (last.durMs ?? 0) + (durMs ?? 0);
        last.result = 'busy ×${last.busyCount}';
        return;
      }
      _add(
        JournalEntry(
          time: _now(),
          channel: 'ble',
          op: op,
          params: redactParams(op, params),
          status: 'busy_retry',
          durMs: durMs,
          result: 'busy ×1',
        )..busyCount = 1,
      );
      return;
    }
    _add(
      JournalEntry(
        time: _now(),
        channel: 'ble',
        op: op,
        params: redactParams(op, params),
        status: status,
        durMs: durMs,
        result: _summary(result),
        error: _cut(
          error == null
              ? null
              : scrubSecrets(error.toString(), _secrets) as String?,
          journalErrorLimit,
        ),
      ),
    );
  }

  /// A backend request made for the commissioning itself (never the
  /// reporter's own uploads). Only `METHOD /path` is kept: no query, no
  /// body.
  void http(
    String method,
    String path, {
    required String status,
    int? httpStatus,
    int? durMs,
    Object? error,
  }) {
    final clean = Uri.tryParse(path)?.path ?? path.split('?').first;
    _add(
      JournalEntry(
        time: _now(),
        channel: 'http',
        op: _cut('$method $clean', 96)!,
        status: status,
        httpStatus: httpStatus,
        durMs: durMs,
        error: _cut(
          error == null
              ? null
              : scrubSecrets(error.toString(), _secrets) as String?,
          journalErrorLimit,
        ),
      ),
    );
  }

  /// The entries as `commands[]` (oldest first).
  List<Map<String, dynamic>> snapshot() => [
    for (final e in _entries) e.toJson(),
  ];

  /// The newest entry as the session report's `last_command` (null when
  /// none). [now] for `age_s`.
  Map<String, dynamic>? lastCommand(DateTime now) {
    if (_entries.isEmpty) return null;
    final e = _entries.last;
    final status = switch (e.status) {
      'busy_retry' => 'fail',
      final s => s,
    };
    return {
      'op': e.op,
      'status': status,
      if (e.durMs != null) 'dur_ms': e.durMs,
      'age_s': now.difference(e.time).inSeconds.clamp(0, 1 << 30),
    };
  }

  void clear() => _entries.clear();
}
