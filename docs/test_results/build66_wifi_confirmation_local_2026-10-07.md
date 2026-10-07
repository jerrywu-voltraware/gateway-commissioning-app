# Build 66: Wi-Fi confirmation before station selection

- Scope: user requested a signed release APK installed on the connected phone. No public release or remote push requested.
- Source: `fb659c7`; version `1.0.11+66`.
- Wi-Fi keep/change is a separate decision before site selection. Selecting a site cannot silently choose the current Wi-Fi.
- New gateways verify Wi-Fi and the upload target before station provisioning; MQTT account establishment follows station selection. Existing commissioned gateways retain the upload-readiness requirement.
- Confirmation belongs to the connected gateway and exact SSID. Returning to Wi-Fi confirmation permits changing the network. Wi-Fi-only changes preserve existing device identity.
- Firmware unable to report network status receives explicit upgrade guidance. Delivery targets the current 1.7.47 gateways; completed station steps retain existing resume behavior.
- Independent source review passed. Scoped Dart analysis reported no issues. Functional and physical-device acceptance tests were not run, as requested.
- Release build passed in 190.2 seconds; official v2/v3 signature, zipalign, package/version, production endpoint and all new localized strings across three ABIs passed independent verification.
- APK: `build/dist/app_fb659c7_b66_prod.apk`, 61,243,812 bytes; SHA-256 `6ad5569aa145b9384a1ffc2a7d9a8cc3f2a082dcb21797a13584b74bcfd63825`.
- `adb install -r` on connected phone `ce08171898c05cdd0c7e` returned `Success`; package readback is versionCode 66 / versionName 1.0.11. Installed base.apk SHA-256 equals the delivered APK. Existing app data preserved; no uninstall or data clearing.
- Public update channel remains Build 65; Build 66 is delivered locally and its build number is consumed. No push, public release or backend deployment performed.
- Evidence: `build66_artifact_review_2026-10-07.json`. Artifact retained in the main workspace; isolated build worktree cleaned after verification.

## User acceptance on the phone

1. Start configuration on a connected gateway: confirm that Wi-Fi choice appears before station selection even when Wi-Fi already works.
2. Choose to keep Wi-Fi, then verify station selection opens.
3. Return to Wi-Fi confirmation and choose another Wi-Fi: save the network, then verify station selection follows successful connection.
4. On an existing gateway, verify its site/gateway identity is unchanged by a Wi-Fi-only change.
