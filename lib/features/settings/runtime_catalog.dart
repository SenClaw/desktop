// Settings → Runtime → "Engines & Frameworks": search/filter the runtime
// index merged with what's installed (runtime-protocol.md §5.1 `GET
// /api/runtimes/catalog`), install/update, uninstall a version, install from
// a local folder or archive, view logs, and stop a runtime's processes.

import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/i18n/l10n.dart';
import '../../core/transport/api_client.dart' show ApiException;
import '../../core/transport/connection.dart';
import '../../theme/tokens.dart';
import 'decision_widgets.dart';
import 'runtime_models.dart';

class RuntimeCatalogCard extends ConsumerStatefulWidget {
  const RuntimeCatalogCard({
    super.key,
    required this.installed,
    required this.processes,
    required this.onChanged,
  });
  final List<InstalledRuntime> installed;
  final List<RuntimeProcessInfo> processes;
  final VoidCallback onChanged;

  @override
  ConsumerState<RuntimeCatalogCard> createState() => _RuntimeCatalogCardState();
}

const _typeFilters = [
  ('all', 'All types'),
  ('llm-engine', 'LLM engines'),
  ('decision', 'Decision'),
  ('browser', 'Browser'),
  ('ocr', 'OCR'),
  ('asr', 'Speech to text'),
  ('tts', 'Text to speech'),
];

class _RuntimeCatalogCardState extends ConsumerState<RuntimeCatalogCard> {
  final _search = TextEditingController();
  bool _compatibleOnly = false;
  String _typeFilter = 'all';

  /// Runtime id → its active install/update job, polled here while [active].
  final _jobs = <String, RuntimeInstallJob>{};
  Timer? _poll;

