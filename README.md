# GIOS Commissioning

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

協定沿用韌體NUS UUID、JSON envelope與字串result，單一指令queue；req_id關聯ACK、UTF-8 byte framing、逾時清空。v1.7採get_net_status，舊版退回get_status；舊版無NTP時敏感命令可能被拒，畫面提供升級指引。OTP已啟用時拒絕敏感操作。

現場流程：登入／離線 → 掃描Gateway → 身份及WiFi → 上線確認 → 選PTU → 編號與連線數read-back → 連續三次後端更新 → 報告／健康。第一版不涵蓋補機／換機／移機。實機與長時間驗收見上一層 `REWRITE_ACCEPTANCE.md`。
