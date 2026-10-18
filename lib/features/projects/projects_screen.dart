// Projects: the list, and a project's page with its five tabs.
//
// A project is a folder that sessions and kanban boards work in, with a
// context and facts of its own. Which project is open is
// `openProjectProvider` (the Kanban screen does the same with its boards), so
// other screens can land on a project without a route per project.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/l10n.dart';
import '../../models/project.dart';
import '../../theme/tokens.dart';
import '../../widgets/refresh_on_mount.dart';
import '../../widgets/section_scaffold.dart';
import 'project_boards_tab.dart';
import 'project_chats_tab.dart';
import 'project_context_tab.dart';
import 'project_dialogs.dart';
import 'project_facts_tab.dart';
import 'project_overview_tab.dart';
import 'project_widgets.dart';
import 'projects_provider.dart';

class ProjectsScreen extends ConsumerWidget {
  const ProjectsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Another window may have changed a project: reload when this one is back.
    ref.watch(projectsFocusRefreshProvider);
    final open = ref.watch(openProjectProvider);
    return RefreshOnMount(
      providers: [projectsProvider],
      child: open == null
          ? const _ProjectListView()
          : ProjectDetailView(key: ValueKey(open), projectId: open),
    );
  }
}

// ── List ──────────────────────────────────────────────────────────────────
class _ProjectListView extends ConsumerWidget {
  const _ProjectListView();

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final created = await showCreateProjectDialog(context);
    if (created != null) {
      ref.read(openProjectProvider.notifier).state = created.id;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final projects = ref.watch(projectsProvider);
    final showArchived = ref.watch(showArchivedProjectsProvider);
    return SectionScaffold(
      title: context.tr('Projects'),
      subtitle: context.tr(
          'A folder your sessions and boards work in, with a context and facts of its own'),
      actions: [
        Row(mainAxisSize: MainAxisSize.min, children: [
          Text(context.tr('Show archived'),
              style: TextStyle(color: c.textSecondary, fontSize: 12)),
          const SizedBox(width: AppTokens.s4),
          Switch(
            value: showArchived,
            onChanged: (v) =>
                ref.read(showArchivedProjectsProvider.notifier).state = v,
          ),
        ]),
        const SizedBox(width: AppTokens.s4),
        IconButton(
          tooltip: context.tr('Refresh'),
          icon: const Icon(Icons.refresh, size: 18),
          onPressed: () => ref.invalidate(projectsProvider),
        ),
        const SizedBox(width: AppTokens.s4),
        FilledButton.icon(
          onPressed: () => _create(context, ref),
          icon: const Icon(Icons.add, size: 16),
          label: Text(context.tr('New project')),
        ),
      ],
      body: projects.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(
                context.trArgs('Load failed: {error}',
                    {'error': projectErrorText(context, e)}),
                style: TextStyle(color: c.textMuted)),
            const SizedBox(height: AppTokens.s8),
            TextButton(
                onPressed: () => ref.invalidate(projectsProvider),
                child: Text(context.tr('Refresh'))),
          ]),
        ),
        data: (all) {
          final list =
              showArchived ? all : all.where((p) => !p.archived).toList();
          if (list.isEmpty) {
            return _Empty(
              hasArchived: all.any((p) => p.archived),
              onCreate: () => _create(context, ref),
            );
          }
          return ListView(
            padding: const EdgeInsets.all(AppTokens.s16),
            children: [for (final p in list) _ProjectTile(project: p)],
          );
        },
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.hasArchived, required this.onCreate});
  final bool hasArchived;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.folder_special_outlined, size: 48, color: c.textMuted),
        const SizedBox(height: AppTokens.s12),
        Text(context.tr('No projects yet'),
            style: TextStyle(color: c.textSecondary, fontSize: 15)),
        const SizedBox(height: AppTokens.s4),
        Text(
            hasArchived
                ? context.tr('Archived projects are hidden — turn on “Show archived”.')
                : context.tr(
                    'Create a project to give sessions and boards a folder, a context and facts of their own.'),
            textAlign: TextAlign.center,
            style: TextStyle(color: c.textMuted, fontSize: 12)),
        const SizedBox(height: AppTokens.s16),
        FilledButton.icon(
          onPressed: onCreate,
          icon: const Icon(Icons.add, size: 16),
          label: Text(context.tr('New project')),
        ),
      ]),
    );
  }
}

