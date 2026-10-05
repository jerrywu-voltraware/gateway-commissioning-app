import 'dart:async';
import 'package:flutter/material.dart';
import 'next_action_guide.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import '../application/backend_environment.dart';
import '../application/commissioning_controller.dart';
import '../core/direct_mode.dart';
import '../core/gateway_identity.dart';
import '../core/gateway_proximity.dart';
import '../core/protocol.dart';
import '../data/contracts.dart';
import '../data/nearby_gateway_scan.dart';
import '../data/recent_gateways.dart';
import '../l10n/l10n.dart';

// i18n（docs/i18n.md）：其他檔與測試引用的 top-level 文字維持同名，由 const
// 改成讀 [L10n.current] 的 getter；字串在 lib/l10n/parts/gatewayDiscovery_*.arb。

/// 1.0.0+17 (user on the phone: the list's scan showed no progress, only
/// 「搜尋已停止・未發現附近閘道器」 at the end): the live scan runs until it
/// is stopped, but its first [gatewaySearchWindow] is a search with a
/// visible end — a progress bar (elapsed / window) and 「已找到 N 台」. After
/// it, the scan goes on (RSSI) and one line says what was found.
const gatewaySearchWindow = nearbyScanWindow;

/// 1.0.0+17: a search that found nothing is run once more after this pause
/// (HANDOFF §5.3 P2: the first scan after an install sometimes found
/// nothing and 〔重新搜尋〕 did).
const gatewayRescanDelay = Duration(seconds: 1);

/// 1.0.0+17: the progress area's head while the search runs.
String get gatewaySearchingText => L10n.current.gatewayDiscovery_searching;

/// 1.0.0+17: the head while the one automatic second search waits / runs.
String get gatewayRetryingText => L10n.current.gatewayDiscovery_retrying;

/// 1.0.0+17: the head while 〔辨識〕 pauses the search.
String get gatewayBusyText => L10n.current.gatewayDiscovery_busy;

/// 1.0.0+22: the head once a gateway is selected — its link is kept, so the
/// scan stopped (〔重新搜尋〕 lets it go and searches again).
String get gatewaySearchPausedText =>
    L10n.current.gatewayDiscovery_searchPaused;

/// 1.0.0+17: the second search found nothing either.
String get gatewayNotFoundText => L10n.current.gatewayDiscovery_notFound;

/// 1.0.0+17: the installer stopped the scan with nothing heard.
String get gatewayStoppedText => L10n.current.gatewayDiscovery_stopped;

/// 1.0.0+17: counted live under the progress bar.
String gatewayFoundCountText(int count) =>
    L10n.current.gatewayDiscovery_foundCount(count);

/// 1.0.0+17: the line after the search. [withHint]: the nearest hint
/// (「本樁的閘道器通常是訊號最強的那台…」) is shown under it — then the
/// line only counts, the hint says which to pick.
String gatewayFoundText(int count, {bool withHint = false}) => withHint
    ? L10n.current.gatewayDiscovery_found(count)
    : L10n.current.gatewayDiscovery_foundPick(count);

/// 1.0.0+17: where the list's search is.
enum _Search {
  /// No search runs (over with results, stopped, or never started).
  idle,

  /// The progress bar runs ([gatewaySearchWindow]); paused by 〔辨識〕.
  searching,

  /// Nothing found: waiting [gatewayRescanDelay] to search once more.
  retrying,

  /// The second search found nothing either: 〔重新搜尋〕 is the main button.
  notFound,
}

/// 1.0.0+8: the tile's badge for a gateway not yet configured.
String get gatewayUnconfiguredLabel =>
    L10n.current.gatewayDiscovery_unconfigured;

/// No verified identity yet; absence of phone history is not unconfigured.
String get gatewayPendingLabel => L10n.current.gatewayDiscovery_pending;

/// Guidance follows only the backend state already resolved for this card.
String get gatewayBackendOfflineNote =>
    L10n.current.gatewayDiscovery_backendOfflineNote;
String get gatewayBackendNoRecordNote =>
    L10n.current.gatewayDiscovery_backendNoRecordNote;

/// [presence] 是 [backendPresenceShort] 的結果。不比對中文字面量：以同一個
/// 函式對固定輸入算出「離線」「無紀錄」的短語再比（同源，哪個語言都對）。
// TODO(i18n Phase C): switch to B3 enum (backendPresenceShort 的結構化結果)
String? gatewayBackendNoteFor(String presence) {
  if (presence == _backendOfflineShort) return gatewayBackendOfflineNote;
  if (presence == _backendNoRecordShort) return gatewayBackendNoRecordNote;
  return null;
}

const _probeUid = 'AABBCCDDEEFF';

/// [backendPresenceShort] 對「後台有這台、回報離線」的短語。
String get _backendOfflineShort => backendPresenceShort(_probeUid, const [
  {'last_seen_mac': _probeUid, 'online': false},
]);

/// [backendPresenceShort] 對「後台沒有這台」的短語。
String get _backendNoRecordShort => backendPresenceShort(_probeUid, const []);

/// The identify button's tooltip (an icon since 1.0.0+8).
String get identifyGatewayLabel => L10n.current.gatewayDiscovery_identifyLabel;

/// 1.0.0+9: on the row for 3 s after 〔辨識〕 blinked it.
String get identifiedHint => L10n.current.gatewayDiscovery_identifiedHint;

/// 1.0.0+9: how long [identifiedHint] stays.
const identifiedHintFor = Duration(seconds: 3);

/// On the row, instead of [identifiedHint], when 〔辨識〕 blinked the gateway
/// only: it has no PTU connected, so no PTU blinks.
String get identifiedGatewayOnlyHint =>
    L10n.current.gatewayDiscovery_gatewayOnlyHint;

/// The SnackBar's sentence for the same ([identifiedGatewayOnlySnackText])
/// when nothing more is known (get_status not read, or no `direct` in it).
String get identifiedGatewayOnlyNote =>
    L10n.current.gatewayDiscovery_gatewayOnlyNote;

/// 1.0.0+22: the SnackBar's sentence when the APP had just switched the
/// gateway to one-to-one on this link ([IdentifyGatewayOnlyKind.switchedToDirect]).
String get identifiedGatewayOnlySwitchedNote =>
    L10n.current.gatewayDiscovery_gatewayOnlySwitchedNote;

/// The bound PTU is absent; hearing another PTU does not mean it can be selected.
String get identifiedGatewayOnlyBoundMissingNote =>
    L10n.current.gatewayDiscovery_gatewayOnlyBoundMissingNote;

/// 1.0.0+22: … when the gateway heard no PTU ([IdentifyGatewayOnlyKind.noCandidate]).
String get identifiedGatewayOnlyNoPtuNote =>
    L10n.current.gatewayDiscovery_gatewayOnlyNoPtuNote;

/// 1.0.0+22: … when every PTU heard is below the threshold
/// ([IdentifyGatewayOnlyKind.weakSignal]; [best] / [min] in dBm).
String identifiedGatewayOnlyWeakNote(int best, int min) =>
    L10n.current.gatewayDiscovery_gatewayOnlyWeakNote(best, min);

/// 1.0.0+22: … while the gateway is still picking among the PTUs heard
/// ([IdentifyGatewayOnlyKind.picking]).
String get identifiedGatewayOnlyPickingNote =>
    L10n.current.gatewayDiscovery_gatewayOnlyPickingNote;

/// 1.0.0+22: the SnackBar's sentence for [reason]; the plain
/// [identifiedGatewayOnlyNote] when there is none.
String identifiedGatewayOnlyNoteFor(
  IdentifyGatewayOnlyReason? reason,
) => switch (reason?.kind) {
  null => identifiedGatewayOnlyNote,
  IdentifyGatewayOnlyKind.switchedToDirect => identifiedGatewayOnlySwitchedNote,
  IdentifyGatewayOnlyKind.boundMissing => identifiedGatewayOnlyBoundMissingNote,
  IdentifyGatewayOnlyKind.noCandidate => identifiedGatewayOnlyNoPtuNote,
  IdentifyGatewayOnlyKind.weakSignal => identifiedGatewayOnlyWeakNote(
    reason!.bestRssi ?? 0,
    reason.minRssi ?? defaultDirectRssi,
  ),
  IdentifyGatewayOnlyKind.picking => identifiedGatewayOnlyPickingNote,
};

/// How long the gateway-only hint and SnackBar stay: longer than
/// [identifiedHintFor], it is a warning to read.
const identifiedGatewayOnlyFor = Duration(seconds: 6);

/// 1.0.0+10: the 「最近」 chip's fill. 1.0.0+14: no longer the nearest
/// card's outline — an outline is the selection's only (a green one was
/// read as 「selected」).
const gatewayNearestColor = Color(0xFF2E7D32);

/// 1.0.0+14 (user on the phone: 「選擇這邊的時候沒有選擇的體感，會不知道是
/// 不是真的選到我要選的」): a card's tap only selects its gateway — outlined
/// in the primary colour, tinted, 「✓ 已選取」 on it — and the page's fixed
/// bottom button ([GatewayConnectBar]) connects to it. Picking the
/// neighbour's gateway (the wrong pile) is one of the worst field errors.
String get gatewaySelectedLabel => L10n.current.gatewayDiscovery_selected;

/// 1.0.0+14: on the selected card and the bottom button while it connects.
String get gatewayConnectingLabel => L10n.current.gatewayDiscovery_connecting;

/// 1.0.0+14: the bottom button while nothing is selected (disabled).
String get gatewayPickFirstLabel => L10n.current.gatewayDiscovery_pickFirst;

/// 1.0.0+22 (select_then_identify, docs/select_then_identify.md): on the
/// selected card once its explicit connection is ready ([GatewayDiscovery.onHold]) —
/// the bulb then blinks at once.
String get gatewayHeldLabel => L10n.current.gatewayDiscovery_held;

/// 1.0.0+22: on the selected card when its connect failed (use the explicit retry button).
String get gatewayHoldFailedLabel => L10n.current.gatewayDiscovery_holdFailed;

/// 1.0.0+22: on the selected card when its kept link dropped (tap it to
/// connect again).
String get gatewayHoldLostLabel => L10n.current.gatewayDiscovery_holdLost;

String get gatewayCleanupFailedText =>
    L10n.current.gatewayDiscovery_cleanupFailed;

/// 1.0.0+22: the SnackBar when the selected gateway's connect failed.
String gatewayHoldFailedText(String title) =>
    L10n.current.gatewayDiscovery_holdFailedText(title);

