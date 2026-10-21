// Plugins → Skills → History (desktop). Every change to one skill: what
// changed it, the diff, what the security scan said, how the skill has behaved
// since (loads, how the turns ended), and a way back. Mirrors the web
// `SkillHistoryPanel`.
//
// Daemon side: `GET /api/skills/:name/history[/:rev]`,
// `POST /api/skills/:name/rollback/:rev`, `GET /api/skill-usage/summary`
// (`../senclaw/docs/skill-history.md`).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/l10n.dart';
import '../../core/transport/api_client.dart';
import '../../core/transport/connection.dart';
import '../../theme/tokens.dart';

// ── Models ──────────────────────────────────────────────────────────────────

class ScanFinding {
  const ScanFinding(this.rule, this.severity, this.title, this.file, this.line);
  final String rule;
  final String severity;
  final String title;
  final String file;
  final int? line;

  factory ScanFinding.fromJson(Map<String, dynamic> j) => ScanFinding(
    '${j['rule'] ?? ''}',
    '${j['severity'] ?? ''}',
    '${j['title'] ?? ''}',
    '${j['file'] ?? ''}',
    j['line'] is int ? j['line'] as int : null,
  );
}

/// What the security scan said about a revision. Never carries matched text.
class ScanSummary {
  const ScanSummary(this.verdict, this.riskScore, this.findings);
  final String verdict; // allow | warn | block
  final int riskScore;
  final List<ScanFinding> findings;

  factory ScanSummary.fromJson(Map<String, dynamic> j) => ScanSummary(
    '${j['verdict'] ?? 'allow'}',
    (j['riskScore'] as num?)?.toInt() ?? 0,
    ((j['findings'] as List?) ?? const [])
        .whereType<Map>()
        .map((f) => ScanFinding.fromJson(Map<String, dynamic>.from(f)))
        .toList(),
  );
}

class SkillRevision {
  const SkillRevision({
    required this.id,
    required this.origin,
    required this.actor,
    required this.contentHash,
    required this.generation,
    required this.fileCount,
    required this.hasSnapshot,
    required this.truncated,
    required this.restoredFrom,
    required this.changeSummary,
    required this.shadows,
    required this.scan,
    required this.createdAt,
    this.diff,
  });

  final String id;

  /// MANUAL | IMPORTED | ROLLBACK | REMOVED | DETECTED | BASELINE
  final String origin;
  final String actor;
  final String contentHash;
  final int generation;
  final int fileCount;

  /// False for a removal, and once the content is older than the newest 30.
  final bool hasSnapshot;

  /// A size cap left something out: the revision cannot be restored.
  final bool truncated;
  final String? restoredFrom;
  final String changeSummary;

  /// The lower-precedence source this skill replaces, when it does.
  final String? shadows;
  final ScanSummary? scan;

  /// Epoch milliseconds.
  final int createdAt;

  /// Unified diff against the parent; only on a single-revision fetch.
  final String? diff;

  factory SkillRevision.fromJson(Map<String, dynamic> j) => SkillRevision(
    id: '${j['id'] ?? ''}',
    origin: '${j['origin'] ?? ''}',
    actor: '${j['actor'] ?? ''}',
    contentHash: '${j['contentHash'] ?? ''}',
    generation: (j['generation'] as num?)?.toInt() ?? 0,
    fileCount: (j['fileCount'] as num?)?.toInt() ?? 0,
    hasSnapshot: j['hasSnapshot'] == true,
    truncated: j['truncated'] == true,
    restoredFrom: j['restoredFrom'] as String?,
    changeSummary: '${j['changeSummary'] ?? ''}',
    shadows: j['shadows'] as String?,
    scan: j['scan'] is Map
        ? ScanSummary.fromJson(Map<String, dynamic>.from(j['scan'] as Map))
        : null,
    createdAt: (j['createdAt'] as num?)?.toInt() ?? 0,
    diff: j['diff'] as String?,
  );

  /// Why this revision cannot be restored, or null when it can.
  String? restoreBlockedReason({
    required bool canRollback,
    required String currentId,
  }) {
    if (id == currentId) return 'This is the current revision.';
    if (origin == 'REMOVED') {
      return 'A removal has no content of its own; pick the revision before it.';
    }
    if (truncated) {
      return 'This revision hit a size cap, so its content is incomplete.';
    }
    if (!hasSnapshot) {
      return 'Its content was dropped: only the newest 30 revisions keep it.';
    }
    if (!canRollback) {
      return 'Only skills in the managed skills directory can be restored.';
    }
    return null;
  }
}

