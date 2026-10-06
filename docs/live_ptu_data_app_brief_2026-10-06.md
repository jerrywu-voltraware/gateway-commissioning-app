# APP 實作簡報：現場除錯 PTU 即時讀值（方案 A 加速上傳＋方案 B 藍牙直讀）— 2026-10-06

寫給在 Mac 上接手 APP_v2 的 AI。使用者（10-06）決定 A、B 兩個都做；韌體與後台由公司機 session 實作，本檔只講 APP 要做的事與對外契約。主設計文件在公司機 `F:\iot_gateway\docs\design\ble_live_ptu_data_2026-10-06.md`（不在 git），本檔自足。行號以 APP_v2 fc489aa 為準。

## 0. 為什麼
「查看上傳資料」不管從「附近閘道器（藍牙掃描）」或「後台在線閘道器」進入，都是 `RecentDataPage.open(site, gateway)` → `GET /api/app/recent`（`lib/presentation/gateway_status_page.dart:514,590`、`recent_data_page.dart:360`），資料新舊受後台上傳頻率政策 N 控制，現場除錯太慢。A 讓閘道器暫時每 1 秒上傳並自動輪詢；B 直接經藍牙讀閘道器記憶體裡每個 PTU 的最新一筆。

## 1. 方案 A：〔加速 5 分鐘〕（只動 APP；後台提供端點）

### 1.1 後台契約
- 既有 `POST /api/app/build-mode/{site}/{gateway}`（無 body；APP key 可用；`DashboardApi.request` 既有路徑 `buildModeFallbackPath`，`lib/application/commissioning_controller.dart:1418`）。成功 `200 {"sent":true,"req_id":"…"}`。錯誤：`404 gateway_not_found`、`409 gateway_offline`、`409 command_in_flight`、`429 rate_limited`（同台 60 秒一次）、`503 mqtt_not_connected`。效果：閘道器改成每 1 秒上傳（`ds_min_ms=ds_max_ms=1000`）。
- **新增** `POST /api/app/build-mode/{site}/{gateway}/end`（公司機實作中；APP key 可用）：立即把全站政策值推回該台。回 `200 {"sent":true|false,"reason":"pushed|deduped|offline|test_mode|session_active|not_in_fleet|mqtt_not_connected"}`；`sent:false` 不是錯誤（後台巡檢會在 ≤ 約 11 分鐘補推）；503 ＝ MQTT 服務未建。
- 不要走藍牙 `set_config`：OTP 啟用時 APP 簽不了（`commissioning_controller.dart:4598`），而且會跟配置流程搶同一條 `BleGatewayLink`。APP 既有程式從不送政策值（`:1507-1511`），維持這個原則。

### 1.2 UI 與行為
- AppBar actions（`recent_data_page.dart:391-398`）加〔加速 5 分鐘〕（`Key('recent-boost')`）；加速中變〔停止加速〕。
- 按下 → POST build-mode → 成功則副標題區（`:417-427` 與 `_Banner` 之間）顯示「加速中・剩 m:ss・閘道器每 1 秒上傳」，每 **2 秒**重抓 `fetchRecentData`（`lib/data/recent_data_api.dart:262`，limit 20）。
- 輪詢用本頁既有的世代號＋`mounted` 模式（`_generation`／`_load()`，`recent_data_page.dart:332-378`）加 `Timer.periodic`；dispose 取消。**不要**用控制器的步驟 9 迴圈（它打 `/api/latest`，形狀不同，`commissioning_controller.dart:9905,10122`）。
- 結束條件任一：倒數到 0、〔停止加速〕、dispose、APP 進背景 >30 秒（`WidgetsBindingObserver`）。結束 → POST end（10 秒逾時）→ `sent:true`「已送回政策值」、`sent:false`／失敗「由後台巡檢在 10 分鐘內恢復」。
- 錯誤文案（ARB `recentDataPage_boost*`）：`gateway_offline`「閘道器未連上後台，無法加速；可改用藍牙即時」；`rate_limited`「60 秒內已送過，請稍候」；`command_in_flight`「閘道器忙碌中，請稍候重試」；503「後台 MQTT 未連線」；其他「加速失敗：{code}」。
- 常數集中：`recentBoostDuration = 5 min`、`recentBoostPoll = 2 s`、`recentBoostBackgroundGrace = 30 s`。
- 練習模式（`DemoSystem`，`lib/data/demo_system.dart`）：build-mode 回 `sent:true`，end 回 `sent:true reason:pushed`，資料照常。

