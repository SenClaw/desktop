import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/l10n.dart';
import '../../core/transport/api_client.dart';
import '../../core/transport/connection.dart';
import '../../theme/tokens.dart';
import '../../widgets/app_markdown.dart';

// ── Models ───────────────────────────────────────────────────────────────

/// One shadow-git checkpoint row (`GET /api/chats/:jid/checkpoints` item).
class Checkpoint {
  final int id;
  final String chatJid;
  final String sha;
  final String? parentSha;
  final String toolName; // Edit | Write | NotebookEdit | Bash | restore
  final String summary;
  final String workspace;
  final int filesChanged;
  final DateTime createdAt;
  const Checkpoint({
    required this.id,
    required this.chatJid,
    required this.sha,
    required this.parentSha,
    required this.toolName,
    required this.summary,
    required this.workspace,
    required this.filesChanged,
    required this.createdAt,
  });

  /// The baseline row has no parent — no diff/explain is possible against it.
  bool get isBaseline => parentSha == null;

  factory Checkpoint.fromJson(Map<String, dynamic> j) => Checkpoint(
    id: (j['id'] as num?)?.toInt() ?? 0,
    chatJid: '${j['chatJid'] ?? ''}',
    sha: '${j['sha'] ?? ''}',
    parentSha: j['parentSha'] as String?,
    toolName: '${j['toolName'] ?? ''}',
    summary: '${j['summary'] ?? ''}',
    workspace: '${j['workspace'] ?? ''}',
    filesChanged: (j['filesChanged'] as num?)?.toInt() ?? 0,
    createdAt: DateTime.tryParse('${j['createdAt']}') ?? DateTime.now(),
  );
}

class DiffFileEntry {
  final String status; // A | M | D | R
  final String path;
  const DiffFileEntry(this.status, this.path);
}

/// `GET /api/chats/:jid/checkpoints/:id/diff` response.
class CheckpointDiff {
  final String fromSha;
  final List<DiffFileEntry> files;
  final String diff;
  final bool truncated;
  const CheckpointDiff({
    required this.fromSha,
    required this.files,
    required this.diff,
    required this.truncated,
  });

  factory CheckpointDiff.fromJson(Map<String, dynamic> j) => CheckpointDiff(
    fromSha: '${j['fromSha'] ?? ''}',
    files: ((j['files'] as List?) ?? const [])
        .whereType<Map>()
        .map((m) => DiffFileEntry('${m['status'] ?? ''}', '${m['path'] ?? ''}'))
        .toList(),
    diff: '${j['diff'] ?? ''}',
    truncated: j['truncated'] == true,
  );
}

// ── Provider ─────────────────────────────────────────────────────────────

class ChangesState {
  final bool loading;
  final bool enabled;
  final String? workspace;
  final List<Checkpoint> items;
  final String? error;
  const ChangesState({
    this.loading = true,
    this.enabled = false,
    this.workspace,
    this.items = const [],
    this.error,
  });

  ChangesState copyWith({
    bool? loading,
    bool? enabled,
    String? workspace,
    List<Checkpoint>? items,
    String? error,
  }) => ChangesState(
    loading: loading ?? this.loading,
    enabled: enabled ?? this.enabled,
    workspace: workspace ?? this.workspace,
    items: items ?? this.items,
    error: error,
  );
}

String _errMsg(Object e) => e is ApiException ? e.message : '$e';

/// Loads and refreshes one chat's checkpoint list, and carries the per-chat
/// diff/restore/explain actions. A `checkpoint:new` WS event for this jid
/// (mirrors `workbench:new` in [WorkbenchNotifier]) re-fetches the list —
/// simplest correct behaviour, since a restore also mints a new row.
class ChangesNotifier extends StateNotifier<ChangesState> {
  ChangesNotifier(this._ref, this.jid) : super(const ChangesState()) {
    _sub = _ref.read(wsClientProvider).events.listen((e) {
      if (e['type'] == 'checkpoint:new' && '${e['groupJid'] ?? ''}' == jid) {
        refresh();
      }
    });
    refresh();
  }

  final Ref _ref;
  final String jid;
  late final StreamSubscription _sub;

  String get _base => '/api/chats/${Uri.encodeComponent(jid)}/checkpoints';

