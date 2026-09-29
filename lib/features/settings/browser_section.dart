// Settings → Browser: the browser-agent engine (v2 = Jev decisions + an
// LLM, legacy = extension scripts), its settings form (partial `PUT` — Save
// sends only the fields that changed), the Chrome extension's pairing state
// (polled every 3s while this section is visible; never starts the
// runtime), and on-demand tab Activity (starts the runtime, so it is a
// button, never a timer). Daemon side:
// `src/browser_agent/{settings,extension,rest}.rs` (branch
// feat/sen-browser-v2). Spec:
// senclaw/plans/260929-0143-sen-browser-runtime/ui-management.md.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/shell.dart' show openRuntimeSettings;
import '../../core/i18n/l10n.dart';
import '../../core/transport/api_client.dart' show ApiException;
import '../../core/transport/connection.dart';
import '../../core/transport/runtime_missing.dart';
import '../../theme/tokens.dart';
import '../../widgets/runtime_missing_banner.dart';
import '../chat/new_chat_dialog.dart' show llmConfigsProvider, LlmConfig;
import 'browser_models.dart';
import 'decision_widgets.dart';
import 'settings_screen.dart' show SettingsBody;

class BrowserSection extends ConsumerWidget {
  const BrowserSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(browserSettingsProvider);
    return SettingsBody(
      title: context.tr('Browser'),
      onRefresh: () {
        ref.invalidate(browserSettingsProvider);
        ref.invalidate(browserExtensionProvider);
      },
      children: [
        async.when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => decisionNotice(
              context, e is ApiException ? e.message : '$e', tone: AppTokens.danger),
          data: (view) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _EngineStatusCard(view: view),
              const _ApprovalsCard(),
              _SettingsFormCard(
                view: view,
                onSaved: () => ref.invalidate(browserSettingsProvider),
              ),
            ],
          ),
        ),
        const _ExtensionCard(),
        const _ActivityCard(),
      ],
    );
  }
}

// ── Engine status ────────────────────────────────────────────────────────

