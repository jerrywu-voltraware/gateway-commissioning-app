# GIOS Commissioning

後端選單為「VPS 正式站／本地測試站／其他網址」。本地預設 `http://192.168.0.12:18000`，手機與電腦連同一區域網路即可，不需USB。網址可修改並記住。APP 不再請派工人員輸入後台密碼：後台憑證在建置時注入（見下方「後台憑證」），沒有注入的建置會顯示「此建置缺少後台憑證，請重新建置」。本地版建置需 `--dart-define=LOCAL_DEVELOPMENT=true`，只允許私有IPv4／loopback使用HTTP，正式站仍使用HTTPS。電腦IP改變時需更新本地網址。Windows若阻擋手機連線，請以系統管理員PowerShell執行後端 `tools/allow_local_api_lan.ps1`；僅放行本地子網的TCP 18000。

Gateway 上傳目標（韌體 1.7.3 起，契約見韌體 docs/mqtt_target.md）：連上 Gateway 後會顯示「Gateway 上傳目標」卡片，比對 Gateway 的 MQTT 目標與 APP 連線環境（正式站→production；本地測試站→後端網址主機，須為私有 IPv4，port 8883；其他網址→私有 IPv4 為本地、正式網域為正式站，其餘僅顯示）。不一致時可經確認後以 BLE `set_mqtt_target` 切換（OTP 規則同 set_wifi），Gateway 重開機後 APP 自動重連並讀回確認。第 7 步若 Gateway 已知目標與 APP 環境不一致會立即停止並說明原因。舊韌體無此欄位時只顯示不支援提示。本地後端需同時開放 TCP 8883（MQTT TLS）。

Android 新站開通 APP，保留原 APP 與 GIOS0901_APP 作參考。資料流為 presentation → Riverpod controller → GatewayLink／GatewayApi；正式BLE與模擬系統使用同一介面。

```powershell
flutter pub get
flutter analyze
flutter test
flutter build apk --debug --dart-define=DEMO_MODE=true
```

## 建置交付 APK（tools/build_apk.ps1）

交給現場或測試的 APK 一律用這支腳本產出，不要直接交 `flutter build apk` 的輸出：release 設定 `signingConfig = null`，Gradle 產物 `build\app\outputs\flutter-apk\app-release.apk` 未簽章，手機裝不上（`INSTALL_PARSE_FAILED_NO_CERTIFICATES`）；少了 `LOCAL_DEVELOPMENT=true` 則連本地後台會被擋「正式環境需要有效的 HTTPS 網址」（第二十輪實例）。

```powershell
# 本地測試版：帶 LOCAL_DEVELOPMENT=true（可連區網 HTTP 後台），debug.keystore 簽章
powershell -ExecutionPolicy Bypass -File tools\build_apk.ps1 -Env local -OutDir <輸出資料夾>
# 正式版：不帶 LOCAL_DEVELOPMENT（只允許 HTTPS），需正式 keystore
powershell -ExecutionPolicy Bypass -File tools\build_apk.ps1 -Env prod -OutDir <輸出資料夾>
```

- 輸出 `app_<git短hash>_<env>.apk`（未給 `-OutDir` 時放 `build\dist\`），最後印出簽章憑證 SHA-256 與 APK 的 sha256。任何一步失敗（含 `apksigner verify`）即 exit 1，不留半成品。
- 工作目錄有未提交的修改會拒絕（檔名的 hash 對不上內容）；純測試可加 `-AllowDirty`，檔名變成 `app_<hash>-dirty_<env>.apk`。
- `local`：用 `%USERPROFILE%\.android\debug.keystore`（alias `androiddebugkey`），與第十九／二十輪現場 APK 同一張憑證（SHA-256 `bea4c874…25ef`），可 `adb install -r` 直接覆蓋安裝。換一台電腦若 debug.keystore 不同，腳本會警告：覆蓋安裝會失敗，請複製原 keystore 或先解除安裝。
- `prod`：讀 `android\key.properties`（`storeFile`、`storePassword`、`keyAlias`、`keyPassword`；`storeFile` 相對路徑以 `android\app` 為基準；此檔已在 .gitignore）或環境變數 `GIOS_KEYSTORE`、`GIOS_KEYSTORE_PASS`、`GIOS_KEY_ALIAS`、`GIOS_KEY_PASS`。沒有設定就在建置前直接失敗並提示，不會產出未簽章 APK，也拒絕用 debug 憑證簽正式版。密碼經環境變數交給 apksigner，不出現在命令列。
- 交付前自行核對：`apksigner verify --print-certs <apk>`（Android SDK `build-tools\<版本>\apksigner.bat`）。

### 後台憑證（`.secrets\<env>.env`，不進 git）

現場 APP 不再輸入後台密碼（09-28）。`build_apk.ps1` 從 `APP_v2\.secrets\local.env`（`-Env local`）或 `APP_v2\.secrets\prod.env`（`-Env prod`）讀取憑證，缺檔或缺值就在建置前失敗。`.secrets/` 已在 .gitignore；值不要寫進任何進 git 的檔案、log 或報告。

```text
# APP_v2\.secrets\local.env（KEY=VALUE，一行一個；# 開頭為註解）
APP_BACKEND_KEY=<後台 .env.local 的 APP_API_KEY>
```

- `prod.env` 同格式，值為正式站 `.env` 的 `APP_API_KEY`。值不可含空白。
- 腳本把值寫進 `build\` 下的暫存 JSON，以 `--dart-define-from-file` 交給 flutter（等同 `--dart-define=APP_BACKEND_KEY=...`，但值不出現在命令列與輸出），建置後立即刪除。
- APP 用它向 `POST /api/auth/app-login` 換 token，token 照舊存安全儲存區（12 小時）。後台 `APP_API_KEY` 只放行 APP 配置用到的端點（dashboard-api `app_key_auth.py`），其他管理端點回 403。
- 可選欄位（沒有就不帶）：`API_BASE=https://<host>`（正式站 API base，`--dart-define=API_BASE`）、`API_CERT_SHA256=<64 位 hex，可含冒號>`（`--dart-define=API_CERT_SHA256`：對正式站主機只接受 SHA-256 指紋完全相符的伺服器憑證，不查系統信任，自簽憑證可用；其他主機與未設定時維持系統信任，本地 http 不受影響）。指紋取法：`openssl s_client -connect <ip>:443 </dev/null | openssl x509 -fingerprint -sha256 -noout`。
- `API_CA_FILE=<CA 憑證 PEM 路徑>`（r33，09-28 起正式站用這個）：腳本讀檔轉 base64，以 `--dart-define=API_CA_PEM_B64` 注入；APP 對正式站用 `SecurityContext(withTrustedRoots: true)` 加信任這張 CA，走正常憑證鏈驗證（含 IP SAN），不用 badCertificateCallback 放行，自簽或別的 CA 簽的憑證一律握手失敗。正式站 nginx 憑證由 IoTGateway-CA 簽發（`E:\iot_gateway\MariaDb_Contabo_Server_Master\mosquitto\certs\ca.crt`，到 2036-02-10），`.secrets\prod.env`／`prodtest.env` 已設定。
- **`API_CERT_SHA256` 的適用範圍**：與 `API_CA_FILE` 同時設定時是額外 pinning——握手後比對 leaf（`SecureSocket.peerCertificate`），兩者都要過；**單獨設定**時是舊的 pinning（不查系統信任、比對 badCertificateCallback 收到的那張），**只適用伺服器只送一張自簽憑證**：伺服器送「leaf＋CA」鏈時 Dart 交給 callback 的是 CA，leaf 指紋永遠不符（r33 登入失敗的原因），所以正式站現在不要單獨用它。
- `-Env prodtest`（**過渡用**）：讀 `.secrets\prodtest.env`（需有 `API_BASE`），用 debug keystore 簽章（同 local，可覆蓋安裝），但**不帶** `LOCAL_DEVELOPMENT`（只走 HTTPS），供正式站只有 IP＋自簽憑證期間做端到端測試。這不是正式版：正式發佈仍須 `-Env prod` 與 release keystore。
- 自己 `flutter run` 測真後台時可加 `--dart-define=APP_BACKEND_KEY=<值>`；不加就是「缺少後台憑證」的畫面。

