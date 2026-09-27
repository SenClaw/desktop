// "How it runs" — which backend answers typed decisions (a Laya checkpoint on
// this machine, or Jev online), the default local model, its thread count,
// loading on demand and unloading when idle. Mirrors
// `web/src/components/settings/DecisionRunSettings.tsx`; the daemon side is
// `src/decision/settings.rs`.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/l10n.dart';
import '../../core/transport/api_client.dart' show ApiException;
import '../../core/transport/connection.dart';
import '../../theme/tokens.dart';
import 'decision_models.dart';
import 'decision_widgets.dart';

final decisionSettingsProvider = FutureProvider<DecisionSettingsView>((ref) async {
  final r = await ref.read(apiClientProvider).get('/api/decision/settings');
  return DecisionSettingsView.fromJson((r as Map).cast<String, dynamic>());
});

/// Idle-unload choices in minutes; 0 = never.
const kIdleUnloadChoices = [5, 15, 30, 60, 180, 0];

/// "15 minutes", "1 hour", "Never".
String idleUnloadLabel(BuildContext context, int minutes) {
  if (minutes == 0) return context.tr('Never');
  if (minutes % 60 == 0) {
    final h = minutes ~/ 60;
    return context.trArgs(h == 1 ? '{n} hour' : '{n} hours', {'n': h});
  }
  return context.trArgs('{n} minutes', {'n': minutes});
}

const _providerLabels = {
  'typesafe': 'TypeSafe Jev (api.typesafe.ai)',
  'cloudflare': 'Cloudflare Workers AI (typesafe/jev)',
  'custom': 'Custom — any /v1/systemone URL',
};

class DecisionRunSettingsCard extends ConsumerStatefulWidget {
  const DecisionRunSettingsCard({super.key, required this.installed, required this.onSaved});

  /// Installed models, for the default-model picker.
  final List<LayaModel> installed;

  /// Called after a save, so the model list re-reads the default and limits.
  final VoidCallback onSaved;

  @override
  ConsumerState<DecisionRunSettingsCard> createState() => _DecisionRunSettingsCardState();
}

class _DecisionRunSettingsCardState extends ConsumerState<DecisionRunSettingsCard> {
  DecisionSettingsView? _view;
  DecisionRunSettings? _draft;
  bool _clearKey = false;
  bool _saving = false;
  bool _testing = false;
  (bool, String)? _test;

  final _threads = TextEditingController();
  final _key = TextEditingController();
  final _model = TextEditingController();
  final _url = TextEditingController();
  final _account = TextEditingController();
  final _timeout = TextEditingController();

