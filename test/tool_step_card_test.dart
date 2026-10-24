import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:senclaw_desktop/core/i18n/l10n.dart';
import 'package:senclaw_desktop/features/chat/widgets/message_widgets.dart';
import 'package:senclaw_desktop/models/chat_message.dart';
import 'package:senclaw_desktop/theme/app_theme.dart';

/// A collapsed group says how much work happened, a step row says what it was
/// *for*, and its command stays one tap away.
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

  Future<void> openGroup(WidgetTester tester) async {
    await tester.tap(find.byType(InkWell).first);
    await tester.pump();
  }

  testWidgets('the collapsed line counts the work by kind', (tester) async {
    await tester.pumpWidget(host([
      tool(
        name: 'Bash',
        title: 'grep -rn foo src/',
        description: 'Survey existing skills and the wiki capability',
      ),
      tool(name: 'Bash', title: 'ls', description: 'List the crate root'),
    ]));
    await tester.pump();

    expect(find.text('Ran 2 commands'), findsOneWidget);
    // Nothing is expanded yet: neither a command nor a step's own sentence.
    expect(find.text('grep -rn foo src/'), findsNothing);
    expect(find.text('List the crate root'), findsNothing);
  });

  testWidgets('a mixed group reads in the order the work happened',
      (tester) async {
    await tester.pumpWidget(host([
      tool(name: 'Read', title: 'a.rs'),
      tool(name: 'ToolSearch', title: 'ToolSearch'),
      tool(name: 'Read', title: 'b.rs'),
      tool(name: 'Edit', title: 'b.rs'),
      tool(name: 'Bash', title: 'cargo test'),
      tool(name: 'Write', title: 'c.rs'),
    ]));
    await tester.pump();

    // Kinds it does not name fold into one clause, last.
    expect(
      find.text('Read 2 files, edited a file, ran a command, '
          'wrote a file, used a tool'),
      findsOneWidget,
    );
  });

  testWidgets('the summary is in Vietnamese when the app is', (tester) async {
    L10n.global = const L10n('vi');
    addTearDown(() => L10n.global = const L10n('en'));
    await tester.pumpWidget(host([
      tool(name: 'Read', title: 'a.rs'),
      tool(name: 'Read', title: 'b.rs'),
      tool(name: 'Bash', title: 'ls'),
      tool(name: 'ToolSearch', title: 'ToolSearch'),
      tool(name: 'ToolSearch', title: 'ToolSearch'),
    ]));
    await tester.pump();

    expect(find.text('Đọc 2 tệp, chạy lệnh, dùng 2 công cụ'), findsOneWidget);
  });

  testWidgets('a lone command is named by kind and says why when opened',
      (tester) async {
    await tester.pumpWidget(host([
      tool(name: 'Bash', title: 'ls', description: 'List the crate root'),
    ]));
    await tester.pump();

    expect(find.text('Ran a command'), findsOneWidget);
    expect(find.text('List the crate root'), findsNothing);

    await openGroup(tester);
    expect(find.text('List the crate root'), findsOneWidget);
  });

  testWidgets('expanding lists the steps headed by their descriptions',
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
    await openGroup(tester);

    expect(find.text('Survey existing skills'), findsOneWidget);
    // Read carries no description of its own, so the line is composed from
    // the verb and what it acted on — never an invented sentence.
    expect(find.text('Read a file · src/lib.rs'), findsOneWidget);
    // Steps are not numbered.
    expect(find.text('1'), findsNothing);
    expect(find.text('2'), findsNothing);
    // The output stays behind the caret.
    expect(find.textContaining('stdout'), findsNothing);
    // And the tool's summary never leaks into the row.
    expect(find.textContaining('Completed'), findsNothing);
  });

  testWidgets('the caret turns down when the group opens', (tester) async {
    await tester.pumpWidget(host([
      tool(name: 'Bash', title: 'ls', description: 'List the crate root'),
      tool(name: 'Bash', title: 'pwd', description: 'Print the directory'),
    ]));
    await tester.pump();

    expect(find.byIcon(Icons.arrow_right), findsOneWidget);
    expect(find.byIcon(Icons.arrow_drop_down), findsNothing);

    await openGroup(tester);
    expect(find.byIcon(Icons.arrow_drop_down), findsOneWidget);
    // Rows with nothing behind them carry no caret of their own.
    expect(find.byIcon(Icons.arrow_right), findsNothing);
  });

  testWidgets('a healthy group carries no status icon', (tester) async {
    await tester.pumpWidget(host([
      tool(name: 'Bash', title: 'ls', description: 'List the crate root'),
      tool(name: 'Bash', title: 'pwd', description: 'Print the directory'),
    ]));
    await tester.pump();
    await openGroup(tester);

    expect(find.byIcon(Icons.check_circle_outline), findsNothing);
    expect(find.byIcon(Icons.error_outline), findsNothing);
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
    await openGroup(tester);
    expect(find.textContaining('Cargo.toml'), findsNothing);

    await tester.tap(find.text('List the crate root'));
    await tester.pump();
    expect(find.textContaining('Cargo.toml'), findsOneWidget);
  });

  testWidgets('an MCP result never spills into the step row', (tester) async {
    // The bug this guards: an MCP tool's `summary` is its raw JSON result, and
    // rendering it under the headline turned every browser step into three
    // lines of escaped JSON. The row is one line; the payload is behind the
    // caret.
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
    await openGroup(tester);

    // The unknown MCP tool has no useful verb, so its display title is the
    // line — not "Used a tool", and not the JSON.
    expect(find.text('Browser Search: giá vàng hôm nay'), findsWidgets);
    expect(find.textContaining('agent_id'), findsNothing);
    expect(find.text('Used a tool'), findsNothing);
  });

  testWidgets('tools with no verb of their own are counted, not previewed',
      (tester) async {
    // "Used 2 tools" is all two bare ToolSearch calls have to say; their
    // titles repeat the tool's own name.
    await tester.pumpWidget(host([
      tool(name: 'ToolSearch', title: 'ToolSearch', summary: '0 matches'),
      tool(name: 'ToolSearch', title: 'ToolSearch', summary: '1 match'),
    ]));
    await tester.pump();
    expect(find.text('Used 2 tools'), findsOneWidget);
  });

  testWidgets('a failure is said in words, not with an icon', (tester) async {
    await tester.pumpWidget(host([
      tool(name: 'Bash', title: 'ls', description: 'List the crate root'),
      tool(
        name: 'Bash',
        title: 'cargo build',
        description: 'Compile the daemon',
        ok: false,
        content: 'linker failed',
      ),
      tool(name: 'Read', title: 'a.rs'),
    ]));
    await tester.pump();
    expect(find.text('Ran 2 commands (1 failed), read a file'), findsOneWidget);
    expect(find.byIcon(Icons.error_outline), findsNothing);

    // The step that failed is still headed by what it was trying to do, and
    // says so itself.
    await openGroup(tester);
    expect(find.text('Compile the daemon'), findsOneWidget);
    expect(find.text('Failed'), findsOneWidget);
  });

  testWidgets('a long step fades out and keeps its caret on screen',
      (tester) async {
    tester.view.physicalSize = const Size(420, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host([
      tool(
        name: 'Bash',
        title: 'ls',
        description: 'Compare the plan-history branch with code-autonomy, '
            'list its uncommitted files, check the merge message style used',
        content: {'stdout': 'x'},
      ),
    ]));
    await tester.pump();
    await openGroup(tester);

    expect(tester.takeException(), isNull);
    final caret = tester.getTopRight(find.byIcon(Icons.arrow_right));
    expect(caret.dx, lessThanOrEqualTo(420));
  });

  // A row's line is one RichText: the verb, the file, the figures. Compare its
  // plain text, the way a person reads it.
  Finder row(String plain) => find.byWidgetPredicate(
      (w) => w is RichText && w.text.toPlainText() == plain);

  const edit = '--- a//p/chat_widgets.dart\n+++ b//p/chat_widgets.dart\n'
      '@@\n-old\n+new1\n+new2\n';

  testWidgets('a file step names the file, then what it did to it',
      (tester) async {
    await tester.pumpWidget(host([
      tool(
        name: 'Read',
        title: 'Read',
        content: {
          'path': '/p/lib/main.dart',
          'lineStart': 590,
          'lineEnd': 701,
          'totalLines': 1000,
        },
      ),
      tool(
        name: 'Edit',
        title: 'Edit',
        content: {'path': '/p/lib/chat_widgets.dart', 'diff': edit},
      ),
    ]));
    await tester.pump();
    await openGroup(tester);

    expect(row('Read  main.dart (590–701) · /p/lib'), findsOneWidget);
    expect(row('Edited  chat_widgets.dart  +2 −1  /p/lib'), findsOneWidget);
  });

  testWidgets('a whole-file read shows no range', (tester) async {
    await tester.pumpWidget(host([
      tool(
        name: 'Read',
        title: 'Read',
        content: {
          'path': '/p/lib/main.dart',
          'lineStart': 1,
          'lineEnd': 40,
          'totalLines': 40,
        },
      ),
    ]));
    await tester.pump();
    await openGroup(tester);

    expect(row('Read  main.dart  /p/lib'), findsOneWidget);
  });

  testWidgets('a write is told from an update by its diff', (tester) async {
    await tester.pumpWidget(host([
      tool(
        name: 'Write',
        title: 'Write',
        content: {
          'path': '/p/new.dart',
          'diff': '--- a//p/new.dart\n+++ b//p/new.dart\n+one\n+two\n',
        },
      ),
      tool(
        name: 'Write',
        title: 'Write',
        content: {
          'path': '/p/old.dart',
          'diff': '--- a//p/old.dart\n+++ b//p/old.dart\n keep\n-gone\n+new\n',
        },
      ),
    ]));
    await tester.pump();
    // Rewriting a file is an edit, in the count as in the row.
    expect(find.text('Wrote a file, edited a file'), findsOneWidget);
    await openGroup(tester);

    expect(row('Wrote  new.dart  +2 −0  /p'), findsOneWidget);
    expect(row('Updated  old.dart  +1 −1  /p'), findsOneWidget);
  });

  testWidgets('the collapsed line totals what the group changed',
      (tester) async {
    await tester.pumpWidget(host([
      tool(
        name: 'Edit',
        title: 'Edit',
        content: {'path': '/p/a.dart', 'diff': edit},
      ),
      tool(
        name: 'Edit',
        title: 'Edit',
        content: {
          'path': '/p/b.dart',
          'diff': '--- a\n+++ b\n+x\n+y\n+z\n',
        },
      ),
      // A failed edit changed nothing and adds nothing to the total.
      tool(name: 'Edit', title: 'Edit c.dart', ok: false, content: 'no match'),
    ]));
    await tester.pump();

    expect(find.text('Edited 3 files (1 failed)'), findsOneWidget);
    expect(row('+5 −1'), findsOneWidget);
  });

  testWidgets('a refused edit still names its file', (tester) async {
    await tester.pumpWidget(host([
      tool(name: 'Edit', title: 'Edit main.rs', ok: false, content: 'no match'),
    ]));
    await tester.pump();
    await openGroup(tester);

    expect(row('Edited  main.rs'), findsOneWidget);
    expect(find.text('Failed'), findsOneWidget);
  });

  testWidgets('a file step with no path falls back to its verb',
      (tester) async {
    // Rows persisted before the daemon sent a Read's path have nothing to name.
    await tester.pumpWidget(host([
      tool(name: 'Read', title: 'Read', content: {'content': 'x', 'lines': 1}),
    ]));
    await tester.pump();
    await openGroup(tester);

    expect(find.text('Read a file'), findsNWidgets(2)); // the line and the row
  });
}
