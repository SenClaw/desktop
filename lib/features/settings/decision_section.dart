// Settings → Decision (Laya): choose how typed decisions run (a Laya checkpoint
// on this machine, or Jev online), manage the checkpoints the daemon runs on
// ONNX Runtime (download / import / load / unload / delete) and try them.
// The web page is `web/src/components/settings/DecisionSettings.tsx`; the
// daemon side is `src/decision/laya/`. Guide: docs/laya-decisions.md.

import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/i18n/l10n.dart';
import '../../core/transport/api_client.dart' show ApiClient, ApiException;
import '../../core/transport/connection.dart';
import '../../core/transport/runtime_missing.dart';
import '../../theme/tokens.dart';
import '../../widgets/runtime_missing_banner.dart';
import 'decision_gate.dart';
import 'decision_models.dart';
import 'decision_playground.dart';
import 'decision_run_settings.dart';
import 'decision_skills.dart';
import 'decision_widgets.dart';
import 'settings_screen.dart' show SettingsBody;

final decisionModelsProvider = FutureProvider<LayaModelList>((ref) async {
  final r = await ref.read(apiClientProvider).get('/api/decision/models');
  return LayaModelList.fromJson((r as Map).cast<String, dynamic>());
});

/// Letters, digits, `.`, `_`, `-` — a model id names a directory.
final _idPattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$');

class DecisionSection extends ConsumerStatefulWidget {
  const DecisionSection({super.key});

  @override
  ConsumerState<DecisionSection> createState() => _DecisionSectionState();
}

class _DecisionSectionState extends ConsumerState<DecisionSection> {
  Timer? _poll;
  Duration? _pollEvery;

