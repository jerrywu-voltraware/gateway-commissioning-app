# iOS 中英語系交接（2026-10-06，給公司 Mac 操作）

對象：使用者明天在公司 Mac 用 Xcode 建置、裝到 iPhone 確認中英切換。
來源 repo：`APP_v2`（GitHub `jerrywu-voltraware/gateway-commissioning-app`，分支 `main`）。
寫這份文件時 HEAD 是 `c264718`；Phase C（`lib/`、`test/`、`docs/i18n.md`）還在 Windows 上進行、尚未 commit。**Mac 上要建的是「Android Build 52 用的同一個 commit」**，不是 `c264718`。

> 本文件只寫存放位置，不寫任何密碼、金鑰、憑證內容。

---

## 1. 這次 iOS 端改了什麼

iOS 原生檔只在 commit `5dca4c9` 改過（Windows 手改，**沒有在 Mac 上編過**）。2026-10-06 在 Windows 用腳本做了結構審核，**全部通過、沒有再改任何 iOS 檔**。

| 檔案 | 內容 |
|---|---|
| `ios/Runner/zh-Hant.lproj/InfoPlist.strings`（新） | `CFBundleDisplayName`＝「GIOS 設備助手」＋4 條權限說明（與 Info.plist 預設值一字不差） |
| `ios/Runner/en.lproj/InfoPlist.strings`（新） | `CFBundleDisplayName`＝"GIOS Device Assistant"＋4 條英文權限說明 |
| `ios/Runner/Info.plist:11-15` | 新增 `CFBundleLocalizations`＝`zh-Hant`、`en` |
| `ios/Runner.xcodeproj/project.pbxproj` | `:20` PBXBuildFile、`:72-73` 兩個 PBXFileReference、`:146` 掛進 Runner 群組、`:249-253` `knownRegions`＝`en`、`Base`、`zh-Hant`、`:284` 加進 Runner 的 Copy Bundle Resources、`:431-439` PBXVariantGroup `InfoPlist.strings` |

權限 key 以 Info.plist 實際為準，共 4 條，兩個 lproj 都齊：
`NSBluetoothAlwaysUsageDescription`、`NSBluetoothPeripheralUsageDescription`、`NSLocalNetworkUsageDescription`、`NSLocationWhenInUseUsageDescription`。

設計說明（為什麼這樣做）：
- **Info.plist 保留中文 `CFBundleDisplayName` 與中文權限說明**當作預設值，各語言由 `xx.lproj/InfoPlist.strings` 覆寫——這是 Apple 慣例。
- `CFBundleDevelopmentRegion`＝`$(DEVELOPMENT_LANGUAGE)`＝專案 `developmentRegion = en`（沒改）。系統語言不是繁中也不是英文（例如日文、簡中）時，桌面名稱與權限提示會走英文。
- `project.pbxproj` 的 Runner 三個設定（Debug／Release／Profile）有 `INFOPLIST_KEY_CFBundleDisplayName = "GIOS 設備助手"`。**它不會蓋掉 lproj**：`INFOPLIST_KEY_*` 只在 `GENERATE_INFOPLIST_FILE = YES` 時生效，而 Runner 沒開（只有 RunnerTests 開）；而且執行時 lproj 的 InfoPlist.strings 本來就優先於 Info.plist。所以保留不動。
- APP 內文字（Dart）**預設繁中、不跟系統語言**，只有「更多」→「語言」能切換（存在 shared_preferences 的 `app_locale`）。**桌面名稱與權限提示則跟 iOS 系統語言**（或 iOS「設定」→ 本 APP →「語言」）。兩者是獨立的，驗收時要分開看。
- `flutter_localizations` 在 iOS 不需額外設定：`CFBundleLocalizations` 已加；`GlobalCupertinoLocalizations` 已在 delegates（`lib/l10n/app_localizations.dart:91`）。`AppDelegate.swift` 不用改。`ios/Podfile` 平台 `iOS 15.0`，`Podfile.lock` 有進 git。

