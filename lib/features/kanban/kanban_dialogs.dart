import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/l10n.dart';
import '../../theme/tokens.dart';
import '../projects/project_widgets.dart' show ProjectPicker;
import '../projects/projects_provider.dart'
    show activeProjectsProvider, projectBoardsProvider;
import 'kanban_providers.dart';

/// A folder field with a "Browse…" button. Returns the picked path via [ctl].
class WorkspaceField extends StatefulWidget {
  const WorkspaceField({super.key, required this.controller, this.label = 'Workspace folder (optional)'});
  final TextEditingController controller;
  final String label;

  @override
  State<WorkspaceField> createState() => _WorkspaceFieldState();
}

class _WorkspaceFieldState extends State<WorkspaceField> {
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(context.tr(widget.label),
          style: TextStyle(color: c.textMuted, fontSize: 11)),
      const SizedBox(height: 2),
      Row(children: [
        Expanded(
          child: TextField(
            controller: widget.controller,
            decoration: InputDecoration(
                isDense: true,
                hintText: context.tr('~/work/… (worker outputs land here)')),
          ),
        ),
        const SizedBox(width: AppTokens.s8),
        OutlinedButton.icon(
          onPressed: () async {
            final dir = await FilePicker.platform.getDirectoryPath(
                dialogTitle: context.tr('Choose the board workspace folder'));
            if (dir != null) setState(() => widget.controller.text = dir);
          },
          icon: const Icon(Icons.folder_open, size: 16),
          label: Text(context.tr('Browse…')),
        ),
      ]),
    ]);
  }
}

/// The project a new board belongs to, and the folder that follows from it.
///
/// With a project chosen the folder is the project's root and cannot be edited
/// (a board of a project works in the project's folder); without one, the
/// ordinary workspace field. [locked] fixes the project when the dialog is
/// opened from the project's own page.
class BoardPlacementFields extends ConsumerWidget {
  const BoardPlacementFields({
    super.key,
    required this.projectId,
    required this.onProjectChanged,
    required this.workspace,
    this.locked = false,
  });

  final String? projectId;
  final ValueChanged<String?> onProjectChanged;
  final TextEditingController workspace;
  final bool locked;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final projects = ref.watch(activeProjectsProvider);
    final project = projects.where((p) => p.id == projectId).firstOrNull;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Boards need no project; with none to pick the choice is not offered.
      if (projects.isNotEmpty || project != null) ...[
        Text(context.tr('Project'),
            style: TextStyle(color: c.textMuted, fontSize: 11)),
        ProjectPicker(
            value: projectId, onChanged: onProjectChanged, enabled: !locked),
        const SizedBox(height: AppTokens.s12),
      ],
      if (project == null)
        WorkspaceField(controller: workspace)
      else
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(context.tr('Workspace folder'),
              style: TextStyle(color: c.textMuted, fontSize: 11)),
          const SizedBox(height: 2),
          Row(children: [
            Icon(Icons.lock_outline, size: 14, color: c.textMuted),
            const SizedBox(width: AppTokens.s4),
            Expanded(
              child: Text(project.root,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: c.textSecondary,
                      fontSize: 12.5,
                      fontFamily: AppTokens.fontMono)),
            ),
          ]),
          Text(context.tr('Follows the project — change it in the project.'),
              style: TextStyle(color: c.textMuted, fontSize: 11)),
        ]),
    ]);
  }
}

/// Template picker dropdown. `value` may be a template id, or the special
/// `'__ai__'` sentinel (AI-generated columns) when [allowAi] is true.
const aiTemplateSentinel = '__ai__';

class TemplateDropdown extends ConsumerWidget {
  const TemplateDropdown(
      {super.key,
      required this.value,
      required this.onChanged,
      this.allowAi = false});
  final String value;
  final void Function(String) onChanged;
  final bool allowAi;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final templates = ref.watch(kanbanTemplatesProvider);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(context.tr('Columns template'),
          style: TextStyle(color: c.textMuted, fontSize: 11)),
      templates.when(
        loading: () => const LinearProgressIndicator(),
        error: (e, _) => Text('$e', style: const TextStyle(fontSize: 11)),
        data: (list) {
          final items = <DropdownMenuItem<String>>[
            if (allowAi)
              DropdownMenuItem(
                  value: aiTemplateSentinel,
                  child: Text('✨ ${context.tr('AI generates columns')}')),
            // Builtin names come from the daemon in English; custom ones are
            // user data and pass through untouched.
            for (final t in list)
              DropdownMenuItem(
                  value: t.id,
                  child: Text(t.builtin
                      ? context.tr(t.name)
                      : context.trArgs('{name} (custom)', {'name': t.name}))),
          ];
          final safe = items.any((i) => i.value == value)
              ? value
              : (items.isNotEmpty ? items.first.value! : '');
          return DropdownButton<String>(
            value: safe,
            isExpanded: true,
            underline: Divider(color: c.border, height: 1),
            items: items,
            onChanged: (v) {
              if (v != null) onChanged(v);
            },
          );
        },
      ),
    ]);
  }
}