  @override
  void dispose() {
    for (final c in [_threads, _key, _model, _url, _account, _timeout]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Take the daemon's copy — on first load and after every save.
  void _adopt(DecisionSettingsView v) {
    _view = v;
    _draft = v.settings;
    _clearKey = false;
    _threads.text = v.settings.local.threads?.toString() ?? '';
    _key.text = '';
    _model.text = v.settings.online.model;
    _url.text = v.settings.online.url;
    _account.text = v.settings.online.accountId;
    _timeout.text = '${v.settings.online.timeoutSecs}';
  }

  DecisionRunSettings get _current => _draft!;

  void _setLocal(DecisionLocalSettings local) => setState(() => _draft = _current.copyWith(local: local));
  void _setOnline(DecisionOnlineSettings online) => setState(() => _draft = _current.copyWith(online: online));

  bool get _dirty => _clearKey || _current != _view!.settings;

  Map<String, dynamic> get _body => _current.toJson(clearApiKey: _clearKey);

  void _toast(String msg) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final r = await ref.read(apiClientProvider).put('/api/decision/settings', body: _body);
      if (!mounted) return;
      setState(() => _adopt(DecisionSettingsView.fromJson((r as Map).cast<String, dynamic>())));
      ref.invalidate(decisionSettingsProvider);
      widget.onSaved();
      _toast(context.tr('Saved how decisions run'));
    } on ApiException catch (e) {
      _toast(e.message);
    } catch (e) {
      _toast('$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _testOnline() async {
    setState(() {
      _testing = true;
      _test = null;
    });
    try {
      final r = await ref.read(apiClientProvider).post('/api/decision/online/test', body: _body);
      if (!mounted) return;
      final m = (r as Map).cast<String, dynamic>();
      setState(() => _test = (
            true,
            context.trArgs('Connected: {model} answered in {ms} ms.', {
              'model': '${m['model'] ?? ''}',
              'ms': decisionNum(context, (m['latencyMs'] as num?) ?? 0, 1),
            })
          ));
    } on ApiException catch (e) {
      if (mounted) setState(() => _test = (false, e.message));
    } catch (e) {
      if (mounted) setState(() => _test = (false, '$e'));
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Widget _field(BuildContext context, String label, Widget child, {String? help, Color? helpColor}) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTokens.s12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.w600, fontSize: 13)),
        const SizedBox(height: AppTokens.s4),
        child,
        if (help != null) ...[
          const SizedBox(height: AppTokens.s4),
          Text(help, style: TextStyle(color: helpColor ?? c.textMuted, fontSize: 12)),
        ],
      ]),
    );
  }

  Widget _localColumn(BuildContext context, DecisionSettingsView view) {
    final local = _current.local;
    final installed = [for (final m in widget.installed) if (m.installed) m];
    final missing = local.defaultModel != null && !installed.any((m) => m.id == local.defaultModel);
    final english = !missing && installed.any((m) => m.id == local.defaultModel && m.kind == 'english');
    final idleChoices = {...kIdleUnloadChoices, local.idleUnloadMinutes}.toList()
      ..sort((a, b) => a == 0 ? 1 : (b == 0 ? -1 : a - b));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _heading(context, Icons.computer_outlined, context.tr('On this machine'), _current.backend == 'local'),
      _field(
        context,
        context.tr('Default model'),
        DropdownButtonFormField<String>(
          key: ValueKey('default-${local.defaultModel}-${installed.length}'),
          initialValue: missing ? null : (local.defaultModel ?? 'auto'),
          isExpanded: true,
          decoration: const InputDecoration(isDense: true),
          items: [
            DropdownMenuItem(value: 'auto', child: Text(context.tr('Pick by language'))),
            for (final m in installed)
              DropdownMenuItem(value: m.id, child: Text('${m.label} (${m.id})', overflow: TextOverflow.ellipsis)),
          ],
          onChanged: (v) => _setLocal(local.copyWith(defaultModel: () => v == null || v == 'auto' ? null : v)),
        ),
        help: missing
            ? context.trArgs('{id} is not installed — install it, or pick another model.', {'id': local.defaultModel})
            : english
                ? context.tr(
                    'This model reads English only: text with accented letters still goes to the Multilingual model (when installed).')
                : context.tr(
                    'Requests that name no model use this one. "Pick by language" = the Multilingual model for text with diacritics, English for plain ASCII.'),
        helpColor: missing
            ? AppTokens.danger
            : english
                ? AppTokens.warning
                : null,
      ),
      _field(
        context,
        context.tr('CPU threads'),
        SizedBox(
          width: 180,
          child: TextField(
            controller: _threads,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              isDense: true,
              hintText: context.trArgs('automatic ({n})', {'n': view.autoThreads}),
            ),
            onChanged: (v) {
              final n = int.tryParse(v);
              _setLocal(local.copyWith(threads: () => n == null || n <= 0 ? null : n.clamp(1, view.maxThreads)));
            },
          ),
        ),
        help: context.trArgs(
            'ONNX Runtime threads per model. Empty = automatic ({n} on this machine). A loaded model keeps the count it was loaded with — unload and load it again to change it.',
            {'n': view.autoThreads}),
      ),
      _field(
        context,
        context.tr('Load on demand'),
        Switch(value: local.autoLoad, onChanged: (v) => _setLocal(local.copyWith(autoLoad: v))),
        help: context.tr(
            'On: a request that needs a model not in RAM loads it (that request takes a few seconds longer). Off: press Load first.'),
      ),
      _field(
        context,
        context.tr('Unload from RAM when unused for'),
        SizedBox(
          width: 180,
          child: DropdownButtonFormField<int>(
            key: ValueKey('idle-${local.idleUnloadMinutes}'),
            initialValue: local.idleUnloadMinutes,
            isExpanded: true,
            decoration: const InputDecoration(isDense: true),
            items: [
              for (final m in idleChoices) DropdownMenuItem(value: m, child: Text(idleUnloadLabel(context, m))),
            ],
            onChanged: (v) => _setLocal(local.copyWith(idleUnloadMinutes: v ?? 15)),
          ),
        ),
        help: context.tr(
            'A model no request has used for this long is unloaded to give the memory back (1.2–1.7 GB each). With Load on demand on, the next request loads it again.'),
      ),
    ]);
  }

  Widget _onlineColumn(BuildContext context, DecisionSettingsView view) {
    final online = _current.online;
    final defaultModel = switch (online.provider) {
      'typesafe' => view.typesafeModel,
      'cloudflare' => view.cloudflareModel,
      _ => context.tr('no model sent'),
    };
    // A saved key only ever goes to the provider (and custom URL) it was
    // saved for — the daemon enforces it; the form says so.
    final saved = view.settings.online;
    final keyApplies = saved.hasApiKey &&
        saved.provider == online.provider &&
        (online.provider != 'custom' || saved.url == online.url.trim());
    final keyHelp = _clearKey
        ? context.tr('The saved key is deleted when you press Save.')
        : keyApplies
            ? context.tr('A key is saved (it is never shown again). Leave empty to keep it.')
            : saved.hasApiKey
                ? context.tr(
                    'The saved key belongs to another provider or URL and is not sent here — enter a key for this choice.')
                : online.provider == 'custom'
                    ? context.tr('Optional for a custom endpoint.')
                    : context.tr('Required.');
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _heading(context, Icons.cloud_outlined, context.tr('Online backend'), _current.backend == 'online'),
      _field(
        context,
        context.tr('Provider'),
        DropdownButtonFormField<String>(
          key: ValueKey('provider-${online.provider}'),
          initialValue: view.providers.contains(online.provider) ? online.provider : null,
          isExpanded: true,
          decoration: const InputDecoration(isDense: true),
          items: [
            for (final p in view.providers)
              DropdownMenuItem(value: p, child: Text(context.tr(_providerLabels[p] ?? p), overflow: TextOverflow.ellipsis)),
          ],
          onChanged: (v) => _setOnline(online.copyWith(provider: v ?? 'typesafe')),
        ),
      ),
      if (online.provider == 'custom')
        _field(
          context,
          'URL',
          TextField(
            controller: _url,
            decoration: const InputDecoration(isDense: true, hintText: 'http://127.0.0.1:8000/v1/systemone'),
            onChanged: (v) => _setOnline(online.copyWith(url: v)),
          ),
          help: context.tr('An endpoint speaking /v1/systemone — LiteLLM, laya-serve, OpenJev…'),
        ),
      if (online.provider == 'cloudflare')
        _field(
          context,
          context.tr('Cloudflare account id'),
          TextField(
            controller: _account,
            decoration: const InputDecoration(isDense: true),
            onChanged: (v) => _setOnline(online.copyWith(accountId: v)),
          ),
        ),
      _field(
        context,
        context.tr('API key'),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _key,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                isDense: true,
                hintText: keyApplies && !_clearKey ? context.tr('•••••••• (saved)') : context.tr('paste the key here'),
              ),
              onChanged: (v) {
                if (v.isNotEmpty) _clearKey = false;
                _setOnline(online.copyWith(apiKey: v));
              },
            ),
          ),
          if (online.hasApiKey) ...[
            const SizedBox(width: AppTokens.s8),
            OutlinedButton(
              onPressed: () => setState(() => _clearKey = !_clearKey),
              child: Text(_clearKey ? context.tr('Keep key') : context.tr('Delete key')),
            ),
          ],
        ]),
        help: keyHelp,
      ),
      _field(
        context,
        context.tr('Model'),
        TextField(
          controller: _model,
          decoration: InputDecoration(isDense: true, hintText: defaultModel),
          onChanged: (v) => _setOnline(online.copyWith(model: v)),
        ),
        help: context.tr('Empty = the provider default (a pinned version, not a moving alias).'),
      ),
      _field(
        context,
        context.tr('Timeout (seconds)'),
        SizedBox(
          width: 120,
          child: TextField(
            controller: _timeout,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(isDense: true),
            onChanged: (v) => _setOnline(online.copyWith(timeoutSecs: (int.tryParse(v) ?? 15).clamp(5, 25))),
          ),
        ),
      ),
      decisionNotice(
        context,
        context.tr(
            'The state and questions of every request go to the chosen provider. For data that must not leave this machine, use On this machine.'),
        tone: AppTokens.warning,
        title: context.tr('Online sends content off this machine'),
      ),
      Wrap(spacing: AppTokens.s8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        OutlinedButton.icon(
          onPressed: _testing ? null : _testOnline,
          icon: _testing
              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.network_check, size: 16),
          label: Text(context.tr('Test connection')),
        ),
        Text(context.tr('sends one very short yes/no question, with the settings as edited (no need to Save)'),
            style: TextStyle(color: context.colors.textMuted, fontSize: 12)),
      ]),
      if (_test != null) ...[
        const SizedBox(height: AppTokens.s8),
        decisionNotice(context, _test!.$2, tone: _test!.$1 ? AppTokens.success : AppTokens.danger),
      ],
    ]);
  }

  Widget _heading(BuildContext context, IconData icon, String text, bool active) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTokens.s8),
      child: Row(children: [
        Icon(icon, size: 16, color: c.textSecondary),
        const SizedBox(width: AppTokens.s6),
        Text(text, style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.w700)),
        if (active) ...[
          const SizedBox(width: AppTokens.s8),
          DecisionChip(context.tr('in use'), color: AppTokens.success),
        ],
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // A refresh replaces the form only while nothing in it is being edited.
    // Adopted from the listener, not here: writing a mounted field's
    // controller during build is a setState-in-build.
    ref.listen<AsyncValue<DecisionSettingsView>>(decisionSettingsProvider, (_, next) {
      final v = next.valueOrNull;
      if (v != null && _view != null && !_dirty && v.settings != _view!.settings) setState(() => _adopt(v));
    });
    final async = ref.watch(decisionSettingsProvider);
    if (_view == null && async.valueOrNull != null) {
      // First data: no field is mounted yet, so filling the controllers is safe.
      _adopt(async.valueOrNull!);
    }
    if (_view == null) {
      return decisionCard(
        context,
        title: context.tr('How it runs'),
        icon: Icons.tune,
        child: async.hasError
            ? decisionNotice(context, '${async.error}', tone: AppTokens.danger)
            : const LinearProgressIndicator(),
      );
    }
    final view = _view!;
    return decisionCard(
      context,
      title: context.tr('How it runs'),
      icon: Icons.tune,
      trailing: FilledButton.icon(
        onPressed: _dirty && !_saving ? _save : null,
        icon: _saving
            ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.save_outlined, size: 16),
        label: Text(context.tr('Save')),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _field(
          context,
          context.tr('Answer with, by default'),
          SegmentedButton<String>(
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            segments: [
              ButtonSegment(
                  value: 'local', icon: const Icon(Icons.computer_outlined, size: 16), label: Text(context.tr('On this machine — Laya'))),
              ButtonSegment(
                  value: 'online', icon: const Icon(Icons.cloud_outlined, size: 16), label: Text(context.tr('Online — Jev API'))),
            ],
            selected: {_current.backend},
            onSelectionChanged: (s) => setState(() => _draft = _current.copyWith(backend: s.first)),
          ),
          help: context.tr('Applies to every request that does not choose; Try it below can still pick either.'),
        ),
        Divider(color: c.border, height: AppTokens.s24),
        LayoutBuilder(builder: (context, box) {
          final local = _localColumn(context, view);
          final online = _onlineColumn(context, view);
          if (box.maxWidth < 760) {
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [local, online]);
          }
          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: local),
            const SizedBox(width: AppTokens.s24),
            Expanded(child: online),
          ]);
        }),
      ]),
    );
  }
}