class _EngineStatusCard extends ConsumerWidget {
  const _EngineStatusCard({required this.view});
  final BrowserSettingsView view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    return decisionCard(
      context,
      title: context.tr('Browser engine'),
      icon: Icons.web_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text('${context.tr('Engine in use')}: ',
                style: TextStyle(color: c.textSecondary, fontSize: 13)),
            Text(
              view.engine == 'v2'
                  ? context.tr('New (Jev + LLM)')
                  : context.tr('Legacy (extension scripts)'),
              style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ]),
          if (!view.runtimeInstalled) ...[
            const SizedBox(height: AppTokens.s12),
            decisionNotice(context, context.tr('The Browser runtime is not installed.'),
                tone: AppTokens.warning),
            const SizedBox(height: AppTokens.s8),
            OutlinedButton.icon(
              onPressed: () => openRuntimeSettings(context, ref),
              icon: const Icon(Icons.settings_outlined, size: 16),
              label: Text(context.tr('Open Runtime settings')),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Waiting for your approval (never starts the runtime) ────────────────

class _ApprovalsCard extends ConsumerStatefulWidget {
  const _ApprovalsCard();
  @override
  ConsumerState<_ApprovalsCard> createState() => _ApprovalsCardState();
}

class _ApprovalsCardState extends ConsumerState<_ApprovalsCard> {
  Timer? _poll;

  /// The approval an Approve/Decline POST is in flight for.
  String? _busy;

  @override
  void initState() {
    super.initState();
    // Cheap and never starts the runtime, unlike `tabs` — safe to poll for
    // as long as this card is on screen, same idea as the extension card's
    // 3s poll (the spec asks 5s here).
    _poll = Timer.periodic(const Duration(seconds: 5), (_) => ref.invalidate(browserApprovalsProvider));
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  void _toast(String msg) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _decide(PendingBrowserApproval a, {required bool approve}) async {
    if (approve) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(ctx.tr('Approve')),
          content: Text(ctx.tr('SenClaw will do this in the browser now.')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.tr('Cancel'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ctx.tr('Approve'))),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    setState(() => _busy = a.approvalId);
    try {
      final outcome =
          await answerBrowserApproval(ref.read(apiClientProvider), a.approvalId, approve: approve);
      if (!mounted) return;
      // A decline that ended the task reads better as a plain "Declined"
      // than as its own status/message — the task not continuing IS the
      // whole story then. These three statuses mean it paused again (for
      // another approval, for the person, for a value) rather than ended;
      // the web card uses the same list.
      const paused = {'needs_approval', 'needs_user', 'needs_input'};
      final ended = !paused.contains(outcome.status);
      _toast(!approve && ended
          ? context.tr('Declined')
          : context.trArgs('The task went on: {status} — {message}',
              {'status': outcome.status, 'message': outcome.message}));
    } on ApiException catch (e) {
      _toast(e.message);
    } catch (e) {
      _toast('$e');
    } finally {
      // Reload on both success and error (including a 404 — the daemon's
      // own signal that someone else already answered it): either way the
      // list this card shows is now stale.
      ref.invalidate(browserApprovalsProvider);
      if (mounted) setState(() => _busy = null);
    }
  }

  Widget _row(BuildContext context, PendingBrowserApproval a) {
    final c = context.colors;
    final busy = _busy == a.approvalId;
    return Container(
      margin: const EdgeInsets.only(bottom: AppTokens.s8),
      padding: const EdgeInsets.all(AppTokens.s12),
      decoration: BoxDecoration(border: Border.all(color: c.border), borderRadius: BorderRadius.circular(AppTokens.rSm)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: AppTokens.s8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text(a.action, style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.w700, fontSize: 13)),
          DecisionChip(_operationLabel(context, a.operation)),
        ]),
        const SizedBox(height: AppTokens.s4),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${context.tr('Goal')}: ',
              style: TextStyle(color: c.textSecondary, fontWeight: FontWeight.w600, fontSize: 12.5)),
          Expanded(child: Text(a.goal, style: TextStyle(color: c.textSecondary, fontSize: 12.5))),
        ]),
        if (a.url != null) ...[
          const SizedBox(height: AppTokens.s4),
          Text(a.url!,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11.5),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ],
        const SizedBox(height: AppTokens.s4),
        Wrap(spacing: AppTokens.s8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text(a.chat, style: TextStyle(color: c.textMuted, fontSize: 11.5, fontFamily: 'monospace')),
          if (a.waitingSecs != null)
            Text(context.trArgs('Waiting {time}', {'time': formatBrowserWaitingTime(a.waitingSecs!)}),
                style: TextStyle(color: c.textMuted, fontSize: 11.5)),
        ]),
        const SizedBox(height: AppTokens.s8),
        Row(children: [
          FilledButton(
            onPressed: busy ? null : () => _decide(a, approve: true),
            child: Text(context.tr('Approve')),
          ),
          const SizedBox(width: AppTokens.s8),
          OutlinedButton(
            onPressed: busy ? null : () => _decide(a, approve: false),
            child: Text(context.tr('Decline')),
          ),
          if (busy) ...[
            const SizedBox(width: AppTokens.s12),
            const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
          ],
        ]),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final async = ref.watch(browserApprovalsProvider);
    return async.when(
      // Hidden while there is no confirmed non-empty list — same call as an
      // empty one, and (like the extension card) a failed 5s poll keeps
      // showing the last good state rather than flashing an error over a
      // transient hiccup: this card is a courtesy notice, never the only
      // way to approve (the chat's own approval prompt always still works).
      skipError: true,
      loading: () => const SizedBox.shrink(),
      error: (e, _) => const SizedBox.shrink(),
      data: (approvals) {
        if (approvals.isEmpty) return const SizedBox.shrink();
        return decisionCard(
          context,
          title: context.tr('Waiting for your approval'),
          icon: Icons.pending_actions_outlined,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final a in approvals) _row(context, a),
            Text(
              context.tr('A browser task paused before this action. Approve only if you want SenClaw to do it.'),
              style: TextStyle(color: c.textMuted, fontSize: 12),
            ),
          ]),
        );
      },
    );
  }
}

/// `CLICK` → "Click", … — anything not in the spec's table is shown as is.
String _operationLabel(BuildContext context, String operation) {
  switch (operation) {
    case 'CLICK':
      return context.tr('Click');
    case 'KEY_ENTER':
      return context.tr('Press Enter');
    case 'DIALOG_ACCEPT':
      return context.tr('Confirm a dialog');
    case 'TYPE_TEXT':
      return context.tr('Type text');
    default:
      return operation;
  }
}

// ── Settings form (grouped, one Save = only the changed fields) ─────────

class _SettingsFormCard extends ConsumerStatefulWidget {
  const _SettingsFormCard({required this.view, required this.onSaved});
  final BrowserSettingsView view;
  final VoidCallback onSaved;

