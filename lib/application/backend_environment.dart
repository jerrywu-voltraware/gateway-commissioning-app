import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/backend_key.dart';
import '../core/local_backend_address.dart';
import '../core/mqtt_target.dart';
import '../data/local_backend_probe.dart';
import '../l10n/l10n.dart';
import 'local_backend_finder.dart';

/// Which backend the APP talks to. The names are the persisted values
/// (`backend_environment`) and the input of [desiredUploadTarget].
enum BackendEnv { production, local, custom }

/// Build-dependent behaviour of the environment switch; injectable in tests.
class EnvSwitchPolicy {
  const EnvSwitchPolicy({
    this.autoSyncDefault = false,
    this.confirmGatewaySwitch = !kDebugMode,
    this.defaultEnvironment = localDevelopmentBuild
        ? BackendEnv.local
        : BackendEnv.production,
    this.localBuild = localDevelopmentBuild,
    this.localAllowed = kDebugMode || localDevelopmentBuild,
  });

  /// r32: the APP may use the local test backend (plain http to a LAN host):
  /// debug and `LOCAL_DEVELOPMENT` builds only, the same rule as the API
  /// client. A prod / prodtest build shows 「本地測試」 as unavailable.
  final bool localAllowed;

  /// Round 29: a local test build (`LOCAL_DEVELOPMENT=true`). Only here does
  /// the done page carry the developer note 「出貨前切回正式站」 (field
  /// drill: it was the done page's biggest button, read as the next step);
  /// a production build never shows it.
  final bool localBuild;

  /// Environment used when nothing was saved yet. A saved choice
  /// (`backend_environment`) always wins over this.
  final BackendEnv defaultEnvironment;

  /// Whether a connect syncs the gateway's upload target by itself
  /// (`set_mqtt_target` without the installer asking). 1.0.0+8: the
  /// 「連線 Gateway 時自動同步上傳目標」 switch is gone from the sheet, so
  /// this is OFF in every build; only tests turn it on. A value saved by
  /// an older version (`auto_sync_upload_target`) is ignored.
  final bool autoSyncDefault;

  /// Release builds ask once before a gateway switch; debug builds do not.
  final bool confirmGatewaySwitch;
}

/// r32: why 「本地測試」 cannot be used in a prod / prodtest build.
String get localUnavailableText =>
    L10n.current.backendEnvironment_localUnavailable;

/// Label of 「本地測試」 where the build cannot use it.
String get localUnavailableLabel =>
    L10n.current.backendEnvironment_localUnavailableLabel;

/// Built with `--dart-define=LOCAL_DEVELOPMENT=true` (field test APKs).
const localDevelopmentBuild = bool.fromEnvironment('LOCAL_DEVELOPMENT');

final envSwitchPolicyProvider = Provider<EnvSwitchPolicy>(
  (ref) => const EnvSwitchPolicy(),
);

const _localDefaultUrl = String.fromEnvironment(
  'LOCAL_API_BASE',
  defaultValue: 'http://192.168.0.12:18000',
);

/// The backend credential this build logs in with ([buildBackendKey]);
/// tests override it.
final backendKeyProvider = Provider<String>((ref) => buildBackendKey);

class BackendEnvState {
  const BackendEnvState({
    this.environment = BackendEnv.production,
    this.localHost = '',
    this.localPort = defaultLocalPort,
    this.customUrl = '',
    this.autoSync = false,
    this.loaded = false,
  });
  final BackendEnv environment;
  final String localHost, customUrl;
  final int localPort;

  /// 「連線 Gateway 時自動同步上傳目標」.
  final bool autoSync;

  /// Saved values have been read from SharedPreferences.
  final bool loaded;

  String get localUrl => composeLocalUrl(localHost, localPort);
  bool get localValid => localHostError(localHost) == null;

  /// Full base URL the APP uses for the selected environment.
  String get base => switch (environment) {
    BackendEnv.production => productionApiBase,
    BackendEnv.local => localUrl,
    BackendEnv.custom => customUrl.trim(),
  };

  /// Upload target the gateway should use for this environment.
  AppUploadTarget get uploadTarget =>
      desiredUploadTarget(environment.name, base);

  String get label => envLabel(environment);

  BackendEnvState copy({
    BackendEnv? environment,
    String? localHost,
    int? localPort,
    String? customUrl,
    bool? autoSync,
    bool? loaded,
  }) => BackendEnvState(
    environment: environment ?? this.environment,
    localHost: localHost ?? this.localHost,
    localPort: localPort ?? this.localPort,
    customUrl: customUrl ?? this.customUrl,
    autoSync: autoSync ?? this.autoSync,
    loaded: loaded ?? this.loaded,
  );
}

