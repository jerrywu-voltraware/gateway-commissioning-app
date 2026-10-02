# 手機目前的 Wi-Fi：Android / iOS 驗證

兩個平台都在 Wi-Fi 表單提供「使用手機目前的 Wi-Fi」。按下後才要求定位權限並讀取 SSID，不會自動更換手機網路，也不會讀取密碼或位置座標。帶入名稱後仍需使用者輸入密碼，再按「儲存並繼續」。

手機須先連到現場路由器／AP；手機與 gateway 仍走原有 BLE 配置流程。這次沒有新增 gateway 指令或修改韌體。

## 已完成的自動檢查

- `flutter analyze`：無問題。
- 完整 `flutter test`：1506 項通過、3 項略過，包含手機中途斷線與殺 App 後續作的自動回歸。
- Wi-Fi 專項測試：68 項通過，涵蓋 Android / iOS 目前網路帶入、手動輸入、權限拒絕、切換網路、晚到結果與既有 `set_wifi` 流程。
- Android `:app:compileDebugKotlin`：通過。
- `ruby tools/build_ios.rb --build`：iOS 未簽章建置通過。

Mac 的完整測試需把 `GIOS_TEST_CJK_FONT` 指向本機的 PingFang.ttc；第一次未指定時的字型載入失敗，已在指定字型後重跑通過。上述結果是編譯與自動測試，不代表已完成手機上的 SSID 讀取或 gateway 連線驗證。目前沒有安裝到手機，也沒有發布版本。

## 上機前

- iOS：Runner 的 Debug / Profile / Release 已指定 `Runner/Runner.entitlements`，含 `com.apple.developer.networking.wifi-info`。開發者帳號的 App ID 與實機 provisioning profile 也必須啟用 Access WiFi Information；舊 profile 若未包含此 entitlement，需由 Xcode 更新後重新簽章安裝。模擬器與未簽章建置不能驗證 SSID 讀取。
- iOS 直接透過 CoreLocation 要求「使用 App 期間」權限，並檢查「精確位置」。不依賴 permission_handler 的 Swift Package 權限編譯快取，也不要求背景定位或取得位置座標。
- Android：允許定位權限／精確位置，並開啟定位服務。Android 12 以上透過含 location info 的網路 callback 取得 SSID；舊版使用 WifiManager 的目前連線資訊。
- Android 交付或安裝的 APK 仍須使用 `tools/build_apk.ps1` 簽章、驗證；本地測試使用 `-Env local`。本次未產生可交付的 APK。

## 請在兩個平台各驗證

| 情境 | 操作 | 預期 |
| --- | --- | --- |
| 正常帶入 | 手機先連上現場 Wi-Fi，開啟表單並按「使用手機目前的 Wi-Fi」 | 出現授權需求（尚未授權時），帶入正確名稱，密碼由使用者填寫；按儲存後沿用原有配置流程 |
| 拒絕權限／關閉精確位置 | 拒絕後再次讀取 | 說明需要的權限，可開啟 App 權限設定，也可手動輸入；原有名稱及密碼不被清掉 |
| 沒有 Wi-Fi／定位服務關閉 | 關閉後讀取 | 顯示可操作提示，不把空名稱填入；手動輸入仍可用 |
| 更換手機網路 | 在系統設定切換到另一個 AP，再回 App 按讀取 | 重新取得新名稱；若名稱不同，清除上一個網路的密碼；名稱相同則保留已輸入密碼 |
| 手動／隱藏網路 | 按「手動輸入其他網路」，修改名稱及密碼 | 不需要讀取 Wi-Fi 權限；名稱保留大小寫及空格 |
| 2.4 / 5 GHz 同名 | 手機連上雙頻同名網路後帶入 | 不把手機的頻段當成 gateway 的能力；確認 AP 的同名 SSID 也提供 2.4 GHz |
| 讀取期間返回 | 按讀取後立即返回上一頁或更換 gateway | 晚到的讀取結果不修改其他頁面或 gateway 的表單 |
| 手機中途斷線 | 配置途中中斷 BLE，重新連線 | 沿用既有對帳／續作流程，不重做已完成的配置 |
| 殺 App 續作 | 配置途中殺 App，再開啟並續作 | 重新向 gateway 對帳，不只相信本地存檔 |

Android 另驗證「選擇其他 Wi-Fi」：只列出掃描到的 2.4 GHz 網路，仍可選自訂／隱藏網路。iOS 不顯示這個掃描入口。

## API 依據

- [Apple：fetchCurrent 的權限與回傳欄位](https://developer.apple.com/documentation/networkextension/nehotspotnetwork/fetchcurrent(completionhandler:))
- [Android：NetworkCallback 的 FLAG_INCLUDE_LOCATION_INFO](https://developer.android.com/reference/android/net/ConnectivityManager.NetworkCallback#FLAG_INCLUDE_LOCATION_INFO)

SSID 讀取僅代表手機已連線的網路名稱，無法保證 gateway 所在位置的訊號、頻段或驗證方式相容。App 保留 2.4 GHz 提示與既有連線結果處理。
