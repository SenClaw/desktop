// What the agent remembers from conversations, one dated fact per row.
//
// Facts are written automatically (a conversation window, or the summary made
// when the context is compacted), so the person has to be able to read them
// and take one away. Client of `/api/memory/facts*` (the daemon's
// `src/gateway/ui_server/memory_facts.rs`; guide `docs/memory-engine.md`).
//
// A fact belongs to an agent (its folder, the "bank"). The picker lists only
// agents that have facts, and a fact is only ever listed or forgotten under
// the agent that owns it.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/i18n/l10n.dart';
import '../../core/transport/api_client.dart';
import '../../core/transport/connection.dart';
import '../../models/project.dart';
import '../../theme/tokens.dart';
import '../projects/projects_provider.dart' show projectNamesProvider;

class MemoryFact {
  final String id;
  final String kind;
  final String text;
  final int? occurredStart;
  final int? occurredEnd;
  final int mentionedAt;
  final List<String> entities;
  final int proofCount;
  final String? supersededBy;

  /// The chat it was said in; only that chat recalls it. Empty means the whole
  /// agent (a fact from before chats were told apart).
  final String origin;

  /// `manual` for a fact a person typed; otherwise what extracted it
  /// (`reflection`, `compaction`, `kanban`). Empty when the daemon is older.
  final String source;
  const MemoryFact({
    required this.id,
    required this.kind,
    required this.text,
    required this.occurredStart,
    required this.occurredEnd,
    required this.mentionedAt,
    required this.entities,
    required this.proofCount,
    required this.supersededBy,
    required this.origin,
    this.source = '',
  });

  factory MemoryFact.fromJson(Map<String, dynamic> j) => MemoryFact(
    id: '${j['id'] ?? ''}',
    kind: '${j['kind'] ?? 'world'}',
    text: '${j['text'] ?? ''}',
    occurredStart: (j['occurredStart'] as num?)?.toInt(),
    occurredEnd: (j['occurredEnd'] as num?)?.toInt(),
    mentionedAt: (j['mentionedAt'] as num?)?.toInt() ?? 0,
    entities: [for (final e in (j['entities'] as List? ?? const [])) '$e'],
    proofCount: (j['proofCount'] as num?)?.toInt() ?? 1,
    supersededBy: j['supersededBy'] as String?,
    origin: '${j['origin'] ?? ''}',
    source: '${j['source'] ?? ''}',
  );

  /// A fact replaced because the person changed their mind.
  bool get replaced => supersededBy != null;

  /// Typed by a person; no conversation replaces it.
  bool get typed => source == 'manual';
}

class FactBank {
  final String bank;
  final int current;
  final int replaced;
  const FactBank(this.bank, this.current, this.replaced);

  factory FactBank.fromJson(Map<String, dynamic> j) => FactBank(
    '${j['bank'] ?? ''}',
    (j['current'] as num?)?.toInt() ?? 0,
    (j['replaced'] as num?)?.toInt() ?? 0,
  );
}

/// What a listing asks for. A record, so two equal queries share one provider.
typedef FactsQuery = ({String bank, String q, bool history});

final factBanksProvider = FutureProvider.autoDispose<List<FactBank>>((
  ref,
) async {
  final r = await ref.read(apiClientProvider).get('/api/memory/facts/banks');
  final list = (r is Map ? r['banks'] : null) as List? ?? const [];
  return list
      .whereType<Map>()
      .map((m) => FactBank.fromJson(m.cast<String, dynamic>()))
      .toList();
});

final factsProvider = FutureProvider.autoDispose
    .family<List<MemoryFact>, FactsQuery>((ref, query) async {
      final q = query.q.trim();
      final r = await ref
          .read(apiClientProvider)
          .get(
            '/api/memory/facts',
            query: {
              'bank': query.bank,
              'limit': 100,
              if (q.isNotEmpty) 'q': q,
              if (query.history) 'history': 'true',
            },
          );
      final list = (r is Map ? r['facts'] : null) as List? ?? const [];
      return list
          .whereType<Map>()
          .map((m) => MemoryFact.fromJson(m.cast<String, dynamic>()))
          .toList();
    });