  @override
  ConsumerState<_SettingsFormCard> createState() => _SettingsFormCardState();
}

class _SettingsFormCardState extends ConsumerState<_SettingsFormCard> {
  late BrowserSettings _original;
  late BrowserSettings _draft;
  bool _saving = false;

  final _localModel = TextEditingController();
  final _hostedModel = TextEditingController();
  final _profile = TextEditingController();
  final _startUrl = TextEditingController();
  final _maxSteps = TextEditingController();
  final _bandsLocalAct = TextEditingController();
  final _bandsLocalFallback = TextEditingController();
  final _bandsHostedAct = TextEditingController();
  final _bandsHostedFallback = TextEditingController();

  @override
  void initState() {
    super.initState();
    _adopt(widget.view.settings);
  }

  @override
  void didUpdateWidget(covariant _SettingsFormCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A background reload replaces `view`; keep an in-progress edit rather
    // than clobbering it, same as the Decision settings card.
    if (!_dirty) _adopt(widget.view.settings);
  }

  @override
  void dispose() {
    for (final c in [
      _localModel,
      _hostedModel,
      _profile,
      _startUrl,
      _maxSteps,
      _bandsLocalAct,
      _bandsLocalFallback,
      _bandsHostedAct,
      _bandsHostedFallback,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _adopt(BrowserSettings s) {
    _original = s;
    _draft = s;
    _localModel.text = s.localModel;
    _hostedModel.text = s.hostedModel ?? '';
    _profile.text = s.profile;
    _startUrl.text = s.startUrl;
    _maxSteps.text = '${s.maxSteps}';
    _bandsLocalAct.text = '${s.bandsLocal.act}';
    _bandsLocalFallback.text = '${s.bandsLocal.fallback}';
    _bandsHostedAct.text = '${s.bandsHosted.act}';
    _bandsHostedFallback.text = '${s.bandsHosted.fallback}';
  }

  bool get _dirty => browserSettingsDiff(_original, _draft).isNotEmpty;

  void _toast(String msg) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _save() async {
    final diff = browserSettingsDiff(_original, _draft);
    if (diff.isEmpty) return;
    setState(() => _saving = true);
    try {
      final r =
          await ref.read(apiClientProvider).put('/api/browser-agent/settings', body: diff);
      final view = BrowserSettingsView.fromJson((r as Map).cast<String, dynamic>());
      if (!mounted) return;
      setState(() => _adopt(view.settings));
      widget.onSaved();
      _toast(context.tr('Settings saved'));
    } on ApiException catch (e) {
      // The 422 `error` text is written for a person reading it — show it
      // exactly as the daemon sent it, no rewording.
      _toast(e.message);
    } catch (e) {
      _toast('$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _field(BuildContext context, String label, Widget child, {String? help}) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTokens.s12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.w600, fontSize: 13)),
        const SizedBox(height: AppTokens.s4),
        child,
        if (help != null) ...[
          const SizedBox(height: AppTokens.s4),
          Text(help, style: TextStyle(color: c.textMuted, fontSize: 12)),
        ],
      ]),
    );
  }

  Widget _groupHeading(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.only(bottom: AppTokens.s8),
        child: Text(text,
            style: TextStyle(color: context.colors.textPrimary, fontWeight: FontWeight.w700)),
      );

  /// LLM model picker for `textModel` / `fallbackModel`: an empty sentinel
  /// stands for "Active chat model" (`null` on the wire) — a real `null` in
  /// `DropdownButtonFormField.items` is avoidable ambiguity the rest of the
  /// app's dropdowns steer clear of too (see `defaultModel` in
  /// decision_run_settings.dart).
  Widget _llmModelField(BuildContext context,
      {required String? value, required List<LlmConfig> configs, required ValueChanged<String?> onChanged}) {
    const none = '';
    final missing = value != null && !configs.any((c) => c.id == value);
    final sel = missing ? none : (value ?? none);
    return DropdownButtonFormField<String>(
      key: ValueKey('llm-$sel-${configs.length}'),
      initialValue: sel,
      isExpanded: true,
      decoration: const InputDecoration(isDense: true),
      items: [
        DropdownMenuItem(value: none, child: Text(context.tr('Active chat model'))),
        for (final cfg in configs)
          DropdownMenuItem(value: cfg.id, child: Text(cfg.label, overflow: TextOverflow.ellipsis)),
      ],
      onChanged: (v) => onChanged(v == null || v == none ? null : v),
    );
  }

  Widget _generalGroup(BuildContext context) {
    final d = _draft;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _groupHeading(context, context.tr('General')),
      _field(
        context,
        context.tr('Engine'),
        DropdownButtonFormField<String>(
          key: ValueKey('engine-${d.engine}'),
          initialValue: d.engine,
          isExpanded: true,
          decoration: const InputDecoration(isDense: true),
          items: [
            DropdownMenuItem(value: 'auto', child: Text(context.tr('Auto'))),
            DropdownMenuItem(value: 'v2', child: Text(context.tr('New (Jev + LLM)'))),
            DropdownMenuItem(value: 'legacy', child: Text(context.tr('Legacy (extension scripts)'))),
          ],
          onChanged: (v) => setState(() => _draft = d.copyWith(engine: v ?? 'auto')),
        ),
        help: context.tr(
            'Auto uses the new engine once the Browser runtime is installed. Applies to chats started afterwards.'),
      ),
      _field(
        context,
        context.tr('Default browser'),
        DropdownButtonFormField<String>(
          key: ValueKey('driver-${d.defaultDriver}'),
          initialValue: d.defaultDriver,
          isExpanded: true,
          decoration: const InputDecoration(isDense: true),
          items: [
            DropdownMenuItem(value: 'managed', child: Text(context.tr("SenClaw's own Chrome"))),
            DropdownMenuItem(value: 'extension', child: Text(context.tr('Your Chrome (extension)'))),
          ],
          onChanged: (v) => setState(() => _draft = d.copyWith(defaultDriver: v ?? 'managed')),
        ),
      ),
      Padding(
        padding: const EdgeInsets.only(bottom: AppTokens.s12),
        child: Row(children: [
          Expanded(
            child: Text(context.tr("Run SenClaw's Chrome without a window"),
                style: TextStyle(
                    color: context.colors.textPrimary, fontWeight: FontWeight.w600, fontSize: 13)),
          ),
          Switch(value: d.headless, onChanged: (v) => setState(() => _draft = d.copyWith(headless: v))),
        ]),
      ),
      _field(
        context,
        context.tr('Chrome profile name'),
        TextField(
          controller: _profile,
          decoration: const InputDecoration(isDense: true),
          onChanged: (v) => setState(() => _draft = d.copyWith(profile: v)),
        ),
      ),
      _field(
        context,
        context.tr('Step budget'),
        SizedBox(
          width: 140,
          child: TextField(
            controller: _maxSteps,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(isDense: true),
            onChanged: (v) {
              final n = int.tryParse(v);
              if (n != null) setState(() => _draft = d.copyWith(maxSteps: n.clamp(1, 120)));
            },
          ),
        ),
      ),
      _field(
        context,
        context.tr('Start page'),
        TextField(
          controller: _startUrl,
          decoration: const InputDecoration(isDense: true),
          onChanged: (v) => setState(() => _draft = d.copyWith(startUrl: v)),
        ),
      ),
    ]);
  }