Windows 端審核方式（Mac 上請改用 `plutil`，見 §3.4）：用 Python 解析 pbxproj（括號平衡、無重複 key、80 個 ID 全唯一、每個引用的 ID 都有定義、每個檔案參考都在群組內、每個 PBXBuildFile 恰好在一個 build phase）、`plistlib` 解析 Info.plist、逐行驗 InfoPlist.strings 的 `"key" = "value";` 語法、UTF-8 無 BOM、兩語系 key 與 Info.plist 權限 key 完全一致。另做 4 種故意改壞的測試，腳本都能抓到。

---

## 2. 上次 iOS 是怎麼建置／簽章／上傳的（依紀錄整理）

| 項目 | 內容 | 出處 |
|---|---|---|
| Bundle ID | `com.voltraware.gatewayCommissioning` | `project.pbxproj:512` |
| Team | `WS5238QS59`；簽章為 Xcode 自動管理（Runner 沒寫 `CODE_SIGN_STYLE`，預設 Automatic，**未確認**） | `project.pbxproj:504` |
| Apple 帳號／憑證 | 在公司 Mac 的 Xcode → Settings → Accounts 與鑰匙圈（Keychain）；不在 repo | `APP_RELEASE_MANUAL.md` §9 |
| 後台金鑰與 CA | Mac 上的 `APP_v2/.secrets/prod.env`、`APP_v2/.secrets/ca.crt`（已被 git 排除；Mac 上是否還在**未確認**） | `IOS_BUILD.md` |
| 建置輔助 | `ruby tools/build_ios.rb --check`（唯讀）→ `--configure`（把正式後台設定寫進 `ios/Flutter/Generated.xcconfig`，**會把正式金鑰寫進本機產生檔，不可分享或 commit**）→ Xcode 建置 | `IOS_BUILD.md`、`tools/build_ios.rb` |
| 上傳 | Xcode Product → Archive → Organizer 驗證、上傳 App Store Connect → TestFlight 裝到 iPhone | `APP_RELEASE_MANUAL.md` §9 |
| 版本慣例 | Version 固定 **1.0.11**，只遞增 Build；同一核定 commit 的 Android 與 iOS **共用同一 Build 號**。Xcode 的 Version／Build 來自 `pubspec.yaml`（`$(FLUTTER_BUILD_NAME)`／`$(FLUTTER_BUILD_NUMBER)`），**不要在 Xcode General 頁手改** | `APP_RELEASE_MANUAL.md` §1、`Info.plist` |
| 上次已知 iOS 紀錄 | 2026-09-30：使用者在 iPhone 跑完整配置流程、用 TestFlight 管理，當時 TestFlight 有 iOS Build 21（Version 1.0.0）。之後 Build 22–51 紀錄都寫「未建置／上傳 iOS」 | `HANDBOOK_CODEX.md` 2026-09-30 段 |

注意：上次在 TestFlight 的 Version 是 1.0.0，這次是 1.0.11。App Store Connect 目前實際狀態**未確認**；若與上述策略不符，手冊規定先回報差異、不自行另開 Version 或撤換審查中的提交。

---

## 3. 在 Mac 上的步驟

### 3.1 同步程式碼

```sh
cd <Mac 上的 APP_v2 路徑>          # 路徑未確認
git status                         # 必須乾淨
git fetch origin
git checkout main
git pull --ff-only origin main
git log -1 --format='%h %s'        # 要等於 Android Build 52 的來源 commit
grep '^version:' pubspec.yaml      # 要是 version: 1.0.11+52
```

- 寫這份文件時 `pubspec.yaml` 還是 `1.0.11+51`，Build 52 的版號與 Phase C 由 Windows 端 commit／push。**若 Mac 看到的不是 `1.0.11+52`，先停，不要在 Mac 上自己改版號。**
- `.secrets/prod.env`、`.secrets/ca.crt` 必須在 Mac 的 `APP_v2/.secrets/`（不在 git 裡）。

