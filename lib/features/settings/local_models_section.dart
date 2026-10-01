// Settings → Local models (runtime-protocol.md §5.3): the GGUF/MLX model
// files the daemon manages, run by whichever runtime is selected for their
// format slot. Download from a Hugging Face repo, load/unload/delete, and the
// shared engine settings (temperature, top_k, top_p, …) applied when a model
// has no override of its own.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/shell.dart' show openRuntimeSettings;
import '../../core/i18n/l10n.dart';
import '../../core/transport/api_client.dart' show ApiException;
import '../../core/transport/connection.dart';
import '../../core/transport/runtime_missing.dart';
import '../../theme/tokens.dart';
import '../../widgets/runtime_missing_banner.dart';
import 'decision_widgets.dart';
import 'runtime_models.dart' show RuntimeCandidate, RuntimeProcessInfo;
import 'settings_screen.dart' show SettingsBody;

/// TurboFieldfareRepack's only source. Must match `SupportedModelSource`.
const _gturboRepo = 'mlx-community/gemma-4-26b-a4b-it-4bit';
const _gturboRevision = '0d77464eeb233a2da68ebf9d7dc4edaac7db956d';

Map<String, dynamic> _asMap(dynamic v) => v is Map ? v.cast<String, dynamic>() : {};
List<Map<String, dynamic>> _asMapList(dynamic v) => (v as List? ?? const [])
    .whereType<Map>()
    .map((e) => e.cast<String, dynamic>())
    .toList();

/// `LocalModel.runtime` — the format slot's own selection, so a model with no
/// runtime behind its format can say so instead of just failing to load.
class LocalModelRuntimeRef {
  const LocalModelRuntimeRef({required this.slot, required this.selected});
  final String slot;
  final RuntimeCandidate? selected;

  factory LocalModelRuntimeRef.fromJson(Map<String, dynamic> j) => LocalModelRuntimeRef(
        slot: '${j['slot'] ?? ''}',
        selected: j['selected'] is Map
            ? RuntimeCandidate.fromJson(_asMap(j['selected']))
            : null,
      );
}

class LocalModel {
  const LocalModel({
    required this.key,
    required this.name,
    required this.format,
    required this.path,
    required this.sizeBytes,
    required this.capabilities,
    required this.vision,
    required this.embedding,
    required this.mmprojPath,
    required this.quant,
    required this.repo,
    required this.contextLength,
    required this.runtime,
    required this.process,
  });
  final String key;
  final String name;
  final String format; // gguf | mlx
  final String path;
  final int sizeBytes;
  final List<String> capabilities;
  final bool vision;
  final bool embedding;
  final String? mmprojPath;
  final String? quant;
  final String? repo;
  final int? contextLength;
  final LocalModelRuntimeRef runtime;
  final RuntimeProcessInfo? process;

  bool get loaded => process != null && process!.state == 'ready';
  bool get loading =>
      process != null && (process!.state == 'starting' || process!.state == 'stopping');

  factory LocalModel.fromJson(Map<String, dynamic> j) => LocalModel(
        key: '${j['key'] ?? ''}',
        name: '${j['name'] ?? j['key'] ?? ''}',
        format: '${j['format'] ?? ''}',
        path: '${j['path'] ?? ''}',
        sizeBytes: (j['sizeBytes'] as num?)?.toInt() ?? 0,
        capabilities:
            (j['capabilities'] as List? ?? const []).map((e) => '$e').toList(),
        vision: j['vision'] == true,
        embedding: j['embedding'] == true,
        mmprojPath: j['mmprojPath'] as String?,
        quant: j['quant'] as String?,
        repo: j['repo'] as String?,
        contextLength: (j['contextLength'] as num?)?.toInt(),
        runtime: LocalModelRuntimeRef.fromJson(_asMap(j['runtime'])),
        process: j['process'] is Map
            ? RuntimeProcessInfo.fromJson(_asMap(j['process']))
            : null,
      );
}

class LocalModelDownload {
  const LocalModelDownload({
    required this.downloadId,
    required this.repo,
    required this.files,
    required this.format,
    required this.state,
    required this.receivedBytes,
    required this.totalBytes,
    required this.percent,
    required this.error,
  });
  final String downloadId;
  final String repo;
  final List<String> files;
  final String format;
  final String state; // queued|listing|downloading|done|failed|cancelled
  final int receivedBytes;
  final int totalBytes;
  final double? percent;
  final String? error;

