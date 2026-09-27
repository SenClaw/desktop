// "Try it" — ask typed questions, locally (a Laya model, loaded on demand when
// Settings allow) or online, and see the distributions that come back.
// Mirrors the playground on the web page.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/l10n.dart';
import '../../core/transport/api_client.dart' show ApiException;
import '../../core/transport/connection.dart';
import '../../theme/tokens.dart';
import 'decision_models.dart';
import 'decision_presets.dart';
import 'decision_run_settings.dart' show decisionSettingsProvider;
import 'decision_widgets.dart';

class DecisionPlayground extends ConsumerStatefulWidget {
  const DecisionPlayground({
    super.key,
    required this.models,
    required this.compiled,
    required this.backend,
    required this.local,
    required this.onAsked,
  });

  /// Every row of the model list; what can answer depends on [local].
  final List<LayaModel> models;
  final bool compiled;

  /// The backend chosen in Settings (`local` or `online`).
  final String backend;
  final DecisionLocalSettings local;

  /// Called after an answer, so the list refreshes its ask counters.
  final VoidCallback onAsked;

  @override
  ConsumerState<DecisionPlayground> createState() => _DecisionPlaygroundState();
}

class _DecisionPlaygroundState extends ConsumerState<DecisionPlayground> {
  String _model = 'auto';

  /// `settings`, `local` or `online`.
  String _backend = 'settings';
  String _preset = kDecisionPresets.first.key;
  final _state = TextEditingController(text: kDecisionPresets.first.state);
  final _questions = TextEditingController(text: kDecisionPresets.first.questions);
  bool _asking = false;
  DecisionResult? _result;
  String? _error;

  @override
  void dispose() {
    _state.dispose();
    _questions.dispose();
    super.dispose();
  }

  void _choosePreset(String? key) {
    final p = kDecisionPresets.where((p) => p.key == key).firstOrNull;
    if (p == null) return;
    setState(() {
      _preset = p.key;
      _state.text = p.state;
      _questions.text = p.questions;
      _result = null;
      _error = null;
    });
  }

  /// Plain text stays text; anything that parses as a JSON string, array or
  /// object is sent as JSON (an object state is read as `json.dumps` text).
  Object _parseState(String text) {
    try {
      final v = jsonDecode(text.trim());
      if (v is String || v is List || v is Map) return v as Object;
    } catch (_) {
      // plain text
    }
    return text;
  }

