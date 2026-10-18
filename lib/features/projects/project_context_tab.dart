// A project's Context tab: the markdown the daemon puts in the system prompt
// of every session of the project (and in the instructions of its kanban
// workers), read again on every turn — so an edit counts from the next turn.
//
// A write carries the version it was edited from; the daemon refuses it with a
// 409 and the text as it is now when the file changed in between (a second
// window, or a hand edit of CONTEXT.md). The person then picks which copy wins.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/l10n.dart';
import '../../core/transport/api_client.dart';
import '../../models/project.dart';
import '../../theme/tokens.dart';
import 'project_widgets.dart';
import 'projects_provider.dart';

enum _ConflictChoice { useServer, overwrite, keepEditing }

class ProjectContextTab extends ConsumerStatefulWidget {
  const ProjectContextTab({super.key, required this.project});
  final Project project;

  @override
  ConsumerState<ProjectContextTab> createState() => _ProjectContextTabState();
}

class _ProjectContextTabState extends ConsumerState<ProjectContextTab>
    with AutomaticKeepAliveClientMixin {
  final _ctl = TextEditingController();

  /// The copy the editor was loaded from or last saved, and its version.
  String _baseline = '';
  int _version = 0;
  int _maxChars = ProjectContext.defaultMaxChars;
  bool _loaded = false;

  /// The server's copy moved on while there are unsaved edits here.
  bool _remoteChanged = false;
  bool _busy = false;
  String? _error;

  String get _id => widget.project.id;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _ctl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  bool get _dirty => _ctl.text != _baseline;

  void _adopt(ProjectContext s) {
    _ctl.text = s.content;
    _baseline = s.content;
    _version = s.updatedAt;
    _maxChars = s.maxChars;
    _loaded = true;
    _remoteChanged = false;
  }

  /// A fresh copy from the daemon: taken silently when nothing was edited
  /// here, otherwise noted so the person decides.
  void _onServer(ProjectContext s) {
    if (!_loaded) {
      setState(() => _adopt(s));
    } else if (s.updatedAt != _version) {
      setState(() {
        if (_dirty) {
          _remoteChanged = true;
        } else {
          _adopt(s);
        }
      });
    }
  }

  int get _chars => _ctl.text.trim().runes.length;

  Future<void> _save({int? overwriteVersion}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    final saved = context.tr(
        'Saved — sessions of the project read it from their next turn.');
    try {
      final s = await ref
          .read(projectsApiProvider)
          .saveContext(_id, _ctl.text, overwriteVersion ?? _version);
      if (!mounted) return;
      setState(() {
        _baseline = _ctl.text;
        _version = s.updatedAt;
        _maxChars = s.maxChars;
        _remoteChanged = false;
        _busy = false;
      });
      messenger.showSnackBar(SnackBar(content: Text(saved)));
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      if (e.status == 409 && e.body != null) {
        await _resolveConflict(ProjectContext.fromJson(e.body!));
      } else {
        setState(() => _error = projectErrorText(context, e));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = projectErrorText(context, e);
      });
    }
  }

  /// Shows the text as it is now and lets the person choose what happens to
  /// the edit in progress.
  Future<void> _resolveConflict(ProjectContext current) async {
    final choice = await showDialog<_ConflictChoice>(
      context: context,
      builder: (dctx) => _ConflictDialog(current: current, mine: _ctl.text),
    );
    if (!mounted) return;
    switch (choice) {
      case _ConflictChoice.useServer:
        setState(() => _adopt(current));
      case _ConflictChoice.overwrite:
        // Written against the version just seen, so a third change in between
        // is refused again rather than lost.
        await _save(overwriteVersion: current.updatedAt);
      case _ConflictChoice.keepEditing:
      case null:
        setState(() => _remoteChanged = true);
    }
  }

  Future<void> _reloadFromServer() async {
    ref.invalidate(projectContextProvider(_id));
    try {
      final s = await ref.read(projectContextProvider(_id).future);
      if (mounted) setState(() => _adopt(s));
    } catch (_) {
      // The provider's own error state is shown by build.
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final c = context.colors;
    ref.listen<AsyncValue<ProjectContext>>(projectContextProvider(_id),
        (_, next) => next.whenData(_onServer));
    final server = ref.watch(projectContextProvider(_id));
    if (!_loaded) {
      return server.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Text(
              context.trArgs('Load failed: {error}',
                  {'error': projectErrorText(context, e)}),
              style: TextStyle(color: c.textMuted)),
        ),
        // `_onServer` adopts it on the next frame.
        data: (s) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && !_loaded) setState(() => _adopt(s));
          });
          return const SizedBox.shrink();
        },
      );
    }

    final over = _chars > _maxChars;
    final warn = !over && _chars >= ProjectContext.warnChars;
    final counterColor = over
        ? AppTokens.danger
        : warn
            ? AppTokens.warning
            : c.textMuted;

    return Padding(
      padding: const EdgeInsets.all(AppTokens.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
              context.tr(
                  'Describe the project in markdown: what it is, how it is built, rules to follow. Every session of the project reads it at each turn, and so do its kanban workers. The agent cannot write here.'),
              style: TextStyle(color: c.textMuted, fontSize: 12.5)),
          if (widget.project.hasClaudeMd)
            Padding(
              padding: const EdgeInsets.only(top: AppTokens.s4),
              child: Text(
                  context.tr(
                      'The folder already has a CLAUDE.md, which the agent reads as well — this context adds to it.'),
                  style: TextStyle(color: c.textMuted, fontSize: 12.5)),
            ),
          if (_remoteChanged)
            Padding(
              padding: const EdgeInsets.only(top: AppTokens.s8),
              child: Row(children: [
                const Icon(Icons.sync_problem,
                    size: 16, color: AppTokens.warning),
                const SizedBox(width: AppTokens.s8),
                Expanded(
                  child: Text(
                      context.tr(
                          'The context changed elsewhere while you were editing. Saving will show both copies.'),
                      style: const TextStyle(
                          color: AppTokens.warning, fontSize: 12.5)),
                ),
                TextButton(
                    onPressed: _reloadFromServer,
                    child: Text(context.tr('Discard my edits and reload'))),
              ]),
            ),
          const SizedBox(height: AppTokens.s12),
          Expanded(
            child: TextField(
              controller: _ctl,
              expands: true,
              maxLines: null,
              minLines: null,
              textAlignVertical: TextAlignVertical.top,
              style: const TextStyle(
                  fontSize: 13, height: 1.4, fontFamily: AppTokens.fontMono),
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                hintText: context.tr('# What this project is…'),
              ),
            ),
          ),
          const SizedBox(height: AppTokens.s8),
          Row(children: [
            Text(
                context.trArgs('{n} / {max} characters',
                    {'n': _chars, 'max': _maxChars}),
                style: TextStyle(
                    color: counterColor,
                    fontSize: 12,
                    fontWeight: over || warn ? FontWeight.w600 : null)),
            const SizedBox(width: AppTokens.s8),
            Expanded(
              child: Text(
                  over
                      ? context.tr(
                          'Past the limit, the end is cut when the context goes into the prompt.')
                      : warn
                          ? context.tr(
                              'Getting long: it is sent at every turn, so it costs tokens each time.')
                          : '',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: counterColor, fontSize: 12)),
            ),
            TextButton(
              onPressed: _dirty && !_busy
                  ? () => setState(() {
                        _ctl.text = _baseline;
                        _error = null;
                      })
                  : null,
              child: Text(context.tr('Revert')),
            ),
            const SizedBox(width: AppTokens.s8),
            FilledButton(
              onPressed: _dirty && !_busy ? _save : null,
              child: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(context.tr('Save context')),
            ),
          ]),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: AppTokens.s8),
              child: Text(_error!,
                  style:
                      const TextStyle(color: AppTokens.danger, fontSize: 12)),
            ),
        ],
      ),
    );
  }
}

