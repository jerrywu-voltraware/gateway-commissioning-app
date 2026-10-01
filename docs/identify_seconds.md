# 辨識秒數（2026-10-01）

右上角更多 → 連接模式，既有設定對話框內的「辨識秒數」。整數 0..255，預設 6；
按「儲存秒數」後保存到 SharedPreferences 的 identify_seconds，重啟沿用。
0＝PTU 關燈；Gateway 只取消辨識燈效、恢復正常狀態燈，不永久關閉其他指示。

掃描清單與配置頁都使用同一偏好，送 identify {target:both,duration_ms:秒數*1000}。
新 Gateway（get_config.identify_ptu_protocol=a2_seconds）同時套用 Gateway LED 與 PTU。
PTU 封包 A2 00／A2 01／A2 05／A2 06／A2 FF，無應用層回覆。
APP 的「已送出」只代表 Gateway 處理／提交成功，不是 PTU 已執行；0 不建立新的辨識資格。

舊 Gateway：identify_ptu_supported=true 時支援 1..30 秒；更早裸 identify 固定 6 秒。
不支援所選值時明確提示，不夾限或忽略設定。保留歷史 ACK 解析，timeout 不再推論 PTU 未實作。
Gateway target/mac/編號/綁定選台行為不變。儲存偏好本身不發硬體指令。