String envLabel(BackendEnv env) => switch (env) {
  BackendEnv.production => L10n.current.backendEnvironment_labelProduction,
  BackendEnv.local => L10n.current.backendEnvironment_labelLocal,
  BackendEnv.custom => L10n.current.backendEnvironment_labelCustom,
};

/// Snack text shown at start when the saved choice differs from the build
/// default (e.g. a test APK that remembered 正式站 from step 7's 「切回正式站」);
/// user switches already announce themselves via [_syncGateway]'s snack.
String? environmentChangeHint(
  BackendEnvState? previous,
  BackendEnvState next, {
  required BackendEnv buildDefault,
}) {
  if (previous == null) return null;
  if (!previous.loaded && next.loaded) {
    return next.environment == buildDefault
        ? null
        : L10n.current.backendEnvironment_changeHint(next.label);
  }
  return null;
}

final backendEnvProvider =
    NotifierProvider<BackendEnvController, BackendEnvState>(
      BackendEnvController.new,
    );

/// Single source of truth for the backend environment and its URLs, shared
/// by the prep-page selector and the AppBar switch; persisted under the
/// existing SharedPreferences keys.
class BackendEnvController extends Notifier<BackendEnvState> {
  static const _envKey = 'backend_environment';
  static const _localKey = 'backend_local_url';
  static const _customKey = 'backend_custom_url';
  static const _autoSyncKey = 'auto_sync_upload_target';

  /// Completes once the saved values are loaded.
  Future<void> ready = Future.value();

  @override
  BackendEnvState build() {
    final policy = ref.read(envSwitchPolicyProvider);
    ready = _load();
    return BackendEnvState(
      environment: policy.defaultEnvironment,
      autoSync: policy.autoSyncDefault,
    );
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final oldLocal = Uri.tryParse(prefs.getString(_localKey) ?? '');
    if (oldLocal != null &&
        ['127.0.0.1', 'localhost', '10.0.2.2'].contains(oldLocal.host)) {
      await prefs.setString(_localKey, _localDefaultUrl);
    }
    if (!ref.mounted) return;
    final saved = prefs.getString(_envKey);
    final savedEnv = BackendEnv.values
        .where((e) => e.name == saved)
        .firstOrNull;
    final endpoint =
        parseLocalUrl(prefs.getString(_localKey)) ??
        parseLocalUrl(_localDefaultUrl);
    state = state.copy(
      environment: savedEnv,
      localHost: endpoint?.host ?? '',
      localPort: endpoint?.port ?? defaultLocalPort,
      customUrl: prefs.getString(_customKey) ?? '',
      // 1.0.0+8: the saved switch value no longer overrides the policy.
      loaded: true,
    );
  }

  Future<void> select(BackendEnv env) async {
    state = state.copy(environment: env);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_envKey, env.name);
  }

  /// Stores the typed PC address; it is persisted only once it is valid.
  void setLocalHost(String host) {
    if (host == state.localHost) return;
    state = state.copy(localHost: host);
    unawaited(_saveLocal());
  }

  void setLocalPort(int port) {
    if (port == state.localPort) return;
    state = state.copy(localPort: port);
    unawaited(_saveLocal());
  }

  void setCustomUrl(String url) {
    if (url == state.customUrl) return;
    state = state.copy(customUrl: url);
    unawaited(
      SharedPreferences.getInstance().then(
        (prefs) => prefs.setString(_customKey, url.trim()),
      ),
    );
  }

  Future<void> setAutoSync(bool value) async {
    state = state.copy(autoSync: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoSyncKey, value);
  }

  Future<void> _saveLocal() async {
    final snapshot = state;
    if (!snapshot.localValid) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_localKey, snapshot.localUrl);
  }
}

/// `GET /healthz` of a backend base URL (the 「手機 → 後端」 row). Never
/// sends credentials; an unparsable URL counts as unreachable.
final backendProbeProvider = FutureProvider.autoDispose
    .family<ProbeResult, String>((ref, base) async {
      final uri = Uri.tryParse(base.trim());
      if (uri == null || !uri.hasAuthority) {
        return ProbeResult(
          ProbeOutcome.unreachable,
          detail: L10n.current.backendEnvironment_invalidUrl,
        );
      }
      try {
        return await ref.read(localBackendProberProvider).probe(uri);
      } catch (error) {
        return ProbeResult(ProbeOutcome.unreachable, detail: '$error');
      }
    });
