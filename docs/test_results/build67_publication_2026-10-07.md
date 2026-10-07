## Android Build67 active - 2026-10-07 14:48 Taiwan

- Version1.0.11 Build67; source2e416406b4ef786c482f14c8ee82dc7c91607abd, source tag android-v1.0.11-b67. Public release405461646; run20261007T064620Z.
- Gateway list exit moved to fixed bottom bar under search, labeled Back to home with home icon; confirmation wording aligned. Includes Build66 explicit Wi-Fi confirmation before station selection.
- Signed APK app_2e41640_b67_prod.apk,61243812 bytes,SHA256fd119b3ce378a8714177b266647c9b6f38d94c2bd97a7563f07f1f87bc6ac665. Release build133s; static analysis, independent source/artifact/pins review, signature/zipalign/three-ABI endpoint/localization checks passed.
- Full draft/public downloads and production HTTPS readback passed. Channel65->67; old65 assets and all nine running services unchanged. No backend/firmware deployment or iOS release.
- No functional tests or ADB install this round; user accepts by in-app update. Existing field-guide changes preserved. APK retained APP_v2/build/dist; isolated APP_build67 cleaned after artifact preservation checks.
- Evidence: workspace docs/test_results/build67_artifact_review_2026-10-07.json, android_build67_rollout_pins.json, build67_draft_verification_2026-10-07.json, android_build67_public_channel_github_2026-10-07.json, android_build67_public_channel_post_2026-10-07.json.
- Authorized rollback only: py -3 -X utf8 tools/deployment/run_build67_rollout.py rollback restores channel65, preserves assets; installed phones are not downgraded.
- Next candidate Build68; Build66 remains a local-only delivery already consumed.
