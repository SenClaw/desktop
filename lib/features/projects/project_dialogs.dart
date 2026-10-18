// The two dialogs of the project screens: creating a project, and deleting
// one for good.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/l10n.dart';
import '../../core/transport/api_client.dart';
import '../../models/project.dart';
import '../../theme/tokens.dart';
import 'project_widgets.dart';
import 'projects_provider.dart';

/// Returns the created project, or null when the person cancels.
Future<Project?> showCreateProjectDialog(BuildContext context) =>
    showDialog<Project>(
        context: context, builder: (_) => const CreateProjectDialog());

class CreateProjectDialog extends ConsumerStatefulWidget {
  const CreateProjectDialog({super.key});

  @override
  ConsumerState<CreateProjectDialog> createState() =>
      _CreateProjectDialogState();
}

class _CreateProjectDialogState extends ConsumerState<CreateProjectDialog> {
  final _name = TextEditingController();
  final _root = TextEditingController();
  final _description = TextEditingController();
  final _rootState = ValueNotifier<RootFieldState>(RootFieldState.idle);
  String _factsWrite = 'project';
  bool _inheritCommon = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _root.dispose();
    _description.dispose();
    _rootState.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      !_busy && _name.text.trim().isNotEmpty && _rootState.value.valid;

  /// A folder picked in the system dialog proposes its own name, unless the
  /// person already typed one.
  void _proposeName(String dir) {
    if (_name.text.trim().isNotEmpty) return;
    final base = dir.split('/').where((s) => s.isNotEmpty).lastOrNull;
    if (base != null) _name.text = base;
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final p = await ref.read(projectsApiProvider).create(
            name: _name.text.trim(),
            root: _root.text.trim(),
            description: _description.text.trim(),
            factsWrite: _factsWrite,
            inheritCommon: _inheritCommon,
          );
      if (mounted) Navigator.of(context).pop(p);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = projectErrorText(context, e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AlertDialog(
      backgroundColor: c.surface,
      title: Text(context.tr('New project')),
      content: SizedBox(
        width: 540,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                  context.tr(
                      'Sessions and kanban boards of a project work in its folder, read its context, and share its facts.'),
                  style: TextStyle(color: c.textMuted, fontSize: 12)),
              const SizedBox(height: AppTokens.s12),
              TextField(
                controller: _name,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                    isDense: true, labelText: context.tr('Name')),
              ),
              const SizedBox(height: AppTokens.s12),
              ProjectRootField(
                controller: _root,
                state: _rootState,
                onPicked: _proposeName,
              ),
              const SizedBox(height: AppTokens.s12),
              TextField(
                controller: _description,
                maxLines: 2,
                decoration: InputDecoration(
                    isDense: true,
                    labelText: context.tr('Description (optional)')),
              ),
              const SizedBox(height: AppTokens.s12),
              FactsWriteField(
                  value: _factsWrite,
                  onChanged: (v) => setState(() => _factsWrite = v)),
              SwitchListTile(
                value: _inheritCommon,
                onChanged: (v) => setState(() => _inheritCommon = v),
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(context.tr('Also read the agent’s common facts'),
                    style: const TextStyle(fontSize: 13)),
                subtitle: Text(
                    context.tr(
                        'Off: only the project’s own facts are recalled in its chats.'),
                    style: TextStyle(color: c.textMuted, fontSize: 11.5)),
              ),
              if (_error != null) ...[
                const SizedBox(height: AppTokens.s8),
                Text(_error!,
                    style: const TextStyle(
                        color: AppTokens.danger, fontSize: 12)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            child: Text(context.tr('Cancel'))),
        ListenableBuilder(
          listenable: _rootState,
          builder: (context, _) => FilledButton(
            onPressed: _canSubmit ? _submit : null,
            child: _busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Text(context.tr('Create')),
          ),
        ),
      ],
    );
  }
}

/// Returns what the daemon deleted, or null when the person cancels (or the
/// daemon did not answer in time — the screens reload either way).
Future<ProjectPurge?> showPurgeProjectDialog(
        BuildContext context, Project project) =>
    showDialog<ProjectPurge>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PurgeProjectDialog(project: project),
    );