`DEMO_MODE=true` 完全使用模擬BLE／API，安裝報告會標示模擬。不加此旗標即使用真實BLE。通訊套件已改為 `universal_ble 2.3.0`（BSD-3-Clause，允許免費商用），不再需要 FBP 商用授權旗標。授權全文保存在 `THIRD_PARTY_NOTICES.md`，發佈時應隨附。

API預設 `https://dashboard.voltraware.com`，可在畫面改設定。預設僅系統TLS信任，不繞過憑證；設定 `API_CA_FILE` 時正式站另外信任該 CA（正常鏈驗證）；`API_CERT_SHA256` 為可選的 leaf 指紋 pinning（見上）。`LOCAL_DEVELOPMENT=true` 才允許localhost／127.0.0.1／Android emulator localhost的HTTP；真機連本機可用adb reverse測試。WiFi密碼不落地；以建置憑證換得的 token 存安全儲存區。


Android minSdk24，Gradle release 輸出不簽章，交付 APK 由 `tools/build_apk.ps1` 簽章並驗證（見上）。正式keystore與發佈程序仍待備妥；目前只能產出 local 版作開發測試。

Wi-Fi 名稱下方可掃描手機周邊的 2.4 GHz 網路，依訊號排序，同名合併；選取後填入SSID，密碼仍需輸入。需開啟手機Wi-Fi、定位服務並允許精確位置。系統限制重複掃描時會提示稍候重試；隱藏SSID可手動輸入。手機掃描結果不保證Gateway所在位置也收得到訊號。

協定沿用韌體NUS UUID、JSON envelope與字串result，單一指令queue；req_id關聯ACK、UTF-8 byte framing、逾時清空。v1.7採get_net_status，舊版退回get_status；舊版無NTP時敏感命令可能被拒，畫面提供升級指引。OTP已啟用時拒絕敏感操作。

現場流程：登入／離線 → 掃描Gateway → 身份及WiFi → 上線確認 → 選PTU → 編號與連線數read-back → 連續三次後端更新 → 報告／健康。第一版不涵蓋補機／換機／移機。實機與長時間驗收見上一層 `REWRITE_ACCEPTANCE.md`。

## 閘道器搜尋與辨識

進入選擇閘道器畫面會持續搜尋，找到裝置立即顯示並可點選；連線前、切到背景或離開畫面會停止搜尋。列表採精簡排列，可依名稱或位址篩選，RSSI 更新不改變列表順序。最近成功讀取身分的 5 台裝置會保留在手機，練習模式與真實裝置分開保存。最近清單可直接嘗試重連，未收到廣播不代表關機。

列表分開顯示兩種狀態：
- RSSI 隨藍牙廣播更新；10 秒未收到廣播會從附近列表移除，最近使用的裝置保留並顯示「未收到廣播」。手動停止搜尋後保留最後結果，不代表即時訊號。被其他手機連線的裝置可能不再廣播。
- 「後端回報在線上／離線」使用目前登入環境的 fleet-status，每 15 秒更新。僅用曾透過 BLE get_config 驗證的 gateway_uid 對應後端 last_seen_mac；新裝置、未登入、讀取失敗、重複或衝突資料顯示未知，不依廣播名称推測。

支援 identify_supported 的韌體在連線後提供「辨識這台・雙閃 6 秒」。辨識效果為每秒兩次短閃，結束後恢復原有呼吸／恆亮狀態。舊韌體仍可連線，畫面提示更新後才支援雙閃。這次不包含 QR Code 功能。

## 星狀 PTU 綁定名單（韌體 1.7.36 起）

修第 25 輪 P0「星狀連錯樁」（閘道器只看編號，把附近帶舊編號的外來 PTU 當成自己的連走）。韌體契約見 `ble_multi_wifi_gateway/docs/cmd_contract.md` §3B（`star_macs`）。韌體 1.7.37 起名單未設定時只看編號、`assign_device_id` 不會建立名單，所以由 APP 寫入：

