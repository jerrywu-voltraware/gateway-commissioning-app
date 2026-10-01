import 'protocol.dart';

/// The APP's own preference default (2026-10-01: 4, so the PTU packet is
/// `A2 04`). Distinct from [legacyBareIdentifySeconds].
const defaultIdentifySeconds = 4;

/// Firmware before PTU identify runs its bare identify for a fixed six
/// seconds (IDENTIFY_DEFAULT_MS); the APP cannot change that. Also what an
/// ack without any duration (such a bare ack) means.
const legacyBareIdentifySeconds = 6;

/// PTU identify packet `A2 xx` (2026-10-01): `A2 00` light off, `A2 01` light
/// stays ON until the next `A2 00` (it is NOT a 1-second blink), `A2 02..0A`
/// on for 2..10 seconds, then off by itself. So the only seconds the APP
/// offers or sends are 0 and 2..10; 1 and anything above 10 are rejected
/// explicitly, never clamped.
const minTimedIdentifySeconds = 2;
const maxIdentifySeconds = 10;

/// What an identify ack (or a stored log of one) may still carry: whole
/// seconds of a byte, as older firmware and 1.7.45 accept 0..255. Only the
/// ack parsing ([identifySecondsOf]) is this tolerant; the APP never sends
/// more than [maxIdentifySeconds].
const maxIdentifyAckSeconds = 255;

const identifySecondsPreference = 'identify_seconds';
const identifySecondsError = '請輸入 0（關燈）或 2–10 的整數秒數（1 秒會讓 PTU 燈恆亮，不提供）';

/// 0 (light off) or 2..10 (timed). 1 is the constant-on packet, so no.
bool isValidIdentifySeconds(int seconds) =>
    seconds == 0 ||
    (seconds >= minTimedIdentifySeconds && seconds <= maxIdentifySeconds);

int? parseIdentifySeconds(String text) {
  final value = text.trim();
  if (!RegExp(r'^[0-9]+$').hasMatch(value)) return null;
  final seconds = int.tryParse(value);
  return seconds != null && isValidIdentifySeconds(seconds) ? seconds : null;
}

/// The `a2_seconds` capability takes 0 (off) or 2..10 seconds, the same for
/// the gateway LED and the PTU; 1 would become `A2 01` (constant on), so it
/// is refused like everything else out of range. Older PTU-capable gateways
/// (3-byte packet) support only 1..30 seconds; pre-PTU gateways receive their
/// original bare identify (fixed six seconds, so the default 4 is refused
/// with `identify_duration_unsupported` there). Never clamp.
Map<String, dynamic> identifyCommandParams(
  Map<String, dynamic> config,
  int seconds, {
  String target = 'both',
}) {
  if (seconds < 0 || seconds > maxIdentifyAckSeconds) {
    throw const GatewayFailure('invalid_identify_seconds');
  }
  if (config['identify_ptu_supported'] != true) {
    if (seconds != legacyBareIdentifySeconds) {
      throw const GatewayFailure('identify_duration_unsupported');
    }
    return const {};
  }
  if (config['identify_ptu_protocol'] == 'a2_seconds') {
    // Never a duration_ms of 1000: the gateway turns it into `A2 01`.
    if (!isValidIdentifySeconds(seconds)) {
      throw const GatewayFailure('invalid_identify_seconds');
    }
    return {'target': target, 'duration_ms': seconds * 1000};
  }
  if (seconds == 0 || seconds > 30) {
    throw const GatewayFailure('identify_duration_unsupported');
  }
  return {'target': target, 'duration_ms': seconds * 1000};
}

int identifySecondsOf(Map<String, dynamic> ack) {
  final ms = ack['duration_ms'];
  if (ms is num &&
      ms.isFinite &&
      ms >= 0 &&
      ms <= maxIdentifyAckSeconds * 1000) {
    return (ms / 1000).ceil();
  }
  final seconds = ack['ptu_duration_s'];
  return seconds is int && seconds >= 0 && seconds <= maxIdentifyAckSeconds
      ? seconds
      : legacyBareIdentifySeconds;
}

String gatewayIdentifyText(Map<String, dynamic> ack) {
  if (ack['target'] == 'ptu') return '僅處理 PTU，閘道器燈號未變更';
  if (ack['gateway_led'] == 'unavailable') return '閘道器燈效無法使用';
  return identifySecondsOf(ack) == 0
      ? '閘道器已停止辨識，恢復正常燈號'
      : '閘道器雙閃 ${identifySecondsOf(ack)} 秒';
}