class PurgeProjectDialog extends ConsumerStatefulWidget {
  const PurgeProjectDialog({super.key, required this.project});
  final Project project;

  @override
  ConsumerState<PurgeProjectDialog> createState() => _PurgeProjectDialogState();
}

class _PurgeProjectDialogState extends ConsumerState<PurgeProjectDialog> {
  bool _busy = false;
  String? _error;
  bool _timedOut = false;

  /// Banks past this size make the wait worth a warning of its own.
  static const _slowFacts = 5000;

  Future<void> _purge() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final api = ref.read(projectsApiProvider);
    try {
      final done = await api.purge(widget.project.id);
      if (mounted) Navigator.of(context).pop(done);
    } on ApiTimeout {
      // The daemon carries on without us: say so, and reload to see where it got.
      api.refreshAfterPurge(widget.project.id);
      if (mounted) {
        setState(() {
          _busy = false;
          _timedOut = true;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = projectErrorText(context, e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = widget.project;
    final boards = ref.watch(projectBoardsProvider(p.id));
    final facts = ref.watch(
        projectFactsProvider((id: p.id, q: '', history: false)));
    String count(AsyncValue<Object?> v, int? Function() n) =>
        v.hasValue ? '${n() ?? 0}' : (v.hasError ? '?' : '…');
    final factTotal = facts.valueOrNull?.total ?? 0;

    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        backgroundColor: c.surface,
        title: Text(
            context.trArgs('Delete “{name}” for good?', {'name': p.name})),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_timedOut)
                  Text(
                      context.tr(
                          'The daemon has not answered yet, but it may still be deleting. Close this and reload in a minute.'),
                      style: const TextStyle(
                          color: AppTokens.warning, fontSize: 13))
                else ...[
                  Text(
                      context.tr(
                          'This cannot be undone. Nothing inside the project folder is touched.'),
                      style: TextStyle(color: c.textSecondary, fontSize: 13)),
                  const SizedBox(height: AppTokens.s12),
                  _line(
                      context,
                      context.trArgs(
                          '{n} sessions leave the project and keep their history; from now on they run like any other session.',
                          {'n': p.chatCount})),
                  _line(
                      context,
                      context.trArgs(
                          '{n} boards leave the project and keep running in the folder they ran in.',
                          {'n': count(boards, () => boards.value?.length)})),
                  _line(
                      context,
                      context.trArgs('{n} facts of the project are deleted.',
                          {'n': count(facts, () => facts.value?.total)})),
                  _line(context, context.tr('The project context is deleted.')),
                  const SizedBox(height: AppTokens.s12),
                  Text(
                      context.tr(
                          'Deleting a large fact bank is slow: about 23 seconds for 20,000 facts. Keep the app open until it finishes.'),
                      style: TextStyle(
                          color: factTotal >= _slowFacts
                              ? AppTokens.warning
                              : c.textMuted,
                          fontSize: 12)),
                ],
                if (_busy) ...[
                  const SizedBox(height: AppTokens.s12),
                  const LinearProgressIndicator(),
                  const SizedBox(height: AppTokens.s4),
                  Text(context.tr('Deleting…'),
                      style: TextStyle(color: c.textMuted, fontSize: 12)),
                ],
                if (_error != null) ...[
                  const SizedBox(height: AppTokens.s8),
                  Text(_error!,
                      style: const TextStyle(
                          color: AppTokens.danger, fontSize: 12)),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: _busy ? null : () => Navigator.of(context).pop(),
              child: Text(_timedOut ? context.tr('Close') : context.tr('Cancel'))),
          if (!_timedOut)
            FilledButton(
              onPressed: _busy ? null : _purge,
              style: FilledButton.styleFrom(
                  backgroundColor: AppTokens.danger,
                  foregroundColor: Colors.white),
              child: Text(context.tr('Delete permanently')),
            ),
        ],
      ),
    );
  }

  Widget _line(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.only(bottom: AppTokens.s4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('•  ', style: TextStyle(color: context.colors.textMuted)),
            Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
          ],
        ),
      );
}