  bool get active => state == 'queued' || state == 'listing' || state == 'downloading';
  bool get failed => state == 'failed';

  factory LocalModelDownload.fromJson(Map<String, dynamic> j) => LocalModelDownload(
        downloadId: '${j['downloadId'] ?? ''}',
        repo: '${j['repo'] ?? ''}',
        files: (j['files'] as List? ?? const []).map((e) => '$e').toList(),
        format: '${j['format'] ?? ''}',
        state: '${j['state'] ?? ''}',
        receivedBytes: (j['receivedBytes'] as num?)?.toInt() ?? 0,
        totalBytes: (j['totalBytes'] as num?)?.toInt() ?? 0,
        percent: (j['percent'] as num?)?.toDouble(),
        error: j['error'] as String?,
      );
}

class LocalModelsData {
  const LocalModelsData({required this.root, required this.models, required this.downloads});
  final String root;
  final List<LocalModel> models;
  final List<LocalModelDownload> downloads;

  factory LocalModelsData.fromJson(Map<String, dynamic> j) => LocalModelsData(
        root: '${j['root'] ?? ''}',
        models: _asMapList(j['models']).map(LocalModel.fromJson).toList(),
        downloads: _asMapList(j['downloads']).map(LocalModelDownload.fromJson).toList(),
      );
}

final localModelsProvider = FutureProvider<LocalModelsData>((ref) async {
  final r = await ref.read(apiClientProvider).get('/api/local-models');
  return LocalModelsData.fromJson(_asMap(r));
});

class LocalModelsSection extends ConsumerStatefulWidget {
  const LocalModelsSection({super.key});

  @override
  ConsumerState<LocalModelsSection> createState() => _LocalModelsSectionState();
}

