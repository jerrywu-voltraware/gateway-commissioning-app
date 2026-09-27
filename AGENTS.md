# AGENTS.md — APP_v2（前線配置 APP，Flutter／Android）

先讀 `..\HANDBOOK_CODEX_2026-09-27.md`（§0 紅線、§3.2 本 repo、§5.4 對帳規則、§5.8 一對一流程、§11.6 建置安裝）與 `..\AGENTS.md`。
現況（09-27 傍晚）：分支 `wip/network-check` **`f548e59`**（r28 一對一修正：沒有本樁 PTU 時〔先完成配置〕、上傳誤報改看 `mqtt_connected`、無鄰近資料時校正不放寬門檻），745 tests、`flutter analyze` 0；r29 實機驗證用此版，一對一演練已達完成條件。本 repo 沒有 remote。舊版 `..\APP\` 不要動。

## 本 repo 紅線
- 交付或上機的 APK 一律用 `tools\build_apk.ps1`（簽章＋apksigner verify；工作樹 dirty 會拒建）；不要交 `flutter build apk` 的未簽章輸出。
- 本地測試版必須 `-Env local`（`LOCAL_DEVELOPMENT=true`）；`-Env prod` 需正式 keystore（目前沒有，會停）。
- 續作／斷線恢復一律先 `get_ble_devices` 對帳，不信本地存檔；`busy` 是暫時狀態要重試；`verified:false` 不是失敗。
- 星狀 `max_connections` 一律 5；星狀 `star_macs` 名單要在第一個 `assign_device_id` 之前送出。
- 直連：APP 不自己預選 PTU，跟隨閘道器選台；確認需「辨識過且辨識 MAC == 閘道器目前連線 MAC」。
- 指令／ack 欄位語意以 `..\ble_multi_wifi_gateway\docs\cmd_contract.md` 為準。
- 不把 Wi-Fi 密碼、登入密碼、API key 寫進 log、診斷包或文件（README 內已有的值不要抄出）。
- 每次 APP 改動後至少回歸「手機中途斷線」與「殺 APP 續作」兩個情境；backlog 中 R27-1（驗證核對 `ptu.mac`／閘道器 mode）待下一批修改時處理。

## 指令
```powershell
flutter analyze
flutter test
powershell -ExecutionPolicy Bypass -File tools\build_apk.ps1 -Env local     # -> build\dist\app_<hash>_local.apk
& C:\Users\woo75\AppData\Local\Android\Sdk\platform-tools\adb.exe -s ce08171898c05cdd0c7e install -r build\dist\app_<hash>_local.apk
flutter build apk --debug --dart-define=DEMO_MODE=true                      # 無硬體 demo
```
套件名 `com.voltraware.gateway_commissioning`；本地後台預設 `http://192.168.0.12:18000`。
