# Header and recent metrics follow-up (2026-10-06)

- User reports tiny English title, wrapped Chinese title, and requests PTU IOUT, separate PTU/PRU temperatures and efficiency on Recent data.
- Existing uncommitted edits in commissioning_page, gateway_discovery, verify_live_panel and their layout tests are preserved except the title behavior explicitly requested here.
- Header plan: keep a normal-size, single-line name; move support and environment controls to a separate toolbar row. Keep the existing More menu beside the title.
- Recent-data contract currently exposes input_mv/input_ma/bus_mv/temp_c only. Asked user for metric field names and efficiency definition; dependent data changes pending.
- Prior TLS report remains unresolved; current screenshots show data uploads working, which does not establish what fixed that earlier build's TLS error.
- Header implemented: full single-line title with no scale-down, existing menu beside it, support/environment controls in a 48 dp secondary row. Existing title text-scaling cap of 1.3 is retained.
- Focused title widget test passed: `flutter test --no-pub test/en_layout_test.dart --name 'AppBar title whole' --reporter expanded` (Flutter 3.44.3), 1 test passed across start/gateway pages and text scales 1.0, 1.3 and 1.5. The test now asserts one line, no shrinking, and no overlap with either controls row.
- Read-only schema retrieval using the existing CA was blocked by Python's certificate verifier (`CA cert does not include key usage extension`). No certificate verification bypass or server/environment changes were made. Backend field definitions are still needed; current parsing and old current values have not been relabeled as IOUT.
- Required recovery regression passed: `flutter test --no-pub test/link_loss_test.dart --name 'step 8 stops at a phone link loss|restore .*configures only unfinished PTUs' --reporter expanded`, 2 passed.
- Header has not been rebuilt/installed on the iPhone in this turn. Recent metrics remain pending backend field definitions and the efficiency basis; no speculative field mappings were added.

## PRU clarification and API contract
- User confirmed current means PRU IOUT, and requested device errors on Recent data.
- Located backend source via GitHub: MariaDb_Contabo_Server_Master, branch rewrite/commissioning-20260922, dashboard-api/app_recent.py. Its SQL/serializer excludes receiver measurements and error_num.
- Prepared docs/backend_recent_pru_metrics.patch to add existing database columns pru_iout (mA), pru_vrect (mV), pru_Temp_degC (C), error_num. Existing temp_c is ptu_ampTemp_degC.
- App now parses additive fields, uses receiver current only in latest/history, shows separate temperatures and efficiency. Missing fields remain unknown, never input-current fallback. Efficiency follows dashboard services.py formula: 100 * PRU VRECT * IOUT / (PTU VIN * IIN), same sample; zero input or missing data is unknown.
- Error number > 0 or PTU fault state triggers a red device warning. Upload freshness is separate from device health. History includes error codes.
- Server patch is prepared only; it has NOT been deployed. App has NOT been rebuilt/installed. Validation pending.

## Validation and remaining delivery
- User asked to show raw error codes first; descriptions will be supplied later. No error-code interpretation was invented.
- Backend source inspected at commit e739bf8f1c7bd692babf8f6f4b401b16b1cff856. Patch target: dashboard-api/app_recent.py in MariaDb_Contabo_Server_Master (rewrite/commissioning-20260922).
- Flutter 3.44.3 targeted recent-data tests: 2 new PRU/error tests passed; 2 updated legacy-data/table-layout tests passed. Tests distinguish 2.00 A input from 1.50 A receiver output, verify 72% efficiency, separate 49/37 C temperatures, missing receiver values, code 12, history code, and refresh clearing the warning.
- Required link-loss/killed-app restore tests: 2 passed. Backend patched serializer isolated tests: 2 cases passed (no database/live deployment test). ARB merge/button consistency passed; git diff whitespace check passed.
- Backend deployment steps: apply docs/backend_recent_pru_metrics.patch in the backend checkout using git apply, run its focused app_recent tests, and deploy through that project's documented process. No database schema migration is introduced: all selected fields already exist in backend services.py.
- Then rebuild/install the APP using the configured Flutter 3.44.3 iOS process; compare station 20 / gateway 1 PRU IOUT and temperatures against the backend, and verify a real error code if available. These deployment/device checks remain outstanding; do not describe them as completed.
- Existing compact-layout font-dependent suite was not run in this turn. Its fixture now supplies receiver current for its existing current layout expectations; additional measurement rows may require scrolling on small devices.

## Display correction
- User clarified: current reads PRU IOUT, but measurement labels must not show PTU/PRU. Current now uses the existing localized Current label; temperature labels use Transmitter temp / Receiver temp (發射端溫度 / 接收端溫度).
- Latest card displays separate PTU MAC and PRU MAC rows; missing PRU MAC remains --:--:--. The additive server patch now exposes the existing pru_mac database field.
- Focused PRU metrics/widget tests: 2 passed, including distinct current source, localized labels, both MAC addresses, and raw error code. Backend PRU MAC serializer check passed.
- Changes remain source-only; neither server deployment nor iPhone installation has occurred.

- User supplied real backend log, station 20 / gateway 1 at 2026-10-06 11:38:15: PRU IOUT 1051 mA, PTU input 1403 mA, temperatures 59/20 C, PTU MAC DF:B0:25:F3:40:AC and PRU MAC 2F:F7:F6:24:00:A2, error 0. Dedicated regression verifies current 1.05 A using existing two-decimal A formatting (raw current retained as 1051 mA). Existing dashboard efficiency formula gives 61.1%.
- Required recovery tests after label/MAC correction: 2 passed.

## User-provided error code descriptions
- Added the exact supplied 19-code mapping with Chinese and English descriptions. Latest card and history show description plus padded uppercase hex code; unknown codes show 未知錯誤 (0xXX). Null remains unknown (--), distinct from 0 / no error.
- Codes 163 (PRU charged), 178 (charge complete), 179 (restart charging) are informational; zero is normal. Other nonzero codes are faults. Independent PTU fault state still triggers a warning even if the code reports a completion notice.
- Focused code-table, localization and widget tests: 3 passed, including notifications replacing the prior red fault on refresh and unknown code in history. Deployment/iPhone installation remains outstanding.