- **指派前先送（第 27 輪）**：第 7 步按「配置」後、第一個 `assign_device_id` 之前，APP 先送 `set_config {"star_macs":[…]}`＝這台閘道器的目標清單（本次勾選的 PTU＋先前已配置在本機、這次沒動的 PTU：已列入名單的，或名單尚未設定時編號在範圍內且唯一的已連線 PTU；與勾選 PTU 同編號的不列；最多 5 台），再用 `get_config` 讀回核對。閘道器會斷開不在名單的連線（APP 以 `get_ble_devices` 等最多 5 秒），外來同編號 PTU 佔滿 5 格時指派才不會 `No free slot`；名單生效後外來 PTU 的編號不再算「已被佔用」。「重新連線並繼續」「重試這 N 台」也會先送。失敗自動重試 3 次，仍失敗時第 7/8 步提示「PTU 綁定名單未寫入，繼續配置…」並照常指派（不阻塞）。
- **驗證後送最終名單**：星狀第 9 步資料驗證通過、完成頁出現後，APP 以 `get_ble_devices` 回讀本機範圍內（#起始～+4）的 PTU，再送一次名單並讀回核對。名單＝本次勾選／指派／核對過的 PTU（含中斷後續作前已完成的）、指派前清單中沒動的 PTU（這時沒連線也保留）、閘道器已列入名單的，以及名單尚未生效時編號在範圍內且唯一的已連線 PTU；**移除指派失敗、驗證時略過（未驗證）、以及本次先勾後取消的 PTU**；一個編號只列一台，本次的優先。只在 `fw_version` ≥ 1.7.36 時送（1.7.36「自動收編」與 1.7.37「明確設定」送出內容相同；舊韌體會把未知參數算 rejected）；直連模式不送。
- **失敗不阻塞完成**：自動重試 3 次（間隔 2 秒），仍失敗時完成頁顯示「PTU 綁定名單未寫入，請重試」與「重試寫入綁定名單」按鈕；安裝報告另有一行「PTU 綁定名單：已寫入 #…／未寫入」。
- **直連切回星狀**：第 8 步把 `max_connections` 由 1 改成星狀時（直連期間名單不會更新，舊名單會擋掉新選的 PTU），緊接著以本次選定的 PTU 重送名單，再 `join_fleet`；失敗時第 7/8 步提示「驗證完成後會再寫一次」。
- **外來 PTU 提示**：星狀 PTU 列表讀 `get_status.star.foreign_ptus` 與 `get_ble_devices` 的 `star_enforced`／`star_listed`，有忽略中的同編號 PTU 時顯示「附近有 N 台編號相同的其他 PTU，已被閘道器忽略（不會連線）」等人話提示，不顯示韌體代碼。
- 程式：`lib/core/star_allow_list.dart`（`starTargetList`／`starAllowList` 規則與文字）、`CommissioningController._starListBeforeAssign`／`writeStarList`；測試 `test/round26_star_macs_test.dart`、`test/round27_star_before_assign_test.dart`。

## 一對一：本樁 PTU 不在場（r34，APP 1.0.0+2）

配置完成後本樁 PTU 壞掉或被拿走時，現場人員再連同一台閘道器，第 2 步（找到閘道器）直接處理，不必走到第 7 步才看到「綁定的 PTU 不在場」。

- **顯示條件**（`CommissioningController._checkBoundPtu`）：閘道器 `fleet_joined`、`direct_autoconnect_supported`、`max_connections == 1`、`get_config.direct_bind_mac` 非空，且 `get_status.direct.state` 不是 `connected`（`bound_missing`／`scanning`／`connecting`；契約 `ble_multi_wifi_gateway/docs/cmd_contract.md` §3A 狀態字串、Level 3 `get_status` 的 `direct{state,bound_mac,ptu_mac}`）。已綁定且 PTU 在場不顯示；未綁定仍走 round 28 的〔辨識並綁定〕卡。
- **卡片**（`Key('ptu-missing')`）：「本樁 PTU 不在場（綁定 MAC 後 4 碼 xxxx）」＋〔更換 PTU〕（confirm 後送 `set_config {"direct_bind_mac": ""}`，再沿用目前站點到第 7 步，不重輸站號；`replaceBoundPtu`）與〔PTU 已上電，重新檢查〕（再讀 `get_status`，連上即轉綠「PTU 已連線」；`recheckBoundPtu`）。
- **現場回報**：卡片出現時送一筆 `status` 事件，`error_message` 為「本樁 PTU 不在場：閘道器綁定 …」（`FieldReporter.noteDirectPtuMissing`），後台救援頁時間軸看得到。
- 測試：`test/round34_ptu_missing_test.dart`。

## 完成頁〔查看最近資料〕（09-28，APP 1.0.0+3；畫面改版 1.0.0+4；使用者實機回饋修正 1.0.0+5）

現場人員配置完想確認資料真的進了後台，不必登入後台網頁、不必給 key：完成頁底部多一顆〔查看最近資料〕（`Key('done-recent')`），開新頁「站 S 閘道器 G 最近資料」，用 APP 自己的低權限 session 查後台唯讀端點。

- **後台契約**：`GET {API_BASE}/api/app/recent/{site_id}/{gateway_id}?limit=20`，header `X-API-Key`（沿用 `DashboardApi.request`，正式站走 `cert_pin.dart` 的 CA 信任）；回 `{site_id, gateway_id, count, items:[{ts, seq, device_id, ptu_mac, ptu_state, input_mv, input_ma, bus_mv, temp_c}]}`。`count` 0 ＝ 後台尚未收到資料；非 2xx／連不上 ＝ 錯誤。
- **畫面**（`lib/presentation/recent_data_page.dart`，1.0.0+4 改版：現場人員只要看「資料有沒有進來、最新一筆、PTU 正不正常」；1.0.0+5 依使用者實機回饋：拔掉折線圖、表格 360 dp 不再被切、PTU 改顯示 MAC 後 3 組），由上到下：
  1. **狀態橫幅**（`Key('recent-banner')`，icon key `recent-banner-<kind>`）：最近一筆 <30 秒 → 綠「資料正常上傳中」；30 秒～10 分鐘 → 黃「最近 N 秒／分鐘沒有新資料」；≥10 分鐘 → 紅同句；count 0 → 灰「後台尚未收到這台閘道器的資料，請稍等 20 秒再重新整理」＋〔重新整理〕；錯誤 → 紅人話＋〔重試〕（`recentBanner`）。橫幅下方一行小字「最近 N 筆・跨 N 秒・平均每秒 X 筆」（`Key('recent-trend')`，`recentTrendText`）。
  2. **最新一筆大字卡**（`Key('recent-latest')`）：`input_mv/1000` V（一位小數）、`input_ma/1000` A（兩位小數）、`temp_c` °C 三個大數字，下一行「PTU 9A:96:00・狀態中文・HH:mm:ss（N 秒前）」（PTU 為 MAC 後 3 組、保留冒號，`RecentItem.ptuShort`／`ptuMacShort`；1.0.0+4 的「PTU 9600」後 4 碼看不懂），卡片底部小字「MAC 90:5F:E8:9A:96:00」（`Key('recent-latest-mac')`，`ptuMacFull`）。`ptu_state` 中文對照 `ptuStateLabels`，來源韌體 `ble_multi_wifi_gateway/main/http/mqtt_uploader.c` `ptu_state_to_string`（CONFIGURATION 設定中、POWER_SAVE 省電、LOW_POWER 低功率、POWER_TRANSFER 充電中、LATCH_FAULT／LATCHING_FAULT 鎖定故障、LOCAL_FAULT 本地故障、OTA_MODE、COOLING 冷卻中、EXCEEDED_RANGE PRU 超出範圍、UNKNOWN 未知；其他照原字串，空／NULL 顯示 `--`）。`*_FAULT` 狀態卡片邊框轉紅並加一行「PTU 回報故障」（`Key('recent-latest-fault')`）。星狀多台 PTU 時依 `ptu_mac`（無則 `device_id`）分組，每台一張小卡 `Key('recent-latest-<後4碼>')`（key 仍用後 4 碼；`recentLatestPerDevice`）。
  3. **最近資料**（`ExpansionTile` 預設收合）：1.0.0+5 改為固定欄寬、整列單行不換行的自製表格（`Key('recent-table')`；1.0.0+4 的 `DataTable` 在手機寬度最後一欄「狀態」被截斷）。一對一（所有列同一 PTU）：時間 66｜V 42｜A 42｜°C 30｜狀態 58 dp，含左右 16 dp 邊距共 286 dp，360 dp 螢幕不需橫向捲動、無 PTU 欄；多台 PTU 才加 PTU 欄（MAC 後 3 組，72 dp）並包 `SingleChildScrollView(scrollDirection: horizontal)`（`Key('recent-table-scroll')`）。狀態欄用短標籤 `ptuStateShortLabels`／`ptuStateShort`（充電／待機（IDLE）／省電／低功率／設定／冷卻／超範圍／故障（所有 `*_FAULT`）／OTA／未知；其他截 4 字，空／NULL `--`）。
  4. 右上〔重新整理〕；載入中 AppBar 下方進度條、按鈕停用。不自動輪詢；仍取 `limit=20`。
  5. 1.0.0+5 移除電流 mA 折線圖與趨勢卡（`RecentSparklinePainter`，使用者不需要）。
