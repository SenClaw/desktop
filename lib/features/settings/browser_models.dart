// `/api/browser-agent/*` shapes: engine settings, the Chrome extension's
// pairing state, and on-demand tab activity. Mirrors
// `src/browser_agent/{settings,extension,rest}.rs` on the daemon side
// (branch feat/sen-browser-v2). Spec:
// senclaw/plans/260929-0143-sen-browser-runtime/ui-management.md.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/transport/api_client.dart' show ApiClient;
import '../../core/transport/connection.dart';

Map<String, dynamic> _asMap(dynamic v) => v is Map ? v.cast<String, dynamic>() : {};
List<String> _asStrings(dynamic v) => (v as List? ?? const []).map((e) => '$e').toList();
double _dbl(Object? v, double fallback) => v is num ? v.toDouble() : fallback;
int _int(Object? v, int fallback) => v is num ? v.toInt() : fallback;
String? _str(Object? v) => v is String && v.isNotEmpty ? v : null;

/// A confidence band (`bandsLocal` / `bandsHosted`): act at or above [act],
/// ask the LLM at or above [fallback] (`fallback <= act`, both 0..1).
class BrowserBands {
  const BrowserBands({required this.act, required this.fallback});
  final double act;
  final double fallback;

  factory BrowserBands.fromJson(Map<String, dynamic> j) =>
      BrowserBands(act: _dbl(j['act'], 0.6), fallback: _dbl(j['fallback'], 0.2));

  Map<String, dynamic> toJson() => {'act': act, 'fallback': fallback};

  BrowserBands copyWith({double? act, double? fallback}) =>
      BrowserBands(act: act ?? this.act, fallback: fallback ?? this.fallback);

  @override
  bool operator ==(Object other) =>
      other is BrowserBands && other.act == act && other.fallback == fallback;
  @override
  int get hashCode => Object.hash(act, fallback);
}

/// `BrowserSettings` — `src/browser_agent/settings.rs`, camelCase on the
/// wire. Every field is optional on `PUT`; this class always carries a full
/// value (the daemon's own defaults fill in what wasn't stored), and
/// [browserSettingsDiff] is what turns an edit into the partial body Save
/// actually sends.
class BrowserSettings {
  const BrowserSettings({
    this.engine = 'auto',
    this.defaultDriver = 'managed',
    this.decisionBackend = 'auto',
    this.localModel = 'laya-browser',
    this.hostedModel,
    this.hostedDomains = const [],
    this.sensitiveDomains = const [],
    this.domainDrivers = const {},
    this.textModel,
    this.fallbackModel,
    this.bandsLocal = const BrowserBands(act: 0.6, fallback: 0.2),
    this.bandsHosted = const BrowserBands(act: 0.5, fallback: 0.25),
    this.maxSteps = 40,
    this.headless = true,
    this.profile = 'default',
    this.startUrl = 'https://duckduckgo.com/',
  });

  /// `auto` | `v2` | `legacy`.
  final String engine;

  /// `managed` (SenClaw's own Chrome) | `extension` (the user's Chrome).
  final String defaultDriver;

  /// `auto` | `local` | `hosted` | `llm-only`.
  final String decisionBackend;
  final String localModel;

  /// `null` = the provider's own configured default.
  final String? hostedModel;
  final List<String> hostedDomains;
  final List<String> sensitiveDomains;

  /// host → `managed` | `extension`.
  final Map<String, String> domainDrivers;

  /// LLM config id; `null` = the active chat model.
  final String? textModel;

  /// LLM config id; `null` = the active chat model.
  final String? fallbackModel;
  final BrowserBands bandsLocal;
  final BrowserBands bandsHosted;
  final int maxSteps;
  final bool headless;
  final String profile;
  final String startUrl;

