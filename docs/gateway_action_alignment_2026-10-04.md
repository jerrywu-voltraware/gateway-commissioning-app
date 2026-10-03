# Gateway action alignment (2026-10-04)

- Diagnosis: `_cardActions` estimates the Bluetooth button using the longest possible label. When the estimated action row does not fit, the fallback places Start on its own lower row, matching the reported iOS symptom.
- Implemented: measure the current label and keep Bluetooth and Start together; move the identification control above them when space is limited. Both text buttons share the available width proportionally and can wrap text at larger accessibility sizes.
- Extended the existing card interaction cases with Android/iOS themes and assertions that Disconnect and Start share the same vertical center without overlapping the identification control.
- Layout validation blocked: `flutter test --no-pub test/gateway_card_layout_test.dart --name 'iOS.*320' --reporter expanded` failed in font setup before executing the case (`loadRealFonts()` returned false). Required Roboto/CJK test fonts are unavailable; no environment changes or retries performed.
- Static analysis passed: `dart analyze lib/presentation/gateway_discovery.dart test/gateway_card_layout_test.dart` reported no issues.
- Required recovery regression passed: `flutter test --no-pub test/link_loss_test.dart --name 'step 8 stops at a phone link loss|restore .*configures only unfinished PTUs' --reporter expanded` reported 2 passed.
- Device validation pending. The parent handbook and parent AGENTS.md referenced by this checkout are absent on this Mac; the supplied user rules and repository AGENTS.md apply.

## Remaining validation

- With the required fonts available, run `flutter test --no-pub test/gateway_card_layout_test.dart`.
- On the iPhone, rerun from Xcode, select and connect a gateway, and verify that Disconnect and Start have the same vertical center. Repeat with enlarged system text; identification should move above the pair when space is limited, and all three actions should remain usable.

## AppBar title follow-up

- The single-line title shared toolbar width with the support, environment and menu controls; its inherited overflow behavior ellipsized the name when constrained.
- Wrapped the title in a left-aligned, scale-down-only `FittedBox` so the complete current name, `GIOS 設備助手`, fits the remaining space without changing toolbar height or action hit targets.
- Targeted analysis passed: `dart analyze lib/presentation/commissioning_page.dart` reported no issues. The required recovery command recorded above also passed both cases after this title change (2 passed).
- The existing font-dependent layout validation remains blocked as recorded above; no font/environment changes made. Device appearance is not yet verified.
- iPhone check: rerun from Xcode, open gateway selection with the support icon visible, and confirm the complete title beside all three controls, including with enlarged system text.

## Empty identification row follow-up

- User's new iPhone screenshot shows an empty row between the connection hint and the two buttons before connecting.
- Cause: the preceding narrow-layout change moved `_identifyControl` above the buttons even when it was only the 40 dp placeholder returned before the link was held. Its 4 dp spacing made a 44 dp empty row.
- Fixed `_cardActions` to include identification only for a held connection. Before connecting, neither its width reservation nor its extra row is present; the two text buttons remain together.
- Validation passed: `dart analyze lib/presentation/gateway_discovery.dart` reported no issues. `flutter test --no-pub test/select_then_identify_test.dart test/link_loss_test.dart --name 'rapid A B A B selects only|step 8 stops at a phone link loss|restore .*configures only unfinished PTUs' --reporter expanded` passed all 3 selected cases (selection/connect/identify, phone link loss, killed-app resume).
- The previously blocked real-font layout suite has not been retried. The blank-row fix has not yet been visually verified on the iPhone.
- iPhone check: select a gateway before connecting and confirm the hint sits directly above the buttons; connect and confirm the bulb appears and Disconnect/Start remain aligned.