- **資料層**：`lib/data/recent_data_api.dart`（`RecentData`／`RecentItem`／`fetchRecentData`／`ptuMacShort`／`ptuMacFull`）；練習模式 `DemoSystem` 回每台已連線 PTU 一列。
- **現場回報**：進入此頁呼叫 `FieldReporter.noteRecentDataViewed()`（`status` 事件、`error_message`「查看最近資料」）。完成頁出現時 session 已以 `completed` 結束（`FieldReporter.end`），所以從完成頁進入不會送出；只有 session 仍開著時才送。
- 測試：`test/recent_data_test.dart`（含 360×800、devicePixelRatio 1 的表格無 overflow 測試、PTU 後 3 組格式、短狀態標籤）。

## 閘道器清單頁的出路（09-29，APP 1.0.0+6）

現場回饋：閘道器清單頁（第 1 步）沒有回首頁的路——系統返回鍵直接退出 APP；〔結束並重新選擇閘道器〕只是原地寫「已取消」；而 `cancel()` 斷線後沒清 `peer`，紅框「手機與閘道器的藍牙已斷線」把 APP 自己斷的線當成斷線事故。1.0.0+6 修正（`lib/application/commissioning_controller.dart` `leaveList`／`cancel`、`lib/presentation/commissioning_page.dart`）：

- 清單頁按鈕改為〔結束配置〕（`leaveListLabel`，仍是 `Key('page-cancel')`）→ 問一次「結束這次配置並回首頁？」（`Key('leave-confirm')`，〔留在清單〕`leave-confirm-stay`／〔結束〕`leave-confirm-end`）→ `CommissioningController.leaveList()`：關掉殘留連線、交還監控租約、現場 session 仍開著就以 `abandoned` 結束，回第 0 步；`lastDone`（「上一台已完成：站 S 閘道器 G」）保留，已存進度不動。第 2 步起維持〔結束並重新選擇閘道器〕與原本的確認框。
- 系統返回鍵：只有首頁（第 0 步、無操作進行中）才離開 APP（`PopScope.canPop`）；清單頁按返回＝〔結束配置〕但不問；第 2 步起維持「結束目前配置？」；完成頁維持〔完成〕。
- `cancel()`：一律清掉 `peer`（紅框不再出現）；在清單頁且無操作進行中時不寫「已取消」訊息；其餘（回第 1 步、還原暫時綁定、`FieldReporter.end('abandoned')`）不變。`CommissionState.copy` 新增 `clearPeer`。
- 測試：`test/list_exit_test.dart`；`round17b`／`round28` 對應更新。

## 「閘道器狀態」——完成後也能看（1.0.0+5）

完成頁按〔完成〕後就沒有入口再看〔查看最近資料〕；1.0.0+5 加一頁「閘道器狀態」（`lib/presentation/gateway_status_page.dart`，`GatewayStatusPage`），**不改配置流程本身**。

- **入口**：(a) 首頁（第 0 步）〔檢查並開始〕下方一顆次要按鈕〔閘道器狀態〕（`Key('home-gateway-status')`，`OutlinedButton`）；(b) AppBar 拓撲選單（`Key('topology-menu')`，hub 圖示）第一項「閘道器狀態…」（`Key('gateway-status-menu')`），任何步驟都可開（操作進行中選單本來就停用）。
- **上半「最近配置（這支手機）」**：本機記住這支手機最近完成配置的閘道器（`lib/data/recent_commissions.dart`，`RecentCommission{site, gateway, gatewayName(BLE 名稱), doneAt}`；`SharedPreferences` key `recent_commissions`／練習模式 `demo_recent_commissions`，與 `recent_gateways` 同一方式），最多 10 筆、同站同閘道器只留最新一筆；`CommissioningController.finishDone`（〔完成〕／〔配置下一台〕／完成頁的系統返回）在清狀態前寫入一筆。每列「站 S 閘道器 G」＋「BLE 名稱・MM-DD HH:mm 完成」，`Key('gs-recent-<S>-<G>')`。
- **下半「後台在線閘道器」**：`GET /api/gateways/fleet-status`（APP key 白名單已允許；`lib/data/fleet_status_api.dart`，`FleetGateway`／`fetchFleetStatus`），每列讀 `site_id`、`gateway_id`、`online`、`ble_connected`、`direct.connected`／`direct.label`（一對一才有）、`device_last_seen`（PTU 最後一筆，r34）、`last_heartbeat`；fleet-status 沒有閘道器名稱欄位。顯示「站 S 閘道器 G」＋「在線／離線・PTU 已連線／未連線・最近資料 N 秒前」（`gatewayStatusLine`；PTU 已連線＝`direct.connected` 或 `ble_connected>0`；沒有 `device_last_seen` 時退回「最近心跳 N 秒前」，兩者皆無「尚無資料」），`Key('gs-fleet-<S>-<G>')`，依站、閘道器排序。
- 每列點進去 → `RecentDataPage.open(context, site, gateway)`。右上〔重新整理〕（`Key('gs-refresh')`），載入中進度條＋「正在向後台查詢…」（`Key('gs-loading')`），錯誤紅字＋〔重試〕（`Key('gs-error')`／`gs-retry`；本機清單仍顯示、仍可點），空清單文案「這支手機還沒有完成過配置。」／「後台目前沒有任何閘道器。」（`gs-recent-empty`／`gs-fleet-empty`）。
- 測試：`test/gateway_status_test.dart`（儲存規則、finishDone 寫入、fleet 欄位解析、三態＋點列導向、360 dp、兩個入口）。

