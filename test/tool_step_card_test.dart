import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:senclaw_desktop/features/chat/widgets/message_widgets.dart';
import 'package:senclaw_desktop/models/chat_message.dart';
import 'package:senclaw_desktop/theme/app_theme.dart';

/// A step must be headed by what it was *for*, and its command must stay one
/// tap away.
///
/// The regression this guards against is silent: drop the `description` on the
/// wire (or in the accessor) and every step falls back to "Ran a command",
/// which still looks like a working card — exactly the display this replaced.
void main() {
  ChatMessage tool({
    required String name,
    String title = '',
    String summary = '',
    String description = '',
    Object? content,
    bool ok = true,
  }) =>
      ChatMessage(
        id: 'tool-$name-$title-$description',
        kind: MessageKind.tool,
        data: {
          'toolName': name,
          'title': title,
          'summary': summary,
          'description': description,
          'ok': ok,
          'content': content,
        },
      );

  Widget host(List<ChatMessage> tools) => MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: SingleChildScrollView(child: ToolGroupCard(tools: tools)),
        ),
      );

  testWidgets('the collapsed line counts the steps and names the first',
      (tester) async {
    await tester.pumpWidget(host([
      tool(
        name: 'Bash',
        title: 'grep -rn foo src/',
        description: 'Survey existing skills and the wiki capability',
      ),
      tool(name: 'Bash', title: 'ls', description: 'List the crate root'),
    ]));
    await tester.pump();

    expect(
      find.text('2 steps · Survey existing skills and the wiki capability'),
      findsOneWidget,
    );
    // Nothing is expanded yet, so no command is on screen.
    expect(find.text('grep -rn foo src/'), findsNothing);
  });

  testWidgets('a single step shows its own headline with no count',
      (tester) async {
    await tester.pumpWidget(host([
      tool(name: 'Bash', title: 'ls', description: 'List the crate root'),
    ]));
    await tester.pump();

    expect(find.text('List the crate root'), findsOneWidget);
    expect(find.textContaining('1 steps'), findsNothing);
  });

  testWidgets('expanding lists numbered steps headed by their descriptions',
      (tester) async {
    await tester.pumpWidget(host([
      tool(
        name: 'Bash',
        title: 'grep -rn foo src/',
        summary: 'Completed',
        description: 'Survey existing skills',
        content: {'stdout': 'hit'},
      ),
      tool(
        name: 'Read',
        title: 'src/lib.rs',
        description: '',
        content: {'text': 'fn main() {}'},
      ),
    ]));
    await tester.pump();
    await tester.tap(find.byType(InkWell).first);
    await tester.pump();

    // Step numbers, and the headline of each step.
    expect(find.text('1'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('Survey existing skills'), findsOneWidget);
    // Read carries no description of its own, so the line is composed from
    // the verb and what it acted on — never an invented sentence.
    expect(find.text('Read a file · src/lib.rs'), findsOneWidget);
    // The output stays behind the chevron.
    expect(find.textContaining('stdout'), findsNothing);
    // And the tool's summary never leaks into the row.
    expect(find.textContaining('Completed'), findsNothing);
  });

  testWidgets('the command detail opens on the step row', (tester) async {
    await tester.pumpWidget(host([
      tool(
        name: 'Bash',
        title: 'ls',
        description: 'List the crate root',
        content: {'stdout': 'Cargo.toml'},
      ),
    ]));
    await tester.pump();
    await tester.tap(find.byType(InkWell).first); // open the group
    await tester.pump();
    expect(find.textContaining('Cargo.toml'), findsNothing);

    // With one step, the header and the step row carry the same headline —
    // the row is the second one.
    await tester.tap(find.text('List the crate root').last);
    await tester.pump();
    expect(find.textContaining('Cargo.toml'), findsOneWidget);
  });

  testWidgets('an MCP result never spills into the step row', (tester) async {
    // The bug this guards: an MCP tool's `summary` is its raw JSON result, and
    // rendering it under the headline turned every browser step into three
    // lines of escaped JSON. The row is one line; the payload is behind the
    // chevron.
    const payload =
        '{ "content": [ { "text": "{\\n \\"agent_id\\": \\"web:main\\"}" } ] }';
    await tester.pumpWidget(host([
      tool(
        // The daemon puts what the call was for into the title, so the row
        // says what was searched rather than only that a search happened.
        name: 'mcp__core__browser_search',
        title: 'Browser Search: giá vàng hôm nay',
        summary: payload,
        content: {'raw': payload},
      ),
    ]));
    await tester.pump();
    await tester.tap(find.byType(InkWell).first);
    await tester.pump();

    // The unknown MCP tool has no useful verb, so its display title is the
    // line — not "Used a tool", and not the JSON.
    expect(find.text('Browser Search: giá vàng hôm nay'), findsWidgets);
    expect(find.textContaining('agent_id'), findsNothing);
    expect(find.text('Used a tool'), findsNothing);
  });

  testWidgets('the collapsed line does not preview a composed label',
      (tester) async {
    // "10 steps · Discovered a tool" tells the reader nothing that "10 steps"
    // did not, so the preview is only for a sentence the model wrote.
    await tester.pumpWidget(host([
      tool(name: 'ToolSearch', title: 'ToolSearch', summary: '0 matches'),
      tool(name: 'ToolSearch', title: 'ToolSearch', summary: '1 match'),
    ]));
    await tester.pump();
    expect(find.text('2 steps'), findsOneWidget);
  });

  testWidgets('a failed step is still headed by what it was trying to do',
      (tester) async {
    await tester.pumpWidget(host([
      tool(
        name: 'Bash',
        title: 'cargo build',
        description: 'Compile the daemon',
        ok: false,
        content: 'linker failed',
      ),
    ]));
    await tester.pump();
    expect(find.text('Compile the daemon'), findsOneWidget);
    expect(find.byIcon(Icons.error_outline), findsWidgets);
  });
}
