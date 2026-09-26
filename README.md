# GIOS Commissioning

後端選單為「VPS 正式站／本地測試站／其他網址」。本地預設 `http://192.168.0.12:18000`，手機與電腦連同一區域網路即可，不需USB。網址可修改並記住；密碼為 `54974211`。本地版建置需 `--dart-define=LOCAL_DEVELOPMENT=true`，只允許私有IPv4／loopback使用HTTP，正式站仍使用HTTPS。電腦IP改變時需更新本地網址。Windows若阻擋手機連線，請以系統管理員PowerShell執行後端 `tools/allow_local_api_lan.ps1`；僅放行本地子網的TCP 18000。

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

`DEMO_MODE=true` 完全使用模擬BLE／API，安裝報告會標示模擬。不加此旗標即使用真實BLE。通訊套件已改為 `universal_ble 2.3.0`（BSD-3-Clause，允許免費商用），不再需要 FBP 商用授權旗標。授權全文保存在 `THIRD_PARTY_NOTICES.md`，發佈時應隨附。

API預設 `https://dashboard.voltraware.com`，可在畫面改設定。僅系統TLS信任，不繞過憑證。`LOCAL_DEVELOPMENT=true` 才允許localhost／127.0.0.1／Android emulator localhost的HTTP；真機連本機可用adb reverse測試。WiFi密碼不落地；登入取得的API key存安全儲存區。


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