### 1.3 測試
- widget：按鈕 → `paths` 含 build-mode → 2 秒後第二次 recent → 倒數文字 → 〔停止加速〕→ `paths` 含 `/end`；dispose 也送 end；各錯誤碼文案；`sent:false` 文案。
- mock 用 `test/recent_data_test.dart:71-105` 的 `_Api implements GatewayApi`（記錄 `paths`，`gate` 可卡回應）。

## 2. 方案 B：〔藍牙即時〕（韌體 1.7.47 新指令 `get_ptu_data`）

### 2.1 指令契約（以韌體 `docs/cmd_contract.md` 為準；此處為 2026-10-06 設計 v1）
- 送：`link.command('get_ptu_data')`，可帶 `{"slot": 0..4}` 只取一槽、`{"all": true}` 連無資料槽也列。唯讀，不需 ts／OTP。
- ack 同其他 op：`{req_id, status:"ok"|"fail", result:<JSON 字串>, ts}`；`BleGatewayLink.command` 已會把 `result` 字串 jsonDecode（`lib/data/ble_gateway_link.dart:808` 附近）。
- 成功 result：
  ```json
  {"mode":"normal","upload_paused":false,"uptime_ms":123456789,"max_connections":1,
   "devices":[{"slot":0,"device_id":1,"connected":true,"rssi":-61,
               "age_ms":850,"received_at_ms":123455939,
               "ptu":{"state":"POWER_TRANSFER","vin_mv":53200,"iin_ma":1403,"vbus_mv":…,"ampTemp_c":59,"mac":"DF:B0:25:F3:40:AC", …},
               "pru":{"iout_ma":1051, …vrect／溫度／mac 等鍵名同上傳 record…},
               "err":{"num":0,"data":0,"limit":0}}]}
  ```
  **韌體 1.7.47（commit 8fede6d）實作後的修正**：錯誤欄位是巢狀 `err{num,data,limit}`（與上傳 record 相同），不是頂層 `error_num`；PTU 未連線時 `device_id` 為 `null`；`slot` 固定有值。`errorNum = err.num`。以韌體 `docs/cmd_contract.md` §2／§9 為準。
  - `ptu`／`pru` 物件鍵名**與閘道器上傳到後台的 record 完全相同**（契約 §4.4）；後台 `ingest/ingest.py:675-700` 有 record 鍵 → DB 欄位的對應表（例 `pru.iout_ma → pru_iout`），拿它當 `RecentItem` 欄位對應的依據。
  - `devices` 預設只含已連線或 `age_ms` < 60000 的槽；測試模式 `mode` ≠ `normal` 時為空陣列。
  - 沒有 `device_seq`、`crc16`、`measure_ts_ms`；時間一律用 `age_ms`（現在 − 收到時間）。
  - 失敗 result：`ptu_data_unavailable`、`bad_slot`。
- 大小約每槽 0.5–0.6 KB，5 槽約 3 KB，分片約 0.4 秒送完；`JsonFrames` 上限 64 KB 可收（`lib/core/protocol.dart:403-454`）。
- 韌體端對藍牙來源的這個 op **不會**另外回 MQTT ack，APP 1 Hz 輪詢不會灌後台。

### 2.2 進入方式與 link 共用
- `gateway_status_page.dart:460` `_nearbyTile(p)` 有 `GatewayPeer p`（`lib/data/contracts.dart:1-5`：`id`（Android MAC／iOS UUID）、`name`、`rssi`）。改 `RecentDataPage.open(context, site, gateway, {GatewayPeer? peer})`（`recent_data_page.dart:308-324`）；後台清單與完成頁（`commissioning_page.dart:4381`）不傳 peer。
- 只有 `peer != null` 才顯示來源切換〔後台〕／〔藍牙即時〕（`Key('recent-source')`，SegmentedButton 放副標題列）。
- 全 APP 只有一條 `BleGatewayLink`（`linkProvider`，`commissioning_controller.dart:55`）；`connect` 會 `_invalidate` 清掉進行中 pending（`ble_gateway_link.dart:436`），進行中 lifecycle 回 `busy`（`:430`）。規則：
  1. 若 link 目前已連著同一台（比對 `peer.id`；需要在 `GatewayLink` 介面加 `String? get connectedId` 或等價查詢），**直接重用**，離開頁面**不**斷線（連線屬於配置流程）。
  2. 否則 `connect(peer)`；離開頁面或切回〔後台〕時 `disconnect()`。
  3. `busy` → 顯示「藍牙忙碌中（配置流程使用中），先用後台資料」，停在〔後台〕。
- 控制器 dispose 會 disconnect（`commissioning_controller.dart:2706`）：從完成頁重用連線時，若控制器先 dispose，本頁要能偵測斷線並顯示「藍牙已斷開」＋〔重新連線〕。

