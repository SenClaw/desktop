// The pane a file row of a tool group opens: the file beside the chat, Markdown
// rendered and everything else as text, one tab per file, and a chat that stays
// usable the whole time. A file that cannot be shown says so in the pane.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:senclaw_desktop/core/config/app_config.dart';
import 'package:senclaw_desktop/core/i18n/l10n.dart';
import 'package:senclaw_desktop/core/prefs.dart';
import 'package:senclaw_desktop/core/transport/api_client.dart';
import 'package:senclaw_desktop/core/transport/connection.dart';
import 'package:senclaw_desktop/core/transport/ws_client.dart';
import 'package:senclaw_desktop/features/chat/widgets/message_widgets.dart';
import 'package:senclaw_desktop/features/file_pane/file_pane_provider.dart';
import 'package:senclaw_desktop/features/file_pane/file_pane_split.dart';
import 'package:senclaw_desktop/features/file_pane/markdown_outline.dart';
import 'package:senclaw_desktop/models/chat_message.dart';
import 'package:senclaw_desktop/theme/app_theme.dart';

const _jid = 'web:main';

class _FakeWs extends WsClient {
  _FakeWs() : super(const AppConfig(host: 'x', uiPort: 0, wsPort: 0));
  @override
  Stream<WsEvent> get events => const Stream<WsEvent>.empty();
  @override
  Stream<WsStatus> get statusStream => const Stream<WsStatus>.empty();
  @override
  void send(Map<String, dynamic> msg) {}
  @override
  void dispose() {}
}

/// The daemon's `/api/workspace/file`: a path answers with its text, with a
/// whole answer, or with the error it throws.
class _FakeApi implements ApiClient {
  _FakeApi(this.files);
  final Map<String, Object> files;
  final reads = <String>[];

