# 連上閘道器即切一對一／燈泡未連 PTU 的原因提示（2026-10-01，1.0.0+22）

產品是 1 閘道器 + 1 PTU 同鐵殼，殼外 LED 由 PTU 控制：「辨識」要讓閘道器對已連
PTU 寫 A2 才會亮。舊行為：一對一偏好下，APP 到第 7 步 `_directDiscover` 才送
`set_config {max_connections:1}`；之前閘道器仍是出廠 NVS 的星狀（5），不連新 PTU，
所以清單燈泡與步驟 1-6 的辨識都 `ptu_write=not_connected`。韌體 1.7.46 改出廠預設為
1，但已出貨機器 NVS 仍是 5，由 APP 補救。

## B1 連上閘道器就切一對一（`CommissioningController._ensureDirectLimit`）
- 條件：連接模式偏好＝一對一（`topologyProvider.topology.isDirect`）、韌體支援直連選台
  （`direct_autoconnect_supported`；舊韌體走清單流程，第 7 步自己設上限）、不在
  test mode，且閘道器**不在服務中**（`fleet_joined != true`）。一對多偏好完全不送；
  已是 1 不送。服務中的星狀站（fleet_joined 且 max_connections>1）屬 r33 既有的
  「這台閘道器是星狀模式，要改成一對一嗎？」詢問，由安裝人員決定，不自動切。
- 時機：
  - 主流程 `_connect`：get_config（含 1.0.0+19 的 build mode 讀回）之後、讀網路狀態之前。
  - 清單燈泡 `identifyPeer`（臨時連線）：get_config 之後、identify 之前。
  - 1.0.0+22 起點選卡片即連線並保持（`holdPeer`）：保持連線建立時 get_config 之後；
    選取列的燈泡改用保持中的連線，不再重連（見 `select_then_identify.md`）。
- 動作：`max_connections != 1` → `set_config {max_connections:1}`；`ble_enabled == false`
  → `set_ble_enabled {enabled:true}`（比照第 7 步）。本地 config 同步改成 1／true。
- 韌體收到 max_connections 變更會重啟 BLE 掃描（cmd_handler.c `gios_ble_restart_scan`）；
  手機端 GATT 連線不受影響——第 7 步既有做法就是送完直接輪詢 get_status，這裡沿用，
  不另做等待或重連。
- 第 7 步 `_directDiscover` 判斷不變（已是 1 就不再送）。

## B2 燈泡 not_connected 的具體原因（`identifyPeerGatewayOnlyReason`）
`identifyPeer` 收到 `ptu_write=='not_connected'`（或舊韌體 target=both 失敗、降級成
target=gateway 的路徑）時，趁仍連線多讀一次 `get_status`，由
`identifyGatewayOnlyReasonOf`（core/direct_mode.dart）依 `direct` 區塊判斷，
文案在 presentation/gateway_discovery.dart（`identifiedGatewayOnly*`），SnackBar 顯示：

| 判斷 | 文案 |
|---|---|
| 這次連線剛送過 max_connections=1 | 已切換為一對一，閘道器正在重新尋找 PTU，請稍後再按 |
| `candidates` 為空（且未連 PTU） | 閘道器附近沒聽到 PTU，請確認 PTU 已上電 |
| 候選全部 `rssi_med`（無則 `rssi_peak`）< 門檻 | PTU 訊號太弱（最強 -xx dBm，需 ≥ 門檻），請靠近或檢查天線 |
| 其他（有候選選台中、或 get_status 時已連上 PTU） | 閘道器正在選擇 PTU，請 3 秒後再按 |

門檻取 get_config `auto_connect_min_rssi`，無則 -55（`directMinRssiOf`）。
get_status 讀不到、或韌體沒有 `direct`（舊版／`state:"off"`）→ reason 為 null，
回退既有「閘道器已閃燈；它目前沒連到 PTU，PTU 不會閃」。列上的短提示仍是
「閘道器已閃・PTU 不會閃」。`identifyPeer` 的 `Future<bool>` 簽名不變；每次呼叫重設。

DemoSystem 的 `directStatus()` 候選已補 `rssi_med`／`reason`，供測試。
測試：`test/direct_on_connect_test.dart`。