  /// Model id → the action a button of that row is waiting on.
  final _pending = <String, String>{};

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  /// Refresh every second while anything downloads, copies or loads; every
  /// 15 s while a model sits in RAM, so an idle unload shows up without a
  /// click; not at all otherwise.
  void _syncPoll(LayaModelList list) {
    final every = list.models.any((m) => m.busy) || _pending.isNotEmpty
        ? const Duration(seconds: 1)
        : list.models.any((m) => m.loaded != null)
            ? const Duration(seconds: 15)
            : null;
    if (every == _pollEvery) return;
    _poll?.cancel();
    _poll = every == null ? null : Timer.periodic(every, (_) => ref.invalidate(decisionModelsProvider));
    _pollEvery = every;
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _act(LayaModel m, String action, Future<void> Function(ApiClient api) run) async {
    setState(() => _pending[m.id] = action);
    // A long load answers only when the weights are in RAM; refresh right
    // away so the row shows "loading" while it waits.
    Timer(const Duration(milliseconds: 200), () {
      if (mounted) ref.invalidate(decisionModelsProvider);
    });
    try {
      await run(ref.read(apiClientProvider));
    } on ApiException catch (e) {
      _toast(e.message);
    } catch (e) {
      _toast('$e');
    } finally {
      // `ref` is unusable once the section is gone (someone left mid-load).
      if (mounted) {
        setState(() => _pending.remove(m.id));
        ref.invalidate(decisionModelsProvider);
      }
    }
  }

  Future<void> _load(LayaModel m) => _act(m, 'load', (api) async {
        final r = await api.post('/api/decision/models/${m.id}/load');
        final ms = r is Map && r['loaded'] is Map ? (r['loaded']['load_ms'] as num? ?? 0) : 0;
        if (mounted) {
          _toast(context.trArgs('Loaded {name} in {s} s', {'name': m.label, 's': decisionNum(context, ms / 1000)}));
        }
      });

  Future<void> _unload(LayaModel m) => _act(m, 'unload', (api) async {
        await api.post('/api/decision/models/${m.id}/unload');
        if (mounted) _toast(context.trArgs('Unloaded {name} from RAM', {'name': m.label}));
      });

  Future<void> _download(LayaModel m) => _act(m, 'download', (api) async {
        await api.post('/api/decision/models/${m.id}/download');
        if (mounted) _toast(context.trArgs('Downloading {name}', {'name': m.label}));
      });

  Future<void> _cancel(LayaModel m) =>
      _act(m, 'cancel', (api) => api.post('/api/decision/models/${m.id}/cancel'));

  void _refreshAll() {
    ref.invalidate(decisionModelsProvider);
    ref.invalidate(decisionSettingsProvider);
    ref.invalidate(decisionGateProvider);
    ref.invalidate(decisionSkillsProvider);
  }

  Future<void> _delete(LayaModel m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.trArgs('Delete {name}?', {'name': m.label})),
        content: Text(m.loaded != null
            ? ctx.tr('It is unloaded from RAM first, then its files are deleted.')
            : ctx.tr('Its files are deleted from disk.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.tr('Cancel'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTokens.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(ctx.tr('Delete')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _act(m, 'delete', (api) async {
      final r = await api.delete('/api/decision/models/${m.id}');
      final cleared = r is Map && r['defaultCleared'] == true;
      if (cleared && mounted) ref.invalidate(decisionSettingsProvider);
      if (mounted) {
        _toast(cleared
            ? context.trArgs('Deleted {name}; the default model is back to Pick by language', {'name': m.label})
            : context.trArgs('Deleted {name}', {'name': m.label}));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final async = ref.watch(decisionModelsProvider);
    return SettingsBody(
      title: context.tr('Decision (Laya)'),
      onRefresh: _refreshAll,
      children: [
        Text(
          context.tr(
              'Laya is an open "System One" model, compatible with Jev: it does not write text, it answers typed questions — choice (pick a label), score (place on a rubric), noul (how likely a statement holds) — with probabilities. It runs inside the daemon on ONNX Runtime (CPU); a loaded model holds about its own size in RAM. For Vietnamese, use the Multilingual model: the English one reads Vietnamese wrong and still sounds sure.'),
          style: TextStyle(color: c.textMuted, fontSize: 12),
        ),
        const SizedBox(height: AppTokens.s16),
        // A failed poll keeps showing the last list: switching to the error
        // branch would unmount the settings card and lose unsaved edits.
        async.when(
          skipError: true,
          loading: () => const LinearProgressIndicator(),
          error: (e, _) {
            final missing = runtimeMissingFrom(e);
            if (missing != null) {
              // The gate and skills routes stay in the daemon and answer with
              // no sen-sysone at all (runtime-protocol.md §5.2) — only the
              // model list and playground need the decision runtime, so only
              // they get replaced by the banner.
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RuntimeMissingBanner(error: missing),
                  const SizedBox(height: AppTokens.s16),
                  const DecisionGateCard(),
                  const DecisionSkillsCard(),
                ],
              );
            }
            return decisionNotice(context, e is ApiException ? e.message : '$e', tone: AppTokens.danger);
          },
          data: (list) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _syncPoll(list);
            });
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DecisionRunSettingsCard(
                  installed: list.models,
                  onSaved: () => ref.invalidate(decisionModelsProvider),
                ),
                decisionCard(
                  context,
                  title: context.tr('Models'),
                  icon: Icons.memory_outlined,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final m in list.models)
                        _ModelRow(
                          model: m,
                          compiled: list.compiled,
                          isDefault: list.local.defaultModel == m.id,
                          idleUnloadMinutes: list.local.idleUnloadMinutes,
                          pending: _pending[m.id],
                          onDownload: () => _download(m),
                          onCancel: () => _cancel(m),
                          onLoad: () => _load(m),
                          onUnload: () => _unload(m),
                          onDelete: () => _delete(m),
                        ),
                      if (list.root.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: AppTokens.s4),
                          child: SelectableText(context.trArgs('Stored in {path}', {'path': list.root}),
                              style: TextStyle(color: c.textMuted, fontSize: 11.5, fontFamily: 'monospace')),
                        ),
                    ],
                  ),
                ),
                DecisionPlayground(
                  models: list.models,
                  compiled: list.compiled,
                  backend: list.backend,
                  local: list.local,
                  onAsked: () => ref.invalidate(decisionModelsProvider),
                ),
                const DecisionGateCard(),
                const DecisionSkillsCard(),
                _ImportCard(onStarted: () => ref.invalidate(decisionModelsProvider)),
                _CustomRepoCard(onStarted: () => ref.invalidate(decisionModelsProvider)),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _ModelRow extends StatelessWidget {
  const _ModelRow({
    required this.model,
    required this.compiled,
    required this.isDefault,
    required this.idleUnloadMinutes,
    required this.pending,
    required this.onDownload,
    required this.onCancel,
    required this.onLoad,
    required this.onUnload,
    required this.onDelete,
  });

  final LayaModel model;
  final bool compiled;

  /// Settings name this model as the default.
  final bool isDefault;

  /// The idle-unload limit, for the countdown on a loaded row (0 = never).
  final int idleUnloadMinutes;
  final String? pending;
  final VoidCallback onDownload;
  final VoidCallback onCancel;
  final VoidCallback onLoad;
  final VoidCallback onUnload;
  final VoidCallback onDelete;

  Widget _spinner() => const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2));

  Widget _status(BuildContext context) {
    final c = context.colors;
    final m = model;
    final j = m.job;
    final small = TextStyle(color: c.textMuted, fontSize: 12);
    if (j != null && j.active) {
      final verb = switch (j.status) {
        'verifying' => context.tr('checking sha256'),
        'copying' => context.tr('copying'),
        'listing' => context.tr('listing files'),
        _ => context.tr('downloading'),
      };
      final size = j.totalBytes > 0
          ? '${decisionBytes(context, j.doneBytes)} / ${decisionBytes(context, j.totalBytes)}'
          : decisionBytes(context, j.doneBytes);
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        LinearProgressIndicator(value: j.progress ?? 0, minHeight: 4),
        const SizedBox(height: 4),
        Text('$verb ${j.currentFile ?? ''} · $size', style: small, maxLines: 1, overflow: TextOverflow.ellipsis),
      ]);
    }
    if (m.loading || pending == 'load') {
      return Row(children: [
        _spinner(),
        const SizedBox(width: AppTokens.s8),
        Text(context.tr('Loading into RAM…'), style: small),
      ]);
    }
    if (m.loaded != null) {
      final l = m.loaded!;
      final left = idleUnloadMinutes * 60 - l.idleSecs;
      return Wrap(spacing: AppTokens.s8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
        DecisionChip(context.tr('Loaded'), color: AppTokens.success, icon: Icons.bolt),
        if (l.onDemand)
          Tooltip(
            message: context.tr('A request loaded it on demand, not the Load button.'),
            child: DecisionChip(context.tr('on demand'), color: AppTokens.cyan),
          ),
        Text(
          context.trArgs('loaded in {s} s · {threads} threads · {batch} · {n} asks', {
            's': decisionNum(context, l.loadMs / 1000),
            'threads': l.threads,
            'batch': l.fixedBatch ? context.tr('fixed batch of 1') : context.tr('dynamic batch'),
            'n': l.asks,
          }),
          style: small,
        ),
        if (idleUnloadMinutes > 0)
          Text(
            left <= 30
                ? context.tr('unloading soon for lack of use')
                : context.trArgs('unloads in ~{n} min if unused', {'n': (left / 60).ceil()}),
            style: small,
          ),
      ]);
    }
    if (m.installed) {
      return DecisionChip(context.tr('Installed'), color: AppTokens.brand, icon: Icons.download_done);
    }
    if (j?.status == 'error') {
      return Text(context.trArgs('Error: {e}', {'e': j!.error ?? ''}),
          style: const TextStyle(color: AppTokens.danger, fontSize: 12));
    }
    if (j?.status == 'cancelled') {
      return Text(context.tr('Cancelled — press Download to resume'),
          style: const TextStyle(color: AppTokens.warning, fontSize: 12));
    }
    return Text(context.tr('Not installed'), style: small);
  }

  List<Widget> _actions(BuildContext context) {
    final m = model;
    final busy = pending != null;
    return [
      if (!m.installed && !m.jobActive && m.catalog)
        FilledButton.icon(
          onPressed: busy ? null : onDownload,
          icon: const Icon(Icons.download, size: 16),
          label: Text(context.tr('Download')),
        ),
      if (m.jobActive)
        OutlinedButton.icon(
          onPressed: busy ? null : onCancel,
          icon: const Icon(Icons.stop_circle_outlined, size: 16),
          label: Text(context.tr('Cancel')),
        ),
      if (m.installed && m.loaded == null)
        FilledButton.icon(
          onPressed: busy || m.loading || !compiled ? null : onLoad,
          icon: pending == 'load' || m.loading ? _spinner() : const Icon(Icons.play_arrow_rounded, size: 16),
          label: Text(context.tr('Load')),
        ),
      if (m.loaded != null)
        OutlinedButton.icon(
          onPressed: busy ? null : onUnload,
          icon: const Icon(Icons.power_settings_new, size: 16),
          label: Text(context.tr('Unload from RAM')),
        ),
      if ((m.installed || m.sizeBytes > 0 || m.job != null) && !m.jobActive)
        IconButton(
          tooltip: context.tr('Delete'),
          onPressed: busy || m.loading ? null : onDelete,
          icon: const Icon(Icons.delete_outline, size: 18, color: AppTokens.danger),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final m = model;
    final size = m.sizeBytes > 0
        ? decisionBytes(context, m.sizeBytes)
        : m.approxSizeMb != null
            ? '~${decisionNum(context, m.approxSizeMb! / 1024)} GB'
            : null;
    final meta = TextStyle(color: c.textMuted, fontSize: 11.5, fontFamily: 'monospace');
    final repo = m.repo;

    return Container(
      margin: const EdgeInsets.only(bottom: AppTokens.s8),
      padding: const EdgeInsets.all(AppTokens.s12),
      decoration: BoxDecoration(
        color: c.bg,
        border: Border.all(color: m.loaded != null ? AppTokens.success.withValues(alpha: 0.5) : c.border),
        borderRadius: BorderRadius.circular(AppTokens.rMd),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(
            m.loaded != null
                ? Icons.bolt
                : m.installed
                    ? Icons.download_done
                    : Icons.cloud_outlined,
            size: 18,
            color: m.loaded != null
                ? AppTokens.success
                : m.installed
                    ? AppTokens.brand
                    : c.textMuted,
          ),
        ),
        const SizedBox(width: AppTokens.s12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: AppTokens.s8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text(m.label, style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.w600)),
              if (m.kind == 'multilingual') DecisionChip(context.tr('Multilingual'), color: AppTokens.cyan),
              if (m.kind == 'english') const DecisionChip('English'),
              if (!m.catalog) DecisionChip(context.tr('custom')),
              if (isDefault) DecisionChip(context.tr('default'), color: AppTokens.warning, icon: Icons.star_rounded),
              if (size != null) Text(size, style: TextStyle(color: c.textMuted, fontSize: 12)),
            ]),
            if (m.description.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(m.description, style: TextStyle(color: c.textSecondary, fontSize: 12)),
            ],
            const SizedBox(height: 4),
            Wrap(spacing: AppTokens.s8, children: [
              Text(m.id, style: meta),
              if (repo != null)
                InkWell(
                  onTap: () => launchUrl(Uri.parse(m.sourcePage), mode: LaunchMode.externalApplication),
                  child: Text('$repo@${m.revisionLabel}',
                      style: meta.copyWith(color: AppTokens.brand, decoration: TextDecoration.underline)),
                ),
              if (m.sourcePath != null) Text(context.trArgs('from folder {path}', {'path': m.sourcePath!}), style: meta),
            ]),
            const SizedBox(height: AppTokens.s8),
            _status(context),
          ]),
        ),
        const SizedBox(width: AppTokens.s12),
        Wrap(spacing: AppTokens.s8, runSpacing: AppTokens.s8, crossAxisAlignment: WrapCrossAlignment.center, children: _actions(context)),
      ]),
    );
  }
}

