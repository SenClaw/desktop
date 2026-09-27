// The tool-call gate card of Settings → Decision (Laya): before an agent's
// shell command prompts, the decision engine is asked what it does, and a
// confident "only reads / tests / edits" approves it once. Mirrors
// `web/src/components/settings/DecisionGateCard.tsx`; the daemon side is
// `src/decision/gate/`.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/l10n.dart';
import '../../core/transport/api_client.dart' show ApiException;
import '../../core/transport/connection.dart';
import '../../theme/tokens.dart';
import 'decision_widgets.dart';

double? _num(Object? v) => v is num ? v.toDouble() : null;
int _int(Object? v) => v is num ? v.toInt() : 0;

class GateSettings {
  const GateSettings({this.mode = 'off', this.approveAt = 0.9, this.questions = 'auto'});

  /// `off`, `shadow` or `on`.
  final String mode;
  final double approveAt;

  /// `auto`, `laya` or `cookbook`.
  final String questions;

  GateSettings copyWith({String? mode, double? approveAt, String? questions}) => GateSettings(
        mode: mode ?? this.mode,
        approveAt: approveAt ?? this.approveAt,
        questions: questions ?? this.questions,
      );

  factory GateSettings.fromJson(Map<String, dynamic> j) => GateSettings(
        mode: '${j['mode'] ?? 'off'}',
        approveAt: _num(j['approveAt']) ?? 0.9,
        questions: '${j['questions'] ?? 'auto'}',
      );

  Map<String, dynamic> toJson() => {'mode': mode, 'approveAt': approveAt, 'questions': questions};

  @override
  bool operator ==(Object other) =>
      other is GateSettings && other.mode == mode && other.approveAt == approveAt && other.questions == questions;

  @override
  int get hashCode => Object.hash(mode, approveAt, questions);
}

/// One row of the gate's audit log.
class GateLogRow {
  const GateLogRow(this.j);
  final Map<String, dynamic> j;

  int get id => _int(j['id']);
  DateTime get at => DateTime.fromMillisecondsSinceEpoch(_int(j['at']));
  String get command => '${j['command'] ?? ''}';
  String get outcome => '${j['outcome'] ?? 'ask'}';
  String get stage => '${j['stage'] ?? 'engine'}';
  bool get applied => j['applied'] == true;
  String get reason => '${j['reason'] ?? ''}';
  double? get p => _num(j['p']);
  String? get human => j['human'] is String ? j['human'] as String : null;
}

/// `GET /api/decision/gate`.
class GateView {
  const GateView(this.j);
  final Map<String, dynamic> j;

  GateSettings get gate =>
      j['gate'] is Map ? GateSettings.fromJson((j['gate'] as Map).cast<String, dynamic>()) : const GateSettings();
  String get questionSet => '${j['questionSet'] ?? 'laya'}';
  int get timeoutSecs => _int(j['timeoutSecs']);
  List<String> get samples => [for (final s in (j['samples'] as List? ?? const [])) '$s'];
  Map<String, dynamic> get stats =>
      j['stats'] is Map ? (j['stats'] as Map).cast<String, dynamic>() : const <String, dynamic>{};
  List<GateLogRow> get log => [
        for (final r in (j['log'] as List? ?? const []))
          if (r is Map) GateLogRow(r.cast<String, dynamic>())
      ];
}

/// One judgment from `POST /api/decision/gate/check`.
class GateVerdict {
  const GateVerdict(this.j);
  final Map<String, dynamic> j;

  String get command => '${j['command'] ?? ''}';
  String get outcome => '${j['outcome'] ?? 'ask'}';
  String get stage => '${j['stage'] ?? 'engine'}';
  String get reason => '${j['reason'] ?? ''}';
  String? get choice => j['choice'] is String ? j['choice'] as String : null;
  double? get p => j['checks'] is List && (j['checks'] as List).isNotEmpty && (j['checks'] as List).first is Map
      ? _num(((j['checks'] as List).first as Map)['p'])
      : null;
  double? get latencyMs => _num(j['latencyMs']);
  String? get model => j['model'] is String ? j['model'] as String : null;
}

final decisionGateProvider = FutureProvider<GateView>((ref) async {
  final r = await ref.read(apiClientProvider).get('/api/decision/gate', query: {'limit': '30'});
  return GateView((r as Map).cast<String, dynamic>());
});

/// The verdict as a chip: approve, ask, risk list or engine error.
class GateVerdictChip extends StatelessWidget {
  const GateVerdictChip({super.key, required this.outcome, required this.stage, this.applied = false});
  final String outcome;
  final String stage;
  final bool applied;