### 3.2 Flutter 與 CocoaPods

```sh
flutter --version
flutter pub get                    # pubspec 有 generate: true，會一併產生 l10n
flutter gen-l10n                   # 保險再跑一次；lib/l10n/app_localizations*.dart 應無 diff
git status                         # 若 gen-l10n 讓 lib/l10n 有 diff，表示 ARB 與產生檔不同步，先回報
cd ios
pod install                        # 失敗再試 pod install --repo-update
cd ..
```

### 3.3 套用正式後台設定

```sh
ruby tools/build_ios.rb --check        # 唯讀，印出 prod_env_ready 等布林值
ruby tools/build_ios.rb --configure    # 寫入 Generated.xcconfig（含正式金鑰，勿分享）
grep -E 'FLUTTER_BUILD_(NAME|NUMBER)' ios/Flutter/Generated.xcconfig
# 要看到 FLUTTER_BUILD_NAME=1.0.11、FLUTTER_BUILD_NUMBER=52
```

`--configure` 用 `--no-pub`，所以 §3.2 的 `flutter pub get` 一定要先跑。之後若又跑了一般的 `flutter run`／`flutter build`，要重跑 `--configure`。

### 3.4 先用 plutil 驗檔（Mac 才有）

```sh
plutil -lint ios/Runner/Info.plist
plutil -lint ios/Runner/en.lproj/InfoPlist.strings
plutil -lint ios/Runner/zh-Hant.lproj/InfoPlist.strings
plutil -lint ios/Runner.xcodeproj/project.pbxproj
```

四個都要印 `OK`。

### 3.5 Xcode 檢查（開 `ios/Runner.xcworkspace`，不是 `.xcodeproj`）

```sh
open ios/Runner.xcworkspace
```

1. **Localizations 列表**：左側點藍色 Runner 專案 → PROJECT「Runner」→ Info 分頁 → Localizations。應有 English（Development Language）、Chinese, Traditional（zh-Hant），以及 Base（或勾選 Use Base Internationalization）。
2. **InfoPlist.strings 在檔案樹**：Runner 資料夾下有 `InfoPlist.strings`，展開有 `InfoPlist.strings (English)`、`InfoPlist.strings (Chinese, Traditional)`。點任一個 → 右側 File Inspector → Localization 區應勾選 English 與 Chinese, Traditional；Target Membership 只勾 Runner。
3. **Build Phases**：TARGETS「Runner」→ Build Phases → Copy Bundle Resources 內有 `InfoPlist.strings`（只有一個，不是兩個語言各一條）。
4. **顯示名稱**：TARGETS「Runner」→ General → Display Name 顯示「GIOS 設備助手」（預設值，正確）。不要在這裡改成英文——英文由 en.lproj 覆寫。
5. **版本**：General → Identity 的 Version／Build 應顯示 `$(FLUTTER_BUILD_NAME)`／`$(FLUTTER_BUILD_NUMBER)` 或 1.0.11／52，不要手改。
6. **簽章**：Signing & Capabilities → Team 選公司帳號（Team ID `WS5238QS59`），Bundle Identifier `com.voltraware.gatewayCommissioning`，無紅字。

若 1–3 任一項不對，照 §6.1 用 Xcode 重加。

---

## 4. 建置與裝到手機

### A. 快速確認：Xcode 直接裝到接線的 iPhone

1. iPhone 用線接 Mac，Xcode 上方裝置選該 iPhone。
2. **Product → Scheme → Edit Scheme… → Run → Build Configuration 改成 `Release`**（原因見 §6.4：Debug 版從桌面點開不會啟動，驗不了「重開仍英文」）。
3. Product → Run（⌘R）。裝好後拔掉線、從桌面圖示重開測試。
4. 驗完把 Scheme 改回 Debug（Scheme 檔有進 git，**不要 commit 這個改動**）。

