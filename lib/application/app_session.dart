/// 1.0.0+7 (field: 「閘道器狀態」 opened from the start page read 「APP 尚未
/// 登入後台，請回到完成頁…」 — the backend login only ever happened inside
/// the commissioning flow): the pages that read the back office on their
/// own (「閘道器狀態」, 「最近資料」) log the APP in themselves, with the
/// build's backend credential ([backendKeyProvider]) against the backend
/// the AppBar's environment switch selects ([backendEnvProvider]).
///
/// [AppSession.run] wraps one backend call: no session for that backend →
/// the saved token ([SessionStore]) or a fresh login first; a 401 during
/// the call → one re-login and one retry; only a refused login surfaces
/// (the pages say 「連不上後台（原因）」 + 〔重試〕). It never touches the
/// commissioning flow's own login bookkeeping ([CommissioningController]
/// logs in again at its own step 1 as before).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/protocol.dart';
import '../data/contracts.dart';
import 'backend_environment.dart';
import 'commissioning_controller.dart' show apiProvider;

final appSessionProvider = Provider<AppSession>((ref) => AppSession(ref));

class AppSession {
  AppSession(this._ref);
  final Ref _ref;

  /// The base URL of the selected environment once its saved choice is
  /// loaded (a failed load keeps the build default).
  Future<String> baseUrl() async {
    try {
      await _ref.read(backendEnvProvider.notifier).ready;
    } catch (_) {}
    return _ref.read(backendEnvProvider).base.trim();
  }

  /// Runs [call] with a logged-in [GatewayApi]; see the library doc.
  Future<T> run<T>(Future<T> Function(GatewayApi api) call) async {
    final api = _ref.read(apiProvider);
    final base = await baseUrl();
    final key = _ref.read(backendKeyProvider);
    if (!hasSessionFor(api, base)) {
      var restored = false;
      if (api is SessionStore) {
        try {
          restored = await (api as SessionStore).restoreSession(base);
        } catch (_) {}
      }
      if (!restored) await api.login(base, key);
    }
    try {
      return await call(api);
    } on GatewayFailure catch (error) {
      if (error.code != 'authentication') rethrow;
      // The token was refused (expired, or the API restarted): once more
      // with the credential.
      await api.login(base, key);
      return await call(api);
    }
  }
}

/// [api] holds a session for [base] (same origin). An API without
/// [SessionInfo] (fakes, the demo system) is logged in every time — the
/// login there is free.
bool hasSessionFor(GatewayApi api, String base) {
  if (api is! SessionInfo) return false;
  final info = api as SessionInfo;
  if (!info.hasSession) return false;
  final uri = Uri.tryParse(base);
  return uri != null && uri.hasAuthority && info.origin == uri.origin;
}
