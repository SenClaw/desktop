import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/l10n.dart';
import '../../core/transport/api_client.dart';
import '../../core/transport/connection.dart';
import '../../theme/tokens.dart';

/// One row of `GET /api/worktrees` — the isolated git checkout the dispatcher
/// runs a `worktree`-labelled card in.
class _WorktreeInfo {
  final String path;
  final String branch;
  final String base;
  final String repo;
  final String? owner;
  const _WorktreeInfo({
    required this.path,
    required this.branch,
    required this.base,
    required this.repo,
    required this.owner,
  });

  factory _WorktreeInfo.fromJson(Map<String, dynamic> j) => _WorktreeInfo(
        path: '${j['path'] ?? ''}',
        branch: '${j['branch'] ?? ''}',
        base: '${j['base'] ?? ''}',
        repo: '${j['repo'] ?? ''}',
        owner: j['owner'] as String?,
      );
}

/// `GET /api/worktrees/diff` → `diff` field.
class _WorktreeDiff {
  final String base;
  final String branch;
  final String stat;
  final List<String> files;
  final String diff;
  final bool truncated;
  final int commits;
  final bool dirty;
  const _WorktreeDiff({
    required this.base,
    required this.branch,
    required this.stat,
    required this.files,
    required this.diff,
    required this.truncated,
    required this.commits,
    required this.dirty,
  });

  factory _WorktreeDiff.fromJson(Map<String, dynamic> j) => _WorktreeDiff(
        base: '${j['base'] ?? ''}',
        branch: '${j['branch'] ?? ''}',
        stat: '${j['stat'] ?? ''}',
        files: ((j['files'] as List?) ?? const []).map((e) => '$e').toList(),
        diff: '${j['diff'] ?? ''}',
        truncated: j['truncated'] == true,
        commits: (j['commits'] as num?)?.toInt() ?? 0,
        dirty: j['dirty'] == true,
      );
}

String _errMsg(Object e) => e is ApiException ? e.message : '$e';

/// Worktree panel shown in the kanban card detail view: the isolated git
/// branch the dispatcher ran this card in (when labelled `worktree`), its
/// diff against `base`, and Merge / Rebase / Create PR / Discard actions.
///
/// Renders nothing when the board has no `workspace_dir` and no worktree was
/// found — this is opt-in per-card behaviour, not every card has one.
class WorktreePanel extends ConsumerStatefulWidget {
  const WorktreePanel({
    super.key,
    required this.cardId,
    required this.repo,
    this.cardTitle,
  });

  final int cardId;
  final String? repo;
  final String? cardTitle;

  @override
  ConsumerState<WorktreePanel> createState() => _WorktreePanelState();
}

class _WorktreePanelState extends ConsumerState<WorktreePanel> {
  bool _loading = true;
  String? _error;
  _WorktreeInfo? _info;