  Widget _decisionsGroup(BuildContext context, List<LlmConfig> llm) {
    final d = _draft;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _groupHeading(context, context.tr('Decisions')),
      _field(
        context,
        context.tr('Decision backend'),
        DropdownButtonFormField<String>(
          key: ValueKey('backend-${d.decisionBackend}'),
          initialValue: d.decisionBackend,
          isExpanded: true,
          decoration: const InputDecoration(isDense: true),
          items: [
            DropdownMenuItem(
                value: 'auto',
                child: Text(context.tr('Auto (local, hosted only for allowed sites)'),
                    overflow: TextOverflow.ellipsis)),
            DropdownMenuItem(value: 'local', child: Text(context.tr('Local model only'))),
            DropdownMenuItem(value: 'hosted', child: Text(context.tr('Hosted Jev'))),
            DropdownMenuItem(
                value: 'llm-only',
                child: Text(context.tr('LLM only (no decision model)'), overflow: TextOverflow.ellipsis)),
          ],
          onChanged: (v) => setState(() => _draft = d.copyWith(decisionBackend: v ?? 'auto')),
        ),
      ),
      _field(
        context,
        context.tr('Local decision model'),
        TextField(
          controller: _localModel,
          decoration: const InputDecoration(isDense: true),
          onChanged: (v) => setState(() => _draft = d.copyWith(localModel: v)),
        ),
      ),
      _field(
        context,
        context.tr('Hosted model'),
        TextField(
          controller: _hostedModel,
          decoration: const InputDecoration(isDense: true),
          onChanged: (v) =>
              setState(() => _draft = d.copyWith(hostedModel: () => v.trim().isEmpty ? null : v.trim())),
        ),
      ),
      _TagsField(
        label: context.tr('Sites allowed for hosted decisions'),
        help: context.tr("Only these sites' page text may go to the hosted decision model."),
        values: d.hostedDomains,
        onChanged: (v) => setState(() => _draft = d.copyWith(hostedDomains: v)),
      ),
      _TagsField(
        label: context.tr('Sensitive sites'),
        help: context.tr('Always decided locally, with stricter rules.'),
        values: d.sensitiveDomains,
        onChanged: (v) => setState(() => _draft = d.copyWith(sensitiveDomains: v)),
      ),
      _field(
        context,
        context.tr('Text writer model'),
        _llmModelField(context,
            value: d.textModel, configs: llm, onChanged: (v) => setState(() => _draft = d.copyWith(textModel: () => v))),
      ),
      _field(
        context,
        context.tr('Fallback model'),
        _llmModelField(context,
            value: d.fallbackModel,
            configs: llm,
            onChanged: (v) => setState(() => _draft = d.copyWith(fallbackModel: () => v))),
      ),
    ]);
  }

  Widget _sitesGroup(BuildContext context) {
    final d = _draft;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _groupHeading(context, context.tr('Sites')),
      _DomainDriversField(
        label: context.tr('Browser per site'),
        value: d.domainDrivers,
        onChanged: (v) => setState(() => _draft = d.copyWith(domainDrivers: v)),
      ),
    ]);
  }

  Widget _bandColumn(BuildContext context, String label, BrowserBands b, TextEditingController act,
      TextEditingController fallback, ValueChanged<BrowserBands> onChanged) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label,
          style: TextStyle(color: context.colors.textSecondary, fontWeight: FontWeight.w700, fontSize: 12.5)),
      const SizedBox(height: AppTokens.s8),
      _field(
        context,
        context.tr('Act at or above'),
        SizedBox(
          width: 100,
          child: TextField(
            controller: act,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(isDense: true),
            onChanged: (v) {
              final n = double.tryParse(v);
              if (n != null) onChanged(b.copyWith(act: n.clamp(0, 1)));
            },
          ),
        ),
      ),
      _field(
        context,
        context.tr('Ask the LLM at or above'),
        SizedBox(
          width: 100,
          child: TextField(
            controller: fallback,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(isDense: true),
            onChanged: (v) {
              final n = double.tryParse(v);
              if (n != null) onChanged(b.copyWith(fallback: n.clamp(0, 1)));
            },
          ),
        ),
      ),
    ]);
  }

  Widget _advancedGroup(BuildContext context) {
    final d = _draft;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _groupHeading(context, context.tr('Advanced')),
      Text(context.tr('Confidence bands'),
          style: TextStyle(color: context.colors.textPrimary, fontWeight: FontWeight.w600)),
      const SizedBox(height: AppTokens.s8),
      LayoutBuilder(builder: (context, box) {
        final local = _bandColumn(context, context.tr('Local'), d.bandsLocal, _bandsLocalAct,
            _bandsLocalFallback, (b) => setState(() => _draft = d.copyWith(bandsLocal: b)));
        final hosted = _bandColumn(context, context.tr('Hosted'), d.bandsHosted, _bandsHostedAct,
            _bandsHostedFallback, (b) => setState(() => _draft = d.copyWith(bandsHosted: b)));
        if (box.maxWidth < 560) {
          return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [local, const SizedBox(height: AppTokens.s12), hosted]);
        }
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: local),
          const SizedBox(width: AppTokens.s24),
          Expanded(child: hosted),
        ]);
      }),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final llm = ref.watch(llmConfigsProvider).valueOrNull?.configs ?? const [];
    final border = context.colors.border;
    return decisionCard(
      context,
      title: context.tr('Settings'),
      icon: Icons.tune,
      trailing: FilledButton.icon(
        onPressed: _dirty && !_saving ? _save : null,
        icon: _saving
            ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.save_outlined, size: 16),
        label: Text(context.tr('Save')),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _generalGroup(context),
        Divider(color: border, height: AppTokens.s24),
        _decisionsGroup(context, llm),
        Divider(color: border, height: AppTokens.s24),
        _sitesGroup(context),
        Divider(color: border, height: AppTokens.s24),
        _advancedGroup(context),
      ]),
    );
  }
}

