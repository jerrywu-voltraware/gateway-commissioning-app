# 明確連線與識別：BLE 生命週期修正（2026-10-01）

本文件取代 cb2272d「點卡自動連線」流程。快速換卡的實機 log 顯示新 connect 早於舊 client unregister；慢速也曾出現 133，故不把所有 133 歸因於同一競爭。

## 使用流程

| 動作 | 結果 |
|---|---|
| 點選卡片 | 僅選擇並凍結列排序；不啟動連線、不改 Gateway 設定。 |
| 連線以辨識 | 停止掃描並等待清理，連到所選 Gateway；services、notify、MTU 嘗試（或回退 MTU 23）與唯讀 get_config 完成後顯示已連線。 |
| 連線中／斷開中 | 不接受別台或重複 connect，不排隊補連。可取消連線，畫面等待舊操作清理。 |
| 閃燈辨識 | 僅同台 ready 連線可用；送既有 identify，依 ACK 區分 Gateway／PTU 結果。掉線時不隱藏重連。 |
| 斷開 | 先排空舊操作與 cleanup；成功後才可選另一台並明確連線。 |
| 清理失敗／逾時 | 保留隔離狀態，顯示重試斷開；不得把 timeout 當成功，不允許下一 connect。 |
| 開始開通 | 需所選同台已連線，才沿用 held link 進入既有配置流程。只有此明確動作可進入 build mode／配置準備。 |
| 返回／取消／完成／配置下一台 | 等待清理；失敗保留原頁、必要進度與可重試出口。 |

找裝置與識別路徑沒有 set_config、set_ble_enabled、enterBuildMode。未連線、錯台或忙碌時 identifyPeer 拒絕執行；不保留臨時自動連線分支。既有正式配置、fleet 與 PTU 安全規則保留。

## 排程與失效結果

- BleGatewayLink 一次只接受一個連線生命週期；新 connect 在掃描、連線、斷開或清理隔離期間拒絕。
- disconnect 先使 epoch 失效，再等待未完成原生操作與命令佇列，最後清理；每階段檢查 epoch，舊 Future／訂閱不得繼續 setup 或更新新 session。
- 清單與 Nearby 狀態頁使用同一個掃描 owner。Nearby 只能在沒有 held/連線操作時開始；舊頁 finally 完成前不會啟動新掃描或 connect。
- 原生 stopScan 失敗保留隔離；取消訂閱也不丟棄清理錯誤。明確清理成功後恢復。
- 連線／持有／識別／清理期間，狀態頁入口被反應式狀態擋住，避免另一掃描器競爭。
- 60.5 秒是失敗重試的等待預算，排除原生 cleanup/state-query 及 GATT setup；呼叫端 timeout 後仍須等待 disconnect，不代表已釋放。

## 原生限制

universal_ble 2.3.0 沒有 Android GATT close-complete 事件。1.6 秒保護窗超過其 1.5 秒 fallback，再核對 disconnected，是有界防護；極晚的同 MAC 原生 GATT 事件仍需實機驗證。Dart epoch 測試通過不能證明所有原生過期回呼或 133 已根治。

## 驗證範圍

- controller／widget：純選卡零連線、明確 hold、ready 才識別、零隱藏配置、取消與清理失敗恢復、返回／完成失敗保留進度、dispose 不通知已卸載 widget。
- transport：connect／discover／notify／MTU 晚到成功或錯誤、同址與 A/B 重複要求、排空原生操作、清理 timeout 隔離、Nearby 取消與舊 finally 的歸屬。
- 既有配置測試透過 test/support/pick_gateway.dart 執行「選卡 → 明確 BLE 連線 → 開始開通」，保留原配置、安全與恢復斷言。
- 完整測試及 APK／實機結果以 ../../docs/test_results/app_ble_assistant_20261001 的階段記錄與最終報告為準，不把模擬驗證當成實機成功。