  bool _diffExpanded = false;
  bool _diffLoading = false;
  String? _diffError;
  _WorktreeDiff? _diff;

  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant WorktreePanel old) {
    super.didUpdateWidget(old);
    if (old.cardId != widget.cardId || old.repo != widget.repo) {
      _diff = null;
      _diffExpanded = false;
      _load();
    }
  }

  ApiClient get _api => ref.read(apiClientProvider);

  Future<void> _load() async {
    final repo = widget.repo;
    if (repo == null || repo.trim().isEmpty) {
      setState(() {
        _loading = false;
        _info = null;
        _error = null;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await _api.get('/api/worktrees',
          query: {'repo': repo, 'owner': 'kanban:${widget.cardId}'});
      final items = ((r is Map ? r['items'] : null) as List?) ?? const [];
      final found = items
          .whereType<Map>()
          .map((m) => _WorktreeInfo.fromJson(m.cast<String, dynamic>()))
          .firstOrNull;
      if (!mounted) return;
      setState(() {
        _loading = false;
        _info = found;
      });
      if (found != null) _loadDiff(found);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _errMsg(e);
      });
    }
  }

  Future<void> _loadDiff(_WorktreeInfo info) async {
    setState(() {
      _diffLoading = true;
      _diffError = null;
    });
    try {
      final r =
          await _api.get('/api/worktrees/diff', query: {'path': info.path});
      final d = (r is Map ? r['diff'] : null) as Map?;
      if (!mounted) return;
      setState(() {
        _diffLoading = false;
        _diff =
            d == null ? null : _WorktreeDiff.fromJson(d.cast<String, dynamic>());
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _diffLoading = false;
        _diffError = _errMsg(e);
      });
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /// Shared yes/no confirmation used by Merge and Discard.
  Future<bool> _confirm(String title, String message, String confirmLabel,
      {bool danger = false}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        backgroundColor: dctx.colors.surface,
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dctx, false),
              child: Text(dctx.tr('Cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(dctx, true),
              style: danger
                  ? FilledButton.styleFrom(backgroundColor: AppTokens.danger)
                  : null,
              child: Text(confirmLabel)),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _merge() async {
    final info = _info;
    if (info == null) return;
    final ok = await _confirm(
      context.tr('Merge worktree?'),
      context.trArgs(
          'Merge {branch} into the checked-out branch of {repo}? Refused if your checkout has uncommitted changes.',
          {'branch': info.branch, 'repo': info.repo}),
      context.tr('Merge'),
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      await _api.post('/api/worktrees/merge', body: {'path': info.path});
      _snack(L10n.global.t('Merged'));
      await _load();
    } catch (e) {
      _snack(_errMsg(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _rebase() async {
    final info = _info;
    if (info == null) return;
    setState(() => _busy = true);
    try {
      await _api.post('/api/worktrees/rebase', body: {'path': info.path});
      _snack(L10n.global.t('Rebased'));
      await _load();
    } catch (e) {
      _snack(_errMsg(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _createPr() async {
    final info = _info;
    if (info == null) return;
    final titleCtl =
        TextEditingController(text: widget.cardTitle ?? info.branch);
    final bodyCtl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        backgroundColor: dctx.colors.surface,
        title: Text(dctx.tr('Create pull request')),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: titleCtl,
                autofocus: true,
                decoration: InputDecoration(labelText: dctx.tr('Title')),
              ),
              const SizedBox(height: AppTokens.s8),
              TextField(
                controller: bodyCtl,
                maxLines: 4,
                decoration: InputDecoration(
                    labelText: dctx.tr('Description (optional)')),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dctx, false),
              child: Text(dctx.tr('Cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(dctx, true),
              child: Text(dctx.tr('Create PR'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final title = titleCtl.text.trim();
    if (title.isEmpty) return;
    setState(() => _busy = true);
    try {
      final r = await _api.post('/api/worktrees/pr', body: {
        'path': info.path,
        'title': title,
        if (bodyCtl.text.trim().isNotEmpty) 'body': bodyCtl.text.trim(),
      });
      final url = r is Map ? '${r['url'] ?? ''}' : '';
      _snack(url.isEmpty
          ? L10n.global.t('Pull request created')
          : L10n.global.tArgs('Pull request created: {url}', {'url': url}));
    } catch (e) {
      _snack(_errMsg(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _discard() async {
    final info = _info;
    if (info == null) return;
    final ok = await _confirm(
      context.tr('Discard worktree?'),
      context.trArgs(
          'Removes the worktree checkout and deletes the {branch} branch. This cannot be undone.',
          {'branch': info.branch}),
      context.tr('Discard'),
      danger: true,
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      await _api.post('/api/worktrees/remove',
          body: {'path': info.path, 'delete_branch': true});
      _snack(L10n.global.t('Worktree discarded'));
      if (!mounted) return;
      setState(() {
        _info = null;
        _diff = null;
      });
    } catch (e) {
      _snack(_errMsg(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Color _diffLineColor(AppColors c, String l) {
    if (l.startsWith('+') && !l.startsWith('+++')) return AppTokens.success;
    if (l.startsWith('-') && !l.startsWith('---')) return AppTokens.danger;
    if (l.startsWith('@@')) return c.textMuted;
    return c.textSecondary;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppTokens.s12),
        child: Center(
          child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      );
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppTokens.s8),
        child: Text(_error!,
            style: TextStyle(color: AppTokens.danger, fontSize: 12)),
      );
    }
    final info = _info;
    if (info == null) {
      if (widget.repo == null || widget.repo!.trim().isEmpty) {
        return const SizedBox.shrink();
      }
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppTokens.s4),
        child: Text(
          context.tr(
              'Add the "worktree" label to run this card in an isolated branch.'),
          style: TextStyle(color: c.textMuted, fontSize: 12),
        ),
      );
    }

    final diff = _diff;
    final mono = TextStyle(fontFamily: AppTokens.fontMono, fontSize: 11);
    return Container(
      margin: const EdgeInsets.only(top: AppTokens.s8),
      padding: const EdgeInsets.all(AppTokens.s12),
      decoration: BoxDecoration(
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(AppTokens.rLg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.call_split_rounded, size: 16, color: c.accent),
            const SizedBox(width: AppTokens.s8),
            Expanded(
              child: Text(context.tr('Worktree'),
                  style: TextStyle(
                      color: c.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 13)),
            ),
            if (diff?.dirty == true) _chip(context.tr('uncommitted')),
            IconButton(
              tooltip: context.tr('Reload'),
              icon: const Icon(Icons.refresh, size: 16),
              onPressed: _busy ? null : _load,
            ),
          ]),
          const SizedBox(height: 2),
          Text('${info.branch} → ${info.base}',
              style: mono.copyWith(color: c.textSecondary, fontSize: 12)),
          Text(info.path, style: TextStyle(color: c.textMuted, fontSize: 11)),
          const SizedBox(height: AppTokens.s8),
          if (_diffLoading)
            const Padding(
              padding: EdgeInsets.all(AppTokens.s8),
              child: Center(
                  child: SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2))),
            )
          else if (_diffError != null)
            Text(_diffError!,
                style: TextStyle(color: AppTokens.danger, fontSize: 12))
          else if (diff != null) ...[
            if (diff.stat.trim().isNotEmpty)
              Text(diff.stat, style: mono.copyWith(color: c.textSecondary)),
            if (diff.files.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: AppTokens.s4),
                child: Text(diff.files.map((f) => '  $f').join('\n'),
                    style: mono.copyWith(color: c.textMuted)),
              ),
            if (diff.diff.trim().isNotEmpty) ...[
              const SizedBox(height: AppTokens.s4),
              InkWell(
                onTap: () => setState(() => _diffExpanded = !_diffExpanded),
                child: Row(children: [
                  Icon(_diffExpanded ? Icons.expand_less : Icons.expand_more,
                      size: 16, color: c.textMuted),
                  Text(context.tr('Diff'),
                      style: TextStyle(color: c.textMuted, fontSize: 12)),
                ]),
              ),
              if (_diffExpanded) ...[
                Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(maxHeight: 400),
                  padding: const EdgeInsets.all(AppTokens.s8),
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: BorderRadius.circular(AppTokens.rSm),
                    border: Border.all(color: c.border),
                  ),
                  child: SingleChildScrollView(
                    child: SelectionArea(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (final l in diff.diff.split('\n'))
                              Text(l.isEmpty ? ' ' : l,
                                  softWrap: false,
                                  style: mono.copyWith(
                                      height: 1.4,
                                      color: _diffLineColor(c, l))),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                if (diff.truncated)
                  Padding(
                    padding: const EdgeInsets.only(top: AppTokens.s4),
                    child: Text(context.tr('Diff truncated'),
                        style: TextStyle(color: c.textMuted, fontSize: 11)),
                  ),
              ],
            ],
          ],
          const SizedBox(height: AppTokens.s8),
          Wrap(
            spacing: AppTokens.s8,
            runSpacing: AppTokens.s8,
            children: [
              OutlinedButton.icon(
                onPressed: _busy ? null : _merge,
                icon: const Icon(Icons.merge_type, size: 14),
                label: Text(context.tr('Merge')),
              ),
              OutlinedButton.icon(
                onPressed: _busy ? null : _rebase,
                icon: const Icon(Icons.rebase_edit, size: 14),
                label: Text(context.tr('Rebase')),
              ),
              OutlinedButton.icon(
                onPressed: _busy ? null : _createPr,
                icon: const Icon(Icons.call_merge, size: 14),
                label: Text(context.tr('Create PR')),
              ),
              OutlinedButton.icon(
                onPressed: _busy ? null : _discard,
                icon: const Icon(Icons.delete_outline,
                    size: 14, color: AppTokens.danger),
                label: Text(context.tr('Discard'),
                    style: const TextStyle(color: AppTokens.danger)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(String text) => Padding(
        padding: const EdgeInsets.only(right: AppTokens.s8),
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: AppTokens.s6, vertical: 2),
          decoration: BoxDecoration(
            color: AppTokens.warning.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(AppTokens.rSm),
          ),
          child: Text(text,
              style: const TextStyle(
                  color: AppTokens.warning,
                  fontSize: 11,
                  fontWeight: FontWeight.w600)),
        ),
      );
}
