// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appInfo_title => 'GIOS Device Assistant';

  @override
  String assign_assigningResult(int id) {
    return 'Assigning #$id';
  }

  @override
  String get assign_notAssignedLink => 'Not assigned (phone lost the gateway)';

  @override
  String get common_back => 'Back';

  @override
  String get common_cancel => 'Cancel';

  @override
  String get common_close => 'Close';

  @override
  String get common_confirm => 'Confirm';

  @override
  String get common_continue => 'Continue';

  @override
  String get common_copy => 'Copy';

  @override
  String get common_done => 'Done';

  @override
  String get common_dotSeparator => ' · ';

  @override
  String get common_languageEnglish => 'English';

  @override
  String get common_languageZhHant => '繁體中文';

  @override
  String get common_loading => 'Loading…';

  @override
  String get common_ok => 'OK';

  @override
  String get common_refresh => 'Refresh';

  @override
  String get common_retry => 'Retry';

  @override
  String get common_settings => 'Settings';

  @override
  String get common_timeout => 'timed out';

  @override
  String get common_unknown => 'unknown';

  @override
  String gatewayStatus_dataAgo(String age) {
    return '$age ago';
  }

  @override
  String gatewayStatus_doneAt(String time) {
    return 'Done $time';
  }

  @override
  String get gatewayStatus_fleetEmpty => 'The back office has no gateways yet.';

  @override
  String get gatewayStatus_fleetTitle => 'Gateways in the back office';

  @override
  String gatewayStatus_heartbeatAgo(String age) {
    return 'Heartbeat $age ago';
  }

  @override
  String get gatewayStatus_hint =>
      'Tap a row to see that gateway\'s recent data.';

  @override
  String get gatewayStatus_homeCaption =>
      'After setup, check that data reaches the back office';

  @override
  String get gatewayStatus_label => 'View uploaded data';

  @override
  String get gatewayStatus_loading => 'Checking the back office…';

  @override
  String gatewayStatus_name(int site, int gateway) {
    return 'Site $site Gateway $gateway';
  }

  @override
  String get gatewayStatus_nearbyEmpty =>
      'No gateway found nearby. Move closer and tap [Rescan].';

  @override
  String get gatewayStatus_nearbyScanFailed =>
      'Scan failed. Check Bluetooth, Location and Nearby devices permissions, then retry.';

  @override
  String get gatewayStatus_nearbyScanning =>
      'Scanning for nearby gateways (about 8 s)…';

  @override
  String get gatewayStatus_nearbyTitle => 'Nearby gateways (Bluetooth scan)';

  @override
  String get gatewayStatus_nearbyUnconfigured =>
      'Not set up yet, no data to view';

  @override
  String get gatewayStatus_nearbyUnnamed =>
      'No site number yet, no data to view';

  @override
  String get gatewayStatus_nearest => 'Nearest';

  @override
  String get gatewayStatus_noData => 'No data yet';

  @override
  String get gatewayStatus_offline => 'Offline';

  @override
  String get gatewayStatus_online => 'Online';

  @override
  String get gatewayStatus_openSettings => 'Open permission settings';

  @override
  String get gatewayStatus_ptuConnected => 'PTU connected';

  @override
  String get gatewayStatus_ptuDisconnected => 'PTU not connected';

  @override
  String get gatewayStatus_recentEmpty =>
      'No setup finished on this phone with this version yet';

  @override
  String get gatewayStatus_recentTitle => 'Recent setups (this phone)';

  @override
  String get gatewayStatus_rescan => 'Rescan';

  @override
  String get mqttTarget_failBleOnly =>
      'The upload target can only be switched on site over Bluetooth, not by remote command.';

  @override
  String get mqttTarget_failBusy =>
      'The gateway is busy with another command. Wait and retry.';

  @override
  String get mqttTarget_failInvalidHost =>
      'Gateway refused the switch: the local backend address must be a private LAN IPv4 (10.x, 172.16–31.x, 192.168.x), not a host name or public IP.';

  @override
  String get mqttTarget_failInvalidParams =>
      'Gateway refused the switch: bad command parameters. Update the APP and retry.';

  @override
  String get mqttTarget_failInvalidPort =>
      'Gateway refused the switch: the MQTT port must be a whole number from 1 to 65535.';

  @override
  String get mqttTarget_failInvalidReqId =>
      'The APP sent an invalid command number. Reconnect and retry.';

  @override
  String get mqttTarget_failInvalidTarget =>
      'Gateway refused the switch: invalid upload target name. Update the APP and retry.';

  @override
  String get mqttTarget_failNoReason =>
      'The gateway refused to switch the upload target (no reason given).';

  @override
  String get mqttTarget_failNotReady =>
      'The gateway is still starting up. Wait a few seconds and retry.';

  @override
  String get mqttTarget_failNvsWrite =>
      'The gateway could not save the setting. The upload target did not change and it did not restart. Retry; report it if this keeps failing.';

  @override
  String get mqttTarget_failOtaInProgress =>
      'The gateway is updating its firmware (OTA). The upload target cannot change until it finishes. Retry later.';

  @override
  String get mqttTarget_failOther =>
      'The gateway refused to switch the upload target.';

  @override
  String get mqttTarget_failOtpInvalid =>
      'Wrong one-time password (OTP); the gateway refused the switch.';

  @override
  String get mqttTarget_failOtpLocked =>
      'Too many wrong OTPs; the gateway is locked for a while. Try again later.';

  @override
  String get mqttTarget_failOtpRequired =>
      'This gateway has one-time passwords (OTP) on. Switching the upload target needs an OTP; contact your admin.';

  @override
  String get mqttTarget_failOtpReused =>
      'This one-time password was already used. Wait for the next OTP and retry.';

  @override
  String get mqttTarget_failTimeNotSynced =>
      'The gateway has OTP on but its clock is not synced (NTP), so it cannot check the OTP. If this Wi-Fi has no internet, switch to a network that does.';

  @override
  String get mqttTarget_failUnknownOp =>
      'This gateway firmware cannot switch the upload target. Update it to 1.7.3 or later.';

  @override
  String mqttTarget_legacyFirmware(String version) {
    return 'This gateway\'s firmware is too old (version $version) and can only send to production. Update it to 1.7.3 or later.';
  }

  @override
  String mqttTarget_localHost(String host) {
    return 'Local $host';
  }

  @override
  String mqttTarget_localHostNotPrivate(String host) {
    return 'The host \"$host\" in the local test server URL is not a private LAN IPv4 address (10.x.x.x, 172.16–31.x.x, 192.168.x.x), so the gateway cannot upload to it. Use the computer\'s LAN IP in the URL.';
  }

  @override
  String mqttTarget_localHostPort(String host, String port) {
    return 'Local $host:$port';
  }

  @override
  String get mqttTarget_localUrlEmpty =>
      'No local test server URL entered, so the gateway\'s upload target cannot be decided.';

  @override
  String mqttTarget_localUrlUnparsable(String url) {
    return 'Cannot read a host from the local test server URL \"$url\". Enter a URL like http://192.168.1.10:18000.';
  }

  @override
  String mqttTarget_plainLocal(String host) {
    return 'the local test server ($host)';
  }

  @override
  String get mqttTarget_plainProduction => 'the production server';

  @override
  String get mqttTarget_production => 'Production';

  @override
  String mqttTarget_productionHostPort(String host, String port) {
    return 'Production $host:$port';
  }

  @override
  String mqttTarget_reportLegacy(String version) {
    return 'Upload target: production (fixed by firmware $version)';
  }

  @override
  String mqttTarget_reportLine(String where) {
    return 'Upload target: $where';
  }

  @override
  String mqttTarget_reportNote(String warning) {
    return 'Note: $warning';
  }

  @override
  String get mqttTarget_reportUnconfirmed => 'Upload target: not confirmed';

  @override
  String get mqttTarget_shipWarning =>
      'This gateway uploads to a local test server. Switch it back to production before shipping.';

  @override
  String get settings_language => 'Language';
}
