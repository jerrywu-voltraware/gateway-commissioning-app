# 辨識秒數（2026-10-01，PTU 辨識封包 A2 xx 規格更新）

右上角更多 → 連接模式，既有設定對話框內的「辨識秒數」。合法值只有 0（關燈）與
2..10 的整數秒，預設 4（2026-10-01 由 6 改為 4，PTU 封包 A2 04）；按「儲存秒數」後保存到 SharedPreferences 的
identify_seconds，重啟沿用。

PTU 封包 A2 xx，無應用層回覆：
- A2 00：關閉 PTU 燈。
- A2 01：恆亮，不會自己熄（不是 1 秒），要等 A2 00 才關。
- A2 02..A2 0A：亮 2..10 秒後自動關閉。

所以 APP 不提供 1 秒：1 與大於 10 的值一律明確拒絕（設定欄位報錯；指令組裝丟
invalid_identify_seconds），不夾限、不忽略設定，也絕不送出 duration_ms=1000。
0＝PTU 關燈；Gateway 只取消辨識燈效、恢復正常狀態燈，不永久關閉其他指示。

掃描清單與配置頁都使用同一偏好，送 identify {target:both,duration_ms:秒數*1000}。
新 Gateway（get_config.identify_ptu_protocol=a2_seconds）同時套用 Gateway LED 與 PTU。
APP 的「已送出」只代表 Gateway 處理／提交成功，不是 PTU 已執行；0 不建立新的辨識資格。

舊偏好值：舊版 APP 可能存下 1 或大於 10（舊規格允許 0..255）。載入時不合法的值
（1、>10、負數、非整數）一律退回預設 4，不原值送出也不夾限成別的值；設定對話框顯示的
就是實際採用的值，儲存偏好本身不發硬體指令，舊值留在儲存區直到使用者重新儲存。

舊 Gateway：identify_ptu_supported=true 時支援 1..30 秒（舊版 3 byte 封包，與 A2 xx
無關）；更早裸 identify 固定 6 秒。不支援所選值時明確提示，不夾限或忽略設定。
因偏好值只會是 0 或 2..10，舊 Gateway 實際會遇到的只有 0（舊 PTU 版不支援、提示更新
韌體）與非 6 秒（更早版本不支援）。注意：預設 4 ≠ 更早版本固定的 6，所以未支援 PTU
辨識的舊閘道器在預設值下會直接得到 identify_duration_unsupported 提示（不再因預設剛好
是 6 而相容）；要對這種閘道器辨識需手動把秒數設成 6。歷史 ACK 解析仍容忍 0..255 秒（identifySecondsOf），
timeout 不再推論 PTU 未實作。
Gateway target/mac/編號/綁定選台行為不變。

韌體備註：ble_multi_wifi_gateway identify_command.h 目前仍接受 0..255 秒並把
duration_ms=1000 轉成 A2 01，由 APP 端保證不送 1 秒；韌體端是否同步另行決定。
