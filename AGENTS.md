# AGENTS.md — APP_v2（前線配置 APP，Flutter／Android）

先讀 `..\HANDBOOK_CODEX.md`（唯一正式版手冊：§3.2 本 repo 指令、§5.4 對帳規則、§5.8 一對一流程、§6 紅線、§7.4.5 建置安裝；目前狀態以手冊最底的日期段為準，§0 是 09-27 狀況）與 `..\AGENTS.md`。`..\HANDBOOK_CODEX_2026-09-27.md` 已被取代，只供歷史查閱。
現況（09-29 21:35，依 `..\HANDBOOK_CODEX.md` 最底兩段；確切 HEAD 以 `git log -1` 為準）：分支 `wip/network-check`，**1.0.0+19 `f87b788`**；remote `origin`＝GitHub `jerrywu-voltraware/gateway-commissioning-app`（`main`＝工作分支）。手機（adb `ce08171898c05cdd0c7e`）裝正式版 `..\keys\app_f87b788_prod.apk`（versionCode 19）。`flutter test` 1103、`flutter analyze` 0（紀錄值）。未結項目見手冊 §9.1、§9.2 與最底日期段的 backlog。舊版 `..\APP\` 已刪除（程式碼在 GitHub 與 Azure 遠端）。

## 本 repo 紅線
- 交付或上機的 APK 一律用 `tools\build_apk.ps1`（簽章＋apksigner verify；工作樹 dirty 會拒建）；不要交 `flutter build apk` 的未簽章輸出。
- 本地測試版必須 `-Env local`（`LOCAL_DEVELOPMENT=true`）；`-Env prod` 用 `android\key.properties` 指向的正式 keystore 簽章（只能連正式站；缺設定會停）。
- 續作／斷線恢復一律先 `get_ble_devices` 對帳，不信本地存檔；`busy` 是暫時狀態要重試；`verified:false` 不是失敗。
- 「已在監控」的判斷一律要看韌體 `fleet_joined`，不能只看上傳狀態（使用者演練問題 A）。
- 星狀 `max_connections` 一律 5；星狀 `star_macs` 名單要在第一個 `assign_device_id` 之前送出。
- 直連：APP 不自己預選 PTU，跟隨閘道器選台；確認需「辨識過且辨識 MAC == 閘道器目前連線 MAC」；沒有本樁 PTU 時〔先完成配置〕只 `join_fleet`、不送 `set_config`。
- 指令／ack 欄位語意以 `..\ble_multi_wifi_gateway\docs\cmd_contract.md` 為準。
- 不把 Wi-Fi 密碼、登入密碼、API key 寫進 log、診斷包或文件（README 內已有的值使用者決定保留，但不要抄出）。
- 每次 APP 改動後至少回歸「手機中途斷線」與「殺 APP 續作」兩個情境。

## 指令（PowerShell 5.1）
```powershell
flutter analyze
flutter test
powershell -ExecutionPolicy Bypass -File tools\build_apk.ps1 -Env local     # -> build\dist\app_<hash>_local.apk
& C:\Users\woo75\AppData\Local\Android\Sdk\platform-tools\adb.exe -s ce08171898c05cdd0c7e install -r build\dist\app_<hash>_local.apk
flutter build apk --debug --dart-define=DEMO_MODE=true                      # 無硬體 demo
```
套件名 `com.voltraware.gateway_commissioning`；本地後台預設 `http://192.168.0.12:18000`。查手機裝的版本先看 versionCode（`pubspec.yaml` `version: 1.0.0+N` 的 N；versionName 固定 1.0.0）；要確認是哪個建置再比 `base.apk` 雜湊，見手冊 §3.2（在 Git Bash 跑 `adb shell sha256sum /data/...` 要加 `MSYS_NO_PATHCONV=1`，否則路徑被改成 `C:/Program Files/Git/data/...`）。