/// A string list edited as chips: type + Enter (or press Add site) to add,
/// tap a chip's × to remove. Used for `hostedDomains` / `sensitiveDomains`.
class _TagsField extends StatefulWidget {
  const _TagsField({required this.label, required this.help, required this.values, required this.onChanged});
  final String label;
  final String help;
  final List<String> values;
  final ValueChanged<List<String>> onChanged;

  @override
  State<_TagsField> createState() => _TagsFieldState();
}

class _TagsFieldState extends State<_TagsField> {
  final _input = TextEditingController();

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _add() {
    final v = _input.text.trim();
    if (v.isEmpty || widget.values.contains(v)) return;
    widget.onChanged([...widget.values, v]);
    _input.clear();
  }

  void _remove(String v) => widget.onChanged([for (final d in widget.values) if (d != v) d]);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTokens.s12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(widget.label, style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.w600, fontSize: 13)),
        const SizedBox(height: AppTokens.s4),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _input,
              decoration: const InputDecoration(isDense: true, hintText: 'example.com'),
              onSubmitted: (_) => _add(),
            ),
          ),
          const SizedBox(width: AppTokens.s8),
          OutlinedButton(onPressed: _add, child: Text(context.tr('Add site'))),
        ]),
        if (widget.values.isNotEmpty) ...[
          const SizedBox(height: AppTokens.s8),
          Wrap(
            spacing: AppTokens.s8,
            runSpacing: AppTokens.s8,
            children: [
              for (final v in widget.values)
                Chip(
                  label: Text(v, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                  onDeleted: () => _remove(v),
                ),
            ],
          ),
        ],
        const SizedBox(height: AppTokens.s4),
        Text(widget.help, style: TextStyle(color: c.textMuted, fontSize: 12)),
      ]),
    );
  }
}

