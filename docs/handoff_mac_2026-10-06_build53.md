# Mac 接手交接（2026-10-06，Build 53 發布後）

> **2026-10-06 下午追加**（公司機 session 結束前；Mac 尚未同步，這次一併帶過去）：
> 1. **新功能待 APP 實作**：現場除錯 PTU 即時讀值，方案 A（加速上傳 5 分鐘）＋方案 B（藍牙直讀 `get_ptu_data`）。實作簡報 `docs/live_ptu_data_app_brief_2026-10-06.md`（契約、UI、link 共用規則、測試、i18n）。後台 v1.38.0 的 `/end` 端點已 commit（部署進行中，見簡報 §1.1）；韌體 1.7.47 的 `get_ptu_data` 已 commit（未燒錄；錯誤欄位是巢狀 `err{num,data,limit}`）。
> 2. **啟動圖示已換成 1024 Voltraware logo**（commit e1468b8）：`assets/icon/`＋`flutter_launcher_icons` 設定在 pubspec 末尾；iOS AppIcon set 全套已產生（RGB 無 alpha），Mac 建 iOS 時 Xcode 會驗證。重產圖示後要 `git checkout -- ios/Runner.xcodeproj/project.pbxproj`（工具會誤改 `ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS`）。
> 3. 下一版 Build 54 內容預計：A、B 兩功能＋新圖示＋Build 53 留下的 6 項小螢幕版面問題。版號由使用者決定時再改。

寫給在 Mac 上接手 APP_v2 的 AI。公司機（Windows）這一輪做了什麼、現在的正式狀態、留給你的事。所有 hash 以 `git log` 為準。

## 現在的狀態（2026-10-06 13:00 台灣時間）
- **APP_v2 `main` = 4de8302**（已 push origin）。其上：51be5da（Mac 做的 PRU 欄位＋頁首改版）→ 89bf7fb、4de8302（只改測試）→ e9a7266（docs）。來源標籤 `android-v1.0.11-b53` → 4de8302。
- **Android 1.0.11 Build 53 已正式啟用**（13:53 UTC+8 切指標），使用者已在手機透過 APP 內更新安裝並測試完畢（13:0x 回報「Android 測試完畢」，未附問題）。發布庫 `gateway-commissioning-releases` main = 9e002ae（README 目前 Build 53、手冊基準 53／下一版 +54）。
- **後台 v1.37.0 已部署正式站**（12:35）：`GET /api/app/recent/{site}/{gw}` 每筆 item 多回 `pru_iout`、`pru_vrect`、`pru_Temp_degC`、`error_num`、`pru_mac`（IoTLogs 同名欄，沒值 null）。後台 repo `MariaDb_Contabo_Server_Master` origin master = rewrite/commissioning-20260922 = df273f8。Mac 留的 `docs/backend_recent_pru_metrics.patch` 已用掉（CRLF 檔，套用要 `git apply --ignore-whitespace`）。
- iOS 這一輪沒碰（上次只到 TestFlight 1.0.0 Build 21；`docs/ios_i18n_handoff_2026-10-06.md`）。

## Windows 這一輪改了什麼（APP 部分）
- 89bf7fb `test/recent_data_compact_layout_test.dart`、`test/recent_data_test.dart`：51be5da 把標籤「溫度」改成「發射端溫度」、表頭「PTU」改成「PTU MAC」，測試跟著改；fixture 補 `pru_vrect`／`pru_Temp_degC`／`error_num`／`pru_mac`。多 PTU 長故障文字 600 dp 的案例改成不給 `error_num`（故障＋錯誤碼同列時 `_fullyPainted` 寬度差約 2 px，判斷是測試輔助函式假象，未實機確認；**該組合目前無測試涵蓋**）。
- 4de8302 `test/one_thing_screens_test.dart`、`test/wifi_first_test.dart`：頁面列表保留捲動位置導致 finder 找不到元素，測試先捲回頂端再找。
- e9a7266 `README.md` 契約行加五欄；`docs/ios_header_recent_metrics_2026-10-06.md` 追加 Windows 段。
- 沒有改任何 `lib/`。

## 全套測試現況：`flutter test --no-pub` +1690 −12（公司機 Windows、Flutter 3.44.3）
基準：在 Build 52 來源 0a94090 實跑同樣檔案得到「52 就壞」的清單。對照實驗：暫時拿掉 51be5da 在 `commissioning_page.dart` 底部加的 48 dp `PreferredSize` 第二列，C 類全部通過（lib 已還原）。