/// The ledger's numbers for one content version of a skill.
class UsageVersion {
  const UsageVersion(this.loads, this.fallbackRate, this.toolFailureRate);
  final int loads;
  final double? fallbackRate;
  final double? toolFailureRate;
}

String pct(double? r) => r == null ? '–' : '${(r * 100).round()}%';

/// Usage numbers keyed by content hash, from `GET /api/skill-usage/summary`,
/// for the skill at `(source, key)`.
Map<String, UsageVersion> usageByHash(
  dynamic summary,
  String source,
  String key,
) {
  final out = <String, UsageVersion>{};
  if (summary is! Map) return out;
  for (final s in (summary['skills'] as List?) ?? const []) {
    if (s is! Map || s['source'] != source || s['key'] != key) continue;
    for (final v in (s['versions'] as List?) ?? const []) {
      if (v is! Map || v['contentHash'] is! String) continue;
      out[v['contentHash'] as String] = UsageVersion(
        (v['loads'] as num?)?.toInt() ?? 0,
        (v['fallbackRate'] as num?)?.toDouble(),
        (v['toolFailureRate'] as num?)?.toDouble(),
      );
    }
  }
  return out;
}

// ── Presentation helpers ────────────────────────────────────────────────────

({String label, String hint, Color color}) originStyle(String origin) {
  switch (origin) {
    case 'MANUAL':
      return (
        label: 'Edited',
        hint:
            'Written through SenClaw: created, overwritten or saved in the editor.',
        color: AppTokens.brand,
      );
    case 'IMPORTED':
      return (
        label: 'Installed',
        hint: 'Installed from ClawHub.',
        color: AppTokens.brandAlt,
      );
    case 'ROLLBACK':
      return (
        label: 'Restored',
        hint: 'Put back to an earlier revision.',
        color: AppTokens.cyan,
      );
    case 'REMOVED':
      return (
        label: 'Removed',
        hint: 'The skill was removed. Its last content is still restorable.',
        color: AppTokens.danger,
      );
    case 'DETECTED':
      return (
        label: 'Changed outside SenClaw',
        hint:
            'Found different on disk: a CLI install, a kit, or a text editor. Also used to keep what was there just before SenClaw overwrote it.',
        color: AppTokens.warning,
      );
    default:
      return (
        label: 'First seen',
        hint:
            'The first time SenClaw saw this skill; nothing earlier is known.',
        color: Colors.grey,
      );
  }
}

String shadowedName(String source) {
  switch (source) {
    case 'bundled':
      return 'the bundled skill';
    case 'global-compat':
    case 'global-sema':
      return 'the global skill';
    default:
      return 'the $source skill';
  }
}

String ago(BuildContext context, int ms, {DateTime? now}) {
  final s = ((now ?? DateTime.now()).millisecondsSinceEpoch - ms) ~/ 1000;
  if (s < 60) return context.tr('just now');
  final m = (s / 60).round();
  if (m < 60) return context.trArgs('{n} min ago', {'n': m});
  final h = (m / 60).round();
  if (h < 48) return context.trArgs('{n} h ago', {'n': h});
  return context.trArgs('{n} days ago', {'n': (h / 24).round()});
}

/// Added / removed / hunk / header lines of a unified diff, for tinting.
enum DiffLineKind { added, removed, hunk, header, context }

DiffLineKind diffLineKind(String line) {
  if (line.startsWith('+++') || line.startsWith('---')) {
    return DiffLineKind.header;
  }
  if (line.startsWith('+')) return DiffLineKind.added;
  if (line.startsWith('-')) return DiffLineKind.removed;
  if (line.startsWith('@@')) return DiffLineKind.hunk;
  return DiffLineKind.context;
}

// ── Dialog ──────────────────────────────────────────────────────────────────

/// Open the history of the skill `name` living in `source`. [canRollback] is
/// true only for skills in the managed directory. [onRestored] runs after a
/// successful restore so the caller can refresh its skill list.
Future<void> showSkillHistory(
  BuildContext context, {
  required String name,
  required String source,
  required bool canRollback,
  VoidCallback? onRestored,
}) => showDialog<void>(
  context: context,
  builder: (_) => SkillHistoryDialog(
    name: name,
    source: source,
    canRollback: canRollback,
    onRestored: onRestored,
  ),
);