/// New-board dialog: title + columns template + project / workspace folder.
/// [projectId] opens it already in a project, which then cannot be changed.
Future<void> showNewBoardDialog(BuildContext context, WidgetRef ref,
    {String? projectId}) async {
  final titleCtl = TextEditingController();
  final wsCtl = TextEditingController();
  String template = 'standard';
  String? project = projectId;
  final created = await showDialog<int>(
    context: context,
    builder: (dctx) => StatefulBuilder(
      builder: (dctx, setSt) => AlertDialog(
        backgroundColor: dctx.colors.surface,
        title: Text(dctx.tr('New board')),
        content: SizedBox(
          width: 460,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: titleCtl,
              autofocus: true,
              decoration: InputDecoration(
                  labelText: dctx.tr('Title'),
                  hintText: dctx.tr('e.g. Q3 product launch')),
            ),
            const SizedBox(height: AppTokens.s12),
            TemplateDropdown(
                value: template, onChanged: (v) => setSt(() => template = v)),
            const SizedBox(height: AppTokens.s12),
            BoardPlacementFields(
              projectId: project,
              onProjectChanged: (v) => setSt(() => project = v),
              workspace: wsCtl,
              locked: projectId != null,
            ),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dctx),
              child: Text(dctx.tr('Cancel'))),
          FilledButton(
            onPressed: () async {
              if (titleCtl.text.trim().isEmpty) return;
              final id = await ref.read(kanbanApiProvider).createBoard(
                    titleCtl.text.trim(),
                    templateId: template,
                    workspaceDir: project == null ? wsCtl.text.trim() : null,
                    projectId: project,
                  );
              if (project != null) {
                ref.invalidate(projectBoardsProvider(project!));
              }
              if (dctx.mounted) Navigator.pop(dctx, id);
            },
            child: Text(dctx.tr('Create')),
          ),
        ],
      ),
    ),
  );
  if (created != null) ref.read(openBoardProvider.notifier).state = created;
}

/// AI-board dialog: goal + template (incl. "AI generates columns") + project /
/// workspace folder.
Future<void> showGenerateBoardDialog(BuildContext context, WidgetRef ref) async {
  final goalCtl = TextEditingController();
  final wsCtl = TextEditingController();
  String template = aiTemplateSentinel;
  String? project;
  final ok = await showDialog<bool>(
    context: context,
    builder: (dctx) => StatefulBuilder(
      builder: (dctx, setSt) => AlertDialog(
        backgroundColor: dctx.colors.surface,
        title: Text('✨ ${dctx.tr('AI board from a goal')}'),
        content: SizedBox(
          width: 480,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: goalCtl,
              autofocus: true,
              maxLines: 3,
              decoration: InputDecoration(
                  labelText: dctx.tr('Goal'),
                  hintText:
                      dctx.tr('e.g. Plan a customer workshop in 6 weeks')),
            ),
            const SizedBox(height: AppTokens.s12),
            TemplateDropdown(
                value: template,
                allowAi: true,
                onChanged: (v) => setSt(() => template = v)),
            const SizedBox(height: AppTokens.s12),
            BoardPlacementFields(
              projectId: project,
              onProjectChanged: (v) => setSt(() => project = v),
              workspace: wsCtl,
            ),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dctx, false),
              child: Text(dctx.tr('Cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(dctx, true),
              child: Text(dctx.tr('Generate'))),
        ],
      ),
    ),
  );
  if (ok == true && goalCtl.text.trim().isNotEmpty && context.mounted) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(SnackBar(
        content: Text(context.tr('Generating board with AI…'))));
    try {
      final id = await ref.read(kanbanApiProvider).generateBoard(
            goalCtl.text.trim(),
            templateId: template == aiTemplateSentinel ? null : template,
            workspaceDir: project == null ? wsCtl.text.trim() : null,
            projectId: project,
          );
      if (project != null) ref.invalidate(projectBoardsProvider);
      if (id != null) ref.read(openBoardProvider.notifier).state = id;
    } catch (e) {
      messenger.showSnackBar(SnackBar(
          content: Text(L10n.global.tArgs('AI failed: {e}', {'e': e}))));
    }
  }
}