/// `domainDrivers` — host → driver rows, each with its own driver picker and
/// a remove button, plus a row to add a new host.
class _DomainDriversField extends StatefulWidget {
  const _DomainDriversField({required this.label, required this.value, required this.onChanged});
  final String label;
  final Map<String, String> value;
  final ValueChanged<Map<String, String>> onChanged;

  @override
  State<_DomainDriversField> createState() => _DomainDriversFieldState();
}

class _DomainDriversFieldState extends State<_DomainDriversField> {
  final _host = TextEditingController();

  @override
  void dispose() {
    _host.dispose();
    super.dispose();
  }

  void _add() {
    final h = _host.text.trim();
    if (h.isEmpty || widget.value.containsKey(h)) return;
    widget.onChanged({...widget.value, h: 'managed'});
    _host.clear();
  }

  void _setDriver(String host, String driver) => widget.onChanged({...widget.value, host: driver});

  void _remove(String host) =>
      widget.onChanged({for (final e in widget.value.entries) if (e.key != host) e.key: e.value});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final hosts = widget.value.keys.toList()..sort();
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTokens.s12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(widget.label, style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.w600, fontSize: 13)),
        const SizedBox(height: AppTokens.s8),
        for (final h in hosts) _row(context, h),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _host,
              decoration: const InputDecoration(isDense: true, hintText: 'mail.google.com'),
              onSubmitted: (_) => _add(),
            ),
          ),
          const SizedBox(width: AppTokens.s8),
          OutlinedButton.icon(
            onPressed: _add,
            icon: const Icon(Icons.add, size: 16),
            label: Text(context.tr('Add site')),
          ),
        ]),
      ]),
    );
  }

  Widget _row(BuildContext context, String host) {
    final driver = widget.value[host] ?? 'managed';
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTokens.s8),
      child: Row(children: [
        Expanded(
            child: Text(host,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5),
                overflow: TextOverflow.ellipsis)),
        const SizedBox(width: AppTokens.s8),
        SizedBox(
          width: 220,
          child: DropdownButton<String>(
            isExpanded: true,
            value: driver,
            items: [
              DropdownMenuItem(
                  value: 'managed',
                  child: Text(context.tr("SenClaw's own Chrome"), overflow: TextOverflow.ellipsis)),
              DropdownMenuItem(
                  value: 'extension',
                  child: Text(context.tr('Your Chrome (extension)'), overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (v) => _setDriver(host, v ?? 'managed'),
          ),
        ),
        IconButton(
          tooltip: context.tr('Remove'),
          onPressed: () => _remove(host),
          icon: const Icon(Icons.delete_outline, size: 18, color: AppTokens.danger),
        ),
      ]),
    );
  }
}