  Future<void> refresh() async {
    try {
      final r = await _ref.read(apiClientProvider).get(_base);
      if (!mounted) return;
      if (r is Map) {
        final items = ((r['items'] as List?) ?? const [])
            .whereType<Map>()
            .map((m) => Checkpoint.fromJson(m.cast<String, dynamic>()))
            .toList();
        state = state.copyWith(
          loading: false,
          enabled: r['enabled'] == true,
          workspace: r['workspace'] as String?,
          items: items,
        );
      } else {
        state = state.copyWith(loading: false);
      }
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(loading: false, error: _errMsg(e));
    }
  }

  Future<void> setEnabled(bool v) async {
    final prev = state.enabled;
    state = state.copyWith(enabled: v);
    try {
      await _ref
          .read(apiClientProvider)
          .put('$_base/settings', body: {'enabled': v});
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(enabled: prev, error: _errMsg(e));
    }
  }

  Future<CheckpointDiff> fetchDiff(int id) async {
    final r = await _ref.read(apiClientProvider).get('$_base/$id/diff');
    return CheckpointDiff.fromJson((r as Map).cast<String, dynamic>());
  }

  Future<void> restore(int id, {List<String>? files}) => _ref
      .read(apiClientProvider)
      .post(
        '$_base/$id/restore',
        body: {if (files != null && files.isNotEmpty) 'files': files},
      );

  /// Turn a checkpoint into a markdown page under the project's
  /// `docs/changes/`. Same diff as [explain], but with a destination that
  /// survives the conversation. Returns the absolute path so the caller can
  /// show it — the path is the whole point.
  Future<String> document(int id) async {
    final r = await _ref
        .read(apiClientProvider)
        .post('$_base/$id/document', body: const {});
    final m = (r as Map).cast<String, dynamic>();
    return '${m['path'] ?? ''}';
  }

  Future<String> explain(int id, {required String language}) async {
    final r = await _ref
        .read(apiClientProvider)
        .post('$_base/$id/explain', body: {'language': language});
    final m = (r as Map).cast<String, dynamic>();
    return '${m['text'] ?? ''}';
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

final checkpointsProvider =
    StateNotifierProvider.family<ChangesNotifier, ChangesState, String>(
      (ref, jid) => ChangesNotifier(ref, jid),
    );

// ── UI ───────────────────────────────────────────────────────────────────

/// "Changes" dock tab: shadow-git checkpoints for the current chat — list,
/// diff, restore, explain. Ported from the web/desktop right-dock tab set.
class ChangesTab extends ConsumerStatefulWidget {
  const ChangesTab({super.key, required this.jid});
  final String jid;
  @override
  ConsumerState<ChangesTab> createState() => _ChangesTabState();
}

class _ChangesTabState extends ConsumerState<ChangesTab> {
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    ref.listen<ChangesState>(checkpointsProvider(widget.jid), (prev, next) {
      if (next.error != null && next.error != prev?.error) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(next.error!)));
      }
    });
    final state = ref.watch(checkpointsProvider(widget.jid));
    final notifier = ref.read(checkpointsProvider(widget.jid).notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppTokens.s12,
            AppTokens.s8,
            AppTokens.s8,
            AppTokens.s8,
          ),
          child: Row(
            children: [
              Icon(Icons.history_rounded, size: 16, color: c.accent),
              const SizedBox(width: AppTokens.s8),
              Expanded(
                child: Text(
                  context.tr('Checkpoints'),
                  style: TextStyle(
                    color: c.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                tooltip: context.tr('Reload'),
                icon: const Icon(Icons.refresh, size: 16),
                onPressed: notifier.refresh,
              ),
              Switch(
                value: state.enabled,
                onChanged: (v) => notifier.setEnabled(v),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: state.loading
              ? const Center(child: CircularProgressIndicator())
              : state.items.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(AppTokens.s24),
                    child: Text(
                      context.tr(
                        'No checkpoints yet — they appear after the agent edits a file in a git repository.',
                      ),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: c.textMuted, fontSize: 12),
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: AppTokens.s4),
                  itemCount: state.items.length,
                  itemBuilder: (context, i) => _CheckpointRow(
                    jid: widget.jid,
                    checkpoint: state.items[i],
                  ),
                ),
        ),
      ],
    );
  }
}

IconData _toolIcon(String toolName) => switch (toolName) {
  'Edit' => Icons.edit_outlined,
  'Write' => Icons.note_add_outlined,
  'NotebookEdit' => Icons.menu_book_outlined,
  'Bash' => Icons.terminal_rounded,
  'restore' => Icons.restore_rounded,
  _ => Icons.change_history_rounded,
};