### 1.0.0+7（09-29 實機回饋）：自動登入＋「附近閘道器（藍牙掃描）」

- **自動登入**：從首頁直接進此頁曾顯示「APP 尚未登入後台，請回到完成頁…」——後台登入原本只在配置流程第 1 步發生。現在此頁與最近資料頁透過 `lib/application/app_session.dart`（`appSessionProvider`／`AppSession.run`）自己登入：沒有目前環境的 session（`SessionInfo.hasSession`＋`origin` 同源）→ 先試 `SessionStore.restoreSession` 的存檔 token，沒有就用建置憑證 `backendKeyProvider`（`APP_BACKEND_KEY`）呼叫 `DashboardApi.login`（`POST /api/auth/app-login`）；查詢中遇 401 → 重登一次再重試；只有登入被拒才報錯。環境（正式站／本地）沿用 AppBar 環境切換的 `backendEnvProvider.base`。不動 `CommissioningController` 的登入狀態（流程第 1 步仍照舊登入）。錯誤文案統一為「連不上後台（原因）」＋〔重試〕（`recentDataErrorText`／`recentDataErrorReason`；登入被拒＝「後台拒絕此 APP 的登入憑證，請聯絡管理員更新 APP」），不再引導回完成頁。
- **附近閘道器（藍牙掃描）**：新區塊放在「最近配置」與「後台在線閘道器」之間。進頁自動掃約 8 秒（`lib/data/nearby_gateway_scan.dart`：`BleNearbyScanner` 用 `GatewayLink.prepare()` 取權限／藍牙狀態（與第 2 步同一套：`permission`／`location_off`／`bluetooth_off`），先 `GatewayScanner.stopScan()` 停掉流程可能還在跑的即時掃描，再用 `UniversalBle` 收 `GIOS-S` 廣播 8 秒；練習模式 `LinkNearbyScanner` 用 demo link 的 `scan()`；provider `nearbyScannerProvider` 在 `lib/application/nearby_gateways.dart`）。不連線、不配對、不動 `CommissionState`；離開頁面時 `dispose` 完成 `stop` future 讓掃描提前停止。每列「站 S 閘道器 G」＋「RSSI -58 dBm・GIOS-S56-GW01」（`parseGatewayName`；`Key('gs-nearby-<BLE id>')`，RSSI 強者在前），點一列 → `RecentDataPage.open`；廣播名解析不到站號（S0/GW00）的列灰掉不可點。掃描中 `gs-nearby-scanning`「正在掃描附近閘道器（約 8 秒）…」；沒掃到 `gs-nearby-empty`「附近沒有掃到閘道器，請靠近後按〔重新掃描〕」；無權限／藍牙關閉 `gs-nearby-error` 顯示 link 既有文案＋〔開啟權限設定〕（`gs-nearby-settings`，`openAppSettings`）；〔重新掃描〕`gs-nearby-rescan`。
- 「最近配置」空清單文案改為「這支手機尚未用此版本完成過配置」。
- 測試：`test/gateway_status_test.dart` 群組 `1.0.0+7 auto login`（未登入→登入→200；401→重登→200；他站 session 重登；登入被拒→「連不上後台（…）」＋〔重試〕；最近資料頁自動登入；`hasSessionFor`）與 `1.0.0+7 nearby gateways`（有列＋點列導向＋離頁停掃、空＋重新掃描、無權限／藍牙關閉＋〔開啟權限設定〕、掃描中）。

### 1.0.0+8（09-29 介面精簡）：拿掉客戶字樣、練習開關、首頁環境下拉、自動同步開關；清單緊湊化、最近資料完整 MAC、標題不截斷

- 文案：「資料送到正式站，客戶看得到」→ 首頁「資料送到正式站。」（`productionHintText`）、切換環境面板「資料送到正式站」（`productionSheetHint`，`lib/presentation/environment_switch.dart`）；UI 無「客戶」字樣。
- 首頁：移除「使用模擬設備練習／不需要連接閘道器」`SwitchListTile`（`demoProvider`／`DemoSystem` 保留給測試，測試用 `container.read(demoProvider.notifier).set(true)`）；移除「連線環境」`DropdownButtonFormField`，正式站只留一行小字網址（`Key('env-base-line')`），環境切換只靠 AppBar「● 正式站」chip；本地測試／其他網址的位址欄位仍在（那是改位址，不是切環境）。
- 切換環境面板：移除「連線 Gateway 時自動同步上傳目標」開關。旗標 `EnvSwitchPolicy.autoSyncDefault`（`lib/application/backend_environment.dart`）原本 debug ON／release OFF，現在所有建置一律 `false`，舊版存的 `auto_sync_upload_target` 不再讀回；連上閘道器不會自動送 `set_mqtt_target`，只有「連線狀態」的〔同步〕或切換環境時才會（`_syncGateway(explicit: true)`）。
- 第 2 步閘道器清單（`lib/presentation/gateway_discovery.dart`）：每台兩行——第一行「站 81・閘道器 1」粗體＋「-34 dBm」＋小標籤「已配置」／「未配置」（`Key('gateway-configured-<id>')`／`gateway-unconfigured-<id>`；訊號最強仍是 `gateway-nearest-<id>`）；第二行小字「GIOS-S81-GW01・MAC …3A00・後端回報在線上」（`gatewayMacTail`，Wi-Fi MAC 後 4 碼；後端狀態沿用 `backendPresence`）；〔辨識閘道器〕改成燈泡 `IconButton`（`Key('identify-<id>')`，tooltip「辨識閘道器」），點整列＝選擇。360×800 一屏至少 4 台，每張卡 ≤ 72 dp。「最近使用」分組標題保留。
- 最近資料卡（`lib/presentation/recent_data_page.dart`）：`recentLatestLine` 改「PTU 90:5F:E8:9A:96:00・充電中・00:52:33（0 秒前）」（完整 MAC，`recentLatestParts` 兩段放 `Wrap`，窄螢幕狀態可換行；`Key('recent-latest-line-mac')`／`-rest`），底部小字 MAC（`recent-latest-mac`）移除；星狀多台小卡同樣完整 MAC。表格 PTU 欄仍是後 3 組。
- AppBar 標題「GIOS 現場開通」（`appBarTitle`，`Key('appbar-title')`）用 `FittedBox(fit: BoxFit.scaleDown)`，360 dp 不再截成「GIOS …」。
- 測試：`test/ui_trim_test.dart`（無客戶字樣、無 demo 開關、無下拉、無自動同步開關、`autoSyncDefault` false 且忽略舊存值、清單 tile ≤ 72 dp 且 4 台入屏、完整 MAC、標題無省略且有效字級 ≥ 14）；`env_switch_widget_test`／`local_backend_widget_test`／`network_check_test`／`recent_data_test`／`round30_rehearsal_fixes_test`／`widget_test` 依新介面調整。