  @override
  Widget build(BuildContext context) {
    return switch (stage) {
      'risky' => DecisionChip(context.tr('danger list'), color: AppTokens.danger),
      'error' => DecisionChip(context.tr('error → ask'), color: AppTokens.warning),
      _ => outcome == 'allow'
          ? DecisionChip(applied ? context.tr('ran without asking') : context.tr('would run'), color: AppTokens.success)
          : DecisionChip(context.tr('asks you')),
    };
  }
}

class DecisionGateCard extends ConsumerStatefulWidget {
  const DecisionGateCard({super.key});

  @override
  ConsumerState<DecisionGateCard> createState() => _DecisionGateCardState();
}

class _DecisionGateCardState extends ConsumerState<DecisionGateCard> {
  GateSettings? _draft;
  bool _saving = false;
  bool _checking = false;
  final _command = TextEditingController(text: 'bun test src/utils/date.test.ts');
  final _approveAt = TextEditingController();
  GateVerdict? _verdict;
  List<GateVerdict>? _samples;
  String? _error;

  @override
  void dispose() {
    _command.dispose();
    _approveAt.dispose();
    super.dispose();
  }

  void _toast(String msg) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final r = await ref.read(apiClientProvider).put('/api/decision/gate', body: _draft!.toJson());
      if (!mounted) return;
      final v = GateView((r as Map).cast<String, dynamic>());
      setState(() {
        _draft = v.gate;
        _approveAt.text = '${v.gate.approveAt}';
      });
      ref.invalidate(decisionGateProvider);
      _toast(context.tr('Saved the tool-call gate'));
    } on ApiException catch (e) {
      _toast(e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<List<GateVerdict>?> _check(List<String> commands) async {
    setState(() {
      _checking = true;
      _error = null;
    });
    try {
      final r = await ref.read(apiClientProvider).post('/api/decision/gate/check', body: {
        'commands': commands,
        'approveAt': _draft!.approveAt,
        'questions': _draft!.questions,
      });
      final list = (r as Map)['verdicts'] as List? ?? const [];
      return [
        for (final v in list)
          if (v is Map) GateVerdict(v.cast<String, dynamic>())
      ];
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
      return null;
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  String _modeHelp(BuildContext context, String mode) => switch (mode) {
        'shadow' => context.tr(
            'Asks the decision engine and records what it would do, but still shows the prompt — to compare it with your answers before trusting it.'),
        'on' => context.tr(
            'A command scored as surely reading, testing or editing (at or above the threshold) runs once without a prompt. Every other command still asks.'),
        _ => context.tr('The decision engine is not asked; every command that needs approval prompts as before.'),
      };

  Widget _stats(BuildContext context, Map<String, dynamic> s) {
    final c = context.colors;
    final small = TextStyle(color: c.textSecondary, fontSize: 12.5);
    final refused = _int(s['allowRefused']);
    return Wrap(spacing: AppTokens.s16, runSpacing: 4, children: [
      Text(context.trArgs('Judged {n}', {'n': _int(s['total'])}), style: small),
      Text(context.trArgs('would run {n}', {'n': _int(s['wouldAllow'])}), style: small),
      Text(context.trArgs('prompts skipped {n}', {'n': _int(s['applied'])}), style: small),
      Text(context.trArgs('danger list {n}', {'n': _int(s['risky'])}), style: small),
      Text(context.trArgs('errors {n}', {'n': _int(s['errors'])}), style: small),
      Tooltip(
        message: context.tr('Of the commands the gate would have run while the prompt still showed, how you answered.'),
        child: Text(
          context.trArgs('gate runs / you approved {a} · you refused {r}', {'a': _int(s['allowAgreed']), 'r': refused}),
          style: small.copyWith(color: refused > 0 ? AppTokens.danger : null),
        ),
      ),
    ]);
  }

  Widget _logRow(BuildContext context, GateLogRow r) {
    final c = context.colors;
    final human = switch (r.human) {
      'agree' || 'allow' => DecisionChip(context.tr('you approved'), color: AppTokens.success),
      'refuse' => DecisionChip(context.tr('you refused'), color: AppTokens.danger),
      null => const SizedBox.shrink(),
      _ => DecisionChip(context.tr('other answer')),
    };
    final t = r.at;
    final when = '${t.day}/${t.month} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        SizedBox(width: 90, child: Text(when, style: TextStyle(color: c.textMuted, fontSize: 12))),
        Expanded(
          child: Tooltip(
            message: r.reason,
            child: Text(r.command,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontFamily: 'monospace', fontSize: 12.5, color: c.textPrimary)),
          ),
        ),
        const SizedBox(width: AppTokens.s8),
        GateVerdictChip(outcome: r.outcome, stage: r.stage, applied: r.applied),
        if (r.p != null) ...[
          const SizedBox(width: AppTokens.s6),
          Text(decisionNum(context, r.p!), style: TextStyle(color: c.textMuted, fontSize: 12)),
        ],
        const SizedBox(width: AppTokens.s8),
        human,
      ]),
    );
  }

  Widget _verdictView(BuildContext context, GateVerdict v) {
    final c = context.colors;
    return Container(
      margin: const EdgeInsets.only(top: AppTokens.s12),
      padding: const EdgeInsets.all(AppTokens.s12),
      decoration: BoxDecoration(
        color: c.bg,
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(AppTokens.rMd),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: AppTokens.s8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
          GateVerdictChip(outcome: v.outcome, stage: v.stage),
          if (v.choice != null) DecisionChip(v.choice!, color: AppTokens.brand),
          if (v.p != null) Text('reversible = ${decisionNum(context, v.p!)}', style: TextStyle(color: c.textPrimary)),
          if (v.latencyMs != null)
            Text('${decisionNum(context, v.latencyMs!, 1)} ms', style: TextStyle(color: c.textMuted, fontSize: 12)),
          if (v.model != null) Text(v.model!, style: TextStyle(color: c.textMuted, fontSize: 12)),
        ]),
        const SizedBox(height: AppTokens.s6),
        SelectableText(v.reason, style: TextStyle(color: c.textSecondary, fontSize: 12.5)),
        if (v.j['state'] != null)
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text(context.tr('Request and answer (JSON)'), style: const TextStyle(fontSize: 12.5)),
            children: [
              SelectableText(
                const JsonEncoder.withIndent('  ')
                    .convert({'state': v.j['state'], 'questions': v.j['asked'], 'answers': v.j['answers']}),
                style: TextStyle(fontFamily: 'monospace', fontSize: 11.5, color: c.textSecondary),
              ),
            ],
          ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final async = ref.watch(decisionGateProvider);
    final view = async.valueOrNull;
    if (view == null) {
      return decisionCard(
        context,
        title: context.tr('Tool-call gate'),
        icon: Icons.shield_outlined,
        child: async.hasError
            ? decisionNotice(context, '${async.error}', tone: AppTokens.danger)
            : const LinearProgressIndicator(),
      );
    }
    if (_draft == null) {
      _draft = view.gate;
      _approveAt.text = '${view.gate.approveAt}';
    }
    final draft = _draft!;
    final dirty = draft != view.gate;
    final effective = draft.questions == 'auto' ? view.questionSet : draft.questions;
    final stats = view.stats;
    final small = TextStyle(color: c.textMuted, fontSize: 12);

    return decisionCard(
      context,
      title: context.tr('Tool-call gate — agent shell commands'),
      icon: Icons.shield_outlined,
      trailing: FilledButton.icon(
        onPressed: dirty && !_saving ? _save : null,
        icon: const Icon(Icons.save_outlined, size: 16),
        label: Text(context.tr('Save')),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
          context.trArgs(
              'Before an agent asks you to approve a Bash command, the decision engine above (Laya on this machine or Jev online) is asked what the command does. Commands on the danger list (sudo, rm -rf, git push, deploys, secret files, command substitution…) are never sent and always ask — the list, not the threshold, is the safety boundary. The gate can only save a prompt, never refuse; an error or more than {s} s still asks.',
              {'s': view.timeoutSecs}),
          style: small,
        ),
        const SizedBox(height: AppTokens.s12),
        Wrap(spacing: AppTokens.s24, runSpacing: AppTokens.s12, crossAxisAlignment: WrapCrossAlignment.end, children: [
          SegmentedButton<String>(
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            segments: [
              ButtonSegment(value: 'off', label: Text(context.tr('Off'))),
              ButtonSegment(value: 'shadow', label: Text(context.tr('Shadow'))),
              ButtonSegment(value: 'on', label: Text(context.tr('On'))),
            ],
            selected: {draft.mode},
            onSelectionChanged: (s) => setState(() => _draft = draft.copyWith(mode: s.first)),
          ),
          SizedBox(
            width: 140,
            child: TextField(
              controller: _approveAt,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
              decoration: InputDecoration(isDense: true, labelText: context.tr('Threshold to run')),
              onChanged: (v) {
                final n = double.tryParse(v.replaceAll(',', '.'));
                if (n != null) setState(() => _draft = draft.copyWith(approveAt: n.clamp(0.5, 0.99).toDouble()));
              },
            ),
          ),
          SizedBox(
            width: 340,
            child: DropdownButtonFormField<String>(
              key: ValueKey('questions-${draft.questions}-${view.questionSet}'),
              initialValue: draft.questions,
              isExpanded: true,
              decoration: InputDecoration(isDense: true, labelText: context.tr('Questions')),
              items: [
                DropdownMenuItem(
                  value: 'auto',
                  child: Text(context.trArgs('By backend (now: {set})', {'set': view.questionSet == 'laya' ? 'Laya' : 'Cookbook'}),
                      overflow: TextOverflow.ellipsis),
                ),
                DropdownMenuItem(value: 'laya', child: Text(context.tr('Laya: what does this command do (one choice of 8)'))),
                DropdownMenuItem(value: 'cookbook', child: Text(context.tr('Cookbook: the reversible yes/no question (suits Jev)'))),
              ],
              onChanged: (v) => setState(() => _draft = draft.copyWith(questions: v ?? 'auto')),
            ),
          ),
        ]),
        const SizedBox(height: AppTokens.s8),
        Text(
          '${_modeHelp(context, draft.mode)} ${effective == 'laya' ? context.tr('Laya: P(can be undone) = P(read) + P(run tests) + P(edit files in the project).') : context.tr('Cookbook: P(true) of "only reads or changes files in the project and can be undone". Laya on this machine answers it very poorly — it suits Jev online.')}',
          style: small,
        ),
        if (_int(stats['total']) > 0) ...[
          const SizedBox(height: AppTokens.s12),
          _stats(context, stats),
        ],
        if (_int(stats['allowRefused']) > 0) ...[
          const SizedBox(height: AppTokens.s8),
          decisionNotice(
            context,
            context.trArgs(
                '{n} command(s) the gate would have run were refused by you — review them before turning it on, or raise the threshold.',
                {'n': _int(stats['allowRefused'])}),
            tone: AppTokens.danger,
          ),
        ],
        const SizedBox(height: AppTokens.s12),
        if (view.log.isEmpty)
          Text(context.tr('No command has gone through the gate yet — turn on Shadow to start recording.'), style: small)
        else
          for (final r in view.log) _logRow(context, r),
        const SizedBox(height: AppTokens.s16),
        Text(context.tr('Try a command'), style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.w600)),
        const SizedBox(height: AppTokens.s6),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _command,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              decoration: const InputDecoration(isDense: true),
              onSubmitted: (_) async {
                final v = await _check([_command.text]);
                if (v != null && v.isNotEmpty && mounted) setState(() => _verdict = v.first);
              },
            ),
          ),
          const SizedBox(width: AppTokens.s8),
          OutlinedButton(
            onPressed: _checking
                ? null
                : () async {
                    final v = await _check([_command.text]);
                    if (v != null && v.isNotEmpty && mounted) setState(() => _verdict = v.first);
                  },
            child: Text(context.tr('Check')),
          ),
          const SizedBox(width: AppTokens.s8),
          OutlinedButton(
            onPressed: _checking
                ? null
                : () async {
                    final v = await _check(view.samples);
                    if (v != null && mounted) setState(() => _samples = v);
                  },
            child: Text(context.trArgs('Run the {n} sample commands', {'n': view.samples.length})),
          ),
        ]),
        const SizedBox(height: AppTokens.s4),
        Text(context.tr('Uses the threshold and questions as edited (no need to Save); nothing is logged and nobody is asked.'),
            style: small),
        if (_checking) const Padding(padding: EdgeInsets.only(top: AppTokens.s8), child: LinearProgressIndicator()),
        if (_error != null) ...[
          const SizedBox(height: AppTokens.s8),
          decisionNotice(context, _error!, tone: AppTokens.danger),
        ],
        if (_verdict != null) _verdictView(context, _verdict!),
        if (_samples != null) ...[
          const SizedBox(height: AppTokens.s12),
          for (final v in _samples!)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(children: [
                Expanded(
                  child: Text(v.command,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontFamily: 'monospace', fontSize: 12.5, color: c.textPrimary)),
                ),
                const SizedBox(width: AppTokens.s8),
                GateVerdictChip(outcome: v.outcome, stage: v.stage),
                if (v.choice != null) ...[
                  const SizedBox(width: AppTokens.s6),
                  DecisionChip(v.choice!, color: AppTokens.brand),
                ],
                if (v.p != null) ...[
                  const SizedBox(width: AppTokens.s6),
                  Text(decisionNum(context, v.p!), style: TextStyle(color: c.textMuted, fontSize: 12)),
                ],
              ]),
            ),
          const SizedBox(height: AppTokens.s6),
          Text(
            context.trArgs('{a} would run · {r} held by the danger list · {e} errors', {
              'a': _samples!.where((v) => v.outcome == 'allow').length,
              'r': _samples!.where((v) => v.stage == 'risky').length,
              'e': _samples!.where((v) => v.stage == 'error').length,
            }),
            style: small,
          ),
        ],
      ]),
    );
  }
}