String _relativeTime(BuildContext context, DateTime dt) {
  final l = dt.toLocal();
  final now = DateTime.now();
  final diff = now.difference(l);
  if (diff.inSeconds < 60) return context.tr('now');
  if (diff.inMinutes < 60) {
    return context.trArgs('{n}m ago', {'n': diff.inMinutes});
  }
  if (diff.inHours < 24) return context.trArgs('{n}h ago', {'n': diff.inHours});
  if (diff.inDays < 7) return context.trArgs('{n}d ago', {'n': diff.inDays});
  return '${l.day.toString().padLeft(2, '0')}/${l.month.toString().padLeft(2, '0')}';
}

Future<bool> _confirmAction(
  BuildContext context,
  String message,
  String confirmLabel,
) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (dctx) => AlertDialog(
      backgroundColor: dctx.colors.surface,
      content: Text(message, style: TextStyle(color: dctx.colors.textPrimary)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dctx, false),
          child: Text(dctx.tr('Cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dctx, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return ok == true;
}

/// One checkpoint row: icon + summary + relative time + file count. Tapping a
/// non-baseline row expands a panel with the file list and unified diff.
class _CheckpointRow extends ConsumerStatefulWidget {
  const _CheckpointRow({required this.jid, required this.checkpoint});
  final String jid;
  final Checkpoint checkpoint;
  @override
  ConsumerState<_CheckpointRow> createState() => _CheckpointRowState();
}

class _CheckpointRowState extends ConsumerState<_CheckpointRow> {
  bool _expanded = false;
  bool _diffLoading = false;
  bool _documenting = false;
  String? _diffError;
  CheckpointDiff? _diff;
  bool _restoring = false;

  ChangesNotifier get _notifier =>
      ref.read(checkpointsProvider(widget.jid).notifier);

  Future<void> _toggle() async {
    final cp = widget.checkpoint;
    if (cp.isBaseline) return;
    setState(() => _expanded = !_expanded);
    if (_expanded && _diff == null && !_diffLoading) {
      setState(() {
        _diffLoading = true;
        _diffError = null;
      });
      try {
        final d = await _notifier.fetchDiff(cp.id);
        if (!mounted) return;
        setState(() {
          _diff = d;
          _diffLoading = false;
        });
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _diffLoading = false;
          _diffError = _errMsg(e);
        });
      }
    }
  }

  Future<void> _restoreAll() async {
    final cp = widget.checkpoint;
    final ok = await _confirmAction(
      context,
      context.tr(
        'Put the working directory back to this step? Files added later will be removed.',
      ),
      context.tr('Restore all'),
    );
    if (!ok || !mounted) return;
    setState(() => _restoring = true);
    try {
      await _notifier.restore(cp.id);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.tr('Restored'))));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_errMsg(e))));
    } finally {
      if (mounted) setState(() => _restoring = false);
    }
  }

  Future<void> _restoreFile(String path) async {
    final cp = widget.checkpoint;
    final ok = await _confirmAction(
      context,
      context.trArgs('Restore "{path}" to this step?', {'path': path}),
      context.tr('Restore'),
    );
    if (!ok || !mounted) return;
    try {
      await _notifier.restore(cp.id, files: [path]);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.tr('Restored'))));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_errMsg(e))));
    }
  }

  Future<void> _document() async {
    setState(() => _documenting = true);
    try {
      final path = await _notifier.document(widget.checkpoint.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.trArgs('Đã ghi {path}', {'path': path})),
          duration: const Duration(seconds: 8),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_errMsg(e))));
    } finally {
      if (mounted) setState(() => _documenting = false);
    }
  }

  void _explain() {
    final language = L10n.of(context).isVi ? 'vi' : 'en';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheetCtx) => _ExplainSheet(
        jid: widget.jid,
        checkpoint: widget.checkpoint,
        language: language,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final cp = widget.checkpoint;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: cp.isBaseline ? null : _toggle,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppTokens.s12,
              vertical: AppTokens.s8,
            ),
            child: Row(
              children: [
                Icon(_toolIcon(cp.toolName), size: 16, color: c.accent),
                const SizedBox(width: AppTokens.s8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        cp.summary.isEmpty ? cp.toolName : cp.summary,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: c.textPrimary, fontSize: 13),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${_relativeTime(context, cp.createdAt)} · ${context.trArgs('{n} files', {'n': cp.filesChanged})}',
                        style: TextStyle(color: c.textMuted, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                if (_restoring)
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  TextButton(
                    onPressed: _restoreAll,
                    child: Text(context.tr('Restore all')),
                  ),
                if (!cp.isBaseline)
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                    color: c.textMuted,
                  ),
              ],
            ),
          ),
        ),
        if (_expanded && !cp.isBaseline) _buildExpanded(context),
        const Divider(height: 1),
      ],
    );
  }

  Widget _buildExpanded(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppTokens.s12,
        0,
        AppTokens.s12,
        AppTokens.s12,
      ),
      color: c.surfaceAlt.withValues(alpha: 0.4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Spacer(),
              TextButton.icon(
                onPressed: _explain,
                icon: const Icon(Icons.auto_awesome_outlined, size: 14),
                label: Text(context.tr('Explain')),
              ),
              Tooltip(
                message: context.tr(
                    'Ghi thành một trang .md trong docs/changes của dự án. Không commit.'),
                child: TextButton.icon(
                  onPressed: _documenting ? null : _document,
                  icon: _documenting
                      ? const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.description_outlined, size: 14),
                  label: Text(context.tr('Ghi tài liệu')),
                ),
              ),
            ],
          ),
          if (_diffLoading)
            const Padding(
              padding: EdgeInsets.all(AppTokens.s12),
              child: Center(
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else if (_diffError != null)
            Text(
              _diffError!,
              style: TextStyle(color: AppTokens.danger, fontSize: 12),
            )
          else if (_diff != null) ...[
            for (final f in _diff!.files)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    SizedBox(
                      width: 16,
                      child: Text(
                        f.status,
                        style: TextStyle(
                          color: _statusColor(f.status),
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        f.path,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: c.textSecondary, fontSize: 12),
                      ),
                    ),
                    TextButton(
                      onPressed: () => _restoreFile(f.path),
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(0, 0),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        context.tr('Restore'),
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: AppTokens.s6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppTokens.s8),
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(AppTokens.rSm),
                border: Border.all(color: c.border),
              ),
              child: SelectionArea(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final l in _diff!.diff.split('\n'))
                        Text(
                          l.isEmpty ? ' ' : l,
                          softWrap: false,
                          style: TextStyle(
                            fontFamily: AppTokens.fontMono,
                            fontSize: 11,
                            height: 1.4,
                            color: _diffLineColor(c, l),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            if (_diff!.truncated)
              Padding(
                padding: const EdgeInsets.only(top: AppTokens.s4),
                child: Text(
                  context.tr('Diff truncated'),
                  style: TextStyle(color: c.textMuted, fontSize: 11),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Color _statusColor(String status) => switch (status) {
    'A' => AppTokens.success,
    'D' => AppTokens.danger,
    'R' => AppTokens.warning,
    _ => AppTokens.brand,
  };

  Color _diffLineColor(AppColors c, String l) {
    if (l.startsWith('+') && !l.startsWith('+++')) return AppTokens.success;
    if (l.startsWith('-') && !l.startsWith('---')) return AppTokens.danger;
    if (l.startsWith('@@')) return c.textMuted;
    return c.textSecondary;
  }
}

/// Bottom sheet for `POST .../explain`: loading → markdown text, or an error.
class _ExplainSheet extends ConsumerStatefulWidget {
  const _ExplainSheet({
    required this.jid,
    required this.checkpoint,
    required this.language,
  });
  final String jid;
  final Checkpoint checkpoint;
  final String language;
  @override
  ConsumerState<_ExplainSheet> createState() => _ExplainSheetState();
}

class _ExplainSheetState extends ConsumerState<_ExplainSheet> {
  bool _loading = true;
  String? _text;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final text = await ref
          .read(checkpointsProvider(widget.jid).notifier)
          .explain(widget.checkpoint.id, language: widget.language);
      if (!mounted) return;
      setState(() {
        _text = text;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _errMsg(e);
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (sheetCtx, scrollCtl) => Container(
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppTokens.rLg),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(AppTokens.s12),
              child: Row(
                children: [
                  Icon(Icons.auto_awesome_outlined, size: 16, color: c.accent),
                  const SizedBox(width: AppTokens.s8),
                  Expanded(
                    child: Text(
                      context.tr('Explain'),
                      style: TextStyle(
                        color: c.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 16),
                    onPressed: () => Navigator.pop(sheetCtx),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(AppTokens.s16),
                        child: Text(
                          _error!,
                          style: TextStyle(
                            color: AppTokens.danger,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    )
                  : SelectionArea(
                      child: SingleChildScrollView(
                        controller: scrollCtl,
                        padding: const EdgeInsets.all(AppTokens.s12),
                        child: AppMarkdown(
                          _text ?? '',
                          style: TextStyle(color: c.textPrimary, fontSize: 13),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