/// Copy an export already on disk into the model store (a clone on APFS).
class _ImportCard extends ConsumerStatefulWidget {
  const _ImportCard({required this.onStarted});
  final VoidCallback onStarted;

  @override
  ConsumerState<_ImportCard> createState() => _ImportCardState();
}

class _ImportCardState extends ConsumerState<_ImportCard> {
  final _path = TextEditingController();
  final _id = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _path.dispose();
    _id.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final dir = await FilePicker.platform.getDirectoryPath(dialogTitle: context.tr('Choose a Laya export folder'));
    if (dir != null) setState(() => _path.text = dir);
  }

  Future<void> _import() async {
    final path = _path.text.trim();
    final id = _id.text.trim();
    if (path.isEmpty) return;
    if (id.isNotEmpty && !_idPattern.hasMatch(id)) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(context.tr('An id uses letters, digits, . _ - only'))));
      return;
    }
    setState(() => _busy = true);
    try {
      final r = await ref.read(apiClientProvider).post('/api/decision/models/import', body: {
        'path': path,
        if (id.isNotEmpty) 'id': id,
      });
      if (!mounted) return;
      widget.onStarted();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(context.trArgs('Importing {id}', {'id': r is Map ? '${r['id']}' : id}))));
      }
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return decisionCard(
      context,
      title: context.tr('Import from a folder'),
      icon: Icons.folder_open_outlined,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
          context.tr(
              'For an export already on this Mac (for instance one made with the laya Python package). The folder needs the ONNX graph (laya.onnx or onnx/model.onnx), the head config (rl_agent_config.json or laya_config.json) and tokenizer/. On the same APFS volume the copy is a clone: instant, no extra disk.'),
          style: TextStyle(color: c.textMuted, fontSize: 12),
        ),
        const SizedBox(height: AppTokens.s12),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _path,
              decoration: InputDecoration(labelText: context.tr('Folder'), hintText: '/Users/…/models/multilingual', isDense: true),
            ),
          ),
          const SizedBox(width: AppTokens.s8),
          OutlinedButton.icon(
            onPressed: _pick,
            icon: const Icon(Icons.folder_outlined, size: 16),
            label: Text(context.tr('Choose…')),
          ),
          const SizedBox(width: AppTokens.s8),
          SizedBox(
            width: 200,
            child: TextField(
              controller: _id,
              decoration: InputDecoration(labelText: context.tr('id (default: folder name)'), isDense: true),
            ),
          ),
          const SizedBox(width: AppTokens.s8),
          FilledButton(
            onPressed: _busy ? null : _import,
            child: Text(context.tr('Import')),
          ),
        ]),
      ]),
    );
  }
}