class _ProjectTile extends ConsumerWidget {
  const _ProjectTile({required this.project});
  final Project project;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final p = project;
    Widget chip(String text, {Color? color}) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(
            border: Border.all(color: (color ?? c.textMuted).withValues(alpha: 0.5)),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(text,
              style: TextStyle(color: color ?? c.textMuted, fontSize: 11)),
        );
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTokens.s8),
      child: Material(
        color: c.surface,
        borderRadius: BorderRadius.circular(AppTokens.rLg),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppTokens.rLg),
          onTap: () => ref.read(openProjectProvider.notifier).state = p.id,
          child: Container(
            padding: const EdgeInsets.all(AppTokens.s16),
            decoration: BoxDecoration(
              border: Border.all(color: c.border),
              borderRadius: BorderRadius.circular(AppTokens.rLg),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.folder_special_outlined,
                    size: 22, color: p.archived ? c.textMuted : c.accent),
                const SizedBox(width: AppTokens.s12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: p.archived ? c.textMuted : c.textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.w600)),
                      if (p.description.isNotEmpty)
                        Text(p.description,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: c.textSecondary, fontSize: 12.5)),
                      const SizedBox(height: 2),
                      Text(p.root,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: c.textMuted,
                              fontSize: 11.5,
                              fontFamily: AppTokens.fontMono)),
                    ],
                  ),
                ),
                const SizedBox(width: AppTokens.s12),
                Wrap(
                  spacing: AppTokens.s4,
                  runSpacing: AppTokens.s4,
                  alignment: WrapAlignment.end,
                  children: [
                    if (!p.rootExists)
                      chip(context.tr('Folder missing'), color: AppTokens.warning),
                    if (p.archived) chip(context.tr('Archived')),
                    chip(context.trArgs('{n} sessions', {'n': p.chatCount})),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Detail ────────────────────────────────────────────────────────────────
class ProjectDetailView extends ConsumerWidget {
  const ProjectDetailView({super.key, required this.projectId});
  final String projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final project = ref.watch(projectProvider(projectId));
    final p = project.valueOrNull;

    void back() => ref.read(openProjectProvider.notifier).state = null;

    return SectionScaffold(
      title: p?.name ?? context.tr('Project'),
      subtitle: p?.root,
      actions: [
        IconButton(
          tooltip: context.tr('Back to projects'),
          icon: const Icon(Icons.arrow_back, size: 18),
          onPressed: back,
        ),
        IconButton(
          tooltip: context.tr('Refresh'),
          icon: const Icon(Icons.refresh, size: 18),
          onPressed: () {
            ref.invalidate(projectProvider(projectId));
            ref.invalidate(projectsProvider);
            ref.invalidate(projectContextProvider(projectId));
            ref.invalidate(projectChatsProvider(projectId));
            ref.invalidate(projectBoardsProvider(projectId));
            ref.invalidate(projectFactsProvider);
          },
        ),
      ],
      body: project.when(
        // Keeps the tabs (and what is typed in them) while a reload runs.
        skipLoadingOnReload: true,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(
                context.trArgs('Load failed: {error}',
                    {'error': projectErrorText(context, e)}),
                style: TextStyle(color: c.textMuted)),
            const SizedBox(height: AppTokens.s8),
            TextButton(
                onPressed: back, child: Text(context.tr('Back to projects'))),
          ]),
        ),
        data: (p) => _DetailBody(project: p),
      ),
    );
  }
}

class _DetailBody extends StatefulWidget {
  const _DetailBody({required this.project});
  final Project project;

  @override
  State<_DetailBody> createState() => _DetailBodyState();
}

class _DetailBodyState extends State<_DetailBody>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 5, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = widget.project;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!p.rootExists)
          _Banner(
            icon: Icons.warning_amber_rounded,
            color: AppTokens.warning,
            text: context.tr(
                'The project folder no longer exists. Sessions cannot start in it until you point the project at a folder that does (Overview).'),
          ),
        if (p.archived)
          _Banner(
            icon: Icons.archive_outlined,
            color: c.textMuted,
            text: context.tr(
                'This project is archived: it takes no new sessions or boards. Restore it in Overview.'),
          ),
        TabBar(
          controller: _tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [
            Tab(text: context.tr('Overview')),
            Tab(text: context.tr('Context')),
            Tab(text: context.tr('Project facts')),
            Tab(text: context.tr('Boards')),
            Tab(text: context.tr('Sessions')),
          ],
        ),
        Divider(height: 1, color: c.border),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            // Dragging the page would fight the text editors inside.
            physics: const NeverScrollableScrollPhysics(),
            children: [
              ProjectOverviewTab(project: p),
              ProjectContextTab(project: p),
              ProjectFactsTab(project: p),
              ProjectBoardsTab(project: p),
              ProjectChatsTab(project: p),
            ],
          ),
        ),
      ],
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.color, required this.text});
  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: color.withValues(alpha: 0.1),
      padding: const EdgeInsets.symmetric(
          horizontal: AppTokens.s24, vertical: AppTokens.s8),
      child: Row(children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: AppTokens.s8),
        Expanded(
          child: Text(text, style: TextStyle(color: color, fontSize: 12.5)),
        ),
      ]),
    );
  }
}
