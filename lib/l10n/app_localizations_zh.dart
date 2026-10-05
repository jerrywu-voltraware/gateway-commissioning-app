// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appInfo_title => 'GIOS 設備助手';

  @override
  String assign_assigningResult(int id) {
    return '正在指派 #$id';
  }

  @override
  String get assign_notAssignedLink => '尚未指派（手機與閘道器斷線）';

  @override
  String get common_back => '返回';

  @override
  String get common_cancel => '取消';

  @override
  String get common_close => '關閉';

  @override
  String get common_confirm => '確認';

  @override
  String get common_continue => '繼續';

  @override
  String get common_copy => '複製';

  @override
  String get common_done => '完成';

  @override
  String get common_dotSeparator => '・';

  @override
  String get common_languageEnglish => 'English';

  @override
  String get common_languageZhHant => '繁體中文';

  @override
  String get common_loading => '讀取中…';

  @override
  String get common_ok => '確定';

  @override
  String get common_refresh => '重新整理';

  @override
  String get common_retry => '重試';

  @override
  String get common_settings => '設定';

  @override
  String get common_timeout => '逾時';

  @override
  String get common_unknown => '未知';

  @override
  String gatewayStatus_dataAgo(String age) {
    return '$age前';
  }

  @override
  String gatewayStatus_doneAt(String time) {
    return '$time 完成';
  }

  @override
  String get gatewayStatus_fleetEmpty => '後台目前沒有任何閘道器。';

  @override
  String get gatewayStatus_fleetTitle => '後台在線閘道器';

  @override
  String gatewayStatus_heartbeatAgo(String age) {
    return '心跳 $age前';
  }

  @override
  String get gatewayStatus_hint => '點一列即可查看該閘道器的最近資料。';

  @override
  String get gatewayStatus_homeCaption => '架設完後，看資料有沒有正常送到後台';

  @override
  String get gatewayStatus_label => '查看上傳資料';

  @override
  String get gatewayStatus_loading => '正在向後台查詢…';

  @override
  String gatewayStatus_name(int site, int gateway) {
    return '站 $site 閘道器 $gateway';
  }

  @override
  String get gatewayStatus_nearbyEmpty => '附近沒有掃到閘道器，請靠近後按〔重新掃描〕';

  @override
  String get gatewayStatus_nearbyScanFailed => '掃描失敗，請確認藍牙、定位與附近裝置權限後重試。';

  @override
  String get gatewayStatus_nearbyScanning => '正在掃描附近閘道器（約 8 秒）…';

  @override
  String get gatewayStatus_nearbyTitle => '附近閘道器（藍牙掃描）';

  @override
  String get gatewayStatus_nearbyUnconfigured => '尚未配置，無法查看資料';

  @override
  String get gatewayStatus_nearbyUnnamed => '尚未設定站號，無法查看資料';

  @override
  String get gatewayStatus_nearest => '最近';

  @override
  String get gatewayStatus_noData => '尚無資料';

  @override
  String get gatewayStatus_offline => '離線';

  @override
  String get gatewayStatus_online => '在線';

  @override
  String get gatewayStatus_openSettings => '開啟權限設定';

  @override
  String get gatewayStatus_ptuConnected => 'PTU 已連線';

  @override
  String get gatewayStatus_ptuDisconnected => 'PTU 未連線';

  @override
  String get gatewayStatus_recentEmpty => '這支手機尚未用此版本完成過配置';

  @override
  String get gatewayStatus_recentTitle => '最近配置（這支手機）';

  @override
  String get gatewayStatus_rescan => '重新掃描';

  @override
  String get mqttTarget_failBleOnly => '上傳目標只能在現場透過藍牙切換，不接受遠端指令。';

  @override
  String get mqttTarget_failBusy => '閘道器正在處理其他指令，請稍候重試。';

  @override
  String get mqttTarget_failInvalidHost =>
      '閘道器拒絕切換：本地後端位址必須是區網私有 IPv4（10.x、172.16–31.x、192.168.x），不可使用主機名稱或公網 IP。';

  @override
  String get mqttTarget_failInvalidParams => '閘道器拒絕切換：指令參數格式錯誤。請更新 APP 後重試。';

  @override
  String get mqttTarget_failInvalidPort => '閘道器拒絕切換：MQTT 連接埠必須是 1–65535 的整數。';

  @override
  String get mqttTarget_failInvalidReqId => 'APP 送出的指令編號無效，請重新連線後重試。';

  @override
  String get mqttTarget_failInvalidTarget => '閘道器拒絕切換：上傳目標名稱無效。請更新 APP 後重試。';

  @override
  String get mqttTarget_failNoReason => '閘道器拒絕切換上傳目標（未提供原因）。';

  @override
  String get mqttTarget_failNotReady => '閘道器仍在開機初始化，請稍候數秒後重試。';

  @override
  String get mqttTarget_failNvsWrite =>
      '閘道器儲存設定失敗，上傳目標未變更、也沒有重新開機。請重試；若持續失敗請回報。';

  @override
  String get mqttTarget_failOtaInProgress =>
      '閘道器正在更新韌體（OTA），更新完成前無法切換上傳目標，請稍後重試。';

  @override
  String get mqttTarget_failOther => '閘道器拒絕切換上傳目標。';

  @override
  String get mqttTarget_failOtpInvalid => '一次性密碼（OTP）錯誤，閘道器拒絕切換。';

  @override
  String get mqttTarget_failOtpLocked => 'OTP 錯誤次數過多，閘道器暫時鎖定，請稍後再試。';

  @override
  String get mqttTarget_failOtpRequired =>
      '此閘道器已啟用一次性密碼（OTP），切換上傳目標需要 OTP，請聯絡管理員。';

  @override
  String get mqttTarget_failOtpReused => '此一次性密碼已使用過，請等下一組 OTP 後重試。';

  @override
  String get mqttTarget_failTimeNotSynced =>
      '閘道器已啟用 OTP 但時間尚未同步（NTP），無法驗證。若目前 Wi-Fi 無法連到網際網路，請先改用可連外的網路。';

  @override
  String get mqttTarget_failUnknownOp => '閘道器韌體不支援切換上傳目標，需更新至 1.7.3 以上。';

  @override
  String mqttTarget_legacyFirmware(String version) {
    return '這台閘道器韌體太舊（版本 $version），只能送到正式站，請更新到 1.7.3 以上。';
  }

  @override
  String mqttTarget_localHost(String host) {
    return '本地 $host';
  }

  @override
  String mqttTarget_localHostNotPrivate(String host) {
    return '本地測試站網址的主機「$host」不是區網私有 IPv4 位址（10.x.x.x、172.16–31.x.x、192.168.x.x），閘道器無法上傳到此後端。請把網址改成電腦的區網 IP。';
  }

  @override
  String mqttTarget_localHostPort(String host, String port) {
    return '本地 $host:$port';
  }

  @override
  String get mqttTarget_localUrlEmpty => '尚未輸入本地測試站網址，無法決定閘道器的上傳目標。';

  @override
  String mqttTarget_localUrlUnparsable(String url) {
    return '本地測試站網址「$url」無法解析主機位址，請輸入如 http://192.168.1.10:18000 的網址。';
  }

  @override
  String mqttTarget_plainLocal(String host) {
    return '本地測試主機（$host）';
  }

  @override
  String get mqttTarget_plainProduction => '正式站';

  @override
  String get mqttTarget_production => '正式站';

  @override
  String mqttTarget_productionHostPort(String host, String port) {
    return '正式站 $host:$port';
  }

  @override
  String mqttTarget_reportLegacy(String version) {
    return '資料上傳目標：正式站（韌體 $version 固定）';
  }

  @override
  String mqttTarget_reportLine(String where) {
    return '資料上傳目標：$where';
  }

  @override
  String mqttTarget_reportNote(String warning) {
    return '注意：$warning';
  }

  @override
  String get mqttTarget_reportUnconfirmed => '資料上傳目標：未確認';

  @override
  String get mqttTarget_shipWarning => '此閘道器目前上傳到本地測試站，出貨前請切回正式站。';

  @override
  String get settings_language => '語言';
}