### 2.3 輪詢與顯示
- 每 **1 秒**送 `get_ptu_data`；前一個未回就跳過該拍（`_tail` 是序列佇列，`ble_gateway_link.dart:743-828`）。`commandTimeout`（`lib/core/protocol.dart:54-63`）加 `get_ptu_data: 5 s`。
- 每個 device 轉成 `RecentItem`（`lib/data/recent_data_api.dart:30,93-108`）：`ts = now − age_ms`、`deviceId = device_id`、`ptuMac = ptu.mac`、`ptuState = ptu.state`、`inputMv = ptu.vin_mv`、`inputMa = ptu.iin_ma`、`busMv = ptu.vbus_mv`、`tempC = ptu.ampTemp_c`、`pruIoutMa = pru.iout_ma`、`pruVrectMv`／`pruTempC`／`pruMac` 依 ingest 對應表、`errorNum = err.num`（巢狀 `err` 物件）；`device_id` 可能為 null（未連線槽，只在 `all:true` 時出現）。寫成 `RecentItem.fromLiveDevice(Map device, DateTime now)` 並單元測試。
- 重用「最新一筆」卡片與 PTU 分組（`recentLatestPerDevice` `:227`、`recentDeviceKey` `:222`、`_LatestCard` `:616`）。效率、錯誤碼說明、PRU MAC 照現有邏輯。
- 橫幅（`Key('recent-banner')` 同 key、kind 加 `live`）：「藍牙即時・N 秒前」；`age_ms` < 10 s 綠、< 60 s 黃、否則紅；`upload_paused:true` 加一行「閘道器上傳暫停中（藍牙資料仍即時）」；`devices` 空「閘道器目前沒有 PTU 資料」；連線中「藍牙連線中…」。
- 歷史表在藍牙模式顯示本次收到的最近 20 拍（記憶體 ring，每拍每台一列，`seq` 用拍數），不打後台；切回〔後台〕清掉 ring 並重新 `fetchRecentData`。
- `FieldReporter.noteRecentDataViewed()` 照舊只在 session 開著時送（`README.md` 現場回報段）。

### 2.4 測試
- BLE mock 參考 `test/upload_policy_test.dart:43-103` `_DsGateway extends PickGateway`（覆寫 `command`，`sent(op)` 驗證）；`DemoSystem` 同時實作 `GatewayLink` 與 `GatewayApi`（`demo_system.dart:12,383`），練習模式讓 `get_ptu_data` 回每台已連線 PTU 一筆。
- 必測：peer 有無決定切換是否出現；重用連線不斷線／新連線離開斷線；busy 文案；1 Hz 跳拍；欄位對應（含 mac 大小寫與 `pru_Temp_degC` 鍵）；年齡顏色三段；空清單；`upload_paused` 文案；斷線後〔重新連線〕。
- **必跑回歸**（`AGENTS.md:12-21`）：「手機中途斷線」與「殺 APP 續作」兩組既有測試。

## 3. i18n 與交付規範（`docs/i18n.md`）
- 只改 `lib/l10n/parts/recentDataPage_zh.arb` 與 `_en.arb`（key `recentDataPage_boost*`、`recentDataPage_live*`），`py -3 -X utf8 tools/merge_l10n.py` → `flutter gen-l10n` → `flutter analyze` → `flutter test test/l10n_test.dart`；交付前 `merge_l10n.py --check --check-buttons`。按鈕名在句中用方括號。
- `flutter analyze` 不得新增 issue（目前 6 個既有）；全套 `flutter test` 不得多出失敗（已知 12 個，見 `docs/handoff_mac_2026-10-06_build53.md`）。
- 版本：不要自行改 pubspec 版號；Build 54 由使用者決定時再改（`gateway-commissioning-releases/docs/APP_RELEASE_MANUAL.md` 基準 53／下一版 54）。
- 契約若與韌體實作有出入，以韌體 repo `docs/cmd_contract.md` 為準並回報差異，不要自行猜欄位。

## 4. 完成定義
- A：裝手機對 81/1 按〔加速 5 分鐘〕，看到每 2 秒更新、倒數、5 分鐘後或停止後後台把政策值推回（上傳頻率頁的「已套用」回到政策值）。
- B：韌體 1.7.47 燒到一台閘道器後，從藍牙清單進入切〔藍牙即時〕，每秒更新；關掉閘道器 Wi-Fi 仍更新；離開頁面不影響配置流程。
- 兩者皆：測試全綠（扣既有已知）、analyze 無新增、l10n 檢查過、`README.md` 查看上傳資料段補 A／B 說明。
