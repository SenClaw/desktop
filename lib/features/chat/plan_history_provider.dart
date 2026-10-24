import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/i18n/l10n.dart';
import '../../core/transport/connection.dart';
import '../../core/transport/ws_client.dart';

/// One row of the daemon's `plans:list` (`handle_plan_list`): `approval` is a
/// word (`pending` | `startEditing` | `clearContextAndStart` | `cancelled`) and
/// `createdAt` an RFC 3339 string. Older clients read `status` and a numeric
/// `createdAt`; both spellings are still accepted.
class PlanSummary {
  final String id;
  final String title;
  final String approval;
  final DateTime? createdAt;
  final String filePath;
  const PlanSummary(this.id, this.title, this.approval, this.createdAt,
      {this.filePath = ''});

  factory PlanSummary.fromJson(Map<String, dynamic> j) {
    final title = '${j['title'] ?? ''}'.trim();
    return PlanSummary(
      '${j['id'] ?? ''}',
      title.isEmpty ? L10n.global.t('Untitled plan') : title,
      '${j['approval'] ?? j['status'] ?? ''}',
      _parseTime(j['createdAt']),
      filePath: '${j['filePath'] ?? ''}',
    );
  }

  /// The daemon writes a string; a number is read as epoch milliseconds. Anything
  /// else is "unknown", never an exception — a bad date must not hide the plan.
  static DateTime? _parseTime(Object? v) {
    if (v is num) return DateTime.fromMillisecondsSinceEpoch(v.toInt());
    if (v is String) return DateTime.tryParse(v);
    return null;
  }
}

class PlanHistoryState {
  /// Plan summaries keyed by chat jid — a list for one chat never replaces
  /// another's.
  final Map<String, List<PlanSummary>> summariesByJid;
  final Map<String, String> contentById; // id → markdown
  const PlanHistoryState(
      {this.summariesByJid = const {}, this.contentById = const {}});

  List<PlanSummary> forJid(String jid) => summariesByJid[jid] ?? const [];

  /// Whether the daemon has answered a `plan:list` for [jid] yet — tells
  /// "still loading" apart from "no plans".
  bool hasLoaded(String jid) => summariesByJid.containsKey(jid);
}

/// Plan history for a group (web PlanHistoryPanel): plans live in SQLite, so
/// this replays across restarts. `plan:list`→`plans:list`, `plan:get`→`plans:get`.
class PlanHistoryNotifier extends StateNotifier<PlanHistoryState> {
  PlanHistoryNotifier(this._ref) : super(const PlanHistoryState()) {
    _sub = _ref.read(wsClientProvider).events.listen(_onEvent);
  }
  final Ref _ref;
  late final dynamic _sub;

  void requestList(String jid) {
    _ref.read(wsClientProvider).send({'type': 'plan:list', 'groupJid': jid});
  }

  void requestGet(String id) {
    _ref.read(wsClientProvider).send({'type': 'plan:get', 'id': id});
  }

  void _onEvent(WsEvent e) {
    switch (e['type']) {
      case 'plans:list':
        final jid = '${e['groupJid'] ?? ''}';
        final plans = <PlanSummary>[];
        for (final m in ((e['plans'] as List?) ?? const []).whereType<Map>()) {
          // One malformed row must not take the whole list down with it.
          try {
            plans.add(PlanSummary.fromJson(m.cast<String, dynamic>()));
          } catch (_) {}
        }
        state = PlanHistoryState(
          summariesByJid: {...state.summariesByJid, jid: plans},
          contentById: state.contentById,
        );
      case 'plans:get':
        final p = (e['plan'] as Map?)?.cast<String, dynamic>();
        if (p == null) return;
        state = PlanHistoryState(
          summariesByJid: state.summariesByJid,
          contentById: {
            ...state.contentById,
            '${p['id']}': '${p['contentMd'] ?? p['content'] ?? ''}',
          },
        );
      // The daemon writes the plan row when the agent asks for approval and
      // stamps the decision on it afterwards, so both ends change the list.
      case 'plan:exit:request' || 'plan:exit:response':
        final jid = '${e['groupJid'] ?? ''}';
        if (jid.isNotEmpty) requestList(jid);
    }
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

final planHistoryProvider =
    StateNotifierProvider<PlanHistoryNotifier, PlanHistoryState>(
  (ref) => PlanHistoryNotifier(ref),
);
