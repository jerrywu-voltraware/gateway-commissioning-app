# 點選卡片即連線、燈泡用既有連線（select_then_identify，2026-10-01，1.0.0+22）

## 動機
「選擇附近的閘道器」清單的燈泡原本每次都走「停掃描 → 臨時 BLE 連線 → get_config →
`_ensureDirectLimit` → identify → 斷線 → 恢復掃描」。實測閘道器端 identify < 10 ms，
但 Android 連線＋服務探索＋MTU 約 1.5–3 s、get_config 0.3 s，按下後 3–5 秒 PTU 才亮。
改成：**點卡片（選取）就連上並保持連線；燈泡用這條連線即時送；〔連線到 站X · 閘道器N〕
沿用這條連線進入下一步**。

## 流程
| 動作 | 行為 |
|---|---|
| 點卡片 | 選取＋停掃描（列表凍結、保留已聽到的列與最後 RSSI，同 1.0.0+11 暫停行為；搜尋面板保留、標題改「已選取閘道器，搜尋已暫停」，卡片不移動）→ `CommissioningController.holdPeer`：`_link.connect` → get_config → `_ensureDirectLimit`（一對一偏好、未服務中才送 `max_connections:1`；閘道器拒絕不算失敗）→ 保持連線。卡片標記：連線中…（轉圈）→ 已連線／連線失敗（紅底＋SnackBar「無法連線…請靠近後再點一次卡片」）。不是 run：頁面不 busy，其他卡片、燈泡、底部按鈕都可按。 |
| 選取列的燈泡 | 已連線 → `identifyPeer` 走 `_identifyHeld`：不連線、不讀 get_config、不斷線、不 busy，直接送 identify（`identifyCommandParams`、target=both、`ptu_write=not_connected` 四種原因與「僅閘道器」文案沿用）。連線中按下 → 燈泡轉圈、**排隊**到連上後立即送。連線失敗／已斷線時按下 → 先重新連線再送。 |
| 未選取列的燈泡 | **維持舊的臨時連線**（連 → 辨識 → 斷），選取不變；選取那台的保持連線暫時讓出（同時只能一條連線），辨識完自動重新連回選取那台。理由：沿用 1.0.0+14「辨識不是選取」原則（避免按燈泡就把選取移到鄰樁閘道器），也讓未選取時找樁的動作和以前一樣。 |
| 再點同一張卡片 | 已連線／連線中：不動。連線失敗／已斷線：重試連線。 |
| 點另一張卡片 | 選取移過去；`holdPeer(新)` 先結束舊的（`_link.connect` 會先斷舊連線；舊的晚到結果因 token 過期被忽略，也不會去斷新連線）。 |
| 〔連線到 …〕 | `connect` → `_connect` → `_persistentLink(adopt: true)` → `_adoptHeld`：保持中的連線若是同一台且仍連著 → 直接沿用，**不再 `_link.connect`**；仍在連線中 → 等它完成再沿用；失敗／不同台 → 照舊自己連（含重試）。ping、get_config、build mode、`_ensureDirectLimit`、get_net_status 都在 `_connect` 內照舊各跑一次（保持連線時已切成 1，這裡讀到 1 就不再送）。 |
| 〔重新搜尋〕 | `releaseHeld` 斷線 → 清除選取 → 重新搜尋。 |
| 〔結束配置〕／返回（`leaveList`）、`cancel`、清單離開畫面（dispose → `releaseHeld`）、controller dispose | 釋放；沒有孤兒連線。進到第 2 步時連線已被流程接手，`releaseHeld` 是 no-op。 |
| BLE 斷線事件 | `BleGatewayLink`（`GatewaySignalSource.signalConnections` false）→ `heldLinkLost` 通知清單 → 卡片「已斷線」紅底＋SnackBar「…藍牙連線已中斷，再點一次卡片或按燈泡會重新連線」。不支援狀態回報的 link（demo）由下一個指令的 not_connected/disconnected/ble_error/timeout 判定，同樣通知。不自動重連（避免與其他頁面的掃描互搶）。 |

## 掃描恢復規則
- 選取期間（清單有 `onHold`）不掃描：`BleGatewayLink.scanLive()` 開頭會 `disconnect()`，掃描會斷掉保持的連線。`_start`／`_resumeScan`（回到前景、從其他頁面回來、重新啟用）都被擋下。
- 只有〔重新搜尋〕（先釋放連線、清除選取）會重新開始掃描。
- 未選取時一切照舊（自動二次搜尋、停止搜尋、背景暫停／恢復）。

## 實作位置
- `lib/application/commissioning_controller.dart`：`holdPeer`／`_hold`／`_holdCommand`（busy 重試、journal、token 取消）／`releaseHeld`／`heldLinkLost`／`heldPeerId`／`_adoptHeld`／`_identifyHeld`／`_peerIdentify`（臨時與保持兩路共用的 identify＋原因判斷）；`identifyPeer` 先看保持連線；`_persistentLink(adopt:)`；`cancel`／`leaveList`／dispose 釋放；常數 `heldSwitchSettle`（15 s 內 gateway-only 原因報「已切換為一對一」）。
- `lib/presentation/gateway_discovery.dart`：`GatewayDiscovery.onHold`／`onRelease`／`holdLost`；`_select`、`_holdSelected`、`_identifySelected`、`_releaseHold`、`_onHoldLost`；卡片標記 `已連線`／`連線失敗`／`已斷線`（`_SelectedMark`，強制行高，卡片不因「…」字型而長高）。
- `lib/presentation/commissioning_page.dart`：接上 `c.holdPeer`／`c.releaseHeld`／`c.heldLinkLost`。
- `lib/data/demo_system.dart`：`linkedPeer`、`linkDisconnects` 供測試與 demo 觀察。
- `lib/data/ble_gateway_link.dart` `connect`：被新連線取代的舊連線若事後才連上，補一次 `UniversalBle.disconnect`（新連線是同一台時不做），避免快速換卡片留下沒人管的 GATT 連線。
- 保持中的連線指令失敗（not_connected／disconnected／ble_error／timeout）除了通知清單，也主動斷線（`_dropHeld`），避免逾時後連線仍在卻沒人負責。

## 測試
`test/select_then_identify_test.dart`（controller、清單元件、整個 APP 三層）；`test/gateway_select_test.dart` 四條依新行為更新。

## 未實機驗證
- Android 上保持 GATT 連線時 `stopScan`／`connect` 的實際行為與時間；燈泡實際延遲。
- 保持連線期間閘道器收到 `max_connections` 變更重啟 BLE 掃描時手機連線是否真的不斷（程式碼層判定韌體只斷 PTU）。
- APP 進背景時保持中的連線（Android 可能被系統回收；回前景不自動重連，靠「已斷線」提示）。
- 被選取的閘道器在連線期間不廣播：同一現場其他手機看不到它，直到〔重新搜尋〕或離開清單。
- `ble_gateway_link.dart` 舊連線補斷線的時序（只有 host 測試，未上機）。
- 已知小缺口：保持中的燈泡 identify 還在等回覆時按〔連線到 …〕，PTU 已閃但清單不顯示「已送出」（流程接手連線，結果被丟棄）。