class _LocalModelsSectionState extends ConsumerState<LocalModelsSection> {
  Timer? _poll;
  final _pending = <String, String>{};

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  void _syncPoll(LocalModelsData data) {
    final active = data.downloads.any((d) => d.active) ||
        data.models.any((m) => m.loading) ||
        _pending.isNotEmpty;
    if (active && _poll == null) {
      _poll = Timer.periodic(const Duration(milliseconds: 1500),
          (_) => ref.invalidate(localModelsProvider));
    } else if (!active && _poll != null) {
      _poll!.cancel();
      _poll = null;
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _act(String key, String action, Future<void> Function() run) async {
    setState(() => _pending[key] = action);
    try {
      await run();
    } on ApiException catch (e) {
      // A 503 here means no runtime backs this model's format — the daemon's
      // own message plus a way to fix it beats a bare toast.
      final missing = runtimeMissingFrom(e);
      if (missing != null && mounted) {
        showRuntimeMissingSnack(context, ref, missing);
      } else {
        _toast(e.message);
      }
    } catch (e) {
      _toast('$e');
    } finally {
      if (mounted) {
        setState(() => _pending.remove(key));
        ref.invalidate(localModelsProvider);
      }
    }
  }

  Future<void> _load(LocalModel m) => _act(m.key, 'load', () async {
        // llama.cpp's own health budget is up to 600s (runtime-protocol.md
        // §3.2); the default 30s API timeout would cut off a real load in
        // progress and misreport it as a dead daemon.
        await ref.read(apiClientProvider).post(
            '/api/local-models/${Uri.encodeComponent(m.key)}/load',
            timeout: const Duration(minutes: 11));
      });

  Future<void> _unload(LocalModel m) => _act(m.key, 'unload', () async {
        await ref
            .read(apiClientProvider)
            .post('/api/local-models/${Uri.encodeComponent(m.key)}/unload');
      });

  Future<void> _delete(LocalModel m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.trArgs('Delete {name}?', {'name': m.name})),
        content: Text(ctx.tr('Its files are deleted from disk.')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.tr('Cancel'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTokens.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(ctx.tr('Delete')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _deleteAttempt(m, force: false);
  }

  /// `force: false` first — a 409 means it's loaded, so offer to unload and
  /// delete anyway rather than just failing (mirrors the runtime catalog's
  /// uninstall-while-running confirm).
  Future<void> _deleteAttempt(LocalModel m, {required bool force}) async {
    setState(() => _pending[m.key] = 'delete');
    try {
      await ref.read(apiClientProvider).delete(
          '/api/local-models/${Uri.encodeComponent(m.key)}${force ? '?force=1' : ''}');
    } on ApiException catch (e) {
      if (e.status == 409 && !force) {
        if (mounted) setState(() => _pending.remove(m.key));
        if (!mounted) return;
        final retry = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(ctx.tr('Unload and delete?')),
            content: Text(e.message),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.tr('Cancel'))),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: AppTokens.danger),
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(ctx.tr('Unload and delete')),
              ),
            ],
          ),
        );
        if (retry == true) return _deleteAttempt(m, force: true);
        return;
      }
      final missing = runtimeMissingFrom(e);
      if (missing != null && mounted) {
        showRuntimeMissingSnack(context, ref, missing);
      } else {
        _toast(e.message);
      }
    } catch (e) {
      _toast('$e');
    } finally {
      if (mounted) {
        setState(() => _pending.remove(m.key));
        ref.invalidate(localModelsProvider);
      }
    }
  }

  Future<void> _cancelDownload(LocalModelDownload d) async {
    try {
      await ref
          .read(apiClientProvider)
          .post('/api/local-models/downloads/${d.downloadId}/cancel');
      ref.invalidate(localModelsProvider);
    } catch (e) {
      _toast('$e');
    }
  }

  Future<void> _downloadGturbo({bool vision = false}) async {
    try {
      await ref.read(apiClientProvider).post('/api/local-models/download', body: {
        'format': 'gturbo',
        'repo': _gturboRepo,
        'revision': _gturboRevision,
        if (vision) 'vision': true,
      });
      ref.invalidate(localModelsProvider);
    } on ApiException catch (e) {
      _toast(e.message);
    } catch (e) {
      _toast('$e');
    }
  }

  Future<void> _openDownloadDialog() async {
    final started =
        await showDialog<bool>(context: context, builder: (_) => const DownloadModelDialog());
    if (started == true) ref.invalidate(localModelsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final async = ref.watch(localModelsProvider);
    return SettingsBody(
      title: context.tr('Local models'),
      onRefresh: () => ref.invalidate(localModelsProvider),
      children: [
        async.when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) {
            final missing = runtimeMissingFrom(e);
            if (missing != null) return RuntimeMissingBanner(error: missing);
            return Text(e is ApiException ? e.message : '$e');
          },
          data: (data) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _syncPoll(data);
            });
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        context.trArgs('Stored in {path}', {'path': data.root}),
                        style: TextStyle(
                            color: c.textMuted, fontSize: 11.5, fontFamily: 'monospace'),
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: _openDownloadDialog,
                      icon: const Icon(Icons.download, size: 16),
                      label: Text(context.tr('Download')),
                    ),
                  ],
                ),
                const SizedBox(height: AppTokens.s8),
                Text(
                  context.tr(
                    'TurboFieldfare runs only Gemma 4 26B-A4B IT 4-bit. Download repacks that checkpoint into a .gturbo directory (about 14.3 GB).',
                  ),
                  style: TextStyle(color: c.textMuted, fontSize: 12),
                ),
                const SizedBox(height: AppTokens.s8),
                Wrap(
                  spacing: AppTokens.s8,
                  runSpacing: AppTokens.s8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => _downloadGturbo(),
                      icon: const Icon(Icons.memory, size: 16),
                      label: Text(context.tr('Download Gemma 4')),
                    ),
                    if (data.models.any((m) => m.format == 'gturbo' && !m.vision))
                      OutlinedButton.icon(
                        onPressed: () => _downloadGturbo(vision: true),
                        icon: const Icon(Icons.image_outlined, size: 16),
                        label: Text(context.tr('Download image pack')),
                      ),
                  ],
                ),
                const SizedBox(height: AppTokens.s12),
                for (final d in data.downloads.where((d) => d.active))
                  _DownloadProgressRow(download: d, onCancel: () => _cancelDownload(d)),
                for (final d in data.downloads.where((d) => d.failed))
                  _DownloadFailedRow(download: d),
                if (data.models.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: AppTokens.s16),
                    child: Text(
                      context.tr('No local models yet — press Download to fetch one.'),
                      style: TextStyle(color: c.textMuted, fontSize: 12.5),
                    ),
                  )
                else
                  for (final m in data.models)
                    _LocalModelRow(
                      model: m,
                      pending: _pending[m.key],
                      onLoad: () => _load(m),
                      onUnload: () => _unload(m),
                      onDelete: () => _delete(m),
                    ),
                const SizedBox(height: AppTokens.s16),
                const LocalModelsSettingsCard(),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _DownloadProgressRow extends StatelessWidget {
  const _DownloadProgressRow({required this.download, required this.onCancel});
  final LocalModelDownload download;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      margin: const EdgeInsets.only(bottom: AppTokens.s8),
      padding: const EdgeInsets.all(AppTokens.s12),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(AppTokens.rMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text(download.repo,
                  style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.w600)),
            ),
            TextButton(onPressed: onCancel, child: Text(context.tr('Cancel'))),
          ]),
          const SizedBox(height: 4),
          LinearProgressIndicator(value: download.percent, minHeight: 4),
          const SizedBox(height: 4),
          Text(
            download.totalBytes > 0
                ? '${decisionBytes(context, download.receivedBytes)} / ${decisionBytes(context, download.totalBytes)}'
                : decisionBytes(context, download.receivedBytes),
            style: TextStyle(color: c.textMuted, fontSize: 11.5),
          ),
        ],
      ),
    );
  }
}

