import 'protocol.dart';

const defaultIdentifySeconds = 6;
const maxIdentifySeconds = 255;
const identifySecondsPreference = 'identify_seconds';
const identifySecondsError = '請輸入 0–255 的整數秒數';

int? parseIdentifySeconds(String text) {
  final value = text.trim();
  if (!RegExp(r'^[0-9]+$').hasMatch(value)) return null;
  final seconds = int.tryParse(value);
  return seconds != null && seconds >= 0 && seconds <= maxIdentifySeconds
      ? seconds
      : null;
}

/// The new capability also promises 0..255 seconds for the gateway LED.
/// Older PTU-capable gateways support only 1..30 seconds; pre-PTU gateways
/// receive their original bare identify (fixed six seconds). Never clamp.
Map<String, dynamic> identifyCommandParams(
  Map<String, dynamic> config,
  int seconds, {
  String target = 'both',
}) {
  if (seconds < 0 || seconds > maxIdentifySeconds) {
    throw const GatewayFailure('invalid_identify_seconds');
  }
  if (config['identify_ptu_supported'] != true) {
    if (seconds != defaultIdentifySeconds) {
      throw const GatewayFailure('identify_duration_unsupported');
    }
    return const {};
  }
  if (config['identify_ptu_protocol'] == 'a2_seconds') {
    return {'target': target, 'duration_ms': seconds * 1000};
  }
  if (seconds == 0 || seconds > 30) {
    throw const GatewayFailure('identify_duration_unsupported');
  }
  return {'target': target, 'duration_ms': seconds * 1000};
}

int identifySecondsOf(Map<String, dynamic> ack) {
  final ms = ack['duration_ms'];
  if (ms is num && ms.isFinite && ms >= 0 && ms <= 255000) {
    return (ms / 1000).ceil();
  }
  final seconds = ack['ptu_duration_s'];
  return seconds is int && seconds >= 0 && seconds <= maxIdentifySeconds
      ? seconds
      : defaultIdentifySeconds;
}

String gatewayIdentifyText(Map<String, dynamic> ack) {
  if (ack['target'] == 'ptu') return '僅處理 PTU，閘道器燈號未變更';
  if (ack['gateway_led'] == 'unavailable') return '閘道器燈效無法使用';
  return identifySecondsOf(ack) == 0
      ? '閘道器已停止辨識，恢復正常燈號'
      : '閘道器雙閃 ${identifySecondsOf(ack)} 秒';
}
