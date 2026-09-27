import 'package:flutter_test/flutter_test.dart';

import 'package:senclaw_desktop/features/chat/dispatch_ownership.dart';
import 'package:senclaw_desktop/features/dock/dispatch_provider.dart';
import 'package:senclaw_desktop/models/chat_message.dart';

/// A DAG card must appear in the chat that asked for it and nowhere else.
///
/// The bug: `adminFolder` is the agent profile, shared by every session
/// started under it, so a brand-new chat showed every DAG that profile had
/// ever run.
void main() {
  DispatchParent parent({
    String id = 'p-7',
    String folder = 'main',
    String chatJid = '',
  }) =>
      DispatchParent(
        id: id,
        goal: 'do a thing',
        status: 'done',
        adminFolder: folder,
        chatJid: chatJid,
        createdAt: '2026-09-12T10:00:00+00:00',
        tasks: const [],
      );

  ChatMessage toolMsg(String content) => ChatMessage(
        id: 'tool-${content.hashCode}',
        kind: MessageKind.tool,
        data: {
          'toolName': 'DispatchCreateParentAndRun',
          'title': 'DispatchCreateParentAndRun',
          'content': content,
        },
      );

  test('a stamped parent belongs to its own chat only', () {
    final p = parent(chatJid: 'web:main:aaa');
    expect(ownsDispatchParent(p, 'web:main:aaa', const []), isTrue);
    expect(ownsDispatchParent(p, 'web:main:bbb', const []), isFalse);
  });

  test('a legacy parent is claimed by the chat whose tool call created it', () {
    final p = parent(id: 'p-7');
    final creating = [toolMsg('Parent task created: p-7\nStatus: ACTIVE')];
    expect(ownsDispatchParent(p, 'web:main:aaa', creating), isTrue);
    // The other session never mentioned it, so it does not show there.
    expect(ownsDispatchParent(p, 'web:main:bbb', const []), isFalse);
  });

  test('a legacy parent nobody claims is shown nowhere, not everywhere', () {
    // Same profile, no tool call mentioning it: a card in the wrong
    // conversation is worse than a missing one.
    final p = parent(id: 'p-9');
    expect(ownsDispatchParent(p, 'web:main:aaa', [toolMsg('ls -la')]), isFalse);
  });

  test('a parent id does not match a longer one that contains it', () {
    // `p-1` inside `p-12` would attribute the wrong DAG to this chat.
    final p = parent(id: 'p-1');
    final other = [toolMsg('Parent task created: p-12')];
    expect(ownsDispatchParent(p, 'web:main:aaa', other), isFalse);
    final own = [toolMsg('Parent task created: p-1')];
    expect(ownsDispatchParent(p, 'web:main:aaa', own), isTrue);
  });

  test('only tool messages are searched', () {
    // A user who typed the parent id into the chat does not thereby own it.
    final p = parent(id: 'p-7');
    final typed = [
      ChatMessage(
        id: 'u1',
        kind: MessageKind.user,
        text: 'what happened to p-7?',
      ),
    ];
    expect(ownsDispatchParent(p, 'web:main:aaa', typed), isFalse);
  });
}
