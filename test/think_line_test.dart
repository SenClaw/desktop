import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:senclaw_desktop/core/i18n/l10n.dart';
import 'package:senclaw_desktop/features/chat/widgets/message_widgets.dart';
import 'package:senclaw_desktop/models/chat_message.dart';
import 'package:senclaw_desktop/theme/app_theme.dart';
import 'package:senclaw_desktop/theme/tokens.dart';

/// A model's reasoning is a quiet line of its own, like a tool group's, and it
/// is never part of a tool group or of the answer's bubble.
void main() {
  ChatMessage agent(String text,
          {int? tokens, bool streaming = false, String id = 'a'}) =>
      ChatMessage(
        id: id,
        kind: MessageKind.agent,
        text: text,
        tokens: tokens,
        streaming: streaming,
      );

  ChatMessage bash(String title, String description) => ChatMessage(
        id: 'tool-$title',
        kind: MessageKind.tool,
        data: {
          'toolName': 'Bash',
          'title': title,
          'summary': '',
          'description': description,
          'ok': true,
          'content': {'stdout': 'x'},
        },
      );

  Widget item(ChatMessage m) => MessageItem(
        message: m,
        onPermission: (id, key) {},
        onQuestion: (id, answers, other) {},
        onForm: (id, values, submitted) {},
      );

  Widget host(List<Widget> children) => MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ),
      );

  // The box a quiet line opens into: filled, bordered, rounded like a tool
  // group's. Found by its radius so both are measured the same way.
  final box = find.byWidgetPredicate((w) =>
      w is Container &&
      w.decoration is BoxDecoration &&
      (w.decoration as BoxDecoration).borderRadius ==
          BorderRadius.circular(AppTokens.rXl));

  testWidgets('closed, reasoning is one quiet line with its size after it',
      (tester) async {
    await tester.pumpWidget(host([
      item(agent('<think>First I look.\n\nThen I write.</think>', tokens: 718)),
    ]));
    await tester.pump();

    expect(find.text('think'), findsOneWidget);
    expect(find.text('718 tok'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_right), findsOneWidget);
    // No bulb, no bubble, and none of the words yet.
    expect(find.byIcon(Icons.lightbulb), findsNothing);
    expect(find.textContaining('First I look', findRichText: true),
        findsNothing);
    expect(box, findsNothing);
  });

  testWidgets('opened, it is the same rounded box a tool group opens into',
      (tester) async {
    await tester.pumpWidget(host([
      item(agent('<think>First I look.</think>', tokens: 12)),
      ToolGroupCard(tools: [bash('ls', 'List the crate root')]),
    ]));
    await tester.pump();

    await tester.tap(find.text('think'));
    await tester.pump();
    expect(find.textContaining('First I look', findRichText: true),
        findsOneWidget);
    expect(find.byIcon(Icons.arrow_drop_down), findsOneWidget);
    expect(box, findsOneWidget);

    // A tool group opens into a box of exactly this look.
    await tester.tap(find.text('Ran a command'));
    await tester.pump();
    expect(box, findsNWidgets(2));
  });

  testWidgets('an answer keeps its bubble and reasoning stays above it',
      (tester) async {
    await tester.pumpWidget(host([
      // Streaming keeps the bubble's action row (which needs a provider scope)
      // out of this test.
      item(agent('<think>Plan it.</think>The answer is 42.', streaming: true)),
    ]));
    await tester.pump();

    expect(find.text('think'), findsOneWidget);
    expect(find.textContaining('The answer is 42', findRichText: true),
        findsOneWidget);
    expect(tester.getTopLeft(find.text('think')).dy,
        lessThan(tester.getTopLeft(find.textContaining('The answer is 42',
                findRichText: true))
            .dy));

    // The reasoning is not inside the answer's bubble.
    await tester.tap(find.text('think'));
    await tester.pump();
    final bubbleOfAnswer = find.ancestor(
        of: find.textContaining('The answer is 42', findRichText: true),
        matching: find.byType(Container));
    expect(
        find.descendant(
            of: bubbleOfAnswer.last,
            matching: find.textContaining('Plan it', findRichText: true)),
        findsNothing);
  });

  testWidgets('several blocks of reasoning are one line', (tester) async {
    await tester.pumpWidget(host([
      item(agent('<think>One.</think>Middle.<think>Two.</think>End.',
          streaming: true)),
    ]));
    await tester.pump();

    expect(find.text('think'), findsOneWidget);
    await tester.tap(find.text('think'));
    await tester.pump();
    expect(find.textContaining('One.', findRichText: true), findsOneWidget);
    expect(find.textContaining('Two.', findRichText: true), findsOneWidget);
  });

  testWidgets('reasoning between tool calls stays out of both groups',
      (tester) async {
    await tester.pumpWidget(host([
      ToolGroupCard(tools: [bash('ls', 'List the crate root')]),
      item(agent('<think>Now what?</think>', tokens: 5)),
      ToolGroupCard(tools: [bash('pwd', 'Print the directory')]),
    ]));
    await tester.pump();

    expect(find.text('Ran a command'), findsNWidgets(2));
    expect(find.text('think'), findsOneWidget);

    // Opening the reasoning shows no step, and opening a group shows no
    // reasoning: the three are separate lines in the order they happened.
    final ys = [
      tester.getTopLeft(find.text('Ran a command').first).dy,
      tester.getTopLeft(find.text('think')).dy,
      tester.getTopLeft(find.text('Ran a command').last).dy,
    ];
    expect(ys[0], lessThan(ys[1]));
    expect(ys[1], lessThan(ys[2]));
    await tester.tap(find.text('think'));
    await tester.pump();
    expect(find.text('List the crate root'), findsNothing);
    expect(find.text('Print the directory'), findsNothing);
  });

  testWidgets('the label is Vietnamese when the app is', (tester) async {
    L10n.global = const L10n('vi');
    addTearDown(() => L10n.global = const L10n('en'));
    await tester.pumpWidget(host([
      item(agent('<think>Nghĩ.</think>', tokens: 3)),
    ]));
    await tester.pump();
    expect(find.text('suy nghĩ'), findsOneWidget);
  });

  testWidgets('a streaming reasoning-only message shows the pending mark',
      (tester) async {
    await tester.pumpWidget(host([
      item(agent('<think>Working it out', streaming: true)),
    ]));
    await tester.pump();
    expect(find.text('think'), findsOneWidget);
    expect(find.text('…'), findsOneWidget);
  });
}