/// What a bank is called in a picker: an agent's folder as it is, a project's
/// bank (`project:<id>`) by the project's name — or its id while the project
/// list has not loaded, or for a project that no longer exists.
String bankLabel(
  BuildContext context,
  String bank,
  Map<String, String> projectNames,
) {
  final id = projectIdOfBank(bank);
  if (id == null) return bank;
  return context.trArgs('Project: {name}', {'name': projectNames[id] ?? id});
}

String _two(int n) => n.toString().padLeft(2, '0');
String _isoDay(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';

/// The precision a stored span was said at: `2026`, `2026-03` or `2026-03-09`.
/// Mirrors `extract::span_label` in the daemon so a fact reads the same here as
/// in the agent's own tool output. Spans are UTC midnights (`end` exclusive),
/// so they are read in UTC — local time would show 2026-03-08 west of Greenwich.
String spanLabel(int start, int? end) {
  DateTime utc(int s) =>
      DateTime.fromMillisecondsSinceEpoch(s * 1000, isUtc: true);
  final s = utc(start);
  final e = end == null ? null : utc(end);
  bool onDay(DateTime d, int y, int m, int day) =>
      d.year == y && d.month == m && d.day == day;
  final wholeYear =
      s.month == 1 && s.day == 1 && e != null && onDay(e, s.year + 1, 1, 1);
  final nextYear = s.month == 12 ? s.year + 1 : s.year;
  final nextMonth = s.month == 12 ? 1 : s.month + 1;
  final wholeMonth =
      s.day == 1 && e != null && onDay(e, nextYear, nextMonth, 1);
  if (wholeYear) return '${s.year}';
  if (wholeMonth) return '${s.year}-${_two(s.month)}';
  return _isoDay(s);
}

/// The span the fact is about, or — when it has none — the day it was said.
({String label, bool dated}) factWhen(MemoryFact f) {
  final s = f.occurredStart;
  if (s != null) {
    return (label: spanLabel(s, f.occurredEnd ?? s + 86400), dated: true);
  }
  return (
    label: _isoDay(DateTime.fromMillisecondsSinceEpoch(f.mentionedAt * 1000)),
    dated: false,
  );
}

class FactsPanel extends ConsumerStatefulWidget {
  const FactsPanel({super.key});
  @override
  ConsumerState<FactsPanel> createState() => _FactsPanelState();
}

class _FactsPanelState extends ConsumerState<FactsPanel> {
  String? _bank;
  String _submitted = '';
  bool _history = false;
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _reload() {
    ref.invalidate(factBanksProvider);
    ref.invalidate(factsProvider);
  }

  Future<void> _forget(String bank, MemoryFact fact) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.colors.surface,
        title: Text(ctx.tr('Forget this fact?')),
        content: Text(ctx.tr('The agent will stop recalling it.')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(ctx.tr('Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(ctx.tr('Forget')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final done = context.tr('Forgotten');
    try {
      await ref
          .read(apiClientProvider)
          .delete(
            '/api/memory/facts/${Uri.encodeComponent(fact.id)}'
            '?bank=${Uri.encodeQueryComponent(bank)}',
          );
      // Forgetting a replacement brings back what it replaced: reload both.
      _reload();
      messenger.showSnackBar(SnackBar(content: Text(done)));
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(context.trArgs('Forget failed: {error}', {'error': e})),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final banks = ref.watch(factBanksProvider);
    final projectNames = ref.watch(projectNamesProvider);
    return banks.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _notice(
        context,
        e is ApiException && e.status == 503
            ? context.tr(
                'The fact store has not started yet — try again in a moment.',
              )
            : context.trArgs('Load failed: {error}', {'error': e}),
      ),
      data: (list) {
        final bank = list.any((b) => b.bank == _bank)
            ? _bank
            : (list.isEmpty ? null : list.first.bank);
        final current = list.where((b) => b.bank == bank).firstOrNull;
        return Padding(
          padding: const EdgeInsets.all(AppTokens.s16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.tr(
                  'Dated statements the agent picked out of your conversations. '
                  'They are recalled automatically in later chats — forget any '
                  'that are wrong or that you did not want kept.',
                ),
                style: TextStyle(color: c.textMuted, fontSize: 12.5),
              ),
              const SizedBox(height: AppTokens.s12),
              Wrap(
                spacing: AppTokens.s12,
                runSpacing: AppTokens.s8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  DropdownButton<String>(
                    value: bank,
                    hint: Text(context.tr('No agent has facts yet')),
                    underline: const SizedBox.shrink(),
                    isDense: true,
                    style: TextStyle(color: c.textPrimary, fontSize: 12.5),
                    items: [
                      for (final b in list)
                        DropdownMenuItem(
                          value: b.bank,
                          child: Text(
                            '${bankLabel(context, b.bank, projectNames)} · ${b.current}${b.replaced > 0 ? ' (+${b.replaced})' : ''}',
                          ),
                        ),
                    ],
                    onChanged: (v) => setState(() {
                      _bank = v;
                      _submitted = '';
                      _search.clear();
                    }),
                  ),
                  SizedBox(
                    width: 280,
                    child: TextField(
                      controller: _search,
                      enabled: bank != null,
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        isDense: true,
                        prefixIcon: const Icon(Icons.search, size: 18),
                        hintText: context.tr('Search facts…'),
                      ),
                      onSubmitted: (v) => setState(() => _submitted = v),
                    ),
                  ),
                  Tooltip(
                    message: context.tr(
                      'Also list facts that were replaced. A keyword search never shows them.',
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Switch(
                          value: _history,
                          // A keyword search never returns replaced facts.
                          onChanged:
                              bank == null || _submitted.trim().isNotEmpty
                              ? null
                              : (v) => setState(() => _history = v),
                        ),
                        Text(
                          current != null && current.replaced > 0
                              ? context.trArgs('Show replaced ({n})', {
                                  'n': current.replaced,
                                })
                              : context.tr('Show replaced'),
                          style: TextStyle(
                            color: c.textPrimary,
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: context.tr('Refresh'),
                    icon: const Icon(Icons.refresh, size: 18),
                    onPressed: _reload,
                  ),
                ],
              ),
              const SizedBox(height: AppTokens.s8),
              Expanded(
                child: bank == null
                    ? _empty(
                        context.tr(
                          'Nothing remembered yet. Facts appear here a minute or two after a conversation goes quiet.',
                        ),
                      )
                    : _FactList(
                        bank: bank,
                        query: (bank: bank, q: _submitted, history: _history),
                        onForget: (f) => _forget(bank, f),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _empty(String text) => Center(
    child: Text(text, style: TextStyle(color: context.colors.textMuted)),
  );

  Widget _notice(BuildContext context, String text) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(text, style: TextStyle(color: context.colors.textMuted)),
        const SizedBox(height: AppTokens.s8),
        TextButton(onPressed: _reload, child: Text(context.tr('Refresh'))),
      ],
    ),
  );
}

class _FactList extends ConsumerWidget {
  final String bank;
  final FactsQuery query;
  final void Function(MemoryFact) onForget;
  const _FactList({
    required this.bank,
    required this.query,
    required this.onForget,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final facts = ref.watch(factsProvider(query));
    return facts.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Text(
          context.trArgs('Load failed: {error}', {'error': e}),
          style: TextStyle(color: c.textMuted),
        ),
      ),
      data: (list) {
        if (list.isEmpty) {
          return Center(
            child: Text(
              query.q.trim().isNotEmpty
                  ? context.tr('No fact matches that search.')
                  : projectIdOfBank(bank) != null
                  ? context.tr('This project has no facts.')
                  : context.tr('This agent has no facts.'),
              style: TextStyle(color: c.textMuted),
            ),
          );
        }
        return ListView.separated(
          itemCount: list.length,
          separatorBuilder: (_, _) => Divider(height: 1, color: c.border),
          itemBuilder: (_, i) =>
              FactRow(fact: list[i], onForget: () => onForget(list[i])),
        );
      },
    );
  }
}

/// One fact with its date, kind, evidence and a Forget button. Shared with the
/// project's own Facts tab.
class FactRow extends StatelessWidget {
  final MemoryFact fact;
  final VoidCallback onForget;
  const FactRow({super.key, required this.fact, required this.onForget});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final when = factWhen(fact);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppTokens.s8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fact.text,
                  style: TextStyle(
                    color: fact.replaced ? c.textMuted : c.textPrimary,
                    fontSize: 13,
                    decoration: fact.replaced
                        ? TextDecoration.lineThrough
                        : null,
                  ),
                ),
                const SizedBox(height: AppTokens.s4),
                Wrap(
                  spacing: AppTokens.s4,
                  runSpacing: AppTokens.s4,
                  children: [
                    if (fact.replaced)
                      Tooltip(
                        message: context.tr(
                          'The person changed their mind; the newer fact replaced this one. Forgetting the newer fact brings this one back.',
                        ),
                        child: _chip(context.tr('replaced'), Colors.orange),
                      ),
                    if (fact.origin.isNotEmpty)
                      Tooltip(
                        message: context.tr(
                          'Said in this chat; only this chat recalls it.',
                        ),
                        child: _chip(fact.origin, AppTokens.cyan),
                      ),
                    if (fact.typed)
                      Tooltip(
                        message: context.tr(
                          'Typed by hand; what a conversation says never replaces it.',
                        ),
                        child: _chip(context.tr('typed'), AppTokens.success),
                      ),
                    if (fact.source == 'kanban')
                      Tooltip(
                        message: context.tr(
                          'Kept from a kanban card that a worker finished.',
                        ),
                        child: _chip('kanban', AppTokens.brandAlt),
                      ),
                    for (final e in fact.entities) _chip(e, c.textMuted),
                  ],
                ),
              ],
            ),
          ),
          SizedBox(
            width: 120,
            child: when.dated
                ? Text(
                    when.label,
                    style: TextStyle(color: c.textPrimary, fontSize: 12.5),
                  )
                : Tooltip(
                    message: context.tr(
                      'No date in the fact; this is the day it was said.',
                    ),
                    child: Text(
                      context.trArgs('said {date}', {'date': when.label}),
                      style: TextStyle(color: c.textMuted, fontSize: 12.5),
                    ),
                  ),
          ),
          SizedBox(
            width: 90,
            child: Tooltip(
              message: fact.kind == 'world'
                  ? context.tr('Something about the world or the person.')
                  : context.tr(
                      'Something the agent itself did or experienced.',
                    ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: _chip(
                  fact.kind,
                  fact.kind == 'world' ? AppTokens.brand : AppTokens.brandAlt,
                ),
              ),
            ),
          ),
          SizedBox(
            width: 44,
            child: Text(
              fact.proofCount > 1 ? '×${fact.proofCount}' : '—',
              style: TextStyle(color: c.textMuted, fontSize: 12.5),
            ),
          ),
          IconButton(
            tooltip: context.tr('Forget'),
            icon: const Icon(Icons.delete_outline, size: 18),
            color: Colors.redAccent,
            onPressed: onForget,
          ),
        ],
      ),
    );
  }

  Widget _chip(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
    decoration: BoxDecoration(
      border: Border.all(color: color.withValues(alpha: 0.5)),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(text, style: TextStyle(color: color, fontSize: 11)),
  );
}