/// 1.0.0+22: the SnackBar when the selected gateway's kept link dropped.
String gatewayHoldLostText(String title) =>
    L10n.current.gatewayDiscovery_holdLostText(title);

/// 1.0.0+22 (the phone trial): the bulb is on the selected card only once
/// its link is up ([_Hold.held]); every other card — and the selected one
/// while it connects, failed or dropped — keeps the bulb's room empty, so
/// nothing moves when the bulb comes and goes. The compact [IconButton]'s
/// box (a 24 dp icon in the 40 dp padded tap target).
const gatewayBulbBox = 40.0;

/// 1.0.0+22: the selected gateway's kept link ([GatewayDiscovery.onHold]).
enum _Hold {
  /// None kept (nothing selected, the list without [GatewayDiscovery.onHold],
  /// or the flow took the link).
  none,

  /// Its connect runs (「連線中…」; no bulb yet).
  connecting,

  /// Up (「已連線」): the only state with a bulb — it blinks at once.
  held,

  /// Its connect failed (「連線失敗」).
  failed,

  /// It dropped (「已斷線」).
  lost,
  disconnecting,
  cleanupFailed,
}

/// 1.0.0+14: the bottom button for the gateway selected — [title] from the
/// same source as the card's title (「站 80 · 閘道器 2」, 「未配置閘道器
/// …70F0」).
String gatewayConnectLabel(String title) =>
    L10n.current.gatewayDiscovery_connectLabel(title);

/// 1.0.0+14: the gateway selected on [GatewayDiscovery] (not connected
/// yet), shared with the page's fixed [GatewayConnectBar]: the list writes
/// it, the bar shows it and asks the list to connect ([connect]). Cleared
/// when the list goes (〔結束配置〕, 返回, a connected gateway) and on
/// 〔重新搜尋〕.
class GatewayChoice extends ChangeNotifier {
  GatewayPeer? _peer;
  String? _title;
  bool _connecting = false, _busy = false, _disposed = false;
  bool _ready = false;
  bool get ready => _ready;
  bool _scanAllowed = false, _scanStoppable = false;
  bool get scanAllowed => _scanAllowed;
  bool get scanStoppable => _scanStoppable;
  VoidCallback? _connect, _scan;
  Object? _owner;

  /// The gateway selected; null while none is.
  GatewayPeer? get peer => _peer;

  /// Its title as the list shows it (the bottom button's text).
  String? get title => _title;

  /// Its connect runs (the button's spinner and 「連線中…」).
  bool get connecting => _connecting;

  /// The list runs something (a connect or 〔辨識〕): nothing to press.
  bool get busy => _busy;

  /// The bottom button: the list connects to [peer] (its own connect: the
  /// scan stops first).
  void connect() => _connect?.call();

  /// The owning list handles its current scan state; detached bars are inert.
  void scan() {
    if (!_disposed && _owner != null && _scanAllowed) _scan?.call();
  }

  void _set({
    required GatewayPeer? peer,
    required String? title,
    required bool connecting,
    required bool busy,
    required bool ready,
    required bool scanAllowed,
    required bool scanStoppable,
  }) {
    if (_disposed) return;
    if (peer?.id == _peer?.id &&
        title == _title &&
        connecting == _connecting &&
        busy == _busy &&
        ready == _ready &&
        scanAllowed == _scanAllowed &&
        scanStoppable == _scanStoppable) {
      _peer = peer;
      return;
    }
    _peer = peer;
    _title = title;
    _connecting = connecting;
    _busy = busy;
    _ready = ready;
    _scanAllowed = scanAllowed;
    _scanStoppable = scanStoppable;
    notifyListeners();
  }

  /// Forgets the selection without telling the bar (a list being disposed
  /// runs inside a frame); [_changed] tells it after the frame.
  void _reset() {
    _peer = null;
    _title = null;
    _connecting = false;
    _busy = false;
    _ready = false;
    _scanAllowed = false;
    _scanStoppable = false;
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _connect = null;
    _scan = null;
    _owner = null;
    super.dispose();
  }
}

/// Discovery's fixed scan control. Scaffold reserves its height below the
/// scrolling cards, and SafeArea keeps the action above system navigation.
class GatewayScanBar extends StatelessWidget {
  const GatewayScanBar({super.key, required this.choice, this.enabled = true});
  final GatewayChoice choice;
  final bool enabled;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: choice,
    builder: (context, _) => SafeArea(
      top: false,
      child: Material(
        key: const Key('gateway-scan-bar'),
        elevation: 8,
        color: Theme.of(context).colorScheme.surface,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            key: const Key('gateway-scan-toggle'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
            onPressed: enabled && choice.scanAllowed ? choice.scan : null,
            icon: Icon(choice.scanStoppable ? Icons.stop : Icons.search),
            label: Text(
              choice.scanStoppable
                  ? context.l10n.gatewayDiscovery_stopSearch
                  : context.l10n.gatewayDiscovery_searchAgain,
            ),
          ),
        ),
      ),
    ),
  );
}

/// 1.0.0+14: the gateway list's fixed bottom bar (the page's
/// `bottomNavigationBar` on the list): 〔連線到 站 S · 閘道器 N〕 for the
/// gateway selected ([GatewayChoice]), full width, 48 dp. While none is
/// selected it stays, disabled, reading [gatewayPickFirstLabel] — the bar
/// is always there, so selecting a card never moves the list, and it says
/// what to do. While the connect runs: a spinner and 「連線中…」, disabled.
/// A SnackBar (〔辨識〕's 「已閃燈」) sits above it (Scaffold).
class GatewayConnectBar extends StatelessWidget {
  const GatewayConnectBar({
    super.key,
    required this.choice,
    this.enabled = true,
  });
  final GatewayChoice choice;

  /// The page lets it run (nothing else is busy).
  final bool enabled;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: choice,
    builder: (context, _) {
      final colors = Theme.of(context).colorScheme;
      final title = choice.title;
      final connecting = choice.connecting;
      return SafeArea(
        top: false,
        child: Material(
          key: const Key('gateway-connect-bar'),
          elevation: 8,
          color: colors.surface,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: FilledButton(
              key: const Key('gateway-connect'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              onPressed:
                  enabled && title != null && !choice.busy && choice.ready
                  ? choice.connect
                  : null,
              child: connecting
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 10),
                        Flexible(
                          child: Text(
                            gatewayConnectingLabel,
                            key: const Key('gateway-connect-text'),
                            maxLines: 1,
                            softWrap: false,
                          ),
                        ),
                      ],
                    )
                  : Text(
                      title == null
                          ? gatewayPickFirstLabel
                          : gatewayConnectLabel(title),
                      key: const Key('gateway-connect-text'),
                      maxLines: 2,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                    ),
            ),
          ),
        ),
      );
    },
  );
}

/// 1.0.0+14: 「✓ 已選取」 (or a spinner and 「連線中…」) on the selected
/// card — white on the primary colour, the size of the other marks.
/// 1.0.0+22: and its kept link ([phase]): 「已連線」, or on the error
/// colour 「連線失敗」／「已斷線」.
class _SelectedMark extends StatelessWidget {
  const _SelectedMark({
    super.key,
    required this.connecting,
    this.phase = _Hold.none,
    this.selected = true,
  });
  final bool connecting;
  final _Hold phase;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = Theme.of(context).colorScheme;
    final spinning =
        connecting || phase == _Hold.connecting || phase == _Hold.disconnecting;
    final failed =
        !spinning &&
        (phase == _Hold.failed ||
            phase == _Hold.lost ||
            phase == _Hold.cleanupFailed);
    final fill = !selected
        ? colors.surfaceContainerHighest
        : failed
        ? colors.error
        : colors.primary;
    final ink = !selected
        ? colors.onSurfaceVariant
        : failed
        ? colors.onError
        : colors.onPrimary;
    final style = Theme.of(context).textTheme.labelMedium?.copyWith(
      color: ink,
      fontWeight: FontWeight.w700,
      height: 1.2,
    );
    final (icon, text) = !selected
        ? (Icons.bluetooth_disabled, l10n.gatewayDiscovery_notConnected)
        : spinning
        ? (
            null,
            phase == _Hold.disconnecting
                ? l10n.gatewayDiscovery_disconnecting
                : gatewayConnectingLabel,
          )
        : switch (phase) {
            _Hold.held => (Icons.bluetooth_connected, gatewayHeldLabel),
            _Hold.failed => (Icons.error_outline, gatewayHoldFailedLabel),
            _Hold.lost => (Icons.bluetooth_disabled, gatewayHoldLostLabel),
            _Hold.cleanupFailed => (
              Icons.error_outline,
              l10n.gatewayDiscovery_cleanupIncomplete,
            ),
            _ => (Icons.check, gatewaySelectedLabel),
          };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: fill,
        border: Border.all(color: fill),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon == null)
            SizedBox.square(
              dimension: 12,
              child: CircularProgressIndicator(strokeWidth: 2, color: ink),
            )
          else
            Icon(icon, size: 14, color: ink),
          const SizedBox(width: 3),
          // 1.0.0+22: one line height whatever the glyphs (「連線中…」's
          // ellipsis comes from another font): the card does not grow
          // while its explicit connection is pending.
          Text(
            text,
            maxLines: 1,
            softWrap: false,
            style: style,
            strutStyle: style == null
                ? null
                : StrutStyle.fromTextStyle(style, forceStrutHeight: true),
          ),
        ],
      ),
    );
  }
}

/// 1.0.0+11 (phone: 〔辨識〕 paused the scan 2–4 s and every row read
/// 「未收到廣播」, cutting the title to 「站 80・閘道…」): a gateway heard
/// keeps its last RSSI (grey while not heard live) for this long; after
/// that only a selected row stays with [gatewaySignalLostLabel]; other
/// rows leave the list, including remembered gateways.
const gatewayHeardFor = Duration(seconds: 30);

/// 1.0.0+11: a remembered gateway not heard for [gatewayHeardFor].
String get gatewaySignalLostLabel => L10n.current.gatewayDiscovery_signalLost;

/// 1.0.0+11: a remembered gateway never heard by this list.
const gatewayNeverHeardLabel = '—';

/// 1.0.0+11: the SnackBar after 〔辨識〕 blinked [name] — seen even when its
/// row is off screen. 1.0.0+12: [title], the row's title when given (e.g.
/// 「未配置閘道器 …70F0」).
String identifiedSnackText(String name, {String? title}) =>
    L10n.current.gatewayDiscovery_identifiedSnack(title ?? gatewayTitle(name));