### B. 正式：Archive → TestFlight（沿用 `android_releases/docs/APP_RELEASE_MANUAL.md` §9）

**上傳 TestFlight 屬對外發布，要使用者本人決定。**

1. 先確認 App Store Connect 該 App 的 Version 1.0.11 下 **Build 52 還沒用過**；用過就兩平台下一輪統一改用更高的未使用號，不重傳不同產物冒充同號。
2. Xcode 裝置選「Any iOS Device (arm64)」→ Product → Archive。
3. Organizer → 選這次 Archive → 右鍵 Show in Finder → 顯示套件內容 → `Products/Applications/Runner.app/Info.plist`，核對 `CFBundleShortVersionString=1.0.11`、`CFBundleVersion=52`、Bundle ID。也可確認 `Runner.app/en.lproj/InfoPlist.strings` 與 `Runner.app/zh-Hant.lproj/InfoPlist.strings` 存在（Xcode 建置時可能轉成二進位或 UTF-16，用 `plutil -p` 看內容）。
4. Distribute App → App Store Connect → Upload；不要讓工具自動改 Version／Build。
5. 等 Apple processing 完成，在 TestFlight 看到 `1.0.11 (52)` 後，iPhone 開 TestFlight 更新。

---

## 5. 驗收清單

先把 iPhone 系統語言設為英文（設定 → 一般 → 語言與地區 → iPhone 語言 → English），或只改本 APP：設定 → GIOS 設備助手 →「語言」→ English（APP 有兩種語系才會出現這一項）。

| # | 項目 | 期望 | 結果 |
|---|---|---|---|
| 1 | 桌面 APP 名稱（英文系統） | "GIOS Device Assistant"。**桌面可能被截成 "GIOS Device…"**（iOS 桌面寬度有限），在 App Library／Spotlight／設定 內看完整名稱 | |
| 2 | 桌面 APP 名稱（繁中系統） | 「GIOS 設備助手」 | |
| 3 | 權限提示（英文系統） | 藍牙、位置（Wi-Fi 名稱）、區域網路三種提示都是英文。**提示只在第一次出現**：要重看須刪掉 APP 重裝（刪除會清掉 APP 內本機資料，如最近閘道器），或設定 → 一般 → 移轉或重置 iPhone → 重置 → 重置位置與隱私權 | |
| 4 | APP 第一次開（英文系統） | 畫面仍是**繁中**（設計如此：預設繁中、不跟系統） | |
| 5 | 「更多」→「語言」→ English | 全 APP 立即變英文 | |
| 6 | 滑掉 APP 再從桌面重開 | 仍是英文 | |
| 7 | 主要畫面英文不破版 | 首頁、配置流程各步驟、完成頁、狀態頁、更多選單：無文字溢出／黃黑條紋、按鈕字不被截斷到看不懂；可在設定 → 顯示與亮度 → 文字大小 加大再看一次 | |
| 8 | 上傳／分享的報告 | 英文模式下產生的安裝報告／現場報告**仍是中文** | |
| 9 | 切回繁中 | 「More」→「Language」→ 繁體中文，全 APP 回繁中；重開仍繁中 | |
| 10 | 版本 | APP 內顯示的版本為 1.0.11（52） | |
| 11 | 回歸 | 繁中模式跑一次 BLE 找閘道器 → 讀狀態，功能與 Build 51 一致（實機配置是否完整再跑，由使用者決定） | |

---

## 6. 可能的坑

### 6.1 Xcode 不認手改的 pbxproj（Localizations 缺語言、InfoPlist.strings 變紅字或不在 Build Phases）