// ── Chrome extension pairing ─────────────────────────────────────────────

class _ExtensionCard extends ConsumerStatefulWidget {
  const _ExtensionCard();
  @override
  ConsumerState<_ExtensionCard> createState() => _ExtensionCardState();
}

class _ExtensionCardState extends ConsumerState<_ExtensionCard> {
  Timer? _poll;

  /// The pairing code or ext_id an Approve/Remove is in flight for.
  String? _pending;

  @override
  void initState() {
    super.initState();
    // Cheap and never starts the runtime, unlike `tabs` below — safe to
    // poll for as long as this card is on screen.
    _poll = Timer.periodic(const Duration(seconds: 3), (_) => ref.invalidate(browserExtensionProvider));
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  void _toast(String msg) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _approve(String code) async {
    // Resolved before the await: reading `context` after one is only valid
    // while still mounted, and the widget can be disposed mid-request.
    final connected = context.tr('Connected');
    setState(() => _pending = code);
    try {
      final r = await ref
          .read(apiClientProvider)
          .post('/api/browser-agent/extension/pairings/$code/approve');
      final extId = r is Map ? '${r['paired'] ?? ''}' : '';
      ref.invalidate(browserExtensionProvider);
      _toast('$connected $extId');
    } on ApiException catch (e) {
      _toast(e.message);
    } catch (e) {
      _toast('$e');
    } finally {
      if (mounted) setState(() => _pending = null);
    }
  }

  Future<void> _remove(String extId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('Remove')),
        content: Text('$extId\n${ctx.tr('This browser will need to pair again.')}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.tr('Cancel'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTokens.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(ctx.tr('Remove')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _pending = extId);
    try {
      await ref.read(apiClientProvider).delete('/api/browser-agent/extension/paired/$extId');
      ref.invalidate(browserExtensionProvider);
    } on ApiException catch (e) {
      _toast(e.message);
    } catch (e) {
      _toast('$e');
    } finally {
      if (mounted) setState(() => _pending = null);
    }
  }

  Widget _connectedRow(BuildContext context, BrowserExtensionConnected? conn) {
    final c = context.colors;
    if (conn == null) {
      return DecisionChip(context.tr('Not connected'), color: c.textMuted);
    }
    return Wrap(spacing: AppTokens.s8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
      DecisionChip(context.tr('Connected'), color: AppTokens.success, icon: Icons.check_circle_outline),
      Text('${conn.extId} · v${conn.version} · Chrome ${conn.chrome}',
          style: TextStyle(color: c.textMuted, fontSize: 12, fontFamily: 'monospace')),
    ]);
  }

  Widget _pendingRow(BuildContext context, BrowserExtensionPending p) {
    final c = context.colors;
    final busy = _pending == p.code;
    return Container(
      margin: const EdgeInsets.only(bottom: AppTokens.s8),
      padding: const EdgeInsets.all(AppTokens.s8),
      decoration: BoxDecoration(border: Border.all(color: c.border), borderRadius: BorderRadius.circular(AppTokens.rSm)),
      child: Row(children: [
        SizedBox(
          width: 96,
          child: SelectableText(p.code,
              style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w600, letterSpacing: 1)),
        ),
        Expanded(
            child: Text('${p.extId} · ${p.ageSecs}s',
                style: TextStyle(color: c.textMuted, fontSize: 11.5, fontFamily: 'monospace'),
                overflow: TextOverflow.ellipsis)),
        FilledButton(
          onPressed: busy ? null : () => _approve(p.code),
          child: Text(context.tr('Approve')),
        ),
      ]),
    );
  }

  Widget _pairedRow(BuildContext context, BrowserExtensionPaired p) {
    final c = context.colors;
    final busy = _pending == p.extId;
    return Container(
      margin: const EdgeInsets.only(bottom: AppTokens.s8),
      padding: const EdgeInsets.all(AppTokens.s8),
      decoration: BoxDecoration(border: Border.all(color: c.border), borderRadius: BorderRadius.circular(AppTokens.rSm)),
      child: Row(children: [
        Expanded(
            child: Text('${p.extId}\n${p.pairedAt}',
                style: TextStyle(color: c.textPrimary, fontSize: 12, fontFamily: 'monospace'))),
        OutlinedButton(
          onPressed: busy ? null : () => _remove(p.extId),
          child: Text(context.tr('Remove')),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final async = ref.watch(browserExtensionProvider);
    return decisionCard(
      context,
      title: context.tr('Chrome extension'),
      icon: Icons.extension_outlined,
      child: async.when(
        // A failed 3s poll keeps showing the last good state instead of
        // flashing an error over what may just be a transient hiccup.
        skipError: true,
        loading: () => const LinearProgressIndicator(),
        error: (e, _) =>
            decisionNotice(context, e is ApiException ? e.message : '$e', tone: AppTokens.danger),
        data: (state) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _connectedRow(context, state.connected),
          const SizedBox(height: AppTokens.s12),
          Text(
            context.tr(
                'Install the SenClaw extension in Chrome and open its side panel; its pairing code appears here — or send `pair approve <CODE>` in any chat.'),
            style: TextStyle(color: c.textMuted, fontSize: 12),
          ),
          if (state.pending.isNotEmpty) ...[
            const SizedBox(height: AppTokens.s12),
            Text(context.tr('Waiting to pair'),
                style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.w600)),
            const SizedBox(height: AppTokens.s8),
            for (final p in state.pending) _pendingRow(context, p),
          ],
          if (state.paired.isNotEmpty) ...[
            const SizedBox(height: AppTokens.s12),
            Text(context.tr('Paired browsers'),
                style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.w600)),
            const SizedBox(height: AppTokens.s8),
            for (final p in state.paired) _pairedRow(context, p),
          ],
        ]),
      ),
    );
  }
}