/// The SnackBar after 〔辨識〕 blinked the gateway only (no PTU connected);
/// 1.0.0+22: [note] says why when known ([identifiedGatewayOnlyNoteFor]).
String identifiedGatewayOnlySnackText(
  String name, {
  String? title,
  String? note,
}) => L10n.current.gatewayDiscovery_gatewayOnlySnack(
  title ?? gatewayTitle(name),
  note ?? identifiedGatewayOnlyNote,
);

/// 1.0.0+10: a small mark on a gateway row (labelMedium): outlined, or
/// [filled] (white text on [color]).
class GatewayMark extends StatelessWidget {
  const GatewayMark(
    this.text, {
    super.key,
    required this.color,
    this.filled = false,
  });
  final String text;
  final Color color;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelMedium?.copyWith(
      color: filled ? Colors.white : color,
      fontWeight: FontWeight.w700,
      height: 1.2,
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: filled ? color : null,
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text, maxLines: 1, softWrap: false, style: style),
    );
  }
}

class GatewayDiscovery extends ConsumerStatefulWidget {
  const GatewayDiscovery({
    super.key,
    required this.enabled,
    required this.onConnect,
    this.onIdentify,
    this.identifyGatewayOnly,
    this.identifyGatewayOnlyReason,
    this.now,
    this.choice,
    this.onHold,
    this.onRelease,
    this.holdLost,
  });
  final bool enabled;

  /// Explicit Bluetooth connection for identification. Selection alone is
  /// local. True means services, notifications and writes are ready; no
  /// configuration is changed until [onConnect] starts commissioning.
  final Future<bool> Function(GatewayPeer)? onHold;

  /// 1.0.0+22: the kept link goes (〔重新搜尋〕, the list closed).
  final Future<void> Function()? onRelease;

  /// 1.0.0+22: the ids of gateways whose kept link dropped.
  final Stream<String>? holdLost;

  /// Connects to the gateway selected — 1.0.0+14: from [choice]'s bottom
  /// button ([GatewayConnectBar]), never from a card's tap.
  final Future<void> Function(GatewayPeer) onConnect;

  /// 1.0.0+14: the selection shared with the page's [GatewayConnectBar];
  /// null: the list keeps its own (nothing outside can connect).
  final GatewayChoice? choice;

  /// 「辨識」 on a row: blink it and stay on the list (1.0.0+9). Answers
  /// whether the identify was really sent (1.0.0+10: 「已閃燈」 only then —
  /// not after a cancel or a failure). Null hides the button.
  final Future<bool> Function(GatewayPeer)? onIdentify;

  /// Asked right after [onIdentify] answered true: whether only the gateway
  /// blinked (no PTU connected) — the row and the SnackBar then say so
  /// ([identifiedGatewayOnlyNote]). Null: the identify reached everything
  /// it was meant for.
  final bool Function()? identifyGatewayOnly;

  /// 1.0.0+22: asked with [identifyGatewayOnly] when it answers true: why
  /// the PTU side was not reached, for the SnackBar's sentence
  /// ([identifiedGatewayOnlyNoteFor]). Null / answering null: the plain
  /// [identifiedGatewayOnlyNote].
  final IdentifyGatewayOnlyReason? Function()? identifyGatewayOnlyReason;

  /// The clock ([gatewayHeardFor]); tests set it.
  final DateTime Function()? now;

  /// 1.0.0+17: the search's length ([gatewaySearchWindow]); a layout test
  /// stretches it to check the page while the search runs.
  @visibleForTesting
  static Duration searchWindow = gatewaySearchWindow;
  @override
  ConsumerState<GatewayDiscovery> createState() => _GatewayDiscoveryState();
}