class SkillHistoryDialog extends ConsumerStatefulWidget {
  const SkillHistoryDialog({
    super.key,
    required this.name,
    required this.source,
    required this.canRollback,
    this.onRestored,
  });
  final String name;
  final String source;
  final bool canRollback;
  final VoidCallback? onRestored;

  @override
  ConsumerState<SkillHistoryDialog> createState() => _SkillHistoryDialogState();
}

class _SkillHistoryDialogState extends ConsumerState<SkillHistoryDialog> {
  List<SkillRevision>? _revisions;
  String _key = '';
  String _source = '';
  String? _error;
  String? _selectedId;
  SkillRevision? _detail;
  Map<String, UsageVersion> _usage = const {};
  bool _restoring = false;

  String get _base => '/api/skills/${Uri.encodeComponent(widget.name)}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = ref.read(apiClientProvider);
    try {
      final h = await api.get(
        '$_base/history',
        query: {'source': widget.source},
      );
      final list = ((h['revisions'] as List?) ?? const [])
          .whereType<Map>()
          .map((r) => SkillRevision.fromJson(Map<String, dynamic>.from(r)))
          .toList();
      if (!mounted) return;
      _key = '${h['key'] ?? widget.name}';
      _source = '${h['source'] ?? widget.source}';
      setState(() {
        _revisions = list;
        _error = null;
        if (_selectedId == null || !list.any((r) => r.id == _selectedId)) {
          _selectedId = list.isEmpty ? null : list.first.id;
        }
      });
      _loadDetail();
      // The numbers are optional: a daemon without the ledger just shows none.
      try {
        final u = await api.get(
          '/api/skill-usage/summary',
          query: {'days': 30},
        );
        if (mounted) setState(() => _usage = usageByHash(u, _source, _key));
      } catch (_) {}
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _revisions = const [];
        _error = e is ApiException ? e.message : '$e';
      });
    }
  }

  Future<void> _loadDetail() async {
    final id = _selectedId;
    if (id == null) {
      setState(() => _detail = null);
      return;
    }
    setState(() => _detail = null);
    try {
      final r = await ref
          .read(apiClientProvider)
          .get(
            '$_base/history/${Uri.encodeComponent(id)}',
            query: {'source': widget.source},
          );
      if (!mounted || _selectedId != id) return;
      setState(
        () => _detail = SkillRevision.fromJson(
          Map<String, dynamic>.from(r['revision'] as Map),
        ),
      );
    } catch (_) {
      if (mounted && _selectedId == id) setState(() => _detail = null);
    }
  }

  Future<void> _restore(SkillRevision rev) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('Restore this revision?')),
        content: Text(
          ctx.tr(
            "The skill's files are put back as they were. The current content stays in the history.",
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(ctx.tr('Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(ctx.tr('Restore')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _restoring = true);
    // Read before the await: a context is not used across an async gap.
    final messenger = ScaffoldMessenger.maybeOf(context);
    final restored = context.tr('Skill restored');
    final failed = context.tr('Could not restore this revision');
    try {
      await ref
          .read(apiClientProvider)
          .post('$_base/rollback/${Uri.encodeComponent(rev.id)}');
      messenger?.showSnackBar(SnackBar(content: Text(restored)));
      widget.onRestored?.call();
      if (mounted) {
        _selectedId = null;
        await _load();
      }
    } catch (e) {
      messenger?.showSnackBar(
        SnackBar(content: Text(e is ApiException ? e.message : failed)),
      );
    } finally {
      if (mounted) setState(() => _restoring = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Dialog(
      backgroundColor: c.surface,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 920, maxHeight: 620),
        child: Padding(
          padding: const EdgeInsets.all(AppTokens.s20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${context.tr('History')} · ${widget.name}',
                      style: TextStyle(
                        color: c.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(context.tr('Close')),
                  ),
                ],
              ),
              const SizedBox(height: AppTokens.s8),
              Expanded(child: _body(context)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    final c = context.colors;
    final revs = _revisions;
    if (revs == null) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Text(
          '${context.tr('Could not load the history')}: $_error',
          style: const TextStyle(color: AppTokens.danger),
        ),
      );
    }
    if (revs.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppTokens.s24),
          child: Text(
            context.tr(
              "No history yet. A skill's history starts the first time it is changed through SenClaw or seen by the daemon.",
            ),
            textAlign: TextAlign.center,
            style: TextStyle(color: c.textMuted),
          ),
        ),
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 310,
          child: ListView.builder(
            itemCount: revs.length,
            itemBuilder: (_, i) => _RevisionTile(
              rev: revs[i],
              current: i == 0,
              selected: revs[i].id == _selectedId,
              usage: _usage[revs[i].contentHash],
              onTap: () {
                if (revs[i].id == _selectedId) return;
                setState(() => _selectedId = revs[i].id);
                _loadDetail();
              },
            ),
          ),
        ),
        VerticalDivider(width: AppTokens.s20, color: c.border),
        Expanded(child: _detailPane(context, revs)),
      ],
    );
  }

  Widget _detailPane(BuildContext context, List<SkillRevision> revs) {
    final c = context.colors;
    final rev =
        _detail ??
        revs.cast<SkillRevision?>().firstWhere(
          (r) => r!.id == _selectedId,
          orElse: () => null,
        );
    if (rev == null) return const Center(child: CircularProgressIndicator());
    final why = rev.restoreBlockedReason(
      canRollback: widget.canRollback,
      currentId: revs.first.id,
    );
    final style = originStyle(rev.origin);
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                context.tr(style.label),
                style: TextStyle(
                  color: c.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: AppTokens.s8),
              Expanded(
                child: Text(
                  '${DateTime.fromMillisecondsSinceEpoch(rev.createdAt).toLocal().toString().split('.').first} · ${context.tr('generation')} ${rev.generation} · ${context.trPlural(rev.fileCount, '{n} file', '{n} files')}',
                  style: TextStyle(color: c.textMuted, fontSize: 12),
                ),
              ),
              Tooltip(
                message: why == null ? '' : context.tr(why),
                child: OutlinedButton.icon(
                  key: const ValueKey('skill-history-restore'),
                  onPressed: why == null && !_restoring
                      ? () => _restore(rev)
                      : null,
                  icon: const Icon(Icons.restore, size: 14),
                  label: Text(context.tr('Restore')),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          SelectableText(
            '${rev.id} · sha256 ${rev.contentHash.length >= 12 ? rev.contentHash.substring(0, 12) : rev.contentHash} · ${rev.actor}${rev.restoredFrom != null ? ' · ${context.tr('restored from')} ${rev.restoredFrom}' : ''}',
            style: TextStyle(
              color: c.textMuted,
              fontSize: 11,
              fontFamily: AppTokens.fontMono,
            ),
          ),
          if (rev.shadows != null) ...[
            const SizedBox(height: AppTokens.s12),
            _Note(
              color: AppTokens.cyan,
              title: context.trArgs(
                'This skill replaces {what} with the same name.',
                {'what': context.tr(shadowedName(rev.shadows!))},
              ),
              body: context.tr(
                'Skills in the managed directory take precedence over bundled ones; the other one is hidden while this exists.',
              ),
            ),
          ],
          if (rev.scan != null && rev.scan!.findings.isNotEmpty) ...[
            const SizedBox(height: AppTokens.s12),
            _ScanFindings(scan: rev.scan!),
          ],
          const SizedBox(height: AppTokens.s12),
          Text(
            context.tr('CHANGE'),
            style: TextStyle(
              color: c.textMuted,
              fontSize: 11,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 6),
          if (rev.diff == null)
            const Padding(
              padding: EdgeInsets.all(8),
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            DiffView(diff: rev.diff!),
        ],
      ),
    );
  }
}