/// A download that ended in `state: "failed"` — shown until superseded by a
/// fresh attempt for the same repo, same shape as a Laya model's job error.
class _DownloadFailedRow extends StatelessWidget {
  const _DownloadFailedRow({required this.download});
  final LocalModelDownload download;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      margin: const EdgeInsets.only(bottom: AppTokens.s8),
      padding: const EdgeInsets.all(AppTokens.s12),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: AppTokens.danger.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(AppTokens.rMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(download.repo,
              style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(
            context.trArgs('Download failed: {e}', {'e': download.error ?? ''}),
            style: const TextStyle(color: AppTokens.danger, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _LocalModelRow extends ConsumerWidget {
  const _LocalModelRow({
    required this.model,
    required this.pending,
    required this.onLoad,
    required this.onUnload,
    required this.onDelete,
  });
  final LocalModel model;
  final String? pending;
  final VoidCallback onLoad;
  final VoidCallback onUnload;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final busy = pending != null;
    final noRuntime = model.runtime.selected == null;
    return Container(
      margin: const EdgeInsets.only(bottom: AppTokens.s8),
      padding: const EdgeInsets.all(AppTokens.s12),
      decoration: BoxDecoration(
        color: c.bg,
        border: Border.all(
            color: model.loaded ? AppTokens.success.withValues(alpha: 0.5) : c.border),
        borderRadius: BorderRadius.circular(AppTokens.rMd),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(model.loaded ? Icons.bolt : Icons.description_outlined,
                size: 18, color: model.loaded ? AppTokens.success : c.textMuted),
          ),
          const SizedBox(width: AppTokens.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: AppTokens.s8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(model.name,
                        style: TextStyle(
                            color: c.textPrimary, fontWeight: FontWeight.w600)),
                    DecisionChip(model.format.toUpperCase(),
                        color: model.format == 'mlx' ? AppTokens.cyan : AppTokens.brand),
                    if (model.vision) DecisionChip(context.tr('vision')),
                    if (model.embedding) DecisionChip(context.tr('embedding')),
                    if (model.quant != null) DecisionChip(model.quant!),
                    Text(decisionBytes(context, model.sizeBytes),
                        style: TextStyle(color: c.textMuted, fontSize: 12)),
                  ],
                ),
                if (model.repo != null) ...[
                  const SizedBox(height: 4),
                  Text(model.repo!,
                      style: TextStyle(
                          color: c.textMuted, fontSize: 11.5, fontFamily: 'monospace')),
                ],
                const SizedBox(height: AppTokens.s4),
                if (model.loaded)
                  DecisionChip(context.tr('Loaded'), color: AppTokens.success, icon: Icons.bolt)
                else if (model.loading || pending == 'load')
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    const SizedBox(
                        width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                    const SizedBox(width: AppTokens.s8),
                    Text(context.tr('Loading…'), style: TextStyle(color: c.textMuted, fontSize: 12)),
                  ]),
                if (noRuntime) ...[
                  const SizedBox(height: AppTokens.s4),
                  InkWell(
                    onTap: () => openRuntimeSettings(context, ref),
                    child: Text(
                      context.trArgs(
                          'No runtime selected for {format} — open Runtime settings ›',
                          {'format': model.format.toUpperCase()}),
                      style: const TextStyle(
                          color: AppTokens.warning,
                          fontSize: 12,
                          decoration: TextDecoration.underline),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppTokens.s12),
          Wrap(
            spacing: AppTokens.s8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (!model.loaded)
                FilledButton.icon(
                  onPressed: busy || noRuntime ? null : onLoad,
                  icon: pending == 'load'
                      ? const SizedBox(
                          width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.play_arrow_rounded, size: 16),
                  label: Text(context.tr('Load')),
                )
              else
                OutlinedButton.icon(
                  onPressed: busy ? null : onUnload,
                  icon: const Icon(Icons.power_settings_new, size: 16),
                  label: Text(context.tr('Unload')),
                ),
              IconButton(
                // Deleting a loaded model is allowed — `_deleteAttempt` offers
                // to unload-and-delete on the daemon's 409, so pre-disabling
                // this for a loaded model would make that flow unreachable.
                tooltip: context.tr('Delete'),
                onPressed: busy ? null : onDelete,
                icon: const Icon(Icons.delete_outline, size: 18, color: AppTokens.danger),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// HF repo id → `hf-files` → pick a GGUF file + optional mmproj, or the whole
/// MLX snapshot. Pops `true` when a download was started.
class DownloadModelDialog extends ConsumerStatefulWidget {
  const DownloadModelDialog({super.key});

  @override
  ConsumerState<DownloadModelDialog> createState() => _DownloadModelDialogState();
}

class _DownloadModelDialogState extends ConsumerState<DownloadModelDialog> {
  final _repo = TextEditingController();
  bool _loadingFiles = false;
  String? _error;
  String _format = 'unknown'; // gguf | mlx | unknown
  List<Map<String, dynamic>> _files = const [];
  String? _selectedFile;
  String? _selectedMmproj;
  bool _starting = false;

  /// A lookup succeeded for the repo currently in the field — cleared on any
  /// edit, since the last lookup no longer describes the new text. Downloading
  /// an un-looked-up (or `unknown`-format) repo is refused server-side anyway.
  bool _lookupDone = false;

  @override
  void dispose() {
    _repo.dispose();
    super.dispose();
  }

  Future<void> _fetchFiles() async {
    final repo = _repo.text.trim();
    if (repo.isEmpty) return;
    setState(() {
      _loadingFiles = true;
      _error = null;
      _files = const [];
      _selectedFile = null;
      _selectedMmproj = null;
      _lookupDone = false;
    });
    try {
      final r = await ref
          .read(apiClientProvider)
          .get('/api/local-models/hf-files', query: {'repo': repo});
      final m = (r as Map).cast<String, dynamic>();
      final files = _asMapList(m['files']);
      setState(() {
        _format = '${m['format'] ?? 'unknown'}';
        _files = files;
        _lookupDone = true;
        // The common case is one model file plus an optional vision
        // projector beside it — pre-select the first non-mmproj entry.
        final firstModel =
            files.where((f) => f['mmproj'] != true).cast<Map<String, dynamic>?>().firstWhere(
                  (f) => f != null,
                  orElse: () => null,
                );
        _selectedFile = firstModel?['name'] as String?;
      });
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loadingFiles = false);
    }
  }

  Future<void> _start() async {
    final repo = _repo.text.trim();
    if (repo.isEmpty) return;
    if (_format == 'gguf' && _selectedFile == null) {
      setState(() => _error = context.tr('Choose a GGUF file'));
      return;
    }
    setState(() {
      _starting = true;
      _error = null;
    });
    try {
      final pinned = repo.toLowerCase() == _gturboRepo && _format != 'gguf';
      await ref.read(apiClientProvider).post('/api/local-models/download', body: {
        'repo': repo,
        if (pinned) 'format': 'gturbo',
        if (pinned) 'revision': _gturboRevision,
        if (!pinned && _format == 'gguf') 'file': _selectedFile,
        if (!pinned && _selectedMmproj != null) 'mmproj': _selectedMmproj,
      });
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ggufFiles = _files.where((f) => f['mmproj'] != true).toList();
    final mmprojFiles = _files.where((f) => f['mmproj'] == true).toList();
    return AlertDialog(
      backgroundColor: c.surface,
      title: Text(context.tr('Download a model')),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _repo,
                  decoration: InputDecoration(
                    labelText: context.tr('Hugging Face repo'),
                    hintText: 'org/name',
                    isDense: true,
                  ),
                  onChanged: (_) => setState(() => _lookupDone = false),
                  onSubmitted: (_) => _fetchFiles(),
                ),
              ),
              const SizedBox(width: AppTokens.s8),
              OutlinedButton(
                onPressed: _loadingFiles ? null : _fetchFiles,
                child: Text(context.tr('Look up')),
              ),
            ]),
            if (_loadingFiles) ...[
              const SizedBox(height: AppTokens.s12),
              const LinearProgressIndicator(),
            ],
            if (_format == 'mlx' && _repo.text.trim().toLowerCase() == _gturboRepo) ...[
              const SizedBox(height: AppTokens.s12),
              Text(
                context.tr(
                  'This repo is the TurboFieldfare source. SenClaw repacks the pinned revision into a .gturbo directory instead of saving the raw MLX snapshot.',
                ),
                style: TextStyle(color: c.textMuted, fontSize: 12),
              ),
            ] else if (_format == 'mlx') ...[
              const SizedBox(height: AppTokens.s12),
              Text(context.tr('MLX snapshot — the whole repo is downloaded.'),
                  style: TextStyle(color: c.textMuted, fontSize: 12)),
            ],
            if (_format == 'gguf' && ggufFiles.isNotEmpty) ...[
              const SizedBox(height: AppTokens.s12),
              Text(context.tr('GGUF file'),
                  style: TextStyle(color: c.textSecondary, fontWeight: FontWeight.w600)),
              const SizedBox(height: AppTokens.s4),
              DropdownButtonFormField<String>(
                initialValue: _selectedFile,
                isExpanded: true,
                decoration: const InputDecoration(isDense: true),
                items: [
                  for (final f in ggufFiles)
                    DropdownMenuItem(
                      value: f['name'] as String,
                      child: Text(
                        '${f['name']}${f['quant'] != null ? ' (${f['quant']})' : ''}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (v) => setState(() => _selectedFile = v),
              ),
              if (mmprojFiles.isNotEmpty) ...[
                const SizedBox(height: AppTokens.s8),
                Text(context.tr('Vision projector (optional)'),
                    style: TextStyle(color: c.textSecondary, fontWeight: FontWeight.w600)),
                const SizedBox(height: AppTokens.s4),
                DropdownButtonFormField<String?>(
                  initialValue: _selectedMmproj,
                  isExpanded: true,
                  decoration: const InputDecoration(isDense: true),
                  items: [
                    DropdownMenuItem(value: null, child: Text(context.tr('None'))),
                    for (final f in mmprojFiles)
                      DropdownMenuItem(
                        value: f['name'] as String,
                        child: Text('${f['name']}', overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (v) => setState(() => _selectedMmproj = v),
                ),
              ],
            ],
            if (_error != null) ...[
              const SizedBox(height: AppTokens.s12),
              Text(_error!, style: const TextStyle(color: AppTokens.danger, fontSize: 12)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(false), child: Text(context.tr('Cancel'))),
        FilledButton(
          onPressed: _starting || !_lookupDone || _format == 'unknown' ? null : _start,
          child: _starting
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(context.tr('Download')),
        ),
      ],
    );
  }
}

/// Default engine settings (§5.3 `GET|PUT /api/local-models/settings`):
/// default context length plus the shared `<local-models>/settings.json`
/// fields. Round-trips every key it doesn't render a control for untouched —
/// the file is snake_case and shared with the runtimes, so this form must
/// never rename or drop a field it doesn't know about.
class LocalModelsSettingsCard extends ConsumerStatefulWidget {
  const LocalModelsSettingsCard({super.key});

  @override
  ConsumerState<LocalModelsSettingsCard> createState() => _LocalModelsSettingsCardState();
}

class _LocalModelsSettingsCardState extends ConsumerState<LocalModelsSettingsCard> {
  bool _loaded = false;
  bool _saving = false;
  String? _flash;
  final _defaultContextLength = TextEditingController();
  final _temperature = TextEditingController();
  final _topK = TextEditingController();
  final _topP = TextEditingController();
  final _maxNewTokens = TextEditingController();
  final _maxKvTokens = TextEditingController();
  bool _enableThinking = false;

  /// Whether `enable_thinking` existed in the loaded `engine` object, or the
  /// user has flipped the switch this session. A bare `bool` has no "absent"
  /// state, so without this a save would inject `enable_thinking: false` for
  /// every model that never set it — see `_save`.
  bool _enableThinkingKnown = false;

  /// TurboQuant KV (`kv_cache_bits`): `null` = off (FP16 KV), `3` = TQ3,
  /// `4` = TQ4. Known/unknown like `enable_thinking`, for the same reason.
  int? _kvCacheBits;
  bool _kvCacheBitsKnown = false;

  /// KV packed on Metal (`mlx_kv_cache_bits`): `null` = FP16, `4` or `8`.
  int? _mlxKvCacheBits;
  bool _mlxKvCacheBitsKnown = false;

  /// Every other engine key the daemon sent — passed back exactly as
  /// received so a field this form doesn't render yet survives a save.
  Map<String, dynamic> _engineRest = {};

  static const _knownKeys = [
    'temperature',
    'top_k',
    'top_p',
    'max_new_tokens',
    'max_kv_tokens',
    'enable_thinking',
    'kv_cache_bits',
    'mlx_kv_cache_bits',
  ];

  /// The engine remaps a legacy `2` to TQ3 and treats `0` as off; anything
  /// else the dropdown cannot show reads as off too.
  static int? _turboQuantBits(dynamic v) => switch ((v as num?)?.toInt()) {
        2 || 3 => 3,
        4 => 4,
        _ => null,
      };

  static int? _metalKvBits(dynamic v) => switch ((v as num?)?.toInt()) {
        4 => 4,
        8 => 8,
        _ => null,
      };

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _defaultContextLength.dispose();
    _temperature.dispose();
    _topK.dispose();
    _topP.dispose();
    _maxNewTokens.dispose();
    _maxKvTokens.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await ref.read(apiClientProvider).get('/api/local-models/settings');
      final m = (r as Map).cast<String, dynamic>();
      final engine = _asMap(m['engine']);
      if (mounted) {
        setState(() {
          _defaultContextLength.text =
              m['defaultContextLength'] == null ? '' : '${m['defaultContextLength']}';
          _temperature.text = engine['temperature'] == null ? '' : '${engine['temperature']}';
          _topK.text = engine['top_k'] == null ? '' : '${engine['top_k']}';
          _topP.text = engine['top_p'] == null ? '' : '${engine['top_p']}';
          _maxNewTokens.text =
              engine['max_new_tokens'] == null ? '' : '${engine['max_new_tokens']}';
          _maxKvTokens.text =
              engine['max_kv_tokens'] == null ? '' : '${engine['max_kv_tokens']}';
          _enableThinking = engine['enable_thinking'] == true;
          _enableThinkingKnown = engine.containsKey('enable_thinking');
          _kvCacheBits = _turboQuantBits(engine['kv_cache_bits']);
          _kvCacheBitsKnown = engine.containsKey('kv_cache_bits');
          _mlxKvCacheBits = _metalKvBits(engine['mlx_kv_cache_bits']);
          _mlxKvCacheBitsKnown = engine.containsKey('mlx_kv_cache_bits');
          _engineRest = {...engine}..removeWhere((k, _) => _knownKeys.contains(k));
        });
      }
    } catch (_) {
      // Defaults stay blank — the form is still usable to set fresh values.
    } finally {
      if (mounted) setState(() => _loaded = true);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      // `PUT` is a partial merge (runtime-protocol.md §5.3): every key here is
      // included only when it already existed or the user set it this
      // session, so a field this form doesn't know about — or never touched —
      // is never overwritten with a default the daemon never asked for.
      final defaultContextLength = _defaultContextLength.text.trim();
      await ref.read(apiClientProvider).put('/api/local-models/settings', body: {
        if (defaultContextLength.isNotEmpty)
          'defaultContextLength': int.tryParse(defaultContextLength),
        'engine': {
          ..._engineRest,
          if (_temperature.text.trim().isNotEmpty)
            'temperature': double.tryParse(_temperature.text.trim()),
          if (_topK.text.trim().isNotEmpty) 'top_k': int.tryParse(_topK.text.trim()),
          if (_topP.text.trim().isNotEmpty) 'top_p': double.tryParse(_topP.text.trim()),
          if (_maxNewTokens.text.trim().isNotEmpty)
            'max_new_tokens': int.tryParse(_maxNewTokens.text.trim()),
          if (_maxKvTokens.text.trim().isNotEmpty)
            'max_kv_tokens': int.tryParse(_maxKvTokens.text.trim()),
          if (_enableThinkingKnown) 'enable_thinking': _enableThinking,
          if (_kvCacheBitsKnown) 'kv_cache_bits': _kvCacheBits,
          if (_mlxKvCacheBitsKnown) 'mlx_kv_cache_bits': _mlxKvCacheBits,
        },
      });
      if (mounted) setState(() => _flash = context.tr('Saved'));
    } on ApiException catch (e) {
      if (mounted) setState(() => _flash = e.message);
    } catch (e) {
      if (mounted) setState(() => _flash = '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _bitsField({
    required String label,
    required String hint,
    required int? value,
    required List<(int?, String)> options,
    required ValueChanged<int?> onChanged,
  }) =>
      SizedBox(
        width: 240,
        child: DropdownButtonFormField<int?>(
          initialValue: value,
          isExpanded: true,
          decoration: InputDecoration(labelText: label, helperText: hint, isDense: true),
          items: [
            for (final (v, text) in options) DropdownMenuItem(value: v, child: Text(text)),
          ],
          onChanged: onChanged,
        ),
      );

  Widget _numField(TextEditingController ctrl, String label) => SizedBox(
        width: 160,
        child: TextField(
          controller: ctrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: label, isDense: true),
        ),
      );

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const LinearProgressIndicator();
    final c = context.colors;
    return decisionCard(
      context,
      title: context.tr('Default engine settings'),
      icon: Icons.tune,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.tr(
                'Applied to a model when it has no override of its own. Fields left empty use the engine\'s own default.'),
            style: TextStyle(color: c.textMuted, fontSize: 12),
          ),
          const SizedBox(height: AppTokens.s12),
          Wrap(spacing: AppTokens.s12, runSpacing: AppTokens.s12, children: [
            _numField(_defaultContextLength, context.tr('Default context length')),
            _numField(_temperature, context.tr('Temperature')),
            _numField(_topK, context.tr('Top K')),
            _numField(_topP, context.tr('Top P')),
            _numField(_maxNewTokens, context.tr('Max new tokens')),
            _numField(_maxKvTokens, context.tr('Max KV tokens')),
          ]),
          const SizedBox(height: AppTokens.s12),
          Wrap(spacing: AppTokens.s12, runSpacing: AppTokens.s12, children: [
            _bitsField(
              label: context.tr('TurboQuant KV'),
              hint: context.tr('Compresses the KV cache on long contexts. MLX.'),
              value: _kvCacheBits,
              options: [
                (null, context.tr('Off (FP16)')),
                (3, context.tr('TQ3 — 3-bit')),
                (4, context.tr('TQ4 — 4-bit')),
              ],
              onChanged: (v) => setState(() {
                _kvCacheBits = v;
                _kvCacheBitsKnown = true;
              }),
            ),
            _bitsField(
              label: context.tr('KV packed on Metal'),
              hint: context.tr('mlx.core.quantize — saves RAM, MLX only.'),
              value: _mlxKvCacheBits,
              options: [
                (null, 'FP16'),
                (4, context.tr('4-bit')),
                (8, context.tr('8-bit')),
              ],
              onChanged: (v) => setState(() {
                _mlxKvCacheBits = v;
                _mlxKvCacheBitsKnown = true;
              }),
            ),
          ]),
          const SizedBox(height: AppTokens.s12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(context.tr('Enable thinking'),
                        style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.w600)),
                    Text(
                      context.tr(
                          'For models that support a separate reasoning pass before the answer.'),
                      style: TextStyle(color: c.textMuted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Switch(
                  value: _enableThinking,
                  onChanged: (v) => setState(() {
                        _enableThinking = v;
                        _enableThinkingKnown = true;
                      })),
            ],
          ),
          const SizedBox(height: AppTokens.s12),
          Row(children: [
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.save_outlined, size: 16),
              label: Text(context.tr('Save')),
            ),
            if (_flash != null) ...[
              const SizedBox(width: AppTokens.s12),
              Text(_flash!, style: TextStyle(color: c.textMuted, fontSize: 12)),
            ],
          ]),
        ],
      ),
    );
  }
}
