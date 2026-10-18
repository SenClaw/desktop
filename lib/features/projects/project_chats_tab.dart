// A project's Sessions tab: the sessions created in it. A session belongs to a
// project from the moment it is created and cannot be moved, so this list only
// grows (until a session is deleted).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/i18n/l10n.dart';
import '../../models/project.dart';
import '../../theme/tokens.dart';
import '../chat/agents_provider.dart' show selectedJidProvider;
import '../chat/new_chat_dialog.dart' show showNewChatProvider;
import 'project_widgets.dart';
import 'projects_provider.dart';

class ProjectChatsTab extends ConsumerWidget {
  const ProjectChatsTab({super.key, required this.project});
  final Project project;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final chats = ref.watch(projectChatsProvider(project.id));
    return Padding(
      padding: const EdgeInsets.all(AppTokens.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Expanded(
              child: Text(
                  context.tr(
                      'Sessions created in this project work in its folder. A session cannot be moved into or out of a project later.'),
                  style: TextStyle(color: c.textMuted, fontSize: 12.5)),
            ),
            const SizedBox(width: AppTokens.s12),
            FilledButton.icon(
              onPressed: project.archived
                  ? null
                  : () {
                      ref.read(newChatProjectProvider.notifier).state =
                          project.id;
                      ref.read(showNewChatProvider.notifier).state = true;
                      context.go('/chat');
                    },
              icon: const Icon(Icons.add, size: 16),
              label: Text(context.tr('New session here')),
            ),
          ]),
          if (project.archived)
            Padding(
              padding: const EdgeInsets.only(top: AppTokens.s4),
              child: Text(
                  context.tr('An archived project takes no new sessions.'),
                  style: const TextStyle(
                      color: AppTokens.warning, fontSize: 12.5)),
            ),
          const SizedBox(height: AppTokens.s12),
          Expanded(
            child: chats.when(
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
                    child: Text(
                        context.tr('No session has been created in this project yet.'),
                        style: TextStyle(color: c.textMuted)),
                  );
                }
                return ListView.separated(
                  itemCount: list.length,
                  separatorBuilder: (_, _) => Divider(height: 1, color: c.border),
                  itemBuilder: (_, i) => _ChatTile(chat: list[i]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatTile extends ConsumerWidget {
  const _ChatTile({required this.chat});
  final ProjectChat chat;

  /// `last_active` is an ISO timestamp; anything else is shown as it came.
  String _when(String? raw) {
    if (raw == null || raw.isEmpty) return '';
    final d = DateTime.tryParse(raw);
    return d == null ? raw : formatStamp(d.toLocal().millisecondsSinceEpoch);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final isCode = chat.groupType == 'code';
    return ListTile(
      dense: true,
      leading: Icon(isCode ? Icons.terminal : Icons.chat_bubble_outline,
          color: c.accent, size: 20),
      title: Text(chat.name.isEmpty ? chat.jid : chat.name,
          maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [
          context.tr(isCode ? 'Code' : 'Chat'),
          if (chat.folder.isNotEmpty) chat.folder,
        ].join(' · '),
        style: TextStyle(color: c.textMuted, fontSize: 11.5),
      ),
      trailing: Text(_when(chat.lastActive),
          style: TextStyle(color: c.textMuted, fontSize: 12)),
      onTap: () {
        ref.read(showNewChatProvider.notifier).state = false;
        ref.read(selectedJidProvider.notifier).state = chat.jid;
        context.go('/chat');
      },
    );
  }
}