| 測試 | 類別 | 根因 | 建議 |
|---|---|---|---|
| direct_pick_compact「large text: readable PTU data can be scrolled above fixed actions」 | A 既有 | actions bar 232 > 200，52 就壞 | 不急 |
| env_switch_widget「r32 …」 | A 既有 | 61 > 60，52 就壞 | 不急 |
| one_thing_screens「3. the Wi-Fi page … 360x640」 | A 既有 | 52 時 779 > 640，現在 797 | 不急 |
| direct_pick_compact「MAC and RSSI initially visible 360x640 / 1.3」 | **C 51be5da** | 48 dp 列；RSSI 底 437 > 內容區 419，要捲才看到 | 第二列只在寬螢幕出現或縮小 |
| round29_done_page「star done page 360x640, font 1.0」與「font 1.3」 | **C 51be5da** | 〔完成〕落在第一屏外（611 > 572） | 同上 |
| gateway_card_layout「360x740 @1.3」「320x658 @1.1」 | **C 51be5da** | 690 > 672、627 > 590，第一張卡＋連線鈕被擠到第一屏下 | 同上 |
| en_layout「recent data page, table open」 | **C 51be5da** | 英文表頭 "Transmitter temp" 欄寬 100 在字體 1.0 就截斷（`lib/presentation/recent_data_page.dart:926`；Android Roboto 也會） | 加寬欄或縮短英文字 |
| gateway_card_layout「360x640 @1.1」「360x640 @1.3」「320x640 @1.3」 | D 字型相依 | 拿掉 48 dp 列仍壞；疑 Windows／Mac CJK 系統字型度量不同，有一個 120.0 邊界值 | **請在 Mac 跑一次看是否通過** |

C 類 6 個都不是 P0（紅線 1：當機、資料遺失、連錯樁、閘道器失聯、現場人員沒有出路），所以 Build 53 照常放行；它們是使用者在小螢幕大字體時「第一屏看得到」不成立，內容仍可捲到。

`flutter analyze --no-pub`：6 個既有 issue（`docs/manual_capture_test.dart` ×5、`test/field_help_widget_test.dart:72`、`lib/presentation/next_action_guide.dart:262` 其一；皆 Build 52 之前就有）。

## 使用者實測時值得知道的資料面現象（非 APP 錯）
- 閘道器 81/1 的 `pru_Temp_degC` 後台回 **247**（既有 uint8 溫度 240–255 問題，API 原樣回傳）。
- 20/1 在 11:53:32 有一筆 `error_num = 1`。

## 環境與流程備忘
- 同步後先 `flutter pub get`（Windows 這邊沒跑會因 l10n 的 `Intl` 解析不到而編不過；pubspec.lock 沒變）。測試用 `flutter test --no-pub`。
- 版本：pubspec 目前 1.0.11+53 已發布。下一版 Build 54 要由使用者決定；手冊 `gateway-commissioning-releases/docs/APP_RELEASE_MANUAL.md` 基準已改 53／下一版 +54。發布 helper 在公司機 `F:\iot_gateway\tools\deployment\*build53*`（不在 git）。
- 定版後只為 P0 開新版（`AGENTS.md` 紅線 1）；其餘進 backlog。
- 後台契約：`lib/data/recent_data_api.dart` 檔頭註解＋`README.md`「後台契約」行；後台端 `dashboard-api/app_recent.py` docstring。改欄位先改兩邊文件。

## 回滾（需使用者同意；在公司機或家裡機執行）
- Android 指標回 52（不刪資產、不降級已裝 53 的手機）：`tools/deployment/android_build53_rollout.py rollback --run-id 20261006T045041Z …`，完整參數在 `F:\iot_gateway\CONTINUE_2026-10-06_BUILD53_PUBLICATION.md`。
- 後台回 hw-auto 版：VPS `python3 ~/gateway-management-deployments/20261006T043452Z-recent_pru/rollback_gateway_management.py --check` → `--apply`。

## 其他留檔（公司機本機，不在 git）
`F:\iot_gateway\CONTINUE_2026-10-06_RECENT_PRU_API.md`（本輪完整進度）、`CONTINUE_2026-10-06_BUILD53_PUBLICATION.md`、`HANDBOOK_CODEX.md` 最底「2026-10-06 12:59」段、`docs/test_results/build53_*`。
