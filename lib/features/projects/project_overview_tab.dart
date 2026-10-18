// A project's Overview tab: what it is called and where it lives, where its
// facts go, archive/restore, and deleting it for good.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/l10n.dart';
import '../../models/project.dart';
import '../../theme/tokens.dart';
import 'project_dialogs.dart';
import 'project_widgets.dart';
import 'projects_provider.dart';

class ProjectOverviewTab extends ConsumerStatefulWidget {
  const ProjectOverviewTab({super.key, required this.project});
  final Project project;

  @override
  ConsumerState<ProjectOverviewTab> createState() => _ProjectOverviewTabState();
}

class _ProjectOverviewTabState extends ConsumerState<ProjectOverviewTab>
    with AutomaticKeepAliveClientMixin {
  late final TextEditingController _name;
  late final TextEditingController _description;
  late final TextEditingController _root;
  final _rootState = ValueNotifier<RootFieldState>(RootFieldState.idle);
  late String _factsWrite;
  late bool _inheritCommon;
  bool _busy = false;
  String? _error;

  Project get _p => widget.project;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: _p.name);
    _description = TextEditingController(text: _p.description);
    _root = TextEditingController(text: _p.root)
      ..addListener(() => setState(() {}));
    _factsWrite = _p.factsWrite;
    _inheritCommon = _p.inheritCommon;
  }

  @override
  void didUpdateWidget(ProjectOverviewTab old) {
    super.didUpdateWidget(old);
    // A reload brings the saved values back; edits in progress stay. What the
    // form is compared with moves to the new values either way.
    if (old.project.updatedAt != _p.updatedAt && !_dirtyAgainst(old.project)) {
      _name.text = _p.name;
      _description.text = _p.description;
      _root.text = _p.root;
      _factsWrite = _p.factsWrite;
      _inheritCommon = _p.inheritCommon;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _root.dispose();
    _rootState.dispose();
    super.dispose();
  }

  bool _dirtyAgainst(Project p) =>
      _name.text.trim() != p.name ||
      _description.text.trim() != p.description ||
      _root.text.trim() != p.root ||
      _factsWrite != p.factsWrite ||
      _inheritCommon != p.inheritCommon;

  bool get _dirty => _dirtyAgainst(_p);
  bool get _rootChanged => _root.text.trim() != _p.root;
  bool get _canSave =>
      !_busy &&
      _dirty &&
      _name.text.trim().isNotEmpty &&
      (!_rootChanged || _rootState.value.valid);

  void _revert() {
    setState(() {
      _name.text = _p.name;
      _description.text = _p.description;
      _root.text = _p.root;
      _factsWrite = _p.factsWrite;
      _inheritCommon = _p.inheritCommon;
      _error = null;
    });
  }

  Future<void> _save() async {
    final patch = <String, Object?>{
      if (_name.text.trim() != _p.name) 'name': _name.text.trim(),
      if (_description.text.trim() != _p.description)
        'description': _description.text.trim(),
      if (_rootChanged) 'root': _root.text.trim(),
      if (_factsWrite != _p.factsWrite) 'factsWrite': _factsWrite,
      if (_inheritCommon != _p.inheritCommon) 'inheritCommon': _inheritCommon,
    };
    setState(() {
      _busy = true;
      _error = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    final saved = context.tr('Saved');
    try {
      await ref.read(projectsApiProvider).update(_p.id, patch);
      if (!mounted) return;
      setState(() => _busy = false);
      messenger.showSnackBar(SnackBar(content: Text(saved)));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = projectErrorText(context, e);
      });
    }
  }

  Future<void> _toggleArchive() async {
    final messenger = ScaffoldMessenger.of(context);
    final archiving = !_p.archived;
    final msg = context.tr(archiving ? 'Project archived' : 'Project restored');
    try {
      await ref.read(projectsApiProvider).setArchived(_p.id, archiving);
      messenger.showSnackBar(SnackBar(content: Text(msg)));
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
          SnackBar(content: Text(projectErrorText(context, e))));
    }
  }

  Future<void> _purge() async {
    final done = await showPurgeProjectDialog(context, _p);
    if (done == null || !mounted) return;
    ref.read(openProjectProvider.notifier).state = null;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(context.trArgs(
            'Project deleted — {facts} facts removed, {chats} sessions detached.',
            {'facts': done.deletedFacts, 'chats': done.detachedChats}))));
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final c = context.colors;
    return ListView(
      padding: const EdgeInsets.all(AppTokens.s24),
      children: [
        Align(
          alignment: Alignment.topLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _facts(context),
                const SizedBox(height: AppTokens.s16),
                TextField(
                  controller: _name,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                      isDense: true, labelText: context.tr('Name')),
                ),
                const SizedBox(height: AppTokens.s12),
                TextField(
                  controller: _description,
                  maxLines: 2,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                      isDense: true, labelText: context.tr('Description')),
                ),
                const SizedBox(height: AppTokens.s12),
                ProjectRootField(
                  controller: _root,
                  state: _rootState,
                  projectId: _p.id,
                  unchanged: _p.root,
                ),
                if (_rootChanged)
                  Padding(
                    padding: const EdgeInsets.only(top: AppTokens.s4),
                    child: Text(
                        context.tr(
                            'A new folder applies to new sessions and to boards. A session that is already running keeps the folder it started in.'),
                        style: TextStyle(color: c.textMuted, fontSize: 11.5)),
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
                const SizedBox(height: AppTokens.s12),
                // Rebuilds with the root check, which changes without setState.
                ListenableBuilder(
                  listenable: _rootState,
                  builder: (context, _) => Row(children: [
                    FilledButton(
                      onPressed: _canSave ? _save : null,
                      child: _busy
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : Text(context.tr('Save changes')),
                    ),
                    const SizedBox(width: AppTokens.s8),
                    TextButton(
                      onPressed: _dirty && !_busy ? _revert : null,
                      child: Text(context.tr('Revert')),
                    ),
                  ]),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: AppTokens.s8),
                    child: Text(_error!,
                        style: const TextStyle(
                            color: AppTokens.danger, fontSize: 12)),
                  ),
                const SizedBox(height: AppTokens.s24),
                Divider(color: c.border),
                const SizedBox(height: AppTokens.s12),
                _section(
                  context,
                  title: _p.archived ? 'Restore' : 'Archive',
                  text: _p.archived
                      ? 'The project is archived: hidden from lists and closed to new sessions and boards. Restoring brings it back.'
                      : 'Hide the project and close it to new sessions and boards. Its sessions, boards, facts and context stay as they are, and you can restore it.',
                  button: OutlinedButton(
                    onPressed: _toggleArchive,
                    child: Text(
                        context.tr(_p.archived ? 'Restore project' : 'Archive project')),
                  ),
                ),
                const SizedBox(height: AppTokens.s16),
                _section(
                  context,
                  title: 'Delete for good',
                  text:
                      'Removes the project, its facts and its context. Its sessions and boards stay, without the project. Nothing in the project folder is touched.',
                  button: OutlinedButton(
                    onPressed: _purge,
                    style: OutlinedButton.styleFrom(
                        foregroundColor: AppTokens.danger,
                        side: const BorderSide(color: AppTokens.danger)),
                    child: Text(context.tr('Delete permanently…')),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// What the daemon knows about the project that is not a setting.
  Widget _facts(BuildContext context) {
    final c = context.colors;
    Widget chip(IconData icon, String text, {Color? color}) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: c.surfaceAlt,
            borderRadius: BorderRadius.circular(AppTokens.rSm),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 13, color: color ?? c.textMuted),
            const SizedBox(width: 4),
            Text(text, style: TextStyle(color: color ?? c.textSecondary, fontSize: 12)),
          ]),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(spacing: AppTokens.s8, runSpacing: AppTokens.s8, children: [
          if (!_p.rootExists)
            chip(Icons.warning_amber_rounded, context.tr('Folder missing'),
                color: AppTokens.warning),
          if (_p.archived) chip(Icons.archive_outlined, context.tr('Archived')),
          if (_p.isGit) chip(Icons.merge_type, context.tr('Git repository')),
          if (_p.hasClaudeMd)
            chip(Icons.description_outlined, context.tr('Has CLAUDE.md')),
          chip(Icons.forum_outlined,
              context.trArgs('{n} sessions', {'n': _p.chatCount})),
        ]),
        const SizedBox(height: AppTokens.s8),
        SelectableText(
          '${_p.id}  ·  ${context.tr('created')} ${formatStamp(_p.createdAt)}',
          style: TextStyle(
              color: c.textMuted,
              fontSize: 11,
              fontFamily: AppTokens.fontMono),
        ),
      ],
    );
  }

  Widget _section(BuildContext context,
      {required String title, required String text, required Widget button}) {
    final c = context.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(context.tr(title),
                  style: TextStyle(
                      color: c.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(context.tr(text),
                  style: TextStyle(color: c.textMuted, fontSize: 12)),
            ],
          ),
        ),
        const SizedBox(width: AppTokens.s16),
        button,
      ],
    );
  }
}
