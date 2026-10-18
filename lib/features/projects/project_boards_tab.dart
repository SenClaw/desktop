// A project's Boards tab: the kanban boards that belong to it, and the folder
// each board's workers run in.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/i18n/l10n.dart';
import '../../models/project.dart';
import '../../theme/tokens.dart';
import '../kanban/kanban_dialogs.dart' show showNewBoardDialog;
import '../kanban/kanban_providers.dart' show openBoardProvider;
import 'project_widgets.dart';
import 'projects_provider.dart';

class ProjectBoardsTab extends ConsumerWidget {
  const ProjectBoardsTab({super.key, required this.project});
  final Project project;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final boards = ref.watch(projectBoardsProvider(project.id));
    return Padding(
      padding: const EdgeInsets.all(AppTokens.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Expanded(
              child: Text(
                  context.tr(
                      'Kanban boards of this project. Their cards run in the project folder, with the project context.'),
                  style: TextStyle(color: c.textMuted, fontSize: 12.5)),
            ),
            const SizedBox(width: AppTokens.s12),
            FilledButton.icon(
              onPressed: project.archived
                  ? null
                  : () async {
                      final before = ref.read(openBoardProvider);
                      await showNewBoardDialog(context, ref,
                          projectId: project.id);
                      ref.invalidate(projectBoardsProvider(project.id));
                      if (!context.mounted) return;
                      // The dialog opens the board it made.
                      if (ref.read(openBoardProvider) != before) {
                        context.go('/kanban');
                      }
                    },
              icon: const Icon(Icons.add, size: 16),
              label: Text(context.tr('New board')),
            ),
          ]),
          if (project.archived)
            Padding(
              padding: const EdgeInsets.only(top: AppTokens.s4),
              child: Text(
                  context.tr('An archived project takes no new boards.'),
                  style: const TextStyle(
                      color: AppTokens.warning, fontSize: 12.5)),
            ),
          const SizedBox(height: AppTokens.s12),
          Expanded(
            child: boards.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Text(
                    context.trArgs('Load failed: {error}',
                        {'error': projectErrorText(context, e)}),
                    style: TextStyle(color: c.textMuted)),
              ),
              data: (list) {
                if (list.isEmpty) {
                  return Center(
                    child: Text(context.tr('This project has no boards yet.'),
                        style: TextStyle(color: c.textMuted)),
                  );
                }
                return ListView.separated(
                  itemCount: list.length,
                  separatorBuilder: (_, _) => Divider(height: 1, color: c.border),
                  itemBuilder: (_, i) => _BoardTile(board: list[i]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _BoardTile extends ConsumerWidget {
  const _BoardTile({required this.board});
  final ProjectBoard board;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final dir = board.effectiveWorkspaceDir;
    return ListTile(
      dense: true,
      leading: Icon(Icons.view_kanban_outlined, color: c.accent),
      title: Text(board.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        dir == null || dir.isEmpty
            ? context.tr('Runs in a scratch folder')
            : context.trArgs('Runs in {dir}', {'dir': dir}),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
            color: c.textMuted, fontSize: 11.5, fontFamily: AppTokens.fontMono),
      ),
      trailing: Text(context.trArgs('{n} cards', {'n': board.cardCount}),
          style: TextStyle(color: c.textMuted, fontSize: 12)),
      onTap: () {
        ref.read(openBoardProvider.notifier).state = board.id;
        context.go('/kanban');
      },
    );
  }
}