  factory BrowserSettings.fromJson(Map<String, dynamic> j) => BrowserSettings(
        engine: '${j['engine'] ?? 'auto'}',
        defaultDriver: '${j['defaultDriver'] ?? 'managed'}',
        decisionBackend: '${j['decisionBackend'] ?? 'auto'}',
        localModel: '${j['localModel'] ?? 'laya-browser'}',
        hostedModel: _str(j['hostedModel']),
        hostedDomains: _asStrings(j['hostedDomains']),
        sensitiveDomains: _asStrings(j['sensitiveDomains']),
        domainDrivers: _asMap(j['domainDrivers']).map((k, v) => MapEntry(k, '$v')),
        textModel: _str(j['textModel']),
        fallbackModel: _str(j['fallbackModel']),
        bandsLocal: j['bandsLocal'] is Map
            ? BrowserBands.fromJson(_asMap(j['bandsLocal']))
            : const BrowserBands(act: 0.6, fallback: 0.2),
        bandsHosted: j['bandsHosted'] is Map
            ? BrowserBands.fromJson(_asMap(j['bandsHosted']))
            : const BrowserBands(act: 0.5, fallback: 0.25),
        maxSteps: _int(j['maxSteps'], 40),
        headless: j['headless'] != false,
        profile: '${j['profile'] ?? 'default'}',
        startUrl: '${j['startUrl'] ?? 'https://duckduckgo.com/'}',
      );

  Map<String, dynamic> toJson() => {
        'engine': engine,
        'defaultDriver': defaultDriver,
        'decisionBackend': decisionBackend,
        'localModel': localModel,
        'hostedModel': hostedModel,
        'hostedDomains': hostedDomains,
        'sensitiveDomains': sensitiveDomains,
        'domainDrivers': domainDrivers,
        'textModel': textModel,
        'fallbackModel': fallbackModel,
        'bandsLocal': bandsLocal.toJson(),
        'bandsHosted': bandsHosted.toJson(),
        'maxSteps': maxSteps,
        'headless': headless,
        'profile': profile,
        'startUrl': startUrl,
      };

  BrowserSettings copyWith({
    String? engine,
    String? defaultDriver,
    String? decisionBackend,
    String? localModel,
    String? Function()? hostedModel,
    List<String>? hostedDomains,
    List<String>? sensitiveDomains,
    Map<String, String>? domainDrivers,
    String? Function()? textModel,
    String? Function()? fallbackModel,
    BrowserBands? bandsLocal,
    BrowserBands? bandsHosted,
    int? maxSteps,
    bool? headless,
    String? profile,
    String? startUrl,
  }) =>
      BrowserSettings(
        engine: engine ?? this.engine,
        defaultDriver: defaultDriver ?? this.defaultDriver,
        decisionBackend: decisionBackend ?? this.decisionBackend,
        localModel: localModel ?? this.localModel,
        hostedModel: hostedModel != null ? hostedModel() : this.hostedModel,
        hostedDomains: hostedDomains ?? this.hostedDomains,
        sensitiveDomains: sensitiveDomains ?? this.sensitiveDomains,
        domainDrivers: domainDrivers ?? this.domainDrivers,
        textModel: textModel != null ? textModel() : this.textModel,
        fallbackModel: fallbackModel != null ? fallbackModel() : this.fallbackModel,
        bandsLocal: bandsLocal ?? this.bandsLocal,
        bandsHosted: bandsHosted ?? this.bandsHosted,
        maxSteps: maxSteps ?? this.maxSteps,
        headless: headless ?? this.headless,
        profile: profile ?? this.profile,
        startUrl: startUrl ?? this.startUrl,
      );
}

/// The loop's local decision checkpoint, as the daemon finds it on disk.
class DecisionModelState {
  const DecisionModelState({required this.id, required this.needed, required this.installed});
  final String id;

  /// False when every step is the LLM's by choice (`decisionBackend: llm-only`).
  final bool needed;
  final bool installed;

  /// Without the checkpoint every step falls to the chat model: seconds per
  /// step instead of a fraction of one, and nothing else says why.
  bool get missing => needed && !installed;

  factory DecisionModelState.fromJson(Map<String, dynamic> j) => DecisionModelState(
        id: j['id'] is String ? j['id'] as String : '',
        needed: j['needed'] == true,
        installed: j['installed'] == true,
      );
}

/// `GET` / `PUT /api/browser-agent/settings`.
class BrowserSettingsView {
  const BrowserSettingsView({
    required this.settings,
    required this.engine,
    required this.runtimeInstalled,
    this.decisionModel,
  });
  final BrowserSettings settings;

  /// `v2` | `legacy` — `engine` already resolved (never `auto`).
  final String engine;
  final bool runtimeInstalled;

  /// Null from a daemon that predates the field.
  final DecisionModelState? decisionModel;

