// The pre-turn skill router card of Settings → Decision (Laya): which skill a
// request should run with, read from each skill's triggers and the examples in
// its description, loaded outright only when the decision engine co-signs.
// Mirrors `web/src/components/settings/DecisionSkillsCard.tsx`; the daemon side
// is `src/decision/skill_route.rs`.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/l10n.dart';
import '../../core/transport/api_client.dart' show ApiException;
import '../../core/transport/connection.dart';
import '../../theme/tokens.dart';
import 'decision_widgets.dart';

int _int(Object? v) => v is num ? v.toInt() : 0;
double? _num(Object? v) => v is num ? v.toDouble() : null;
String? _str(Object? v) => v is String && v.isNotEmpty ? v : null;

/// `GET /api/decision/skills`.
class SkillsView {
  const SkillsView(this.j);
  final Map<String, dynamic> j;

  String get mode => j['skills'] is Map ? '${(j['skills'] as Map)['mode'] ?? 'off'}' : 'off';
  bool get preTriggerSkill => j['preTriggerSkill'] == true;
  int get timeoutMs => _int(j['timeoutMs']);
  int get candidates => _int(j['candidates']);
  Map<String, dynamic> get stats =>
      j['stats'] is Map ? (j['stats'] as Map).cast<String, dynamic>() : const <String, dynamic>{};
  List<Map<String, dynamic>> get log => [
        for (final r in (j['log'] as List? ?? const []))
          if (r is Map) r.cast<String, dynamic>()
      ];
}

final decisionSkillsProvider = FutureProvider<SkillsView>((ref) async {
  final r = await ref.read(apiClientProvider).get('/api/decision/skills', query: {'limit': '30'});
  return SkillsView((r as Map).cast<String, dynamic>());
});

/// A routing decision as a chip: load, hint, or nothing.
class RouteChip extends StatelessWidget {
  const RouteChip({super.key, required this.name, required this.force});
  final String? name;
  final bool force;

  @override
  Widget build(BuildContext context) {
    if (name == null) return Text('—', style: TextStyle(color: context.colors.textMuted));
    return DecisionChip(
      '${force ? context.tr('load') : context.tr('hint')} · $name',
      color: force ? AppTokens.success : null,
    );
  }
}

class DecisionSkillsCard extends ConsumerStatefulWidget {
  const DecisionSkillsCard({super.key});

  @override
  ConsumerState<DecisionSkillsCard> createState() => _DecisionSkillsCardState();
}

class _DecisionSkillsCardState extends ConsumerState<DecisionSkillsCard> {
  String? _mode;
  bool _saving = false;
  bool _checking = false;
  final _prompt = TextEditingController(text: 'đặt hẹn giờ 10 phút giúp tôi');
  Map<String, dynamic>? _report;
  String? _error;