  Future<void> _ask() async {
    final Object? questions;
    try {
      questions = jsonDecode(_questions.text);
    } on FormatException catch (e) {
      setState(() => _error = context.trArgs('The questions are not valid JSON: {e}', {'e': e.message}));
      return;
    }
    setState(() {
      _asking = true;
      _error = null;
    });
    try {
      final r = await ref.read(apiClientProvider).post('/api/decision/ask', body: {
        if (_backend != 'settings') 'backend': _backend,
        if (_effectiveBackend == 'local' && _model != 'auto') 'model': _model,
        'state': _parseState(_state.text),
        'questions': questions,
      });
      if (!mounted) return;
      setState(() => _result = DecisionResult.fromJson((r as Map).cast<String, dynamic>()));
      widget.onAsked();
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _result = null;
          _error = e.message;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _result = null;
          _error = '$e';
        });
      }
    } finally {
      if (mounted) setState(() => _asking = false);
    }
  }

  String get _effectiveBackend => _backend == 'settings' ? widget.backend : _backend;

  List<Widget> _notices(BuildContext context, List<LayaModel> loaded, List<LayaModel> installed) {
    if (_effectiveBackend == 'online') {
      final online = ref.watch(decisionSettingsProvider).valueOrNull?.settings.online;
      if (online != null && !online.hasApiKey && online.provider != 'custom') {
        return [
          decisionNotice(context, context.tr('Enter the key under How it runs → Online backend, then Save.'),
              tone: AppTokens.warning, title: context.tr('No API key for online')),
        ];
      }
      return const [];
    }
    if (loaded.isNotEmpty) return const [];
    if (installed.isEmpty) {
      return [
        decisionNotice(context, context.tr('Download or import a model above, or switch to Online.'),
            title: context.tr('No model is installed')),
      ];
    }
    return [
      widget.local.autoLoad
          ? decisionNotice(context, context.tr('No model is loaded yet — the first request loads one (a few seconds).'))
          : decisionNotice(context, context.tr('Press Load in the list above, or turn on Load on demand in How it runs.'),
              title: context.tr('No model is loaded')),
    ];
  }

  Widget _editor(BuildContext context, TextEditingController ctrl, String label, String hint) {
    return TextField(
      controller: ctrl,
      minLines: 8,
      maxLines: 18,
      style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
      decoration: InputDecoration(
        labelText: label,
        helperText: hint,
        alignLabelWithHint: true,
        border: const OutlineInputBorder(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final loaded = [for (final m in widget.models) if (m.loaded != null) m];
    final installed = [for (final m in widget.models) if (m.installed) m];
    // With hot-load on, any installed model can answer; without it, only loaded ones.
    final askable = widget.local.autoLoad ? installed : loaded;
    final ids = [for (final m in askable) m.id];
    final model = ids.contains(_model) ? _model : 'auto';
    final local = _effectiveBackend == 'local';
    final canAsk = !_asking && (!local || (widget.compiled && askable.isNotEmpty));
    final defaultModel = widget.local.defaultModel;

    return decisionCard(
      context,
      title: context.tr('Try it'),
      icon: Icons.bolt_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ..._notices(context, loaded, installed),
          Wrap(
            spacing: AppTokens.s12,
            runSpacing: AppTokens.s12,
            children: [
              SizedBox(
                width: 240,
                child: DropdownButtonFormField<String>(
                  key: ValueKey('backend-$_backend-${widget.backend}'),
                  initialValue: _backend,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: context.tr('Answer with'), isDense: true),
                  items: [
                    DropdownMenuItem(
                      value: 'settings',
                      child: Text(
                        context.trArgs('As in settings ({backend})', {
                          'backend': widget.backend == 'online' ? context.tr('Online backend') : context.tr('On this machine'),
                        }),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    DropdownMenuItem(value: 'local', child: Text(context.tr('On this machine — Laya'))),
                    DropdownMenuItem(value: 'online', child: Text(context.tr('Online — Jev API'))),
                  ],
                  onChanged: (v) => setState(() => _backend = v ?? 'settings'),
                ),
              ),
              if (local)
                SizedBox(
                  width: 300,
                  child: DropdownButtonFormField<String>(
                    // Re-created when the askable set changes, so the value is
                    // always one of the items.
                    key: ValueKey('model-$model-${ids.join(',')}-${loaded.length}-$defaultModel'),
                    initialValue: model,
                    isExpanded: true,
                    decoration: InputDecoration(labelText: context.tr('Model'), isDense: true),
                    items: [
                      DropdownMenuItem(
                        value: 'auto',
                        child: Text(
                          defaultModel != null
                              ? context.trArgs('Default ({id})', {'id': defaultModel})
                              : context.tr('Pick by language'),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      for (final m in askable)
                        DropdownMenuItem(
                          value: m.id,
                          child: Text(
                            m.loaded != null
                                ? context.trArgs('{name} · loaded', {'name': m.label})
                                : context.trArgs('{name} · loads on demand', {'name': m.label}),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (v) => setState(() => _model = v ?? 'auto'),
                  ),
                ),
              SizedBox(
                width: 380,
                child: DropdownButtonFormField<String>(
                  initialValue: _preset,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: context.tr('Sample'), isDense: true),
                  items: [
                    for (final p in kDecisionPresets)
                      DropdownMenuItem(value: p.key, child: Text(context.tr(p.label), overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: _choosePreset,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTokens.s16),
          LayoutBuilder(builder: (context, box) {
            final state = _editor(context, _state, context.tr('State'),
                context.tr('Plain text, or JSON (an object, or an array of conversation turns)'));
            final questions = _editor(context, _questions, context.tr('Questions'),
                context.tr('JSON: id → { type, instructions, criteria?, labels? }'));
            if (box.maxWidth < 720) {
              return Column(children: [state, const SizedBox(height: AppTokens.s12), questions]);
            }
            return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(flex: 10, child: state),
              const SizedBox(width: AppTokens.s12),
              Expanded(flex: 14, child: questions),
            ]);
          }),
          const SizedBox(height: AppTokens.s12),
          FilledButton.icon(
            onPressed: canAsk ? _ask : null,
            icon: _asking
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.bolt, size: 16),
            label: Text(context.tr('Ask')),
          ),
          if (_error != null) ...[
            const SizedBox(height: AppTokens.s12),
            decisionNotice(context, _error!, tone: AppTokens.danger),
          ],
          if (_result != null) ...[
            const SizedBox(height: AppTokens.s16),
            Wrap(
              spacing: AppTokens.s12,
              runSpacing: AppTokens.s4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                DecisionChip(_result!.model, color: _result!.online ? AppTokens.brandAlt : AppTokens.success),
                Text(_result!.engine, style: TextStyle(color: c.textMuted, fontSize: 12)),
                Text(context.trArgs('routing: {reason}', {'reason': _result!.reason}),
                    style: TextStyle(color: c.textMuted, fontSize: 12)),
                Text('${decisionNum(context, _result!.latencyMs, 1)} ms',
                    style: TextStyle(color: c.textMuted, fontSize: 12)),
                Text(context.trArgs('{n} input tokens', {'n': _result!.inputTokens}),
                    style: TextStyle(color: c.textMuted, fontSize: 12)),
                if (!_result!.online)
                  Text(context.trArgs('{n} graph runs', {'n': _result!.runs}),
                      style: TextStyle(color: c.textMuted, fontSize: 12)),
              ],
            ),
            const SizedBox(height: AppTokens.s12),
            Wrap(
              spacing: AppTokens.s12,
              runSpacing: AppTokens.s12,
              children: [
                for (final a in _result!.answers) SizedBox(width: 340, child: DecisionAnswerCard(answer: a)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// One answer: what the model picked, and the distribution it picked from.
class DecisionAnswerCard extends StatelessWidget {
  const DecisionAnswerCard({super.key, required this.answer});
  final DecisionAnswer answer;

  Widget _bar(BuildContext context, String label, double p, {bool strong = false}) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [
        Expanded(
          child: Tooltip(
            message: label,
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 12.5,
                    color: strong ? c.textPrimary : c.textSecondary,
                    fontWeight: strong ? FontWeight.w600 : FontWeight.normal)),
          ),
        ),
        const SizedBox(width: AppTokens.s8),
        SizedBox(
          width: 110,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppTokens.rFull),
            child: LinearProgressIndicator(
              value: p,
              minHeight: 6,
              backgroundColor: c.border,
              color: strong ? AppTokens.brand : c.textMuted,
            ),
          ),
        ),
        SizedBox(
          width: 58,
          child: Text(decisionPct(context, p),
              textAlign: TextAlign.right,
              style: TextStyle(
                  fontSize: 12,
                  color: strong ? c.textPrimary : c.textMuted,
                  fontFeatures: const [FontFeature.tabularFigures()])),
        ),
      ]),
    );
  }

  Widget _metric(BuildContext context, String text, String tip) => Tooltip(
        message: tip,
        child: Text(text, style: TextStyle(color: context.colors.textMuted, fontSize: 11.5)),
      );

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final a = answer;
    final List<Widget> body;
    switch (a.type) {
      case '':
        // An online backend's own shape: show it as it came.
        body = [
          SelectableText(const JsonEncoder.withIndent('  ').convert(a.raw),
              style: TextStyle(fontFamily: 'monospace', fontSize: 11.5, color: c.textSecondary)),
        ];
      case 'choice':
        body = [
          Text('→ ${a.choice ?? ''}', style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.w600)),
          const SizedBox(height: AppTokens.s6),
          for (final (label, p) in a.probabilities) _bar(context, label, p, strong: label == a.choice),
        ];
      case 'score':
        final best = a.probabilities.isEmpty
            ? null
            : a.probabilities.reduce((x, y) => y.$2 > x.$2 ? y : x).$1;
        body = [
          Text(
              context.trArgs('score {s} on a 0–{max} scale',
                  {'s': decisionNum(context, a.score ?? 0), 'max': a.probabilities.length - 1}),
              style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.w600)),
          const SizedBox(height: AppTokens.s6),
          for (final (level, p) in a.probabilities)
            _bar(
              context,
              '$level · ${a.legend[level] is String ? a.legend[level] : jsonEncode(a.legend[level])}',
              p,
              strong: level == best,
            ),
        ];
      default:
        final p = a.noul ?? 0;
        body = [
          Text('→ ${p >= 0.5 ? context.tr('yes') : context.tr('no')}',
              style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.w600)),
          const SizedBox(height: AppTokens.s6),
          _bar(context, context.tr('P(holds)'), p, strong: true),
        ];
    }

    return Container(
      padding: const EdgeInsets.all(AppTokens.s12),
      decoration: BoxDecoration(
        color: c.bg,
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(AppTokens.rMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Flexible(
              child: Text(a.id,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontFamily: 'monospace', fontSize: 12.5, color: c.textPrimary, fontWeight: FontWeight.w600)),
            ),
            const SizedBox(width: AppTokens.s8),
            if (a.known) DecisionChip(a.type),
          ]),
          const SizedBox(height: AppTokens.s8),
          ...body,
          const SizedBox(height: AppTokens.s8),
          Wrap(spacing: AppTokens.s12, runSpacing: 2, children: [
            if (a.confidence != null)
              _metric(context, 'confidence ${decisionNum(context, a.confidence!)}',
                  context.tr('How concentrated the distribution is (1 − normalised entropy). Laya says plainly this is NOT a calibrated probability.')),
            if (a.answerConfidence != null)
              _metric(context, 'answer_confidence ${decisionNum(context, a.answerConfidence!)}',
                  context.tr('max(p) — the quantity Laya\'s temperature scaling calibrates: of answers at this level, about that share are right.')),
            if (a.actProbability != null)
              _metric(context, 'act ${decisionNum(context, a.actProbability!)}',
                  context.tr('P(act) from the act/escalate head: whether the model thinks this answer should be acted on (high) or handed to a person (low).')),
          ]),
        ],
      ),
    );
  }
}