  factory BrowserSettingsView.fromJson(Map<String, dynamic> j) => BrowserSettingsView(
        settings: j['settings'] is Map
            ? BrowserSettings.fromJson(_asMap(j['settings']))
            : const BrowserSettings(),
        engine: j['engine'] == 'v2' ? 'v2' : 'legacy',
        runtimeInstalled: j['runtimeInstalled'] == true,
        decisionModel:
            j['decisionModel'] is Map ? DecisionModelState.fromJson(_asMap(j['decisionModel'])) : null,
      );
}

bool _listEq(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _mapEq(Map<String, String> a, Map<String, String> b) {
  if (a.length != b.length) return false;
  for (final e in a.entries) {
    if (b[e.key] != e.value) return false;
  }
  return true;
}

/// Only the fields that differ between [before] and [after] — the body
/// `PUT /api/browser-agent/settings` actually sends. The daemon's merge is
/// shallow (a changed key replaces its whole stored value), so a touched
/// list/map/band always goes in whole, never as a sub-diff.
Map<String, dynamic> browserSettingsDiff(BrowserSettings before, BrowserSettings after) {
  final full = after.toJson();
  final body = <String, dynamic>{};
  if (before.engine != after.engine) body['engine'] = full['engine'];
  if (before.defaultDriver != after.defaultDriver) body['defaultDriver'] = full['defaultDriver'];
  if (before.decisionBackend != after.decisionBackend) body['decisionBackend'] = full['decisionBackend'];
  if (before.localModel != after.localModel) body['localModel'] = full['localModel'];
  if (before.hostedModel != after.hostedModel) body['hostedModel'] = full['hostedModel'];
  if (!_listEq(before.hostedDomains, after.hostedDomains)) body['hostedDomains'] = full['hostedDomains'];
  if (!_listEq(before.sensitiveDomains, after.sensitiveDomains)) {
    body['sensitiveDomains'] = full['sensitiveDomains'];
  }
  if (!_mapEq(before.domainDrivers, after.domainDrivers)) body['domainDrivers'] = full['domainDrivers'];
  if (before.textModel != after.textModel) body['textModel'] = full['textModel'];
  if (before.fallbackModel != after.fallbackModel) body['fallbackModel'] = full['fallbackModel'];
  if (before.bandsLocal != after.bandsLocal) body['bandsLocal'] = full['bandsLocal'];
  if (before.bandsHosted != after.bandsHosted) body['bandsHosted'] = full['bandsHosted'];
  if (before.maxSteps != after.maxSteps) body['maxSteps'] = full['maxSteps'];
  if (before.headless != after.headless) body['headless'] = full['headless'];
  if (before.profile != after.profile) body['profile'] = full['profile'];
  if (before.startUrl != after.startUrl) body['startUrl'] = full['startUrl'];
  return body;
}

final browserSettingsProvider = FutureProvider<BrowserSettingsView>((ref) async {
  final r = await ref.read(apiClientProvider).get('/api/browser-agent/settings');
  return BrowserSettingsView.fromJson(_asMap(r));
});

// ── Chrome extension pairing (never starts the runtime) ─────────────────

class BrowserExtensionConnected {
  const BrowserExtensionConnected({
    required this.extId,
    required this.version,
    required this.chrome,
    required this.piped,
  });
  final String extId;
  final String version;
  final String chrome;
  final bool piped;

  factory BrowserExtensionConnected.fromJson(Map<String, dynamic> j) => BrowserExtensionConnected(
        extId: '${j['ext_id'] ?? ''}',
        version: '${j['version'] ?? ''}',
        chrome: '${j['chrome'] ?? ''}',
        piped: j['piped'] == true,
      );
}

class BrowserExtensionPending {
  const BrowserExtensionPending({required this.code, required this.extId, required this.ageSecs});
  final String code;
  final String extId;
  final int ageSecs;

  factory BrowserExtensionPending.fromJson(Map<String, dynamic> j) => BrowserExtensionPending(
        code: '${j['code'] ?? ''}',
        extId: '${j['ext_id'] ?? ''}',
        ageSecs: _int(j['age_secs'], 0),
      );
}

class BrowserExtensionPaired {
  const BrowserExtensionPaired({required this.extId, required this.pairedAt});
  final String extId;
  final String pairedAt;

  factory BrowserExtensionPaired.fromJson(Map<String, dynamic> j) => BrowserExtensionPaired(
        extId: '${j['ext_id'] ?? ''}',
        pairedAt: '${j['paired_at'] ?? ''}',
      );
}

/// `GET /api/browser-agent/extension` — also embedded as `extension` in
/// `GET /api/browser-agent/tabs`.
class BrowserExtensionState {
  const BrowserExtensionState({required this.connected, required this.pending, required this.paired});
  final BrowserExtensionConnected? connected;
  final List<BrowserExtensionPending> pending;
  final List<BrowserExtensionPaired> paired;

  factory BrowserExtensionState.fromJson(Map<String, dynamic> j) => BrowserExtensionState(
        connected: j['connected'] is Map ? BrowserExtensionConnected.fromJson(_asMap(j['connected'])) : null,
        pending: (j['pending'] as List? ?? const [])
            .whereType<Map>()
            .map((m) => BrowserExtensionPending.fromJson(m.cast<String, dynamic>()))
            .toList(),
        paired: (j['paired'] as List? ?? const [])
            .whereType<Map>()
            .map((m) => BrowserExtensionPaired.fromJson(m.cast<String, dynamic>()))
            .toList(),
      );
}

/// Polled every 3s while the Chrome extension card is visible — cheap, and
/// (unlike `tabs` below) never starts the runtime.
final browserExtensionProvider = FutureProvider<BrowserExtensionState>((ref) async {
  final r = await ref.read(apiClientProvider).get('/api/browser-agent/extension');
  return BrowserExtensionState.fromJson(_asMap(r));
});

// ── Activity (on demand only — GET tabs starts the runtime) ─────────────

class BrowserTab {
  const BrowserTab({
    required this.id,
    required this.owner,
    required this.driver,
    required this.url,
    required this.hold,
    required this.closed,
  });
  final String id;

  /// The chat that owns this tab.
  final String owner;
  final String driver;
  final String url;

  /// `none` | `handover` | `user_active` | `detached`.
  final String hold;
  final bool closed;

  factory BrowserTab.fromJson(Map<String, dynamic> j) => BrowserTab(
        id: '${j['id'] ?? ''}',
        owner: '${j['owner'] ?? ''}',
        driver: '${j['driver'] ?? ''}',
        url: '${j['url'] ?? ''}',
        hold: '${j['hold'] ?? 'none'}',
        closed: j['closed'] == true,
      );
}

class BrowserSession {
  const BrowserSession({
    required this.id,
    required this.driver,
    required this.profile,
    required this.headless,
    required this.tabs,
  });
  final String id;
  final String driver;
  final String profile;
  final bool headless;
  final List<BrowserTab> tabs;

  factory BrowserSession.fromJson(Map<String, dynamic> j) => BrowserSession(
        id: '${j['id'] ?? ''}',
        driver: '${j['driver'] ?? ''}',
        profile: '${j['profile'] ?? ''}',
        headless: j['headless'] == true,
        tabs: (j['tabs'] as List? ?? const [])
            .whereType<Map>()
            .map((m) => BrowserTab.fromJson(m.cast<String, dynamic>()))
            .toList(),
      );
}

/// `GET /api/browser-agent/tabs` — fetch on an explicit "Show open tabs"
/// press only, never on a timer: unlike settings/extension, this call
/// starts the browser runtime.
class BrowserTabsState {
  const BrowserTabsState({required this.sessions, required this.extension});
  final List<BrowserSession> sessions;
  final BrowserExtensionState extension;

  factory BrowserTabsState.fromJson(Map<String, dynamic> j) => BrowserTabsState(
        sessions: (j['sessions'] as List? ?? const [])
            .whereType<Map>()
            .map((m) => BrowserSession.fromJson(m.cast<String, dynamic>()))
            .toList(),
        extension: j['extension'] is Map
            ? BrowserExtensionState.fromJson(_asMap(j['extension']))
            : const BrowserExtensionState(connected: null, pending: [], paired: []),
      );
}

// ── Waiting for your approval (never starts the runtime) ────────────────

/// One paused browser-task action from `GET /api/browser-agent/approvals`,
/// oldest first. `text`/`url`/`waitingSecs` are the fields the daemon may
/// send as `null` — not every paused operation has typed text or ran on a
/// page with a URL to show.
class PendingBrowserApproval {
  const PendingBrowserApproval({
    required this.approvalId,
    required this.taskId,
    required this.chat,
    required this.goal,
    required this.action,
    required this.operation,
    this.text,
    required this.driver,
    this.url,
    this.waitingSecs,
  });

  final String approvalId;
  final String taskId;

  /// The chat that owns the paused task.
  final String chat;
  final String goal;

  /// The paused action's own label, e.g. "Place order" — shown bold,
  /// verbatim (it is the daemon's text, not translated here).
  final String action;

  /// `CLICK` | `KEY_ENTER` | `DIALOG_ACCEPT` | `TYPE_TEXT` | … — see
  /// `_operationLabel` in browser_section.dart for the friendly mapping.
  final String operation;

  /// The text `TYPE_TEXT` would type, when that is the paused operation.
  final String? text;
  final String driver;
  final String? url;
  final int? waitingSecs;

  factory PendingBrowserApproval.fromJson(Map<String, dynamic> j) => PendingBrowserApproval(
        approvalId: '${j['approval_id'] ?? ''}',
        taskId: '${j['task_id'] ?? ''}',
        chat: '${j['chat'] ?? ''}',
        goal: '${j['goal'] ?? ''}',
        action: '${j['action'] ?? ''}',
        operation: '${j['operation'] ?? ''}',
        text: _str(j['text']),
        driver: '${j['driver'] ?? ''}',
        url: _str(j['url']),
        waitingSecs: j['waiting_secs'] is num ? (j['waiting_secs'] as num).toInt() : null,
      );
}

/// Polled every 5s while the approvals card is visible — cheap, and (like
/// `extension` above, unlike `tabs`) never starts the runtime.
final browserApprovalsProvider = FutureProvider<List<PendingBrowserApproval>>((ref) async {
  final r = await ref.read(apiClientProvider).get('/api/browser-agent/approvals');
  return (_asMap(r)['approvals'] as List? ?? const [])
      .whereType<Map>()
      .map((m) => PendingBrowserApproval.fromJson(m.cast<String, dynamic>()))
      .toList();
});

/// `45s` / `3m` / `1h 5m` — seconds compacted to at most two units, the
/// smaller one dropped once whole minutes are reached. The result is spliced
/// into the translated `Waiting {time}` template as-is: the unit letters
/// (`s`/`m`/`h`) are not translated, same as `up {m}m` in runtime_section.dart.
String formatBrowserWaitingTime(int seconds) {
  final s = seconds < 0 ? 0 : seconds;
  if (s < 60) return '${s}s';
  final minutes = s ~/ 60;
  if (minutes < 60) return '${minutes}m';
  final hours = minutes ~/ 60;
  final restMinutes = minutes % 60;
  return restMinutes == 0 ? '${hours}h' : '${hours}h ${restMinutes}m';
}

/// `POST /api/browser-agent/approvals/:id` outcome — `{task_id, status,
/// message, …}` once the task pauses again or ends. Further fields the
/// daemon may add are intentionally not modeled; only these three matter to
/// the UI.
class BrowserApprovalOutcome {
  const BrowserApprovalOutcome({required this.taskId, required this.status, required this.message});
  final String taskId;

  /// `needs_approval` means the task paused again on a new action; anything
  /// else means it ended (done, blocked, error, …).
  final String status;
  final String message;

  factory BrowserApprovalOutcome.fromJson(Map<String, dynamic> j) => BrowserApprovalOutcome(
        taskId: '${j['task_id'] ?? ''}',
        status: '${j['status'] ?? ''}',
        message: '${j['message'] ?? ''}',
      );
}

/// Answers a paused browser task. The task keeps running inside this call
/// until it pauses again or ends — the daemon's own contract calls that
/// "can take minutes" with no fixed ceiling, so this is given a generous
/// timeout instead of the default [kApiTimeout] (unlike every other call in
/// this file, none of which touch the runtime at all). A `404`
/// (`code: "no_approval"`) means someone already answered it elsewhere; it
/// surfaces as an ordinary [ApiException], same as any other daemon error.
Future<BrowserApprovalOutcome> answerBrowserApproval(
  ApiClient api,
  String approvalId, {
  required bool approve,
}) async {
  final r = await api.post(
    '/api/browser-agent/approvals/${Uri.encodeComponent(approvalId)}',
    body: {'approve': approve},
    timeout: const Duration(minutes: 30),
  );
  return BrowserApprovalOutcome.fromJson((r as Map).cast<String, dynamic>());
}