class _RevisionTile extends StatelessWidget {
  const _RevisionTile({
    required this.rev,
    required this.current,
    required this.selected,
    required this.usage,
    required this.onTap,
  });
  final SkillRevision rev;
  final bool current;
  final bool selected;
  final UsageVersion? usage;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final style = originStyle(rev.origin);
    final warn = rev.scan != null && rev.scan!.verdict != 'allow';
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppTokens.s12,
          vertical: AppTokens.s8,
        ),
        decoration: BoxDecoration(
          color: selected ? c.accentSoft : null,
          border: Border(bottom: BorderSide(color: c.border)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                Tooltip(
                  message: context.tr(style.hint),
                  child: _Chip(context.tr(style.label), style.color),
                ),
                if (current) _Chip(context.tr('current'), AppTokens.success),
                if (warn)
                  _Chip(
                    context.trArgs('scan: {n}', {
                      'n': rev.scan!.findings.length,
                    }),
                    rev.scan!.verdict == 'block'
                        ? AppTokens.danger
                        : AppTokens.warning,
                  ),
                if (rev.shadows != null)
                  _Chip(
                    context.trArgs('overrides {what}', {
                      'what': context.tr(shadowedName(rev.shadows!)),
                    }),
                    AppTokens.warning,
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              rev.changeSummary.isEmpty ? '—' : rev.changeSummary,
              style: TextStyle(color: c.textPrimary, fontSize: 12),
            ),
            Text(
              '${ago(context, rev.createdAt)} · ${rev.actor}',
              style: TextStyle(color: c.textMuted, fontSize: 11),
            ),
            if (usage != null)
              Text(
                context.trArgs('{n} loads · fallback {f} · tool failures {t}', {
                  'n': usage!.loads,
                  'f': pct(usage!.fallbackRate),
                  't': pct(usage!.toolFailureRate),
                }),
                style: TextStyle(color: c.textMuted, fontSize: 11),
              ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.text, this.color);
  final String text;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.16),
      borderRadius: BorderRadius.circular(AppTokens.rSm),
    ),
    child: Text(text, style: TextStyle(color: color, fontSize: 11)),
  );
}