### 1.0.0+9（09-29 實機截圖）：AppBar 標題不再用 `FittedBox` 縮小（`LayoutBuilder`：放得下用 titleLarge，否則 titleMedium，不縮放不省略），拓撲選單（直連／星狀／每台 PTU 數／直連進階設定）與主題併入 ⋮（`Key('topology-menu')` 不變，主題預設淺色 `defaultThemeMode`），「● 正式站」chip 緊湊（字 12）；第 2 步清單 tile 改自訂排版（不用 `ListTile`，避免小標籤與第二行重疊）——第一行 `Wrap`「站 81・閘道器 1」＋「已配置／未配置」小標籤＋訊號最強的「最近」實心 chip（`gatewayNearestLabel`，卡片描邊、排第一，<6 dB 仍有「差距小」提示）＋「-39 dBm」，第二行單一 `Text`「GIOS-S81-GW01 · …3A00 · 後端在線」（`backendPresenceShort`：在線／離線／無紀錄／已封存／未知）一個省略號；燈泡〔辨識〕改為只閃燈（`CommissioningController.identifyPeer`：連線→get_config→identify both／gateway→斷線，step 不變，tile 顯示「已閃燈」3 秒），點整列才選擇；測試 `test/ui_trim_test.dart`（載入 SDK Roboto 量寬）。

### 1.0.0+10（邏輯修正＋版面）：審查 1.0.0+9（d308987）後的邏輯修正，以及實機截圖（SM-N950F，360×740 dp，系統字級 1.1）後的版面調整
- 清單〔辨識〕（`CommissioningController.identifyPeer`）：時間上限改為 `identifyPeerTimeout`＝`reconnectBudget`（80 秒；BLE 連線最壞 53 秒）；指令走 `_commandBusy`（閘道器回 busy 會重送，`absorb: false` 不寫入流程 config），舊韌體（沒有 `identify_ptu_supported`）送不帶 target 的 identify；只有仍是目前 generation、且流程沒有選其他閘道器時才斷線（`connect()` 先 `_generation++`），逾時後立即斷線收掉背景連線；結束後還原清單原本的提示（如〔配置下一台〕的「預設沿用站 X」）；回傳是否真的送出，「已閃燈」只在送出時顯示；辨識中按〔取消操作〕只中止辨識（不顯示「已取消…」、不結束現場 session）。
- 〔更換 PTU〕（`replaceBoundPtu`）：先過網路體檢與「沿用目前站點」的所有條件（`_reuseStationBlocked`：網路未就緒／上傳暫停／測試模式／不能沿用站點），全部通過才在進第 7 步前一刻送 `direct_bind_mac: ""`；送出前記 `tempBoundMac = ""`（`replacedBindMarker`）與 `tempRestoreMac = 舊 MAC`，第 7 步取消／結束／〔先完成配置〕由 `_releaseTempBind` 還原舊綁定，按「是這台」才換成新 PTU；`_goBindLater` 任何停下都在紅框說明原因。
- 綁定 PTU 是否在場（`boundPtuPresence`）：`connected` 且 `ptu_mac` 等於綁定 MAC 才算在場，不同時顯示紅卡「連到的不是綁定的 PTU」；`scanning`／`connecting` 且開機 `uptime_sec` 未滿 90 秒（`boundPtuSettle`）或狀態剛變化時，顯示中性卡「正在尋找本樁 PTU…」＋〔重新檢查〕（不回報後台）；沒有 uptime 時只對 `connecting` 顯示中性。卡片的色調、文字與按鈕由 `ptuCardView` 決定。
- 清單掃描：〔辨識〕結束後、從其他頁面（例如「閘道器狀態」）返回清單時，原本在掃描就自動恢復（保留舊的列直到新結果回來）；使用者自己按〔停止搜尋〕則不自動恢復。
- ⋮「閘道器狀態…」在操作進行中（busy）或已連上閘道器（step ≥ 2）時停用，顯示「閘道器狀態（配置進行中不可用）」（`gatewayStatusMenuEnabled`）。
- 最近資料：`recentAgeText` 加上「N 小時」「N 天」；負的年齡當 0 秒；後台回應帶 `Date` header 時（`ServerClock`，`DashboardApi` 記錄時鐘差），新鮮度以後台時間判斷（`recentServerNow`），手機時鐘快 30 秒也不會誤判黃色。
- 第 9 步驗證通過時（安裝報告送出的同一刻）就寫入「閘道器狀態」的本機紀錄，不必等按〔完成〕（同站同閘道器只保留一筆）。
- 測試：新增 `test/logic_fixes_v10_test.dart`（18 項）；`test/gateway_status_test.dart` 改為驗證按〔完成〕前已有紀錄；清單測試的假掃描改為 broadcast（掃描會重新訂閱）。