1. 先關 Xcode，`git checkout -- ios/Runner.xcodeproj/project.pbxproj` 確認是 repo 版本，重開 `Runner.xcworkspace` 再看一次。
2. 仍不行就用 Xcode 重加：
   1. 在檔案樹刪掉 `InfoPlist.strings` 群組（選 **Remove References**，不要 Move to Trash；兩個 `.lproj` 實體檔保留）。
   2. PROJECT「Runner」→ Info → Localizations：若沒有 Chinese, Traditional，按「+」選 Chinese, Traditional (zh-Hant)，跳出的檔案清單全部取消勾選（不要讓它複製 storyboard）→ Finish。
   3. File → Add Files to "Runner"… → 選 `ios/Runner/en.lproj/InfoPlist.strings`，勾 Target：Runner，不要勾 Copy items。Xcode 通常會自動認出 `zh-Hant.lproj` 那份並合成一個 InfoPlist.strings；若沒有，選它 → File Inspector → Localization 勾上 Chinese, Traditional（若問要不要覆蓋現有檔，選保留現有檔／不要覆蓋）。
   4. 回到 §3.5 的 1–3 再檢查一次。
   5. `git diff ios/Runner.xcodeproj/project.pbxproj` 看 Xcode 改了什麼，**只保留 InfoPlist.strings／knownRegions 相關的改動**再交回 Windows 端 commit。
3. Info.plist 不要放進 Copy Bundle Resources（會出現 "Multiple commands produce Info.plist"）。

### 6.2 CocoaPods／Flutter 版本
- `pod install` 失敗：先 `pod repo update` 或 `pod install --repo-update`；仍失敗看是否 Mac 的 Flutter 版本與 Windows 不同（`flutter --version` 兩邊比對）。
- 出現 "CocoaPods could not find compatible versions"：不要改 `Podfile` 的 `platform :ios, '15.0'`，先回報。
- 專案同時有 Flutter 產生的 Swift Package（`FlutterGeneratedPluginSwiftPackage`）與 CocoaPods，屬正常。

### 6.3 簽章
- "No account for team WS5238QS59"：Xcode → Settings → Accounts 登入公司 Apple 帳號。
- "Failed to register bundle identifier"：表示 Team 選錯，不要改 Bundle ID。
- 新 iPhone 第一次跑開發版：iPhone 設定 → 一般 → VPN 與裝置管理 → 信任開發者；iOS 16 以上還要開「開發者模式」。

### 6.4 Debug 版從桌面點不開
- Flutter Debug 版在 iOS 14 以上只能由 Xcode／flutter 啟動，從桌面點圖示會閃退或白畫面。所以 §4-A 要把 Run 改成 Release（或用 TestFlight）。

### 6.5 英文名稱不生效
- 桌面名稱仍是中文：確認系統語言／APP 語言真的是英文；iOS 有時會快取桌面名稱，**刪掉 APP 重裝或重開機**再看。
- 只有權限提示是英文、APP 內是中文：正常（§1 說明），APP 內要從「更多」→「語言」切。

### 6.6 其他
- `--configure` 之後 `ios/Flutter/Generated.xcconfig` 含正式金鑰，此檔已被 git 排除，**不要分享、不要強制加入 git**。
- Xcode 可能自動修改 `project.pbxproj`（例如升級專案格式）或 `Runner.xcscheme`；這些不要順手 commit，先回報再決定。

---

## 7. Windows 上無法驗證、要在 Mac 確認的項目

1. `plutil -lint` 四個檔都 OK（§3.4）。
2. Xcode 正確顯示 Localizations 與 InfoPlist.strings 變體群組、Build Phases 只有一條（§3.5）。
3. 實際建置成功；Archive 內有 `en.lproj`／`zh-Hant.lproj` 的 InfoPlist.strings。
4. 英文系統下桌面名稱與權限提示為英文；桌面名稱截斷程度。
5. Mac 上 `.secrets/` 兩個檔是否還在、`build_ios.rb --check` 是否通過。
6. App Store Connect／TestFlight 現況（Version 1.0.11 是否存在、Build 52 是否可用）。
7. 主要畫面英文版實機排版。