  @override
  Future<dynamic> get(String path,
      {Map<String, dynamic>? query, Duration? timeout}) async {
    expect(path, '/api/workspace/file');
    final file = '${query!['path']}';
    reads.add(file);
    final answer = files[file];
    if (answer == null) throw ApiException(400, 'not a file');
    if (answer is Exception) throw answer;
    if (answer is Map) return answer;
    return {'path': file, 'content': answer, 'truncated': false};
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

ChatMessage _fileStep(String tool, String path, {String? diff, bool ok = true}) =>
    ChatMessage(
      id: '$tool-$path',
      kind: MessageKind.tool,
      data: {
        'toolName': tool,
        'title': '$tool ${path.split('/').last}',
        'ok': ok,
        'content': {'path': path, 'diff': ?diff},
      },
    );

Future<void> _pump(
  WidgetTester tester,
  _FakeApi api, {
  required List<ChatMessage> tools,
  double width = 1000,
}) async {
  tester.view.physicalSize = Size(width, 700);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  final sp = await SharedPreferences.getInstance();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      prefsProvider.overrideWithValue(sp),
      wsClientProvider.overrideWithValue(_FakeWs()),
      apiClientProvider.overrideWithValue(api),
    ],
    child: MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(
        body: FilePaneSplit(
          jid: _jid,
          chat: Consumer(
            builder: (context, ref, _) => Column(
              children: [
                ToolGroupCard(
                  tools: tools,
                  onOpenFile: (p) => openFileInPane(ref, jid: _jid, path: p),
                ),
                const TextField(key: Key('composer')),
              ],
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.pump();
  await tester.tap(find.byType(InkWell).first); // open the group
  await tester.pump();
}

Future<void> _open(WidgetTester tester, String name) async {
  await tester.tap(find.textContaining(name, findRichText: true).first);
  await tester.pump();
  await tester.pump();
}

Finder _rich(String text) => find.textContaining(text, findRichText: true);

Finder _tip(String message) => find.byTooltip(message);

Finder get _composer => find.byKey(const Key('composer'));

void main() {
  group('opening a file', () {
    testWidgets('clicking a file row shows the file, Markdown rendered',
        (tester) async {
      final api = _FakeApi({'/repo/README.md': '# Demo title\n\nSome **bold** words'});
      await _pump(tester, api, tools: [_fileStep('Read', '/repo/README.md')]);
      expect(_rich('Demo title'), findsNothing);

      await _open(tester, 'README.md');

      expect(api.reads, ['/repo/README.md']);
      expect(_rich('Demo title'), findsOneWidget);
      expect(_rich('# Demo title'), findsNothing);
      expect(_rich('bold'), findsOneWidget);
      expect(_rich('**bold**'), findsNothing);
      expect(_tip('Close file'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the row keeps its diff behind the caret', (tester) async {
      final api = _FakeApi({'/repo/a.rs': 'x'});
      await _pump(tester, api, tools: [
        _fileStep('Edit', '/repo/a.rs', diff: '@@ -1 +1 @@\n-old line\n+new line'),
      ]);

      await tester.tap(find.byIcon(Icons.arrow_right).last);
      await tester.pump();

      expect(_rich('new line'), findsOneWidget);
      expect(api.reads, isEmpty);
      expect(_tip('Close file'), findsNothing);
    });

    testWidgets('another file shows as text with line numbers, and no source '
        'switch', (tester) async {
      final api = _FakeApi({'/repo/a.rs': 'fn main() {\n    run();\n}\n'});
      await _pump(tester, api, tools: [_fileStep('Read', '/repo/a.rs')]);

      await _open(tester, 'a.rs');

      expect(_rich('fn main() {'), findsOneWidget);
      expect(_rich('    run();'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('4'), findsNothing, reason: 'the last newline is no line');
      expect(_tip('View source'), findsNothing);
    });

    testWidgets('a Markdown file switches to its source and back',
        (tester) async {
      final api = _FakeApi({'/repo/README.md': '# Demo title\n'});
      await _pump(tester, api, tools: [_fileStep('Read', '/repo/README.md')]);
      await _open(tester, 'README.md');

      await tester.tap(_tip('View source'));
      await tester.pump();
      expect(_rich('# Demo title'), findsOneWidget);

      await tester.tap(_tip('View rendered'));
      await tester.pump();
      await tester.pump();
      expect(_rich('# Demo title'), findsNothing);
      expect(_rich('Demo title'), findsOneWidget);
    });

    testWidgets('Markdown too long to render opens as text', (tester) async {
      await _pump(tester, _FakeApi({'/repo/a.md': '# t ${'x' * 40000}'}),
          tools: [_fileStep('Read', '/repo/a.md')]);
      await _open(tester, 'a.md');

      expect(_rich('# t x'), findsOneWidget);
      expect(_tip('View rendered'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('clicking the row of an open file reads it again',
        (tester) async {
      final api = _FakeApi({'/repo/a.rs': 'before'});
      await _pump(tester, api, tools: [_fileStep('Edit', '/repo/a.rs')]);
      await _open(tester, 'Edited  a.rs');
      expect(_rich('before'), findsOneWidget);

      api.files['/repo/a.rs'] = 'after the edit';
      await _open(tester, 'Edited  a.rs');

      expect(api.reads, hasLength(2));
      expect(_rich('after the edit'), findsOneWidget);
      expect(_tip('Close file'), findsOneWidget, reason: 'still one tab');
    });
  });

  group('tabs', () {
    _FakeApi api() => _FakeApi({
          '/repo/one.txt': 'first file',
          '/repo/two.txt': 'second file',
        });
    final tools = [
      _fileStep('Read', '/repo/one.txt'),
      _fileStep('Read', '/repo/two.txt'),
    ];

    testWidgets('each file has one, and they switch', (tester) async {
      await _pump(tester, api(), tools: tools);
      await _open(tester, 'Read  one.txt');
      await _open(tester, 'Read  two.txt');

      expect(_tip('Close file'), findsNWidgets(2));
      expect(_rich('second file'), findsOneWidget);

      await tester.tap(find.text('one.txt').last);
      await tester.pump();
      await tester.pump();

      expect(_rich('first file'), findsOneWidget);
      expect(_rich('second file'), findsNothing);
    });

    testWidgets('closing the shown tab lands on its neighbour, and the last '
        'closes the pane', (tester) async {
      await _pump(tester, api(), tools: tools);
      await _open(tester, 'Read  one.txt');
      await _open(tester, 'Read  two.txt');

      await tester.tap(_tip('Close file').last);
      await tester.pump();
      await tester.pump();
      expect(_rich('first file'), findsOneWidget);

      await tester.tap(_tip('Close file'));
      await tester.pump();
      expect(_tip('Search in file'), findsNothing);
      expect(tester.getSize(_composer).width, 1000);
    });

    testWidgets('closing the pane keeps the tabs for the next file',
        (tester) async {
      await _pump(tester, api(), tools: tools);
      await _open(tester, 'Read  one.txt');
      await tester.tap(_tip('Close'));
      await tester.pump();
      expect(_tip('Close file'), findsNothing);

      await _open(tester, 'Read  two.txt');
      expect(_tip('Close file'), findsNWidgets(2));
    });
  });

  group('a file that cannot be shown', () {
    testWidgets('a missing file says so in the pane, and Retry reads it again',
        (tester) async {
      final api = _FakeApi({});
      await _pump(tester, api, tools: [_fileStep('Read', '/repo/gone.md')]);

      await _open(tester, 'gone.md');

      expect(find.text('Cannot open gone.md'), findsOneWidget);
      expect(find.text('This file does not exist, or the path is a folder.'),
          findsOneWidget);
      expect(find.text('/repo/gone.md'), findsOneWidget);
      expect(tester.takeException(), isNull);

      api.files['/repo/gone.md'] = 'back again';
      await tester.tap(find.text('Retry'));
      await tester.pump();
      await tester.pump();
      expect(_rich('back again'), findsOneWidget);
    });

    testWidgets('a path the daemon refuses is explained', (tester) async {
      await _pump(
        tester,
        _FakeApi({'a.rs': ApiException(400, 'path must be absolute')}),
        tools: [_fileStep('Read', 'a.rs')],
      );
      await _open(tester, 'a.rs');
      expect(find.text('The path is relative and this chat has no working folder.'),
          findsOneWidget);
    });

    testWidgets('anything else shows what the daemon said', (tester) async {
      await _pump(
        tester,
        _FakeApi({'/repo/a.rs': ApiException(500, 'Permission denied')}),
        tools: [_fileStep('Read', '/repo/a.rs')],
      );
      await _open(tester, 'a.rs');
      expect(find.text('Permission denied'), findsOneWidget);
    });

    testWidgets('a binary file is named as one', (tester) async {
      await _pump(
        tester,
        _FakeApi({'/repo/logo.png': '(binary file — cannot display)'}),
        tools: [_fileStep('Read', '/repo/logo.png')],
      );
      await _open(tester, 'logo.png');
      expect(find.text('This is a binary file, not text.'), findsOneWidget);
    });

    testWidgets('a text file cut mid-character is not called binary',
        (tester) async {
      await _pump(
        tester,
        _FakeApi({
          '/repo/big.md': {
            'content': '(binary file — cannot display)',
            'truncated': true,
          },
        }),
        tools: [_fileStep('Read', '/repo/big.md')],
      );
      await _open(tester, 'big.md');
      expect(find.text('This file is over 512 KB and could not be read as text.'),
          findsOneWidget);
    });

    testWidgets('a cut file says it was cut', (tester) async {
      await _pump(
        tester,
        _FakeApi({
          '/repo/big.log': {'content': 'head of it', 'truncated': true},
        }),
        tools: [_fileStep('Read', '/repo/big.log')],
      );
      await _open(tester, 'big.log');
      expect(_rich('head of it'), findsOneWidget);
      expect(find.text('Truncated to 512 KB'), findsOneWidget);
    });

    testWidgets('an empty file says it is empty', (tester) async {
      await _pump(tester, _FakeApi({'/repo/a.txt': ''}),
          tools: [_fileStep('Read', '/repo/a.txt')]);
      await _open(tester, 'a.txt');
      expect(find.text('(empty file)'), findsOneWidget);
    });
  });

  group('beside the chat', () {
    testWidgets('the chat keeps working with the pane open', (tester) async {
      await _pump(tester, _FakeApi({'/repo/a.rs': 'x'}),
          tools: [_fileStep('Read', '/repo/a.rs')]);
      await _open(tester, 'a.rs');

      expect(tester.getSize(_composer).width, 500);
      await tester.enterText(_composer, 'still typing');
      await tester.pump();
      expect(find.text('still typing'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    for (final width in [300.0, 480.0, 659.0]) {
      testWidgets('at ${width.toInt()} px the pane covers the chat and gives '
          'it back', (tester) async {
        await _pump(tester, _FakeApi({'/repo/a.rs': 'x'}),
            tools: [_fileStep('Read', '/repo/a/b/c/d/e/a.rs')], width: width);
        await tester.enterText(_composer, 'half a message');
        await _open(tester, 'a.rs');

        expect(tester.takeException(), isNull);
        expect(_composer, findsNothing);
        expect(_tip('Expand'), findsNothing, reason: 'it already fills the room');

        await tester.tap(_tip('Close'));
        await tester.pump();
        expect(find.text('half a message'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('at the width where both just fit they stay side by side',
        (tester) async {
      await _pump(tester, _FakeApi({'/repo/a.rs': 'x'}),
          tools: [_fileStep('Read', '/repo/a.rs')], width: 660);
      await _open(tester, 'a.rs');

      expect(_composer, findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('expanding covers the chat and shrinking restores it',
        (tester) async {
      await _pump(tester, _FakeApi({'/repo/a.rs': 'x'}),
          tools: [_fileStep('Read', '/repo/a.rs')]);
      await tester.enterText(_composer, 'half a message');
      await _open(tester, 'a.rs');

      await tester.tap(_tip('Expand'));
      await tester.pump();
      expect(_composer, findsNothing);

      await tester.tap(_tip('Shrink'));
      await tester.pump();
      expect(find.text('half a message'), findsOneWidget);
    });

    testWidgets('a long path does not overflow a narrow pane', (tester) async {
      final deep = '/${List.filled(30, 'folder').join('/')}/${'n' * 60}.md';
      await _pump(tester, _FakeApi({deep: '# t'}),
          tools: [_fileStep('Read', deep)], width: 660);
      await _open(tester, 'nnnn');
      expect(tester.takeException(), isNull);
    });
  });

  group('search', () {
    Future<void> search(WidgetTester tester, String query) async {
      await tester.tap(_tip('Search in file'));
      await tester.pump();
      await tester.enterText(find.widgetWithText(TextField, 'Search in file'),
          query);
      await tester.pump();
      await tester.pump();
    }

    testWidgets('finds in a text file and steps through the matches',
        (tester) async {
      await _pump(tester, _FakeApi({'/repo/a.txt': 'Alpha\nbeta alpha\nalpha\n'}),
          tools: [_fileStep('Read', '/repo/a.txt')]);
      await _open(tester, 'a.txt');

      await search(tester, 'ALPHA');
      expect(find.text('1/3'), findsOneWidget);

      await tester.tap(_tip('Next match'));
      await tester.pump();
      expect(find.text('2/3'), findsOneWidget);

      await tester.tap(_tip('Previous match'));
      await tester.tap(_tip('Previous match'));
      await tester.pump();
      expect(find.text('3/3'), findsOneWidget, reason: 'it wraps around');
    });

    testWidgets('jumps to a match far down a long file', (tester) async {
      final lines = [for (var i = 0; i < 5000; i++) 'line $i'];
      lines[4000] = 'the needle';
      await _pump(tester, _FakeApi({'/repo/a.log': lines.join('\n')}),
          tools: [_fileStep('Read', '/repo/a.log')]);
      await _open(tester, 'a.log');
      expect(_rich('the needle'), findsNothing, reason: 'rows are built lazily');

      await search(tester, 'needle');
      await tester.pump();

      expect(find.text('1/1'), findsOneWidget);
      expect(_rich('the needle'), findsOneWidget);
    });

    testWidgets('a minified file is cut into rows, none of it lost',
        (tester) async {
      await _pump(
        tester,
        _FakeApi({'/repo/a.min.js': '${'x' * 4500}needle${'y' * 100}'}),
        tools: [_fileStep('Read', '/repo/a.min.js')],
      );
      await _open(tester, 'a.min.js');

      expect(find.text('1'), findsOneWidget);
      expect(find.text('2'), findsNothing, reason: 'still one line of the file');

      await search(tester, 'needle');
      expect(find.text('1/1'), findsOneWidget);
      expect(_rich('xneedley'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('in Markdown it reads what the reader sees', (tester) async {
      await _pump(
        tester,
        _FakeApi({
          '/repo/a.md':
              '# Word in a title\n\nA **word** in bold, [a link](http://word.test)\n',
        }),
        tools: [_fileStep('Read', '/repo/a.md')],
      );
      await _open(tester, 'a.md');

      await search(tester, 'word');

      expect(find.text('1/2'), findsOneWidget,
          reason: 'the link address is not on the page');
      expect(tester.takeException(), isNull);
    });

    testWidgets('Cmd+F opens it from inside the pane', (tester) async {
      await _pump(tester, _FakeApi({'/repo/a.txt': 'alpha'}),
          tools: [_fileStep('Read', '/repo/a.txt')]);
      await _open(tester, 'a.txt');
      await tester.tap(_rich('alpha'));
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pump();

      expect(find.widgetWithText(TextField, 'Search in file'), findsOneWidget);
    });

    testWidgets('no match says so, and Escape closes the search',
        (tester) async {
      await _pump(tester, _FakeApi({'/repo/a.txt': 'alpha'}),
          tools: [_fileStep('Read', '/repo/a.txt')]);
      await _open(tester, 'a.txt');

      await search(tester, 'zebra');
      expect(find.text('No results'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(find.text('No results'), findsNothing);
      expect(find.widgetWithText(TextField, 'Search in file'), findsNothing);
    });
  });

  group('contents', () {
    testWidgets('lists the headings and goes to one', (tester) async {
      final body = List.filled(120, 'A line of text.').join('\n\n');
      await _pump(
        tester,
        _FakeApi({'/repo/a.md': '# First\n\n$body\n\n## Second part\n\nend\n'}),
        tools: [_fileStep('Read', '/repo/a.md')],
      );
      await _open(tester, 'a.md');
      final endOfFile = tester.getTopLeft(_rich('Second part').first).dy;
      expect(endOfFile, greaterThan(700));

      await tester.tap(_tip('Contents'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Second part').last);
      await tester.pumpAndSettle();

      expect(tester.getTopLeft(_rich('Second part').first).dy, lessThan(700));
    });

    testWidgets('a file with no headings has no contents button',
        (tester) async {
      await _pump(tester, _FakeApi({'/repo/a.md': 'just words'}),
          tools: [_fileStep('Read', '/repo/a.md')]);
      await _open(tester, 'a.md');
      expect(_tip('Contents'), findsNothing);
    });
  });

  group('parseMarkdown', () {
    test('cuts at headings, not at a # in a fence', () {
      final o = parseMarkdown('intro\n\n# One\ntext\n```sh\n# a comment\n```\n'
          '## Two ##\nmore');
      expect(o.headings.map((h) => h.title), ['One', 'Two']);
      expect(o.headings.map((h) => h.level), [1, 2]);
      expect(o.headings.map((h) => h.line), [2, 7]);
      expect(o.sections, hasLength(3));
      expect(o.sections[1], contains('# a comment'));
      expect(o.headings.map((h) => o.sections[h.section].split('\n').first),
          ['# One', '## Two ##']);
    });

    test('a heading is listed without its inline marks', () {
      final o = parseMarkdown('# **Bold** and `code` and [a link](http://x)');
      expect(o.headings.single.title, 'Bold and code and a link');
    });

    test('comments on their own lines are dropped, in fences kept', () {
      final o = parseMarkdown(
          '<!-- Demo repo -->\n# One\n<!-- two\nlines -->\ntext\n'
          '```html\n<!-- shown -->\n```');
      final all = o.sections.join('\n');
      expect(all, isNot(contains('Demo repo')));
      expect(all, isNot(contains('lines -->')));
      expect(all, contains('<!-- shown -->'));
    });

    test('an unclosed fence runs to the end of the file', () {
      final o = parseMarkdown('# One\n```\n# not a heading');
      expect(o.headings, hasLength(1));
    });

    test('a long stretch without headings is cut at blank lines, nothing lost',
        () {
      final paragraphs = [for (var i = 0; i < 200; i++) 'para $i ${'w' * 80}'];
      final o = parseMarkdown(paragraphs.join('\n\n'));
      expect(o.sections, hasLength(greaterThan(3)));
      expect(o.renderable, isTrue);
      expect(o.sections.join('\n').split('\n').where((l) => l.isNotEmpty),
          paragraphs);
    });

    test('a list with no blank lines is cut too, and a table is not', () {
      final list = parseMarkdown(
          [for (var i = 0; i < 2000; i++) '- item $i of a long list'].join('\n'));
      expect(list.sections.length, greaterThan(1));
      expect(list.renderable, isTrue);

      final table = parseMarkdown(
          ['| a |', '|---|', for (var i = 0; i < 900; i++) '| row $i |'].join('\n'));
      expect(table.sections, hasLength(1));
    });

    test('a fence is never cut, and one line too long cannot be rendered', () {
      final code = ['```', for (var i = 0; i < 500; i++) 'line $i', '', '```'];
      expect(parseMarkdown(code.join('\n')).sections, hasLength(1));
      expect(parseMarkdown('x' * 40000).renderable, isFalse);
    });

    test('CRLF files read the same', () {
      final o = parseMarkdown('# One\r\ntext\r\n## Two\r\n');
      expect(o.headings.map((h) => h.title), ['One', 'Two']);
    });
  });

  group('paths', () {
    test('a relative path is taken from the chat folder', () {
      expect(resolveChatPath('src/a.rs', '/repo'), '/repo/src/a.rs');
      expect(resolveChatPath('./a.rs', '/repo/'), '/repo/a.rs');
      expect(resolveChatPath(r'a.rs', r'C:\repo'), r'C:\repo\a.rs');
    });

    test('an absolute path is left alone, and so is one with no folder', () {
      expect(resolveChatPath('/x/a.rs', '/repo'), '/x/a.rs');
      expect(resolveChatPath('~/a.rs', '/repo'), '~/a.rs');
      expect(resolveChatPath(r'D:\x\a.rs', '/repo'), r'D:\x\a.rs');
      expect(resolveChatPath('a.rs', null), 'a.rs');
    });

    test('the breadcrumb starts at the chat folder when the file is in it', () {
      expect(pathCrumbs('/u/me/repo/docs/a.md', '/u/me/repo'),
          ['repo', 'docs', 'a.md']);
      expect(pathCrumbs('/u/me/other/a.md', '/u/me/repo'),
          ['u', 'me', 'other', 'a.md']);
      expect(pathCrumbs('/a.md', null), ['a.md']);
    });

    test('two files of one name are told apart by folder', () {
      const open = ['/x/one/a.md', '/x/two/a.md', '/x/b.md'];
      expect(tabLabel('/x/one/a.md', open), 'one/a.md');
      expect(tabLabel('/x/b.md', open), 'b.md');
    });

    test('Markdown by extension, whatever its case', () {
      expect(isMarkdownPath('/x/README.MD'), isTrue);
      expect(isMarkdownPath('/x/a.markdown'), isTrue);
      expect(isMarkdownPath('/x/a.md.txt'), isFalse);
    });
  });

  test('every string of the pane has a Vietnamese entry', () {
    const vi = L10n('vi');
    final call = RegExp(r"""\.(?:tr|trArgs)\(\s*'((?:[^'\\]|\\.)*)'""");
    final missing = <String>[];
    final files = Directory('lib/features/file_pane')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));
    for (final f in files) {
      for (final m in call.allMatches(f.readAsStringSync())) {
        if (vi.t(m[1]!) == m[1]) missing.add(m[1]!);
      }
    }
    expect(missing, isEmpty, reason: missing.join('\n'));
  });
}