  @override
  void dispose() {
    _prompt.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final r = await ref.read(apiClientProvider).put('/api/decision/skills', body: {'mode': _mode});
      if (!mounted) return;
      setState(() => _mode = SkillsView((r as Map).cast<String, dynamic>()).mode);
      ref.invalidate(decisionSkillsProvider);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(context.tr('Saved the skill routing mode'))));
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _check() async {
    setState(() {
      _checking = true;
      _error = null;
    });
    try {
      final r = await ref.read(apiClientProvider).post('/api/decision/skills/check', body: {'prompt': _prompt.text});
      if (mounted) setState(() => _report = (r as Map).cast<String, dynamic>());
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  String _modeHelp(BuildContext context, String mode, int timeoutMs) => switch (mode) {
        'shadow' => context.tr(
            'The old way still decides; the new one runs in the background and is recorded to compare — no turn is slowed.'),
        'on' => context.trArgs(
            'The new way decides (waits for the decision engine at most {ms} ms; past that it loads only on a whole trigger match).',
            {'ms': timeoutMs}),
        _ => context.tr('The old way, nothing recorded.'),
      };

  Widget _engineText(BuildContext context, Map<String, dynamic> r) {
    final c = context.colors;
    final fallback = _str(r['fallback']);
    if (fallback != null) {
      return Tooltip(message: fallback, child: DecisionChip(context.tr('no answer'), color: AppTokens.warning));
    }
    final p = _num(r['engineP']);
    return Text('${_str(r['enginePick']) ?? 'none'}${p != null ? ' ${decisionNum(context, p)}' : ''}',
        style: TextStyle(color: c.textMuted, fontSize: 12));
  }

  Widget _logRow(BuildContext context, Map<String, dynamic> r) {
    final c = context.colors;
    final t = DateTime.fromMillisecondsSinceEpoch(_int(r['at']));
    final when = '${t.day}/${t.month} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        SizedBox(width: 90, child: Text(when, style: TextStyle(color: c.textMuted, fontSize: 12))),
        Expanded(
          child: Tooltip(
            message: '${r['reason'] ?? ''}',
            child: Text('${r['prompt'] ?? ''}',
                maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: c.textPrimary, fontSize: 12.5)),
          ),
        ),
        const SizedBox(width: AppTokens.s8),
        RouteChip(name: _str(r['legacyName']), force: r['legacyForce'] == true),
        const SizedBox(width: AppTokens.s6),
        const Icon(Icons.arrow_forward, size: 12),
        const SizedBox(width: AppTokens.s6),
        RouteChip(name: _str(r['routeName']), force: r['routeForce'] == true),
        const SizedBox(width: AppTokens.s8),
        _engineText(context, r),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final async = ref.watch(decisionSkillsProvider);
    final view = async.valueOrNull;
    if (view == null) {
      return decisionCard(
        context,
        title: context.tr('Skill before the turn'),
        icon: Icons.track_changes,
        child: async.hasError
            ? decisionNotice(context, '${async.error}', tone: AppTokens.danger)
            : const LinearProgressIndicator(),
      );
    }
    final mode = _mode ??= view.mode;
    final s = view.stats;
    final small = TextStyle(color: c.textMuted, fontSize: 12);
    final report = _report;

    return decisionCard(
      context,
      title: context.tr('Skill before the turn (pre-skill)'),
      icon: Icons.track_changes,
      trailing: FilledButton.icon(
        onPressed: mode != view.mode && !_saving ? _save : null,
        icon: const Icon(Icons.save_outlined, size: 16),
        label: Text(context.tr('Save')),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
          context.trArgs(
              'Before each chat turn SenClaw guesses which skill fits the request. The old way reads only triggers and when-to-use; the new way also reads the quoted examples in each description, then asks the decision engine (Laya / Jev) to choose among {n} candidates. A skill is loaded outright only when the keywords and the decision engine agree, or a whole trigger matched and the choice is in the top three; otherwise it is only hinted. On 32 real requests with 224 skills: the old way loaded a wrong skill 10 times, the new way 2.',
              {'n': view.candidates}),
          style: small,
        ),
        const SizedBox(height: AppTokens.s12),
        SegmentedButton<String>(
          style: const ButtonStyle(visualDensity: VisualDensity.compact),
          segments: [
            ButtonSegment(value: 'off', label: Text(context.tr('Off'))),
            ButtonSegment(value: 'shadow', label: Text(context.tr('Shadow'))),
            ButtonSegment(value: 'on', label: Text(context.tr('On'))),
          ],
          selected: {mode},
          onSelectionChanged: (v) => setState(() => _mode = v.first),
        ),
        const SizedBox(height: AppTokens.s6),
        Text(_modeHelp(context, mode, view.timeoutMs), style: small),
        if (!view.preTriggerSkill) ...[
          const SizedBox(height: AppTokens.s8),
          decisionNotice(context,
              context.tr('"Pre-trigger skill" is off (Agent Behavior): both ways only hint, neither loads a skill outright.')),
        ],
        if (_int(s['total']) > 0) ...[
          const SizedBox(height: AppTokens.s12),
          Wrap(spacing: AppTokens.s16, runSpacing: 4, children: [
            Text(context.trArgs('Turns {n}', {'n': _int(s['total'])}), style: small),
            Text(context.trArgs('same {n}', {'n': _int(s['same'])}), style: small),
            Text(context.trArgs('old loads {a} · new loads {b}', {'a': _int(s['legacyLoads']), 'b': _int(s['routeLoads'])}),
                style: small),
            Text(context.trArgs('loads held back {n}', {'n': _int(s['loadsWithheld'])}), style: small),
            Text(context.trArgs('engine did not answer {n}', {'n': _int(s['fallbacks'])}), style: small),
          ]),
        ],
        const SizedBox(height: AppTokens.s12),
        if (view.log.isEmpty)
          Text(context.tr('No turn recorded yet — turn on Shadow and chat as usual.'), style: small)
        else
          for (final r in view.log) _logRow(context, r),
        const SizedBox(height: AppTokens.s16),
        Text(context.tr('Try a request'), style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.w600)),
        const SizedBox(height: AppTokens.s6),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _prompt,
              decoration: const InputDecoration(isDense: true),
              onSubmitted: (_) => _check(),
            ),
          ),
          const SizedBox(width: AppTokens.s8),
          OutlinedButton(onPressed: _checking ? null : _check, child: Text(context.tr('Pick a skill'))),
        ]),
        if (_checking) const Padding(padding: EdgeInsets.only(top: AppTokens.s8), child: LinearProgressIndicator()),
        if (_error != null) ...[
          const SizedBox(height: AppTokens.s8),
          decisionNotice(context, _error!, tone: AppTokens.danger),
        ],
        if (report != null) ...[
          const SizedBox(height: AppTokens.s12),
          Wrap(spacing: AppTokens.s8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Text(context.tr('Old:'), style: small),
            RouteChip(
              name: report['legacy'] is Map ? _str((report['legacy'] as Map)['name']) : null,
              force: report['legacy'] is Map && (report['legacy'] as Map)['force'] == true,
            ),
            Text(context.tr('New:'), style: small),
            RouteChip(
              name: report['route'] is Map ? _str((report['route'] as Map)['name']) : null,
              force: report['route'] is Map && (report['route'] as Map)['force'] == true,
            ),
            _engineText(context, report),
            if (_num(report['latencyMs']) != null)
              Text('${decisionNum(context, _num(report['latencyMs'])!, 1)} ms', style: small),
          ]),
          const SizedBox(height: AppTokens.s6),
          SelectableText('${report['reason'] ?? ''}', style: TextStyle(color: c.textSecondary, fontSize: 12.5)),
          const SizedBox(height: AppTokens.s6),
          Wrap(spacing: AppTokens.s6, runSpacing: 4, children: [
            for (final cand in (report['candidates'] as List? ?? const []))
              if (cand is Map)
                DecisionChip('${cand['name']} ${cand['score']}',
                    color: cand['phraseHit'] == true ? AppTokens.brand : null),
          ]),
        ],
      ]),
    );
  }
}