  @override
  void dispose() {
    _search.dispose();
    _poll?.cancel();
    super.dispose();
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _syncPoll() {
    final active = _jobs.values.any((j) => j.active);
    if (active && _poll == null) {
      _poll = Timer.periodic(const Duration(seconds: 1), (_) => _pollJobs());
    } else if (!active && _poll != null) {
      _poll!.cancel();
      _poll = null;
    }
  }

  Future<void> _pollJobs() async {
    for (final entry in _jobs.entries.toList()) {
      if (!entry.value.active) continue;
      try {
        final r = await ref
            .read(apiClientProvider)
            .get('/api/runtimes/jobs/${entry.value.jobId}');
        final job = RuntimeInstallJob.fromJson((r as Map).cast());
        if (!mounted) return;
        setState(() => _jobs[entry.key] = job);
        if (!job.active) widget.onChanged();
      } catch (_) {
        // The job vanished (daemon restarted mid-install) — stop polling it;
        // the next full refresh will show whatever actually landed on disk.
        if (mounted) setState(() => _jobs.remove(entry.key));
      }
    }
    if (mounted) _syncPoll();
  }

  Future<void> _install(String id, {String? version}) async {
    try {
      final r = await ref.read(apiClientProvider).post('/api/runtimes/install', body: {
        'id': id,
        'version': ?version,
      });
      final m = (r as Map).cast<String, dynamic>();
      final job = RuntimeInstallJob(
        jobId: '${m['jobId']}',
        id: '${m['id'] ?? id}',
        version: '${m['version'] ?? version ?? ''}',
        state: 'queued',
        receivedBytes: 0,
        totalBytes: null,
        percent: 0,
        error: null,
        startedAt: DateTime.now().millisecondsSinceEpoch,
        finishedAt: null,
      );
      if (!mounted) return;
      setState(() => _jobs[id] = job);
      _syncPoll();
    } on ApiException catch (e) {
      _toast(e.message);
    } catch (e) {
      _toast('$e');
    }
  }

  Future<void> _uninstall(String id, String version, {bool force = false}) async {
    try {
      final q = force ? '?force=1' : '';
      await ref.read(apiClientProvider).delete('/api/runtimes/$id/versions/$version$q');
      widget.onChanged();
    } on ApiException catch (e) {
      if (e.status == 409 && !force) {
        if (!mounted) return;
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(ctx.tr('Stop it and uninstall?')),
            content: Text(e.message),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text(ctx.tr('Cancel'))),
              FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: Text(ctx.tr('Stop and uninstall'))),
            ],
          ),
        );
        if (ok == true) return _uninstall(id, version, force: true);
        return;
      }
      _toast(e.message);
    } catch (e) {
      _toast('$e');
    }
  }

  Future<void> _stopAllFor(String id) async {
    final matching = widget.processes.where((p) => p.runtimeId == id).toList();
    for (final p in matching) {
      try {
        await ref
            .read(apiClientProvider)
            .post('/api/runtimes/processes/${Uri.encodeComponent(p.key)}/stop');
      } catch (_) {
        // Best-effort — one stuck process must not block stopping the rest.
      }
    }
    widget.onChanged();
  }

  Future<void> _pickAndInstallLocal() async {
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(ctx.tr('Install from folder or archive')),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'folder'),
            child: Text(ctx.tr('Choose a folder…')),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'archive'),
            child: Text(ctx.tr('Choose an archive (.tar.gz / .zip)…')),
          ),
        ],
      ),
    );
    if (choice == null || !mounted) return;
    String? path;
    if (choice == 'folder') {
      path = await FilePicker.platform.getDirectoryPath(
          dialogTitle: context.tr('Choose a runtime package folder'));
    } else {
      final res = await FilePicker.platform.pickFiles(
        dialogTitle: context.tr('Choose a runtime package archive'),
        type: FileType.custom,
        allowedExtensions: const ['gz', 'tgz', 'zip'],
      );
      path = res?.files.single.path;
    }
    if (path == null || !mounted) return;
    try {
      await ref
          .read(apiClientProvider)
          .post('/api/runtimes/install-local', body: {'path': path});
      widget.onChanged();
      if (mounted) _toast(context.tr('Installing from the local path…'));
    } on ApiException catch (e) {
      _toast(e.message);
    } catch (e) {
      _toast('$e');
    }
  }

  Future<void> _viewLogs(String id) async {
    Map<String, dynamic>? data;
    String? error;
    try {
      final r = await ref
          .read(apiClientProvider)
          .get('/api/runtimes/$id/logs', query: {'lines': 200});
      data = (r as Map).cast<String, dynamic>();
    } on ApiException catch (e) {
      error = e.message;
    } catch (e) {
      error = '$e';
    }
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.colors.surface,
        title: Text(ctx.trArgs('Logs — {id}', {'id': id})),
        content: SizedBox(
          width: 640,
          height: 420,
          child: error != null
              ? Text(error, style: const TextStyle(color: AppTokens.danger))
              : SingleChildScrollView(
                  child: SelectableText(
                    (data?['lines'] as List? ?? const []).map((e) => '$e').join('\n'),
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 11.5),
                  ),
                ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(), child: Text(ctx.tr('Close'))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final catalogAsync = ref.watch(runtimeCatalogProvider);
    final catalog = catalogAsync.valueOrNull;
    final catalogError =
        catalogAsync.hasError ? '${catalogAsync.error}' : catalog?.error;

    // The index merged with anything installed that the index doesn't (yet,
    // or ever) list — a sideloaded runtime must still show up as a row.
    final byId = <String, CatalogEntry>{
      for (final e in catalog?.entries ?? const <CatalogEntry>[]) e.id: e,
    };
    for (final r in widget.installed) {
      byId.putIfAbsent(r.id, () => CatalogEntry.fromInstalled(r));
    }
    var rows = byId.values.toList()..sort((a, b) => a.name.compareTo(b.name));
    final q = _search.text.trim().toLowerCase();
    if (q.isNotEmpty) {
      rows = rows
          .where((e) =>
              e.name.toLowerCase().contains(q) ||
              e.id.toLowerCase().contains(q) ||
              e.description.toLowerCase().contains(q))
          .toList();
    }
    if (_compatibleOnly) rows = rows.where((e) => e.compatible).toList();
    if (_typeFilter != 'all') {
      rows = rows.where((e) => e.type == _typeFilter).toList();
    }
    final installedById = {for (final r in widget.installed) r.id: r};

    return decisionCard(
      context,
      title: context.tr('Engines & Frameworks'),
      icon: Icons.widgets_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (catalogError != null)
            Padding(
              padding: const EdgeInsets.only(bottom: AppTokens.s8),
              child: Text(
                context.trArgs(
                    'Could not fetch the runtime index: {e}', {'e': catalogError}),
                style: TextStyle(color: c.textMuted, fontSize: 12),
              ),
            ),
          Wrap(spacing: AppTokens.s8, runSpacing: AppTokens.s8, children: [
            SizedBox(
              width: 260,
              child: TextField(
                controller: _search,
                decoration: InputDecoration(
                  isDense: true,
                  prefixIcon: const Icon(Icons.search, size: 18),
                  hintText: context.tr('Search…'),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            DropdownButton<bool>(
              value: _compatibleOnly,
              items: [
                DropdownMenuItem(value: false, child: Text(context.tr('All'))),
                DropdownMenuItem(
                    value: true, child: Text(context.tr('Compatible only'))),
              ],
              onChanged: (v) => setState(() => _compatibleOnly = v ?? false),
            ),
            DropdownButton<String>(
              value: _typeFilter,
              items: [
                for (final (v, label) in _typeFilters)
                  DropdownMenuItem(value: v, child: Text(context.tr(label))),
              ],
              onChanged: (v) => setState(() => _typeFilter = v ?? 'all'),
            ),
          ]),
          const SizedBox(height: AppTokens.s12),
          if (rows.isEmpty)
            Text(context.tr('No engines match this filter.'),
                style: TextStyle(color: c.textMuted, fontSize: 12.5))
          else
            for (final entry in rows)
              _CatalogRow(
                entry: entry,
                installed: installedById[entry.id],
                job: _jobs[entry.id],
                hasRunningProcess:
                    widget.processes.any((p) => p.runtimeId == entry.id),
                onInstall: () => _install(entry.id),
                onUpdate: () => _install(entry.id, version: entry.latestVersion),
                onUninstall: (v) => _uninstall(entry.id, v),
                onInstallLocal: _pickAndInstallLocal,
                onViewLogs: () => _viewLogs(entry.id),
                onStopAll: () => _stopAllFor(entry.id),
              ),
        ],
      ),
    );
  }
}

class _CatalogRow extends StatelessWidget {
  const _CatalogRow({
    required this.entry,
    required this.installed,
    required this.job,
    required this.hasRunningProcess,
    required this.onInstall,
    required this.onUpdate,
    required this.onUninstall,
    required this.onInstallLocal,
    required this.onViewLogs,
    required this.onStopAll,
  });
  final CatalogEntry entry;
  final InstalledRuntime? installed;
  final RuntimeInstallJob? job;
  final bool hasRunningProcess;
  final VoidCallback onInstall;
  final VoidCallback onUpdate;
  final void Function(String version) onUninstall;
  final VoidCallback onInstallLocal;
  final VoidCallback onViewLogs;
  final VoidCallback onStopAll;

  IconData _typeIcon() => switch (entry.type) {
        'llm-engine' => Icons.memory_outlined,
        'decision' => Icons.alt_route,
        'browser' => Icons.web_outlined,
        'ocr' => Icons.document_scanner_outlined,
        'asr' => Icons.mic_none_outlined,
        'tts' => Icons.volume_up_outlined,
        _ => Icons.extension_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      margin: const EdgeInsets.only(bottom: AppTokens.s8),
      padding: const EdgeInsets.all(AppTokens.s12),
      decoration: BoxDecoration(
        color: c.bg,
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(AppTokens.rMd),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(_typeIcon(), size: 18, color: c.textSecondary),
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
                    Text(entry.name,
                        style: TextStyle(
                            color: c.textPrimary, fontWeight: FontWeight.w600)),
                    if (installed != null) ...[
                      DecisionChip(installed!.version),
                      if (entry.updateAvailable) ...[
                        Icon(Icons.arrow_forward, size: 12, color: c.textMuted),
                        DecisionChip(entry.latestVersion, color: AppTokens.brand),
                      ],
                    ] else if (entry.available)
                      DecisionChip(entry.latestVersion),
                  ],
                ),
                if (entry.description.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(entry.description,
                      style: TextStyle(color: c.textSecondary, fontSize: 12)),
                ],
                if (entry.releaseNotesUrl != null) ...[
                  const SizedBox(height: 4),
                  InkWell(
                    onTap: () => launchUrl(Uri.parse(entry.releaseNotesUrl!),
                        mode: LaunchMode.externalApplication),
                    child: Text(
                      context.trArgs('{v} - Release notes ›',
                          {'v': installed?.version ?? entry.latestVersion}),
                      style: TextStyle(
                          color: AppTokens.brand,
                          fontSize: 11.5,
                          decoration: TextDecoration.underline),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppTokens.s12),
          _trailing(context),
          _kebab(context),
        ],
      ),
    );
  }

  Widget _trailing(BuildContext context) {
    final c = context.colors;
    if (job != null && job!.active) {
      final pct = job!.percent != null ? '${(job!.percent! * 100).round()}%' : '';
      return Row(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, value: job!.percent)),
        const SizedBox(width: AppTokens.s8),
        Text(pct, style: TextStyle(color: c.textMuted, fontSize: 12)),
      ]);
    }
    if (!entry.compatible) {
      return DecisionChip(context.tr('Incompatible'), color: c.textMuted);
    }
    // Installed from a local package before any release was published.
    if (installed != null && !entry.available) {
      return DecisionChip(context.tr('Installed'), color: AppTokens.success);
    }
    if (!entry.available) {
      return DecisionChip(context.tr('Not published yet'), color: c.textMuted);
    }
    if (installed != null && !entry.updateAvailable) {
      return DecisionChip(context.tr('✓ Latest version'), color: AppTokens.success);
    }
    if (installed != null && entry.updateAvailable) {
      return FilledButton(onPressed: onUpdate, child: Text(context.tr('Update')));
    }
    return FilledButton(onPressed: onInstall, child: Text(context.tr('Install')));
  }

  Widget _kebab(BuildContext context) {
    // An update keeps the OLD version installed until nothing is using it
    // (runtime-protocol.md §7.3), so more than one version can be installed
    // at once — offer each by name rather than only ever the newest.
    final versions = installed?.versions ?? const <String>[];
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, size: 18),
      onSelected: (v) {
        if (v.startsWith('uninstall:')) {
          onUninstall(v.substring('uninstall:'.length));
          return;
        }
        switch (v) {
          case 'install-local':
            onInstallLocal();
          case 'logs':
            onViewLogs();
          case 'stop':
            onStopAll();
        }
      },
      itemBuilder: (ctx) => [
        if (versions.length <= 1 && installed != null)
          PopupMenuItem(value: 'uninstall:${installed!.version}', child: Text(ctx.tr('Uninstall')))
        else
          for (final v in versions)
            PopupMenuItem(value: 'uninstall:$v', child: Text(ctx.trArgs('Uninstall {v}', {'v': v}))),
        PopupMenuItem(
            value: 'install-local',
            child: Text(ctx.tr('Install from folder or archive…'))),
        if (installed != null)
          PopupMenuItem(value: 'logs', child: Text(ctx.tr('View logs'))),
        if (hasRunningProcess)
          PopupMenuItem(value: 'stop', child: Text(ctx.tr('Stop running processes'))),
      ],
    );
  }
}