/// Download any Hugging Face repo that has the Laya export layout.
class _CustomRepoCard extends ConsumerStatefulWidget {
  const _CustomRepoCard({required this.onStarted});
  final VoidCallback onStarted;

  @override
  ConsumerState<_CustomRepoCard> createState() => _CustomRepoCardState();
}

class _CustomRepoCardState extends ConsumerState<_CustomRepoCard> {
  final _id = TextEditingController();
  final _repo = TextEditingController();
  final _revision = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _id.dispose();
    _repo.dispose();
    _revision.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final id = _id.text.trim();
    final repo = _repo.text.trim();
    if (!_idPattern.hasMatch(id) || repo.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(context.tr('Give an id (letters, digits, . _ -) and a repo'))));
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(apiClientProvider).post('/api/decision/models/custom', body: {
        'id': id,
        'repo': repo,
        if (_revision.text.trim().isNotEmpty) 'revision': _revision.text.trim(),
      });
      if (!mounted) return;
      widget.onStarted();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(context.trArgs('Downloading {name}', {'name': repo}))));
      }
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return decisionCard(
      context,
      title: context.tr('Download from another Hugging Face repo'),
      icon: Icons.link,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
          context.tr(
              'Any export with the graph, the head config and the tokenizer in the Laya layout. A branch or tag is pinned to its commit when the download starts; LFS files are checked against their sha256.'),
          style: TextStyle(color: c.textMuted, fontSize: 12),
        ),
        const SizedBox(height: AppTokens.s12),
        Row(children: [
          SizedBox(
            width: 180,
            child: TextField(
              controller: _id,
              decoration: InputDecoration(labelText: 'id', hintText: 'laya-int8', isDense: true),
            ),
          ),
          const SizedBox(width: AppTokens.s8),
          Expanded(
            child: TextField(
              controller: _repo,
              decoration: InputDecoration(
                  labelText: context.tr('Repo'), hintText: context.tr('org/name or a huggingface.co URL'), isDense: true),
            ),
          ),
          const SizedBox(width: AppTokens.s8),
          SizedBox(
            width: 140,
            child: TextField(
              controller: _revision,
              decoration: InputDecoration(labelText: context.tr('Revision'), hintText: 'main', isDense: true),
            ),
          ),
          const SizedBox(width: AppTokens.s8),
          FilledButton.icon(
            onPressed: _busy ? null : _start,
            icon: const Icon(Icons.download, size: 16),
            label: Text(context.tr('Download')),
          ),
        ]),
      ]),
    );
  }
}
