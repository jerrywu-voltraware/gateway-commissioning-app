import '../l10n/l10n.dart';

/// The backend credential of this build (09-28: field staff never type a
/// backend password). `tools/build_apk.ps1` injects it from the git-ignored
/// `.secrets/<env>.env` (`APP_BACKEND_KEY=...`, see README) through
/// `--dart-define-from-file`; a plain `flutter run` has none.
///
/// The APP exchanges it for a session token (`POST /api/auth/app-login`)
/// and caches that token as before. On the backend it is `APP_API_KEY`,
/// accepted only by the commissioning endpoints (dashboard-api
/// `app_key_auth.py`), so an APK that leaks it opens no admin page.
const buildBackendKey = String.fromEnvironment('APP_BACKEND_KEY');

/// Shown where a password field used to be when the build has no key.
String get missingBackendKeyText => L10n.current.backendKey_missing;