#### 版面（360 dp，字級 1.1／1.3 都不截斷）
- AppBar：`gatewayTheme` 的 `appBarTheme.titleTextStyle` 統一為 titleMedium w600（字級取自 `ThemeData.localize`，因為 `ThemeData.textTheme` 本身沒有字級），三個頁面都用它；拿掉 1.0.0+9 依寬度切 titleLarge／titleMedium 的 `LayoutBuilder`。求助圖示 `VisualDensity.compact`；環境 chip 改 labelMedium、padding 2、圓點框 12 dp。360 dp、字級 1.3、有求助圖示時「GIOS 現場開通」需 137 dp、可用 170 dp。
- 最近資料頁：標題「最近資料」（`recentDataPageTitle`），閘道器放在下方第一行「站 81 · 閘道器 1」（`recentDataSubtitle`，`Key('recent-subtitle')`）。三個大數字改三等分欄（`_BigNumbers`）：數值同一字級粗體、單位小字同基線、下方標籤「電壓／電流／溫度」；headlineMedium 放不下時三個一起降為 titleLarge（星狀小卡為 titleLarge→titleMedium），不再用 `FittedBox`。PTU 區塊兩行：「PTU 90:5F:E8:9A:96:00」／「充電中・01:34:53（0 秒前）」（`recentLatestParts` 第二段不再以「・」開頭，`recentLatestLine` 不變）。表格欄寬乘上字級比例、儲存格 `ellipsis`，單台 PTU 放不下時也橫向捲動（`Key('recent-table-scroll')`）；折疊標題 bodyMedium。
- 第 2 步閘道器清單 tile 三行：①「站 81 · 閘道器 1」（titleMedium w700，`Expanded`＋ellipsis）與右端「-41 dBm」（bodyMedium）；② 小標籤 `GatewayMark`（labelMedium）：「最近」（實心綠 `gatewayNearestColor`，卡片綠框）、「已配置／未配置」、後端短語（`Key('gateway-presence-<id>')`，辨識後 3 秒顯示「已閃燈」）；③「…3A00」（bodySmall）。廣播名稱不再重複顯示（只在無法解析成站號／閘道器時出現；篩選仍可搜尋）。
- 「最近」規則（實機：81/1 -41 dBm 已配置、80/2 -62 未配置 → 沒有任何標記、80/2 排第一）：聽到兩台以上時，訊號最強那台一律標「最近」，並在所屬分組（最近使用／附近裝置）排第一，已配置的也一樣（取消 r31 的「已配置不標最近、排後面」，已配置由「已配置」標籤表達）。
- 〔開啟權限設定〕只在掃描因權限或定位服務失敗時出現（`Key('gateway-open-settings')`）；說明文字與按鈕間加間距；「選擇附近的閘道器」「最近使用」「附近裝置（N）」為區段標題（titleSmall w600）。流程頁內距與主卡片內距 20→16 dp。
- 閘道器狀態：三個區段的列統一（標題 titleMedium w700、副標 bodySmall）；藍牙列「-40 dBm・GIOS‑S81‑GW01」（`unbrokenName` 把連字號換成不斷行的 U+2011，名稱整段換行），訊號最強那台（兩台以上）加「最近」（`Key('gs-nearby-nearest-<id>')`）；最近配置副標只留「09-29 01:15 完成」；後台列「在線・PTU 已連線・7 秒前」（無資料時「心跳 N 分鐘前」）。
- 首頁「先離線配置，稍後驗證資料」改 bodyMedium，與周圍說明同級（原為 ListTile 標題字級）。
- 驗證頁（第 9 步）每台 PTU：右側只留計數／狀態，〔略過此台〕移到 MAC 下方。
- ⋮「直連進階設定」面板可捲動（`Key('direct-settings-scroll')`）。
- 寫死的字級：錯誤詳細資訊、PTU 詳細（bodySmall）；環境 chip（labelMedium）；清單小標籤（labelMedium，原 11）。
- 字級層級：區段標題 titleSmall w600（狀態頁區段、清單分組、求助面板「請唸給後台」）；卡片標題 titleSmall w700（網路體檢／確認資料上傳、連線狀態）；清單列標題 titleMedium w700（閘道器清單、PTU 清單、狀態頁、環境面板選項）；面板標題 titleLarge（直連進階設定、現場取樣）；折疊標題 bodyMedium（掃描說明、安裝報告、錯誤詳細資訊、最近資料表格）。
- 測試：新增 `test/layout_smoke_test.dart`——首頁、環境面板、閘道器清單（兩台不同 RSSI）、⋮ 選單、網路體檢、站點、完成頁、驗證頁、PTU 不在場卡、直連進階設定、最近資料（單台／星狀，表格展開）、閘道器狀態；每頁在 360×740、360×640 × 字級 1.0／1.1／1.3 下由上捲到下，檢查無例外、`maxLines: 1` 的文字不截斷、文字不超出螢幕右緣（橫向捲動表格除外）、AppBar 標題完整且字級 16。字型用 `test/support/real_fonts.dart`：SDK 的 Roboto＋系統的 Noto Sans TC（或 `GIOS_TEST_CJK_FONT`）做 fallback——只載 Roboto 時中文會畫成約 0.44 em 的缺字方塊，量出來比手機窄；`GatewayApp(theme:)` 讓測試加上 fallback。`ui_trim_test` 新增「已配置的最強那台仍標最近、排第一」；其他測試改用 `ValueKey('demo-gateway')` 點選示範閘道器（名稱不再顯示）。

### 1.0.0+11（實機：清單〔辨識〕時 RSSI 變「未收到廣播」、提示框消失、清單跳動）：清單加 `GlobalKey`（辨識中頁面插入「處理中」列會讓清單整個重建、狀態全失）；掃描暫停／停止時每列保留最後 RSSI（灰色 `colorScheme.outline`），從未收到顯示「—」，掃描中超過 30 秒（`gatewayHeardFor`，暫停時間不算）沒廣播才顯示「訊號中斷」、附近裝置才移除；RSSI 欄最小寬＝「-88 dBm」與「訊號中斷」較寬者（右對齊），標題 `Expanded` 不再被擠；提示框與「最近」在辨識期間不變（排名含 30 秒內聽到的，新結果不足兩台時沿用上次）；進度條暫停時保留 4 dp；〔辨識〕成功另以 SnackBar 顯示「站 80 · 閘道器 2 已閃燈」（`identifiedSnackText`，列內「已閃燈」保留）。測試 `test/identify_pause_test.dart`（真字型 360×740 × 1.1／1.3）。