// ── Activity (on demand — GET tabs starts the runtime) ───────────────────

class _ActivityCard extends ConsumerStatefulWidget {
  const _ActivityCard();
  @override
  ConsumerState<_ActivityCard> createState() => _ActivityCardState();
}

class _ActivityCardState extends ConsumerState<_ActivityCard> {
  bool _loading = false;
  BrowserTabsState? _tabs;
  Object? _error;

  Future<void> _show() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await ref.read(apiClientProvider).get('/api/browser-agent/tabs');
      if (!mounted) return;
      setState(() => _tabs = BrowserTabsState.fromJson((r as Map).cast<String, dynamic>()));
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _tabRow(BuildContext context, BrowserTab t) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTokens.s4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
            width: 120,
            child: Text(t.owner, style: TextStyle(color: c.textSecondary, fontSize: 12), overflow: TextOverflow.ellipsis)),
        Expanded(
            child: Text(t.url,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12), overflow: TextOverflow.ellipsis)),
        const SizedBox(width: AppTokens.s8),
        DecisionChip(context.tr(t.hold)),
      ]),
    );
  }

  Widget _sessionBlock(BuildContext context, BrowserSession s) {
    final c = context.colors;
    if (s.tabs.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: AppTokens.s12),
      padding: const EdgeInsets.all(AppTokens.s12),
      decoration:
          BoxDecoration(color: c.bg, border: Border.all(color: c.border), borderRadius: BorderRadius.circular(AppTokens.rMd)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${context.tr(s.driver)} · ${s.profile}',
            style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.w600)),
        const SizedBox(height: AppTokens.s8),
        for (final t in s.tabs) _tabRow(context, t),
      ]),
    );
  }

  Widget _body(BuildContext context) {
    final c = context.colors;
    if (_error != null) {
      final missing = runtimeMissingFrom(_error!);
      if (missing != null) return RuntimeMissingBanner(error: missing);
      return decisionNotice(context, _error is ApiException ? (_error as ApiException).message : '$_error',
          tone: AppTokens.danger);
    }
    final tabs = _tabs;
    if (tabs == null) return const SizedBox.shrink();
    if (!tabs.sessions.any((s) => s.tabs.isNotEmpty)) {
      return Text(context.tr('No open tabs'), style: TextStyle(color: c.textMuted, fontSize: 12));
    }
    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [for (final s in tabs.sessions) _sessionBlock(context, s)]);
  }

  @override
  Widget build(BuildContext context) {
    return decisionCard(
      context,
      title: context.tr('Activity'),
      icon: Icons.list_alt_outlined,
      trailing: FilledButton.icon(
        onPressed: _loading ? null : _show,
        icon: _loading
            ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.visibility_outlined, size: 16),
        label: Text(context.tr('Show open tabs')),
      ),
      child: _body(context),
    );
  }
}
