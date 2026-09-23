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

`DEMO_MODE=true` 完全使用模擬BLE／API，安裝報告會標示模擬。不加此旗標即使用真實BLE。通訊套件已改為 `universal_ble 2.3.0`（BSD-3-Clause，允許免費商用），不再需要 FBP 商用授權旗標。授權全文保存在 `THIRD_PARTY_NOTICES.md`，發佈時應隨附。

API預設 `https://dashboard.voltraware.com`，可在畫面改設定。僅系統TLS信任，不繞過憑證。`LOCAL_DEVELOPMENT=true` 才允許localhost／127.0.0.1／Android emulator localhost的HTTP；真機連本機可用adb reverse測試。WiFi密碼不落地；登入取得的API key存安全儲存區。


Android minSdk24，正式release沒有debug簽章。正式keystore與發佈程序仍待備妥；目前APK只能作開發測試。

Wi-Fi 名稱下方可掃描手機周邊的 2.4 GHz 網路，依訊號排序，同名合併；選取後填入SSID，密碼仍需輸入。需開啟手機Wi-Fi、定位服務並允許精確位置。系統限制重複掃描時會提示稍候重試；隱藏SSID可手動輸入。手機掃描結果不保證Gateway所在位置也收得到訊號。

協定沿用韌體NUS UUID、JSON envelope與字串result，單一指令queue；req_id關聯ACK、UTF-8 byte framing、逾時清空。v1.7採get_net_status，舊版退回get_status；舊版無NTP時敏感命令可能被拒，畫面提供升級指引。OTP已啟用時拒絕敏感操作。

現場流程：登入／離線 → 掃描Gateway → 身份及WiFi → 上線確認 → 選PTU → 編號與連線數read-back → 連續三次後端更新 → 報告／健康。第一版不涵蓋補機／換機／移機。實機與長時間驗收見上一層 `REWRITE_ACCEPTANCE.md`。