class _GatewayDiscoveryState extends ConsumerState<GatewayDiscovery>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  /// 1.0.0+17: the search's progress (0→1 over [gatewaySearchWindow]);
  /// paused while the scan pauses (〔辨識〕, the background).
  late final AnimationController _progress;
  var _search = _Search.idle;

  /// 1.0.0+17: 1 for the first search, 2 for the automatic second one.
  int _attempt = 1;
  Timer? _retryTimer;

  List<RecentGateway> _recent = [];

  /// 1.0.0+11: the gateways in the running scan's last answer (heard live);
  /// empty while the scan is stopped or paused.
  var _live = <String>{};

  /// 1.0.0+11: every gateway heard by this list and when it was last in a
  /// scan answer — its row keeps that RSSI through a pause (〔辨識〕, another
  /// page, the background) instead of 「未收到廣播」.
  final _heard = <String, ({GatewayPeer peer, DateTime at})>{};

  /// When the scan stopped (null while it runs): the time a gateway was
  /// not heard counts only while scanning — a stopped list keeps its rows
  /// (「搜尋已停止・RSSI 為最後一次結果」), and on the next start every
  /// [_heard] time moves on by the pause.
  DateTime? _pausedAt;

  /// Rebuilds a running list now and then, so a row not heard for
  /// [gatewayHeardFor] says so without a new scan answer.
  Timer? _heardTick;

  /// Round 30 (user rehearsal 09-27, D): the phone's signal ranks the list.
  final _ranker = GatewaySignalRanker();
  var _ranked = <String>[];
  ({String nearest, bool close})? _nearest;
  List<dynamic> _fleet = [];
  List<dynamic> _archived = [];
  String? _backendError;
  DateTime? _backendAt;
  String? _error;

  /// 1.0.0+10: the last scan failed for want of a permission (or a
  /// location service) — only then 〔開啟權限設定〕 is shown.
  bool _needsSettings = false;

  /// 1.0.0+17: the running scan failed (any error, not 「nothing heard」):
  /// its search is not run again by itself.
  bool _scanFailed = false;
  bool _scanning = false, _selecting = false;
  bool _scanActionBusy = false;

  /// 1.0.0+9: the gateway 〔辨識〕 just blinked (「已閃燈」 on its row).
  String? _identified;

  /// [_identified] blinked the gateway only ([identifiedGatewayOnlyHint]).
  bool _identifiedGatewayOnly = false;
  Timer? _identifiedTimer;

  /// The row whose 〔辨識〕 is running (the selected, connected one): its
  /// bulb is a small progress indicator until the identify ends, however
  /// it ends.
  String? _identifyingId;
  int _epoch = 0, _backendEpoch = 0;
  StreamSubscription<List<GatewayPeer>>? _scan;

  /// 1.0.0+10: a live scan is wanted (started and not stopped by the
  /// installer) — resumed when this page is on top again after another
  /// page (「閘道器狀態」's own scan) ended it.
  bool _liveWanted = false;

  /// 1.0.0+10: [_resumeScan] is waiting (the list disabled, busy or not on
  /// top); tried again when that ends.
  bool _resumePending = false;

  /// 1.0.0+10: whether this list's route was on top at the last check.
  bool? _routeCurrent;
  GatewayLink? _activeLink;
  Timer? _refresh;
  Future<void>? _stopping;
  bool _background = false;
  int _lifecycleEpoch = 0;

  /// 1.0.0+14: the gateway selected (a card's tap), and its peer as heard
  /// then; kept through 〔辨識〕 and a lost signal.
  String? _selectedId;
  GatewayPeer? _selectedPeer;

  /// 1.0.0+14: the gateway whose connect runs (the bottom button).
  String? _connectingId;

  /// 1.0.0+14: the cards' order when a gateway was selected — kept while
  /// one is, so the selected card does not move (RSSI and 「最近」 still
  /// change); gateways heard since come after. [_shown]: the order last
  /// built.
  List<String>? _frozen;
  var _shown = <String>[];

  late GatewayChoice _choice;
  GatewayChoice? _ownChoice;
  bool _choiceSyncPending = false;

  /// 1.0.0+22: the gateway whose link the list keeps ([GatewayDiscovery.onHold])
  /// — the selected one — and where that link is; [_holdEpoch] bumps on
  /// every new hold, release and loss (an older hold's answer is ignored).
  String? _holdId;
  var _holdPhase = _Hold.none;
  int _holdEpoch = 0;
  Future<bool>? _holdFuture;
  StreamSubscription<String>? _holdLostSub;

  @override
  void initState() {
    super.initState();
    // Cancelling a run can mount a disabled list that never starts scanning.
    // Create its ticker here, not lazily for the first time during dispose.
    _progress = AnimationController(
      vsync: this,
      duration: GatewayDiscovery.searchWindow,
    )..addStatusListener(_progressStatus);
    _attachChoice();
    _listenHoldLost();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _start(fresh: true);
    });
    _refresh = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) _loadBackend();
    });
    _heardTick = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted && _scanning && _heard.isNotEmpty) setState(() {});
    });
  }

  DateTime _now() => (widget.now ?? DateTime.now)();

  /// The time [gatewayHeardFor] is measured to: now, or when the scan
  /// stopped.
  DateTime _heardClock() => _pausedAt ?? _now();

  /// In a setState: the scan is over (stopped, done or failed).
  void _scanEnded() {
    _scanning = false;
    _pausedAt ??= _now();
  }

  /// The gateways heard within [gatewayHeardFor] before [now], in the
  /// signal ranking.
  List<GatewayPeer> _heardPeers(DateTime now) => [
    for (final heard in _heard.values)
      if (now.difference(heard.at) <= gatewayHeardFor) heard.peer,
  ]..sort((a, b) => _rankOf(a.id) - _rankOf(b.id));

  /// 1.0.0+10 (review P2-5): back on top (e.g. from 「閘道器狀態」, whose
  /// scan stopped this one) — the live scan starts again when it was
  /// wanted.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final current = ModalRoute.of(context)?.isCurrent ?? true;
    final was = _routeCurrent;
    _routeCurrent = current;
    if (was == false && current) _resumeScan();
  }

  @override
  void didUpdateWidget(covariant GatewayDiscovery oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.choice != oldWidget.choice) {
      _detachChoice();
      _attachChoice();
      _scheduleChoiceSync();
    }
    if (widget.holdLost != oldWidget.holdLost) _listenHoldLost();
    // The run that disabled the list (e.g. 〔辨識〕) is over.
    if (widget.enabled && !oldWidget.enabled && _resumePending) _resumeScan();
  }

  /// 1.0.0+14: [GatewayDiscovery.choice] (or one of its own) is this list's.
  void _attachChoice() {
    _choice = widget.choice ?? (_ownChoice ??= GatewayChoice());
    _choice
      .._reset()
      .._connect = _connectSelected
      .._scan = _toggleScan
      .._owner = this;
  }

  /// 1.0.0+14: the list goes (〔結束配置〕, 返回, a gateway connected):
  /// its selection goes too — the bar is told after this frame.
  void _detachChoice() {
    final choice = _choice;
    if (!identical(choice._owner, this)) return;
    choice
      .._reset()
      .._connect = null
      .._scan = null
      .._owner = null;
    if (!identical(choice, _ownChoice)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => choice._changed());
    }
  }

  /// 1.0.0+14: tells [_choice] the selection, its title, and whether a
  /// connect (or 〔辨識〕) runs.
  void _syncChoice() {
    final id = _selectedId;
    final peer = id == null ? null : _heard[id]?.peer ?? _selectedPeer;
    _choice._set(
      peer: peer,
      title: peer == null ? null : _titleOf(peer.name, peer.id).title,
      connecting: _connectingId != null,
      busy:
          _selecting ||
          _identifyingId != null ||
          _holdPhase == _Hold.connecting ||
          _holdPhase == _Hold.disconnecting,
      ready:
          widget.onHold == null || (_holdPhase == _Hold.held && _holdId == id),
      scanAllowed:
          widget.enabled &&
          _canSelect &&
          !_scanActionBusy &&
          !_background &&
          _routeCurrent != false,
      scanStoppable: _scanning || _search == _Search.retrying,
    );
  }

  /// After this frame (never while building: the bar is outside the list).
  void _scheduleChoiceSync() {
    if (_choiceSyncPending) return;
    _choiceSyncPending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _choiceSyncPending = false;
      if (mounted) _syncChoice();
    });
  }

  /// Select locally. While a connection exists or cleanup is running,
  /// disconnect must finish before another card can be selected.
  void _select(GatewayPeer peer) {
    if (!_canSelect || !widget.enabled) return;
    unawaited(HapticFeedback.selectionClick());
    setState(() {
      _frozen ??= List.of(_shown);
      _selectedId = peer.id;
      _selectedPeer = peer;
      _holdId = null;
      _holdPhase = _Hold.none;
    });
    _syncChoice();
  }

  bool get _canSelect =>
      !_selecting &&
      _identifyingId == null &&
      _holdPhase != _Hold.connecting &&
      _holdPhase != _Hold.disconnecting &&
      _holdPhase != _Hold.held &&
      _holdPhase != _Hold.cleanupFailed;

  /// 1.0.0+22: a gateway selected keeps its link ([GatewayDiscovery.onHold]):
  /// no scan meanwhile (it would drop the link) — 〔重新搜尋〕 lets it go.
  bool get _holds => widget.onHold != null && _holdId != null;

  /// A card's explicit connection selects that same peer before taking the
  /// existing serial gate. No await can let another card slip between them.
  Future<bool> _holdFromCard(GatewayPeer peer) {
    if (!widget.enabled || !_canSelect || widget.onHold == null) {
      return Future.value(false);
    }
    _select(peer);
    if (_selectedId != peer.id) return Future.value(false);
    return _holdSelected();
  }

  /// 1.0.0+22: connects to the selected gateway and keeps the link
  /// ([GatewayDiscovery.onHold]); its card says 「連線中…」, then 「已連線」
  /// or 「連線失敗」 (and a SnackBar: use the connect button). A pending connect
  /// for that gateway is not started twice. Answers whether it is held
  /// (false too when superseded: another card, a release, the list gone).
  Future<bool> _holdSelected() {
    final hold = widget.onHold;
    final id = _selectedId;
    final peer = id == null ? null : _heard[id]?.peer ?? _selectedPeer;
    if (!widget.enabled || !_canSelect || hold == null || peer == null) {
      return Future.value(false);
    }
    final pending = _holdFuture;
    if (pending != null && _holdId == peer.id) return pending;
    final epoch = ++_holdEpoch;
    setState(() {
      _holdId = peer.id;
      _holdPhase = _Hold.connecting;
    });
    _syncChoice();
    final run = () async {
      // BleGatewayLink.scanLive disconnects first: the scan stays stopped
      // while the link is kept.
      await _stop();
      var held = false;
      if (mounted && epoch == _holdEpoch) {
        try {
          held = await hold(peer);
        } catch (_) {}
      }
      if (!mounted || epoch != _holdEpoch) return false;
      _holdFuture = null;
      setState(
        () => _holdPhase = held
            ? _Hold.held
            : ref.read(commissionProvider.notifier).heldCleanupRequired
            ? _Hold.cleanupFailed
            : _Hold.failed,
      );
      _syncChoice();
      // Not while 〔連線到 …〕 runs: it connects for itself and says why
      // when it fails.
      if (!held && _connectingId == null) {
        final title = _titleOf(peer.name, peer.id).title;
        _holdSnack(gatewayHoldFailedText(title));
      }
      return held;
    }();
    _holdFuture = run;
    return run;
  }

  /// 1.0.0+22: the kept link goes ([GatewayDiscovery.onRelease]); the
  /// fields at once (callers rebuild), the release awaited.
  Future<void> _releaseHold() async {
    final kept = _holdId != null;
    _holdEpoch++;
    _holdFuture = null;
    if (!kept) return;
    _holdPhase = _Hold.disconnecting;
    try {
      await widget.onRelease?.call();
      _holdId = null;
      _holdPhase = _Hold.none;
    } catch (_) {
      _holdPhase = _Hold.cleanupFailed;
    }
  }

  Future<void> _disconnectSelected() async {
    if (_selecting ||
        _identifyingId != null ||
        _holdPhase == _Hold.disconnecting) {
      return;
    }
    final release = _releaseHold();
    setState(() {});
    _syncChoice();
    await release;
    if (!mounted) return;
    setState(() {});
    _syncChoice();
  }

  void _listenHoldLost() {
    unawaited(_holdLostSub?.cancel());
    _holdLostSub = widget.holdLost?.listen(_onHoldLost);
  }

  /// 1.0.0+22: the selected gateway's kept link dropped: 「已斷線」 on its
  /// card and a SnackBar; reconnect requires the explicit button. Not while
  /// 〔連線到 …〕 runs (the flow has the link then); while another run has
  /// it (〔繼續上次配置〕 to another gateway, 〔取消操作〕) — the APP closed
  /// it itself — the card quietly goes back to 「已選取」.
  void _onHoldLost(String id) {
    if (!mounted ||
        id != _holdId ||
        _holdPhase != _Hold.held ||
        _connectingId != null) {
      return;
    }
    _holdEpoch++;
    _holdFuture = null;
    if (ref.read(commissionProvider).busy) {
      setState(() => _holdPhase = _Hold.none);
      return;
    }
    final cleanupRequired = ref
        .read(commissionProvider.notifier)
        .heldCleanupRequired;
    setState(
      () => _holdPhase = cleanupRequired ? _Hold.cleanupFailed : _Hold.lost,
    );
    _syncChoice();
    final peer = _heard[id]?.peer ?? _selectedPeer;
    if (peer != null) {
      _holdSnack(
        cleanupRequired
            ? gatewayCleanupFailedText
            : gatewayHoldLostText(_titleOf(peer.name, peer.id).title),
      );
    }
  }

  void _holdSnack(String text) {
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          key: const Key('gateway-hold-snack'),
          content: Text(text),
          duration: identifiedGatewayOnlyFor,
        ),
      );
  }

  void _clearSelection() {
    _selectedId = null;
    _selectedPeer = null;
    _frozen = null;
  }

  /// 1.0.0+14: the bottom button ([GatewayChoice.connect]) — the gateway
  /// selected, as last heard.
  void _connectSelected() {
    final id = _selectedId;
    final peer = id == null ? null : _heard[id]?.peer ?? _selectedPeer;
    if (peer != null) unawaited(_connect(peer));
  }

  /// Starts the live scan again when one is wanted and none runs; waits
  /// (see [_resumePending]) while the list is disabled, busy or covered.
  void _resumeScan() {
    if (!_liveWanted || _scanning || _holds) return;
    _resumePending = true;
    if (!widget.enabled ||
        _selecting ||
        _background ||
        _routeCurrent == false) {
      return;
    }
    unawaited(() async {
      await _stopping;
      if (!mounted || !_resumePending || _scanning) return;
      await _start();
    }());
  }

  /// 〔停止搜尋〕: the installer stopped it — not resumed by itself.
  /// 1.0.0+17: nor searched again (no automatic second search).
  Future<void> _toggleScan() async {
    if (!mounted ||
        !widget.enabled ||
        !_canSelect ||
        _scanActionBusy ||
        _background ||
        _routeCurrent == false) {
      return;
    }
    _scanActionBusy = true;
    _syncChoice();
    try {
      if (_scanning || _search == _Search.retrying) {
        await _stopByUser();
      } else {
        await _restartByUser();
      }
    } finally {
      _scanActionBusy = false;
      if (mounted) _syncChoice();
    }
  }

  Future<void> _stopByUser() {
    _liveWanted = false;
    _resumePending = false;
    _retryTimer?.cancel();
    setState(() => _search = _Search.idle);
    return _stop();
  }

  void _progressStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) _searchOver();
  }

  /// 1.0.0+17: the search's window is over (or its scan ended by itself):
  /// gateways heard — the scan goes on, one line says so; none — once more
  /// after [gatewayRescanDelay], then [gatewayNotFoundText] and the scan
  /// stops. A scan that failed ([_scanFailed]: permission, location or
  /// Bluetooth off, any error) is never searched again by itself — its
  /// error and guidance stay.
  void _searchOver() {
    if (!mounted || _search != _Search.searching) return;
    _progress.stop();
    if (_scanFailed || _heardPeers(_heardClock()).isNotEmpty) {
      setState(() => _search = _Search.idle);
      return;
    }
    if (_attempt < 2) {
      setState(() => _search = _Search.retrying);
      unawaited(_stop());
      _retryTimer?.cancel();
      _retryTimer = Timer(gatewayRescanDelay, _retry);
      return;
    }
    _liveWanted = false;
    _resumePending = false;
    setState(() => _search = _Search.notFound);
    unawaited(_stop());
  }

  /// 1.0.0+17: the automatic second search (as a resumed scan: it waits
  /// while the list is disabled, busy, covered or in the background).
  void _retry() {
    if (!mounted || _search != _Search.retrying) return;
    setState(() {
      _attempt = 2;
      _search = _Search.searching;
    });
    _progress.value = 0;
    if (_scanning) {
      unawaited(_progress.forward());
    } else if (_liveWanted) {
      _resumeScan();
    } else {
      unawaited(_start());
    }
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    _progress.dispose();
    unawaited(_holdLostSub?.cancel());
    // 1.0.0+22: a link kept for the list goes with it (none when the flow
    // took it: 〔連線到 …〕 connected).
    unawaited(_releaseHold());
    _detachChoice();
    _ownChoice?.dispose();
    _identifiedTimer?.cancel();
    _heardTick?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _refresh?.cancel();
    _epoch++;
    _backendEpoch++;
    unawaited(_scan?.cancel());
    final link = _activeLink;
    if (link is GatewayScanner) unawaited((link as GatewayScanner).stopScan());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Permission/adapter dialogs can be inactive without leaving the app.
    if (state == AppLifecycleState.inactive) return;
    final lifecycle = ++_lifecycleEpoch;
    if (state != AppLifecycleState.resumed) {
      _background = true;
      unawaited(_stop());
      _backendEpoch++;
      setState(() {
        _live = {};
        _fleet = [];
        _backendError = null;
        _backendAt = null;
      });
      _refresh?.cancel();
    } else if (_background) {
      _background = false;
      unawaited(() async {
        await _stopping;
        if (!mounted || _background || lifecycle != _lifecycleEpoch) return;
        _refresh?.cancel();
        _refresh = Timer.periodic(
          const Duration(seconds: 15),
          (_) => _loadBackend(),
        );
        if (widget.enabled && !_selecting) await _start();
      }());
    }
  }

  Future<void> _loadBackend() async {
    final epoch = ++_backendEpoch;
    if (!ref.read(commissionProvider).loggedIn) {
      if (mounted) {
        setState(() {
          _fleet = [];
          _backendError = null;
          _backendAt = null;
        });
      }
      return;
    }
    final base = ref.read(backendEnvProvider).base;
    try {
      final result = await ref
          .read(apiProvider)
          .request('GET', '/api/gateways/fleet-status?include_archived=true')
          .timeout(const Duration(seconds: 8));
      if (!mounted ||
          epoch != _backendEpoch ||
          base != ref.read(backendEnvProvider).base ||
          !ref.read(commissionProvider).loggedIn) {
        return;
      }
      setState(() {
        _fleet = result['gateways'] as List? ?? [];
        _archived = result['archived_gateways'] as List? ?? [];
        _backendError = null;
        _backendAt = DateTime.now();
      });
    } catch (error) {
      if (mounted && epoch == _backendEpoch) {
        setState(() {
          _fleet = [];
          _archived = [];
          _backendError = backendQueryFailedText(error);
          _backendAt = null;
        });
      }
    }
  }

  Future<void> _stop() async {
    if (_stopping != null) return _stopping;
    // 1.0.0+17: the search's bar pauses with the scan (〔辨識〕).
    _progress.stop();
    final stopping = () async {
      _epoch++;
      final link = _activeLink;
      if (link is GatewayScanner) await (link as GatewayScanner).stopScan();
      await _scan?.cancel();
      _scan = null;
      if (mounted) setState(_scanEnded);
    }();
    _stopping = stopping;
    try {
      await stopping;
    } finally {
      _stopping = null;
    }
  }

  /// 1.0.0+11: the rows heard before stay (grey, their last RSSI) until the
  /// scan hears them again — the list does not flash empty or jump (1.0.0+10
  /// kept them only for a resumed scan, and only until its first answer).
  ///
  /// 1.0.0+17: [fresh] (the page opened, 〔重新搜尋〕) starts a search (the
  /// progress bar); a resumed scan goes on with a search it paused.
  Future<void> _start({bool fresh = false}) async {
    if (!widget.enabled ||
        _scanning ||
        _selecting ||
        _background ||
        _stopping != null ||
        _holds) {
      return;
    }
    if (fresh || _search == _Search.retrying) {
      // A start while the second search waits (e.g. back from the
      // background) is that second search.
      _retryTimer?.cancel();
      _attempt = fresh ? 1 : 2;
      _search = _Search.searching;
      _progress.value = 0;
    }
    final epoch = ++_epoch;
    final link = ref.read(linkProvider);
    _activeLink = link;
    _liveWanted = link is GatewayScanner;
    _resumePending = false;
    final paused = _pausedAt;
    if (paused != null) {
      final gap = _now().difference(paused);
      _heard.updateAll((_, h) => (peer: h.peer, at: h.at.add(gap)));
      _pausedAt = null;
    }
    setState(() {
      _scanning = true;
      _live = {};
      _error = null;
      _needsSettings = false;
      _scanFailed = false;
    });
    if (_search == _Search.searching) unawaited(_progress.forward());
    unawaited(_loadBackend());
    final recent = await RecentGateways.load(link.demo);
    if (!mounted || epoch != _epoch) return;
    setState(() => _recent = recent);
    void update(List<GatewayPeer> peers) {
      if (mounted && epoch == _epoch) {
        // Round 26: gateways heard here are never PTUs (another gateway's
        // advertisement was listed and picked as one in the field).
        ref.read(commissionProvider.notifier).noteGatewayPeers(peers);
        final now = _now();
        for (final peer in peers) {
          _ranker.add(peer.id, peer.rssi, now);
          _heard[peer.id] = (peer: peer, at: now);
        }
        // 1.0.0+11: ranked with the ones heard lately but not in this answer
        // (a resumed scan's first answer has one gateway only: 「最近」 and
        // the hint above the list went away, the list jumped).
        final ids = [
          for (final heard in _heard.entries)
            if (now.difference(heard.value.at) <= gatewayHeardFor) heard.key,
        ];
        final ranked = _ranker.rank(ids, now);
        // 1.0.0+10 (phone: 81/1 at -41 dBm, 80/2 at -62, no 「最近」 at
        // all): the strongest gateway heard is 「最近」 whether configured
        // or not (its 「已配置」 chip says the rest) — r31 left it out, so
        // with one configured and one new gateway nothing was marked.
        final nearest = _ranker.nearest(ids, now);
        setState(() {
          _ranked = ranked;
          // Two or more heard lately but the ranker's readings older than
          // its window (a long pause): the last answer stays.
          _nearest = nearest ?? (ids.length >= 2 ? _nearest : null);
          _live = {for (final peer in peers) peer.id};
        });
      }
    }

    void failure(Object error) {
      if (!mounted || epoch != _epoch) return;
      setState(() {
        _error = error is GatewayFailure
            ? error.message
            : L10n.current.gatewayDiscovery_scanFailed;
        _needsSettings =
            error is! GatewayFailure ||
            error.code == 'permission' ||
            error.code == 'location_off';
        _scanFailed = true;
      });
      // 1.0.0+17: a failed scan ends its search now (no second search).
      _searchOver();
    }

    if (link is GatewayScanner) {
      _scan = (link as GatewayScanner).scanLive().listen(
        update,
        onError: failure,
        onDone: () {
          if (mounted && epoch == _epoch) {
            setState(_scanEnded);
            // 1.0.0+17: a scan that ended by itself ends its search too.
            _searchOver();
          }
        },
      );
    } else {
      try {
        update(await link.scan());
      } catch (error) {
        failure(error);
      }
      if (mounted && epoch == _epoch) {
        setState(_scanEnded);
        _searchOver();
      }
    }
  }

  /// Position in the signal ranking; gateways not heard after all heard.
  int _rankOf(String id) {
    final at = _ranked.indexOf(id);
    return at < 0 ? _ranked.length : at;
  }

  /// r31: a remembered gateway the back office already knows (configured).
  bool _configured(String id) {
    if (!_backendCurrent) return false;
    final uid = _recent.where((r) => r.peer.id == id).firstOrNull?.uid;
    return gatewayConfigured(uid, _fleet);
  }

  /// The back office's list is current (logged in, read within 30 s).
  bool get _backendCurrent =>
      ref.read(commissionProvider).loggedIn &&
      _backendAt != null &&
      DateTime.now().difference(_backendAt!).inSeconds <= 30;

  /// A row's title: 「站 80 · 閘道器 2」 (the name when it does not parse);
  /// 1.0.0+12: 「未配置閘道器 …70F0」 for a gateway known not to be
  /// configured ([gatewayKnownUnconfigured]) — not the station / number
  /// it advertises (an old identity may be left in it). [name]: the name
  /// heard (a recent entry keeps the one it had).
  ({String title, bool unconfigured}) _titleOf(String name, String id) {
    final uid = _recent.where((r) => r.peer.id == id).firstOrNull?.uid;
    final unconfigured = gatewayKnownUnconfigured(
      name: name,
      uid: uid,
      fleet: _fleet,
      archived: _archived,
      backendKnown: _backendCurrent,
    );
    return (
      title: unconfigured
          ? unconfiguredGatewayTitle(gatewayTailText(uid: uid, bleId: id))
          : gatewayTitle(name),
      unconfigured: unconfigured,
    );
  }

  /// Commissioning is explicit and belongs to the same ready link the card
  /// displayed. Its epoch also rejects callbacks retained across a reconnect.
  bool _canStartPeer(GatewayPeer peer, int holdEpoch) =>
      mounted &&
      widget.enabled &&
      !_selecting &&
      _identifyingId == null &&
      !ref.read(commissionProvider).busy &&
      _selectedId == peer.id &&
      _holdId == peer.id &&
      _holdPhase == _Hold.held &&
      _holdEpoch == holdEpoch;

  Future<void> _connect(GatewayPeer peer, {int? expectedHoldEpoch}) async {
    if (!mounted ||
        _selecting ||
        !widget.enabled ||
        ref.read(commissionProvider).busy ||
        _identifyingId != null ||
        _selectedId != peer.id ||
        (expectedHoldEpoch != null &&
            !_canStartPeer(peer, expectedHoldEpoch)) ||
        (widget.onHold != null &&
            (_holdPhase != _Hold.held || _holdId != peer.id))) {
      return;
    }
    final holdEpoch = _holdEpoch;
    _retryTimer?.cancel();
    setState(() {
      _selecting = true;
      _connectingId = peer.id;
      // 1.0.0+17: a gateway chosen ends the search (a failed connect
      // leaves the list stopped, as before).
      _search = _Search.idle;
    });
    _syncChoice();
    try {
      await _stop();
      if (mounted &&
          widget.enabled &&
          !ref.read(commissionProvider).busy &&
          _selectedId == peer.id &&
          (widget.onHold == null ||
              (_holdId == peer.id &&
                  _holdPhase == _Hold.held &&
                  _holdEpoch == holdEpoch))) {
        await widget.onConnect(peer);
      }
    } finally {
      if (mounted) {
        setState(() {
          _selecting = false;
          _connectingId = null;
          // 1.0.0+22: the flow took the kept link (or replaced it): none is
          // the list's now. Another connection needs its explicit button.
          if (widget.onHold != null) {
            _holdEpoch++;
            _holdFuture = null;
            final cleanupRequired = ref
                .read(commissionProvider.notifier)
                .heldCleanupRequired;
            _holdId = cleanupRequired ? peer.id : null;
            _holdPhase = cleanupRequired ? _Hold.cleanupFailed : _Hold.none;
          }
        });
        _syncChoice();
      }
    }
  }

  /// 〔重新搜尋〕: a new list — 1.0.0+14: the selection goes. 1.0.0+17: a
  /// new search (the progress bar, and once more if it finds nothing).
  ///
  /// 1.0.0+22: the selected gateway's kept link goes first.
  Future<void> _restartByUser() async {
    if (!_canSelect || !widget.enabled) return;
    final release = _releaseHold();
    setState(_clearSelection);
    _syncChoice();
    await release;
    if (mounted && _holdPhase != _Hold.cleanupFailed) await _start(fresh: true);
  }

  /// 1.0.0+9: 〔辨識〕 blinks [peer] ([GatewayDiscovery.onIdentify]) and the
  /// list stays; 「已閃燈」 on its row for [identifiedHintFor].
  ///
  /// 1.0.0+10: the hint only when the identify was really sent (not after
  /// 〔取消操作〕 or a failure).
  ///
  /// Identification is available only on the ready selected connection.
  /// A dropped link never starts another connection implicitly. Failure
  /// leaves an explicit reconnect or retry-disconnect action on this list.
  Future<void> _identify(GatewayPeer peer) async {
    final action = widget.onIdentify;
    if (_selecting || !widget.enabled || action == null) return;
    if (_holdPhase != _Hold.held ||
        peer.id != _holdId ||
        peer.id != _selectedId ||
        _identifyingId != null) {
      return;
    }
    setState(() {
      _identified = null;
      _identifyingId = peer.id;
    });
    _syncChoice();
    try {
      if (!mounted || _holdPhase != _Hold.held || _selectedId != peer.id) {
        return;
      }
      final blinked = await action(peer);
      if (mounted && blinked && _selectedId == peer.id) _showIdentified(peer);
    } catch (_) {
      if (!mounted || _selectedId != peer.id) return;
      // A callback failure leaves readiness uncertain. Close the same held
      // connection before allowing a new action; never retry the blink.
      final release = _releaseHold();
      setState(() {});
      _syncChoice();
      await release;
      if (!mounted) return;
      setState(() {});
      _holdSnack(
        _holdPhase == _Hold.cleanupFailed
            ? gatewayCleanupFailedText
            : L10n.current.gatewayDiscovery_identifyIncomplete,
      );
    } finally {
      if (mounted && _identifyingId == peer.id) {
        setState(() => _identifyingId = null);
        _syncChoice();
      }
    }
  }

  /// 「已送出」 (or 「閘道器已閃・PTU 不會閃」) on [peer]'s row for
  /// [identifiedHintFor] and the SnackBar, after its 〔辨識〕 was sent.
  void _showIdentified(GatewayPeer peer) {
    // Read now: the next 〔辨識〕 resets the answer.
    final gatewayOnly = widget.identifyGatewayOnly?.call() ?? false;
    final note = identifiedGatewayOnlyNoteFor(
      gatewayOnly ? widget.identifyGatewayOnlyReason?.call() : null,
    );
    final stays = gatewayOnly ? identifiedGatewayOnlyFor : identifiedHintFor;
    final title = _titleOf(
      _heard[peer.id]?.peer.name ?? peer.name,
      peer.id,
    ).title;
    _identifiedTimer?.cancel();
    setState(() {
      _identified = peer.id;
      _identifiedGatewayOnly = gatewayOnly;
    });
    _identifiedTimer = Timer(stays, () {
      if (mounted) setState(() => _identified = null);
    });
    // 1.0.0+11: also at the bottom of the screen — the row may be off
    // screen.
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          key: const Key('gateway-identified-snack'),
          content: Text(
            gatewayOnly
                ? identifiedGatewayOnlySnackText(
                    peer.name,
                    title: title,
                    note: note,
                  )
                : identifiedSnackText(peer.name, title: title),
          ),
          duration: stays,
        ),
      );
  }

  /// [signalWidth]: the RSSI column's least width; [nearestNow]: the
  /// nearest shown (1.0.0+11).
  Widget _tile(
    GatewayPeer peer, {
    RecentGateway? recent,
    required DateTime now,
    required double signalWidth,
    ({String nearest, bool close})? nearestNow,
  }) {
    final heard = _heard[peer.id];
    final lost = heard != null && now.difference(heard.at) > gatewayHeardFor;
    // Heard in the running scan's last answer; else grey (1.0.0+11).
    final live =
        heard != null && _scanning && !_selecting && _live.contains(peer.id);
    final found = heard == null || lost ? null : heard.peer;
    final last =
        recent ?? _recent.where((r) => r.peer.id == peer.id).firstOrNull;
    final name = heard?.peer.name ?? peer.name;
    // 1.0.0+9: the back-office state as a short phrase (在線／離線／無紀錄／
    // 未知).
    final stale =
        _backendAt == null ||
        DateTime.now().difference(_backendAt!).inSeconds > 30;
    final presence = !ref.watch(commissionProvider).loggedIn || stale
        ? backendUnknownShort
        : backendPresenceShort(
            last?.uid,
            _fleet,
            archived: _archived,
            advertisedName: name,
          );
    final configured = _configured(peer.id);
    // 1.0.0+11: never 「未收到廣播」 (wide: it cut the title) — the last RSSI
    // heard (grey while not live), 「—」 never heard, 「訊號中斷」 not heard
    // for [gatewayHeardFor].
    final signal = heard == null
        ? gatewayNeverHeardLabel
        : lost
        ? gatewaySignalLostLabel
        : heard.peer.rssi <= -127
        ? context.l10n.gatewayDiscovery_signalUnknown
        : '${heard.peer.rssi} dBm';
    // Round 26 (field: two gateways both read 「GIOS-S80-G…」): 「站 80 ·
    // 閘道器 2」 as the title. 1.0.0+10: the advertised name (the live one:
    // a recent entry keeps the name it had) only when it does not parse —
    // the title says the same.
    // 1.0.0+12: 「未配置閘道器 …70F0」 for a gateway known not to be
    // configured (never an old identity it still advertises).
    final (:title, :unconfigured) = _titleOf(name, peer.id);
    // Round 28 (field round 28: this list read 「70F2」, the help panel and
    // the back office 「70F0」): the Wi-Fi MAC tail the back office shows —
    // remembered from an earlier connect, else derived from the Bluetooth
    // MAC. 1.0.0+9: 「…3A00」 (no 「MAC」 word).
    final wifi = gatewayWifiMac(uid: last?.uid, bleId: peer.id);
    final tail = wifi == null ? peer.id : '…${wifi.substring(8)}';
    final theme = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    final nearest = found != null && nearestNow?.nearest == peer.id;
    final small = theme.bodySmall?.copyWith(color: colors.onSurfaceVariant);
    final identified = _identified == peer.id;
    final identifying = _identifyingId == peer.id;
    final backendNote = gatewayBackendNoteFor(presence);
    final detail = [if (title == name) name, tail].join(' · ');
    // 1.0.0+14 (1.0.0+12's 「未配置閘道器 …70F0」 took two lines at text
    // scale 1.1 on a 360 dp phone and looked cut): the card's title is
    // 「未配置閘道器」 on one line, its MAC tail on line 3 like every card's;
    // the SnackBar and the bottom button keep the full [title].
    final cardTitle = unconfigured ? unconfiguredGatewayText : title;
    // 1.0.0+14: the selection (a primary outline, a tint, 「✓ 已選取」),
    // its connect (「連線中…」) and the other cards faded meanwhile.
    final selected = _selectedId == peer.id;
    final connecting = _connectingId == peer.id;
    // 1.0.0+22: the selected gateway's kept link.
    final hold = selected && _holdId == peer.id ? _holdPhase : _Hold.none;
    final faded = _connectingId != null && !connecting;
    // 1.0.0+10 (phone 360 dp at text scale 1.1: line 1 wrapped and pushed
    // the dBm to a second line, line 3 cut 「· …」, the name repeated the
    // title): three short lines per gateway —
    // 1. 「站 81・閘道器 1」 (titleMedium w700, cut with an ellipsis if ever
    //    too long) and 「-40 dBm」 fixed at the right end;
    // 2. the marks as small chips: 「最近」 (filled green, the strongest
    //    gateway only), 「已配置」／「未配置」, the back office's short
    //    phrase (「已閃燈」 for 3 s after 〔辨識〕), then the link state;
    // 3. 「…3A00」 (bodySmall).
    final (badgeKey, badgeText) = configured
        ? ('gateway-configured-', gatewayConfiguredLabel)
        : unconfigured
        ? ('gateway-unconfigured-', gatewayUnconfiguredLabel)
        : ('gateway-pending-', gatewayPendingLabel);
    // Always an Opacity (1 unless faded): the card's subtree is not built
    // anew when a connect starts.
    return Opacity(
      key: ValueKey('gateway-fade-${peer.id}'),
      opacity: faded ? 0.38 : 1,
      child: Card(
        key: ValueKey('gateway-card-${peer.id}'),
        margin: const EdgeInsets.symmetric(vertical: 2),
        // 1.0.0+14: an outline only for the selection (「最近」 is its green
        // chip alone); the border does not move the content.
        shape: selected
            ? RoundedRectangleBorder(
                side: BorderSide(color: colors.primary, width: 2),
                borderRadius: BorderRadius.circular(4),
              )
            : null,
        color: selected
            ? colors.primaryContainer.withValues(alpha: 0.45)
            : null,
        child: Semantics(
          key: ValueKey('gateway-select-${peer.id}'),
          container: true,
          selected: selected,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              InkWell(
                key: ValueKey(peer.id),
                borderRadius: BorderRadius.circular(4),
                // Card taps select; its explicit Bluetooth button connects.
                onTap: widget.enabled && _canSelect
                    ? () => _select(heard?.peer ?? peer)
                    : null,
                child: _tileBody(
                  peer,
                  cardTitle: cardTitle,
                  signal: signal,
                  signalWidth: signalWidth,
                  live: live,
                  nearest: nearest,
                  badgeKey: badgeKey,
                  badgeText: badgeText,
                  configured: configured,
                  identified: identified,
                  identifying: identifying,
                  presence: presence,
                  detail: detail,
                  small: small,
                  selected: selected,
                  connecting: connecting,
                  hold: hold,
                  onIdentify:
                      widget.enabled && !_selecting && _identifyingId == null
                      ? () => _identify(heard?.peer ?? peer)
                      : null,
                ),
              ),
              if (backendNote != null)
                Visibility(
                  key: ValueKey('gateway-backend-note-visibility-${peer.id}'),
                  // Identification temporarily replaces the backend mark.
                  // Keep its room so blinking does not move adjacent cards.
                  visible: !identified,
                  maintainState: true,
                  maintainAnimation: true,
                  maintainSize: true,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                    child: Text(
                      backendNote,
                      key: ValueKey('gateway-backend-note-${peer.id}'),
                      style: small,
                      softWrap: true,
                      overflow: TextOverflow.visible,
                    ),
                  ),
                ),
              if (widget.onHold != null)
                _cardActions(
                  heard?.peer ?? peer,
                  selected: selected,
                  hold: hold,
                  identifying: identifying,
                  identified: identified,
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// A card's three lines and its 〔辨識〕 bulb ([_tile]).
  Widget _tileBody(
    GatewayPeer peer, {
    required String cardTitle,
    required String signal,
    required double signalWidth,
    required bool live,
    required bool nearest,
    required String badgeKey,
    required String badgeText,
    required bool configured,
    required bool identified,
    required bool identifying,
    required String presence,
    required String detail,
    required TextStyle? small,
    required bool selected,
    required bool connecting,
    required _Hold hold,
    required VoidCallback? onIdentify,
  }) {
    final theme = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    return Padding(
      // Explicit-link cards put the bulb in the action row. Their content
      // and start button share the same inset. Keep the metadata-to-action
      // gap compact when status marks wrap on narrow screens.
      padding: EdgeInsets.fromLTRB(
        12,
        8,
        widget.onHold != null ? 12 : 2,
        widget.onHold != null ? 4 : 8,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  key: ValueKey('gateway-head-${peer.id}'),
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Expanded(
                      child: Text(
                        cardTitle,
                        key: ValueKey('gateway-title-${peer.id}'),
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                        style: theme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // 1.0.0+11: a column at least as wide as 「-88 dBm」
                    // and 「訊號中斷」 (right-aligned): the title's room
                    // does not change with the text.
                    ConstrainedBox(
                      constraints: BoxConstraints(minWidth: signalWidth),
                      child: Text(
                        signal,
                        key: ValueKey('gateway-signal-${peer.id}'),
                        maxLines: 1,
                        softWrap: false,
                        textAlign: TextAlign.right,
                        style: theme.bodyMedium?.copyWith(
                          color: live ? null : colors.outline,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Wrap(
                  key: ValueKey('gateway-marks-${peer.id}'),
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (nearest)
                      GatewayMark(
                        gatewayNearestLabel,
                        key: ValueKey('gateway-nearest-${peer.id}'),
                        color: gatewayNearestColor,
                        filled: true,
                      ),
                    GatewayMark(
                      badgeText,
                      key: ValueKey('$badgeKey${peer.id}'),
                      color: configured
                          ? colors.onSurfaceVariant
                          : colors.outline,
                    ),
                    GatewayMark(
                      identified
                          ? (_identifiedGatewayOnly
                                ? identifiedGatewayOnlyHint
                                : identifiedHint)
                          : presence,
                      key: ValueKey('gateway-presence-${peer.id}'),
                      color: identified
                          ? colors.primary
                          : colors.onSurfaceVariant,
                    ),
                    // Connection belongs with the other status marks. Wrap
                    // the group when needed instead of crowding the MAC row.
                    Visibility(
                      visible: selected || widget.onHold != null,
                      maintainSize: true,
                      maintainAnimation: true,
                      maintainState: true,
                      child: _SelectedMark(
                        key: selected
                            ? ValueKey('gateway-selected-${peer.id}')
                            : widget.onHold != null
                            ? ValueKey('gateway-state-${peer.id}')
                            : null,
                        connecting: connecting,
                        phase: hold,
                        selected: selected || widget.onHold == null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  key: ValueKey('gateway-line3-${peer.id}'),
                  children: [
                    Expanded(
                      child: Text(
                        detail,
                        key: ValueKey('gateway-detail-${peer.id}'),
                        style: small,
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (widget.onHold == null && widget.onIdentify != null)
            _identifyControl(
              peer,
              hold: hold,
              identifying: identifying,
              identified: identified,
              onIdentify: onIdentify,
            ),
        ],
      ),
    );
  }

  Widget _identifyControl(
    GatewayPeer peer, {
    required _Hold hold,
    required bool identifying,
    required bool identified,
    required VoidCallback? onIdentify,
  }) => hold == _Hold.held
      ? IconButton(
          key: ValueKey('identify-${peer.id}'),
          tooltip: identifyGatewayLabel,
          // While this row's identify runs: a small spinner in
          // the icon's own 24 dp box, so the row does not change
          // size.
          icon: identifying
              ? SizedBox(
                  key: ValueKey('identify-progress-${peer.id}'),
                  width: 24,
                  height: 24,
                  child: const Padding(
                    padding: EdgeInsets.all(3),
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  ),
                )
              : Icon(identified ? Icons.lightbulb : Icons.lightbulb_outline),
          visualDensity: VisualDensity.compact,
          onPressed: onIdentify,
        )
      : SizedBox(
          key: ValueKey('identify-room-${peer.id}'),
          width: gatewayBulbBox,
          height: gatewayBulbBox,
        );

  Widget _cardActions(
    GatewayPeer peer, {
    required bool selected,
    required _Hold hold,
    required bool identifying,
    required bool identified,
  }) {
    final ownsLink = selected && _holdId == peer.id;
    final release =
        ownsLink &&
        (hold == _Hold.held ||
            hold == _Hold.connecting ||
            hold == _Hold.disconnecting ||
            hold == _Hold.cleanupFailed);
    final canRelease =
        widget.enabled &&
        !_selecting &&
        _identifyingId == null &&
        hold != _Hold.disconnecting;
    final holdEpoch = _holdEpoch;
    final actionStyle = Theme.of(context).textTheme.labelLarge;
    final guideConnect =
        widget.enabled &&
        _canSelect &&
        !release &&
        (selected || (_selectedId == null && _shown.length == 1));
    final guideStart = _canStartPeer(peer, holdEpoch);
    const padding = EdgeInsets.symmetric(horizontal: 10);
    final l10n = context.l10n;
    final bluetoothLabel = !release
        ? l10n.gatewayDiscovery_bluetoothConnect
        : hold == _Hold.disconnecting
        ? l10n.gatewayDiscovery_disconnecting
        : hold == _Hold.connecting
        ? l10n.gatewayDiscovery_cancelConnect
        : hold == _Hold.cleanupFailed
        ? l10n.gatewayDiscovery_retryDisconnect
        : l10n.gatewayDiscovery_disconnect;
    final bluetooth = release
        ? OutlinedButton.icon(
            key: const Key('gateway-disconnect'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 48),
              padding: padding,
              textStyle: actionStyle,
            ),
            onPressed: canRelease
                ? () async {
                    if (_selectedId != peer.id || _holdId != peer.id) return;
                    await _disconnectSelected();
                  }
                : null,
            icon: const Icon(Icons.bluetooth_disabled, size: 20),
            label: Text(bluetoothLabel),
          )
        : NextActionGuide.button(
            active: guideConnect,
            child: FilledButton.icon(
              key: selected
                  ? const Key('gateway-link-identify')
                  : ValueKey('gateway-link-${peer.id}'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 48),
                padding: padding,
                textStyle: actionStyle,
              ),
              onPressed: widget.enabled && _canSelect
                  ? () => _holdFromCard(peer)
                  : null,
              icon: const Icon(Icons.bluetooth, size: 20),
              label: Text(bluetoothLabel),
            ),
          );
    final identify = widget.onIdentify == null || hold != _Hold.held
        ? null
        : _identifyControl(
            peer,
            hold: hold,
            identifying: identifying,
            identified: identified,
            onIdentify:
                widget.enabled &&
                    !_selecting &&
                    _identifyingId == null &&
                    ownsLink &&
                    hold == _Hold.held
                ? () => _identify(peer)
                : null,
          );
    final start = NextActionGuide.button(
      child: FilledButton(
        key: ValueKey('gateway-start-${peer.id}'),
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 48),
          padding: padding,
          textStyle: actionStyle,
        ),
        onPressed: _canStartPeer(peer, holdEpoch)
            ? () => _connect(peer, expectedHoldEpoch: holdEpoch)
            : null,
        child: Text(l10n.gatewayDiscovery_startCommissioning),
      ),
    );
    double widthOf(String label) {
      final painter = TextPainter(
        text: TextSpan(text: label, style: actionStyle),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        maxLines: 1,
      )..layout();
      final width = painter.width;
      painter.dispose();
      return width;
    }

    // Measure the visible label: reserving every possible connection state
    // needlessly splits the shorter Disconnect action from Start.
    final bluetoothWidth = widthOf(bluetoothLabel) + 20 + 8 + 20;
    final startWidth = widthOf(l10n.gatewayDiscovery_startCommissioning) + 20;
    final requiredWidth =
        bluetoothWidth +
        startWidth +
        (identify == null ? 8 : gatewayBulbBox + 16);
    return Padding(
      key: ValueKey('gateway-actions-${peer.id}'),
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Visibility(
            visible: guideConnect || guideStart,
            maintainSize: true,
            maintainState: true,
            maintainAnimation: true,
            child: NextActionHint(
              guideStart ? nextActionBeginCaption : nextActionConnectCaption,
              alignEnd: guideStart,
              active: guideConnect || guideStart,
            ),
          ),
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth >= requiredWidth) {
                return Row(
                  children: [
                    bluetooth,
                    if (identify != null) ...[
                      const SizedBox(width: 8),
                      identify,
                    ],
                    const Spacer(),
                    const SizedBox(width: 8),
                    start,
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Keep the two text actions together on narrow screens.
                  // The secondary identify action can occupy the row above.
                  if (identify != null) ...[
                    Align(alignment: Alignment.centerRight, child: identify),
                    const SizedBox(height: 4),
                  ],
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(flex: bluetoothWidth.ceil(), child: bluetooth),
                      const SizedBox(width: 8),
                      Flexible(flex: startWidth.ceil(), child: start),
                    ],
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  /// 1.0.0+11: the RSSI column's least width — the wider of 「-88 dBm」 (any
  /// two-digit reading) and [gatewaySignalLostLabel], at the text scale.
  double _signalWidth(BuildContext context) {
    final style = DefaultTextStyle.of(
      context,
    ).style.merge(Theme.of(context).textTheme.bodyMedium);
    var width = 0.0;
    for (final sample in ['-88 dBm', gatewaySignalLostLabel]) {
      final painter = TextPainter(
        text: TextSpan(text: sample, style: style),
        textDirection: TextDirection.ltr,
        textScaler: MediaQuery.textScalerOf(context),
        maxLines: 1,
      )..layout();
      if (painter.width > width) width = painter.width;
      painter.dispose();
    }
    return width.ceilToDouble();
  }

  /// 1.0.0+10: 「最近使用」／「附近裝置（N）」 as section titles.
  Widget _groupTitle(String text) => Padding(
    padding: const EdgeInsets.only(top: 8, bottom: 2),
    child: Text(
      text,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
        fontWeight: FontWeight.w600,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );

  /// 1.0.0+17: while the search runs — 「正在搜尋附近的閘道器…」 (「沒找到，
  /// 再搜尋一次…」 for the second one), a bar filling over
  /// [gatewaySearchWindow] (moving while the second one waits) and
  /// 「已找到 N 台」 ([count]: the gateways listed as heard).
  Widget _searchProgress(int count) {
    final theme = Theme.of(context);
    final waiting = _search == _Search.retrying;
    final head = _selecting
        ? gatewayBusyText
        : _holds
        ? gatewaySearchPausedText
        : waiting || _attempt >= 2
        ? gatewayRetryingText
        : gatewaySearchingText;
    final headStyle = theme.textTheme.titleSmall?.copyWith(
      fontWeight: FontWeight.w700,
    );
    return Semantics(
      key: const Key('gateway-search-progress'),
      container: true,
      liveRegion: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 2,
              children: [
                Text(
                  head,
                  key: const Key('gateway-search-head'),
                  style: headStyle,
                ),
                Text(
                  gatewayFoundCountText(count),
                  key: const Key('gateway-found-count'),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            AnimatedBuilder(
              animation: _progress,
              builder: (context, _) => LinearProgressIndicator(
                key: const Key('gateway-search-bar'),
                value: waiting ? null : _progress.value,
                minHeight: 3,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 1.0.0+17: the second search found nothing — what to check, and
  /// 〔重新搜尋〕 as the main button (full width, 52 dp).
  Widget _notFoundBlock() => Column(
    key: const Key('gateway-not-found'),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Semantics(
        liveRegion: true,
        child: Text(
          gatewayNotFoundText,
          key: const Key('gateway-not-found-text'),
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
      if (widget.choice == null) ...[
        const SizedBox(height: 10),
        FilledButton.icon(
          key: const Key('gateway-rescan-primary'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          onPressed: widget.enabled && _canSelect && !_scanActionBusy
              ? _toggleScan
              : null,
          icon: const Icon(Icons.search),
          label: Text(context.l10n.gatewayDiscovery_searchAgain),
        ),
      ],
    ],
  );

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    ref.listen(backendEnvProvider, (_, next) {
      _backendEpoch++;
      setState(() {
        _fleet = [];
        _backendError = null;
        _backendAt = null;
      });
    });
    // Scan changes also reach the external bar without notifying during build.
    _scheduleChoiceSync();
    final selectedId = _selectedId;
    final now = _heardClock();
    // History provides identity metadata, never evidence of proximity.
    // Keep the same scan grace period and pause behavior for both groups.
    final heard = _heardPeers(now);
    final heardIds = {for (final peer in heard) peer.id};
    final recent = [
      for (final (i, r) in _recent.indexed)
        if (heardIds.contains(r.peer.id) ||
            (r.peer.id == selectedId && _heard.containsKey(r.peer.id)))
          (i, r),
    ];
    final recentIds = {for (final (_, r) in recent) r.peer.id};
    // 1.0.0+17: no filter box any more (the user: the list is short and the
    // flow should pick for the installer) — every gateway is listed.
    // 1.0.0+14: while a gateway is selected the cards keep the order they
    // had then ([_frozen]); gateways heard since come after.
    final frozen = _frozen;
    int frozenAt(String id) {
      if (frozen == null) return 0;
      final at = frozen.indexOf(id);
      return at < 0 ? frozen.length : at;
    }

    // Round 30: both lists by the phone's signal, strongest first.
    // 1.0.0+10: configured ones no longer after the others — the strongest
    // (「最近」) is first in its group.
    recent.sort((a, b) {
      final f = frozenAt(a.$2.peer.id) - frozenAt(b.$2.peer.id);
      if (f != 0) return f;
      final c = _rankOf(a.$2.peer.id) - _rankOf(b.$2.peer.id);
      return c != 0 ? c : a.$1 - b.$1;
    });
    final selectedLost =
        selectedId != null &&
        !recentIds.contains(selectedId) &&
        !heardIds.contains(selectedId);
    final ranked = [
      ...heard.where((p) => !recentIds.contains(p.id)),
      // 1.0.0+14: the selected gateway stays listed when not heard for
      // [gatewayHeardFor] (「訊號中斷」).
      if (selectedLost) _heard[selectedId]?.peer ?? _selectedPeer!,
    ].indexed.toList();
    ranked.sort((a, b) {
      final f = frozenAt(a.$2.id) - frozenAt(b.$2.id);
      return f != 0 ? f : a.$1 - b.$1;
    });
    final nearby = [for (final (_, p) in ranked) p];
    _shown = [
      for (final r in recent) r.$2.peer.id,
      for (final p in nearby) p.id,
    ];
    // 1.0.0+14: the bottom button's text follows the card's title (e.g. the
    // back office's list arrived: 「未配置閘道器 …70F0」).
    if (selectedId != null) {
      final peer = _heard[selectedId]?.peer ?? _selectedPeer!;
      if (_choice.peer?.id != selectedId ||
          _choice.title != _titleOf(peer.name, peer.id).title) {
        _scheduleChoiceSync();
      }
    }
    final nearest = heardIds.length >= 2 && heardIds.contains(_nearest?.nearest)
        ? _nearest
        : null;
    final signalWidth = _signalWidth(context);
    // 1.0.0+17: 〔停止搜尋〕 also cancels the automatic second search.
    final stoppable = _scanning || _search == _Search.retrying;
    Widget tile(GatewayPeer peer, {RecentGateway? recent}) => _tile(
      peer,
      recent: recent,
      now: now,
      signalWidth: signalWidth,
      nearestNow: nearest,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              l10n.gatewayDiscovery_selectNearby,
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
            // 1.0.0+17: after the second search found nothing it is the
            // big 〔重新搜尋〕 under the message instead.
            if (widget.choice == null && _search != _Search.notFound)
              FilledButton.icon(
                key: const Key('gateway-scan-toggle'),
                onPressed: widget.enabled && _canSelect && !_scanActionBusy
                    ? _toggleScan
                    : null,
                icon: Icon(stoppable ? Icons.stop : Icons.search),
                label: Text(
                  stoppable
                      ? l10n.gatewayDiscovery_stopSearch
                      : l10n.gatewayDiscovery_searchAgain,
                ),
              ),
            // 1.0.0+10 (phone: always there): only when the scan failed for
            // want of a permission.
            if (_needsSettings)
              TextButton(
                key: const Key('gateway-open-settings'),
                onPressed: widget.enabled ? openAppSettings : null,
                child: Text(l10n.gatewayStatus_openSettings),
              ),
          ],
        ),
        const SizedBox(height: 8),
        // 1.0.0+17: the search's progress (it pauses — and stays, the list
        // does not move — while 〔辨識〕 runs); after it one line.
        if (_search == _Search.searching || _search == _Search.retrying)
          _searchProgress(heard.length)
        else if (_search == _Search.notFound)
          _notFoundBlock()
        else
          Text(
            _selecting
                ? gatewayBusyText
                : heard.isNotEmpty
                ? gatewayFoundText(heard.length, withHint: nearest != null)
                : _scanning
                ? gatewaySearchingText
                : gatewayStoppedText,
            key: const Key('gateway-search-status'),
            // One style whatever it says: 〔辨識〕 moves nothing.
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
        if (widget.enabled &&
            _canSelect &&
            selectedId == null &&
            _shown.length > 1)
          NextActionHint(l10n.gatewayDiscovery_pickCardHint),
        if (_error != null)
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        if (nearest?.close == true)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              '⚠ $gatewayCloseHint',
              key: const Key('gateway-close-hint'),
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        if (recent.isNotEmpty) ...[
          _groupTitle(l10n.gatewayDiscovery_recentGroup),
          ...recent.map((r) => tile(r.$2.peer, recent: r.$2)),
        ],
        if (nearby.isNotEmpty) ...[
          _groupTitle(l10n.gatewayDiscovery_nearbyGroup(nearby.length)),
          ...nearby.map(tile),
        ],
        const SizedBox(height: 8),
        Text(l10n.gatewayDiscovery_rssiNote),
        if (nearest != null)
          Container(
            key: const Key('gateway-nearest-hint'),
            margin: const EdgeInsets.symmetric(vertical: 6),
            padding: const EdgeInsets.all(10),
            color: Theme.of(context).colorScheme.secondaryContainer,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  gatewayNearestHint,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSecondaryContainer,
                  ),
                ),
              ],
            ),
          ),
        if (_backendAt != null) Text(l10n.gatewayDiscovery_backendRefreshNote),
        if (_backendCurrent)
          Text(
            l10n.gatewayDiscovery_backendReferenceNote,
            key: const Key('gateway-backend-reference-note'),
          ),
        // 1.0.0+9: the rows say 「後端未知」 only; the reason is this line.
        if (_backendAt == null && _backendError != null)
          Text(
            _backendError!,
            key: const Key('gateway-backend-error'),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
      ],
    );
  }
}