/// "The context changed elsewhere": the current text, the person's own, and
/// the three things they can do.
class _ConflictDialog extends StatelessWidget {
  const _ConflictDialog({required this.current, required this.mine});
  final ProjectContext current;
  final String mine;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget copy(String title, String text) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: TextStyle(
                      color: c.textPrimary,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: AppTokens.s4),
              Container(
                height: 240,
                width: double.infinity,
                padding: const EdgeInsets.all(AppTokens.s8),
                decoration: BoxDecoration(
                  color: c.surfaceAlt,
                  border: Border.all(color: c.border),
                  borderRadius: BorderRadius.circular(AppTokens.rMd),
                ),
                child: SingleChildScrollView(
                  child: SelectableText(
                    text.isEmpty ? context.tr('(empty)') : text,
                    style: TextStyle(
                        color: c.textSecondary,
                        fontSize: 12,
                        fontFamily: AppTokens.fontMono),
                  ),
                ),
              ),
            ],
          ),
        );
    return AlertDialog(
      backgroundColor: c.surface,
      title: Text(context.tr('The context changed elsewhere')),
      content: SizedBox(
        width: 760,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                context.tr(
                    'Someone else saved the context (or its file was edited) after you opened it. Choose which copy to keep.'),
                style: TextStyle(color: c.textSecondary, fontSize: 13)),
            const SizedBox(height: AppTokens.s12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                copy(context.tr('On the daemon now'), current.content),
                const SizedBox(width: AppTokens.s12),
                copy(context.tr('Your edit'), mine),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () =>
                Navigator.of(context).pop(_ConflictChoice.keepEditing),
            child: Text(context.tr('Keep editing'))),
        OutlinedButton(
            onPressed: () =>
                Navigator.of(context).pop(_ConflictChoice.useServer),
            child: Text(context.tr('Use the daemon’s copy'))),
        FilledButton(
            onPressed: () =>
                Navigator.of(context).pop(_ConflictChoice.overwrite),
            child: Text(context.tr('Overwrite with mine'))),
      ],
    );
  }
}