### 1.0.0+12（09-29 現場：閘道器編號對不上現場標示、未配置的閘道器顯示殘留的舊測試身分）：名稱維持「閘道器 N」；編號可修改；不沿用殘留身分
- 未入列（`fleet_joined` ≠ true）的閘道器不再沿用 NVS 裡的身分：連線後的初始建議不採用它、不設 `suggested_site_known`（站號頁不問「目前站號是 N…」，像新機一樣輸入站號）；`suggestGateway` 的「同站沿用原號」只給已入列的閘道器，未入列一律取後台最小空號（離線走藍牙名稱）。例：NVS 80/2、未入列、後台站 80 沒有閘道器 → 輸入 80 建議 1。已入列重新配置同站維持原號；〔配置下一台〕、沿用站點、〔更換 PTU〕不變。
- 例外（第 26 輪）：這支手機送出 `set_site_identity` 並收到 ack 後記下 {gateway_uid, 藍牙 id, 站, 編號, 時間}（`lib/data/written_identities.dart`，`SharedPreferences` key `written_identities`／練習模式 `demo_written_identities`，30 分鐘內有效；閘道器入列（連上時 `fleet_joined` 或 `join_fleet`）就刪除），重連後照舊沿用並問「目前站號是 N」。
- 閘道器清單與「閘道器狀態」附近閘道器：已知未配置（後台可查且不在 fleet：已驗證的 MAC 不在 fleet／封存清單，沒有驗證 MAC 時看廣播名的站／編號不在後台；或廣播名是出廠 1/1）的閘道器標題改「未配置閘道器 …70F0」（Wi-Fi MAC 後 4 碼），不顯示站號／編號；清單上這種標題放不下一行時換成兩行（不截斷），第三行不再重複 MAC；狀態頁這種列不可點、副標「-71 dBm・尚未配置，無法查看資料」。後台狀態未知時照舊（出廠 1/1 除外）。排序、「最近」、〔辨識〕不變（〔辨識〕的 SnackBar 用列上的標題）。
- 「將配置為 站點 X / 閘道器 N」旁加〔修改〕（`Key('gateway-number-change')`，≥ 48 dp）→ 選號面板（`lib/presentation/gateway_number_picker.dart`，1–`kMaxGatewayId` 按鈕、目前的號碼實心，提示「可改成與現場標示相同的編號」）；後台可查時該站被其他 MAC 使用的號碼標「已使用」（`CommissioningController.usedGatewayNumbers`，仍可選），選了走既有「閘道器編號已被使用」〔取代舊機〕／〔改用閘道器 N〕（`_askNumberTaken`，與自動跳號同一個對話框）；離線可選但標示「目前無法檢查是否重複」。不按〔修改〕就跟以前一樣零輸入；選過的號碼不再被重新配號或跳號對話框覆蓋，改輸入其他站號才回到自動號碼。**+13 取代了〔修改〕**（選號面板與 `usedGatewayNumbers` 已移除，見 1.0.0+13）。
- 測試：新增 `test/gateway_numbering_test.dart`；`layout_smoke_test` 加「站點頁〔修改〕＋選號面板」（線上／離線）；`archived_rejoin_test`（56 改為輸入）、`one_thing_screens_test`／`round26_multi_gateway_test`／`round30_rehearsal_fixes_test`（預先記下本機寫入的身分）、`gateway_discovery_test`（出廠 1/1 標題）、`gateway_status_test`（附近列需後台有該站號）、`identify_pause_test`（SnackBar 文字）依新規格調整。

### 1.0.0+13（09-29 分析：〔修改〕可能讓現場人員選到使用中的號碼並按〔取代舊機〕，後台 `reserve_gateway_identity(force_replace)` 不檢查舊機是否在線 → 兩台同站同號、資料混在一起、心跳互蓋、給該號的指令兩台都執行）：正常安裝全自動配號；換機改明確入口，只能取代離線的舊機；完成頁提示在機殼上標示
- 拿掉〔修改〕與選號面板（刪除 `lib/presentation/gateway_number_picker.dart`、`CommissioningController.usedGatewayNumbers`）：「將配置為 站點 X / 閘道器 N」回到唯讀，號碼一律 `suggestGateway`（後台同站最小空號；離線走藍牙名稱）。+12 的「未入列不沿用殘留身分」「未配置閘道器 …XXXX」保留。
- 站點頁「將配置為 …」下方次要按鈕〔這台是來換掉壞掉的舊機〕（`Key('gateway-swap')`，≥ 48 dp；有站號且後台可查——已登入、配號不是離線猜的——才顯示，否則一行小字「換機需要連上網路」`Key('gateway-swap-offline')`；Wi-Fi 頁不顯示）→ 底部面板（`lib/presentation/gateway_swap_sheet.dart`）列出 `GET /api/gateways/fleet-status?site_id=S` 中本站 `online == false`、且 MAC 不是這台的閘道器（`lib/core/gateway_swap.dart` `offlineSwapCandidates`；沒有 `online` 欄位的不列），每列「閘道器 N」＋「最後上線 3 小時前 · MAC …70F0」（`last_heartbeat`，無則 `last_seen`；`recentAgeText`）；沒有 → 「本站沒有離線的閘道器可以取代」＋〔關閉〕。點一列 → 「確定換機？ 這台將接手 站 S · 閘道器 N。舊機（…XXXX）必須已拆除或斷電。」〔確定換機〕／〔取消〕→「將配置為 站點 S / 閘道器 N（取代舊機 …XXXX）」、按鈕變〔取消換機〕（回自動號）；改打站號（含 500 ms 查詢前就按〔使用站點〕）清掉換機選擇。換機選定時不再跑自動配號與 r33 跳號詢問，本站已滿也可送出。
- 送出：沿用既有取代流程（`_saveWifi` → `configureWifi(replaceExisting: true)`：先 reserve-identity `force_replace` 成功才 `set_site_identity`，`pendingReplace` 不變）。送出前再查一次 fleet-status（`CommissioningController.gatewayOnline`；check-identity 沒有在線欄位）：舊機已變在線 → 不送，對話框「閘道器 N 目前在線上，請先把舊機斷電。」，回站點頁與自動號。r33〔取代舊機〕選過的號碼送出前同樣再查。
- r33「閘道器編號已被使用」（`_askNumberTaken`）與儲存時的「編號已被使用」對話框：占用者在線（fleet-status `online == true`）時不顯示〔取代舊機〕，改說明「閘道器 N 目前在線上，不能取代；如果這台是來換掉它，請先把舊機斷電。」，只留〔改用閘道器 M〕／〔改用下一個可用編號〕與〔取消〕；在線狀態查不到（離線、沒有該列、沒有 `online`）維持原行為（可取代）。r33「身分衝突」（`_confirmConflict`，這台自己的號碼被後台標衝突）的〔取代舊機〕同樣防護：占用該號的另一台在線就只留〔改用其他站號〕；該列的 `last_seen_mac` 是這台自己時，`online` 反映的是這台的心跳，視為查不到（`fleetRowOnline(ownUid:)`，維持可取代）。
- 完成頁摘要卡：原本的「站 S · 閘道器 N」一行改成大字標示卡（`Key('done-label')`）：「請在機殼上標示：」＋大字「站 S · 閘道器 N」（`Key('done-gateway')`，headlineSmall）＋「後台人員靠這個標示找到這台」；讀屏合成一句「請在機殼上標示：站 S · 閘道器 N」（`doneLabelText`）。沒有新增要按的步驟。
- 測試：`test/gateway_numbering_test.dart` 第 3 組改寫為換機（〔修改〕不存在、按鈕只在後台可查時出現、面板只列本站離線且非自己 MAC、確認後 force_replace 先於 set_site_identity、送出前舊機變在線不送、r33 與儲存時對話框在線／離線／未知、改站號清掉換機、完成頁標示卡），第 1 組 `usedGatewayNumbers` 案例改為 `swapCandidates`／`gatewayOnline`；`layout_smoke_test` 的選號面板案例改為站點頁換機按鈕（線上／離線）、換機面板（有離線閘道器／沒有）、換機確認對話框，完成頁加檢查標示卡。