class _Note extends StatelessWidget {
  const _Note({required this.color, required this.title, this.body});
  final Color color;
  final String title;
  final String? body;
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(AppTokens.s12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        border: Border.all(color: color.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(AppTokens.rMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: c.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (body != null)
            Text(body!, style: TextStyle(color: c.textMuted, fontSize: 12)),
        ],
      ),
    );
  }
}

class _ScanFindings extends StatelessWidget {
  const _ScanFindings({required this.scan});
  final ScanSummary scan;
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final color = scan.verdict == 'block'
        ? AppTokens.danger
        : AppTokens.warning;
    return Container(
      padding: const EdgeInsets.all(AppTokens.s12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        border: Border.all(color: color.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(AppTokens.rMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.trArgs('Security scan: {n} findings (risk {r}/100)', {
              'n': scan.findings.length,
              'r': scan.riskScore,
            }),
            style: TextStyle(
              color: c.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          for (final f in scan.findings)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: SelectableText(
                '${f.rule}  ${f.severity} — ${f.title} (${f.file}${f.line != null ? ':${f.line}' : ''})',
                style: TextStyle(
                  color: c.textSecondary,
                  fontSize: 11,
                  fontFamily: AppTokens.fontMono,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A unified diff with the added and removed lines tinted.
class DiffView extends StatelessWidget {
  const DiffView({super.key, required this.diff});
  final String diff;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (diff.trim().isEmpty) {
      return Text(
        context.tr('No content difference from the previous revision.'),
        style: TextStyle(color: c.textMuted, fontSize: 12),
      );
    }
    final lines = diff.trimRight().split('\n');
    return Container(
      constraints: const BoxConstraints(maxHeight: 360),
      decoration: BoxDecoration(
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(AppTokens.rMd),
      ),
      child: SingleChildScrollView(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [for (final line in lines) _diffLine(c, line)],
          ),
        ),
      ),
    );
  }

  Widget _diffLine(dynamic c, String line) {
    final kind = diffLineKind(line);
    final (bg, fg, weight) = switch (kind) {
      DiffLineKind.added => (
        AppTokens.success.withValues(alpha: 0.16),
        AppTokens.success,
        FontWeight.w400,
      ),
      DiffLineKind.removed => (
        AppTokens.danger.withValues(alpha: 0.16),
        AppTokens.danger,
        FontWeight.w400,
      ),
      DiffLineKind.hunk => (
        AppTokens.brand.withValues(alpha: 0.14),
        AppTokens.brand,
        FontWeight.w400,
      ),
      DiffLineKind.header => (
        Colors.transparent,
        c.textPrimary as Color,
        FontWeight.w700,
      ),
      DiffLineKind.context => (
        Colors.transparent,
        c.textSecondary as Color,
        FontWeight.w400,
      ),
    };
    return Container(
      color: bg,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Text(
        line.isEmpty ? ' ' : line,
        softWrap: false,
        style: TextStyle(
          color: fg,
          fontWeight: weight,
          fontSize: 12,
          height: 1.5,
          fontFamily: AppTokens.fontMono,
        ),
      ),
    );
  }
}
