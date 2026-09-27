import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:senclaw_desktop/widgets/app_markdown.dart';
import 'package:senclaw_desktop/widgets/mermaid_diagram.dart';
import 'package:senclaw_desktop/theme/app_theme.dart';

/// A ```mermaid fence must reach [MermaidDiagram], and nothing else may.
///
/// The routing is the part that silently breaks: a typo in the language check,
/// or a renamed `codeBuilder` parameter, and the diagram quietly goes back to
/// being a code block — which still looks plausible on screen.
void main() {
  setUp(() {
    // A widget test has no webview plugin, so the diagram is asked to take its
    // source-fallback path. The routing under test is the same either way.
    MermaidDiagram.debugSupportedOverride = false;
  });
  tearDown(() => MermaidDiagram.debugSupportedOverride = null);

  Widget host(String markdown) => MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(body: SingleChildScrollView(child: AppMarkdown(markdown))),
      );

  testWidgets('a mermaid fence becomes a diagram', (tester) async {
    await tester.pumpWidget(host('''
Trước sơ đồ.

```mermaid
flowchart TD
    A[Start] --> B[End]
```
'''));
    await tester.pump();
    expect(find.byType(MermaidDiagram), findsOneWidget);
  });

  testWidgets('a tag that merely resembles mermaid stays code', (tester) async {
    // An explicit tag is the author's word: `mermaidish` is not mermaid, and
    // its body is never sniffed. (A *bare* fence opening with a diagram
    // keyword is a different case, covered below.)
    await tester.pumpWidget(host('''
```mermaidish
flowchart TD
```
'''));
    await tester.pump();
    expect(find.byType(MermaidDiagram), findsNothing);
  });

  testWidgets('case and padding in the tag still route to the diagram',
      (tester) async {
    await tester.pumpWidget(host('```Mermaid\nflowchart TD\n  A --> B\n```'));
    await tester.pump();
    expect(find.byType(MermaidDiagram), findsOneWidget);
  });

  testWidgets('an untagged fence opening with flowchart is a diagram',
      (tester) async {
    // What a model actually produces most of the time: no language tag, the
    // diagram keyword on the first line. Trusting the tag alone left exactly
    // this case rendering as raw text.
    await tester.pumpWidget(host("""
Luồng pipeline:

```
flowchart TD
    A[Bat dau] --> B(Bootstrap)
    B --> C(Dynamic)
```
"""));
    await tester.pump();
    expect(find.byType(MermaidDiagram), findsOneWidget);
  });

  testWidgets('an untagged fence of ordinary code stays code', (tester) async {
    // The guard on content sniffing: mentioning a graph is not declaring one.
    await tester.pumpWidget(host("""
```
def build_graph(nodes):
    # flowchart of the pipeline
    return nodes
```
"""));
    await tester.pump();
    expect(find.byType(MermaidDiagram), findsNothing);
  });

  test('mermaidSource accepts the shapes a model writes, and nothing else', () {
    // Tagged.
    expect(mermaidSource('mermaid', 'flowchart TD\n A-->B'), isNotNull);
    expect(mermaidSource('Mermaid', 'anything at all'), isNotNull);
    // Untagged, opening with a diagram keyword.
    expect(mermaidSource('', 'flowchart TD\n A-->B'), isNotNull);
    expect(mermaidSource('', 'sequenceDiagram\n A->>B: hi'), isNotNull);
    // A mermaid init directive may precede the keyword.
    expect(
      mermaidSource('', "%%{init: {'theme':'dark'}}%%\ngraph LR\n A-->B"),
      isNotNull,
    );
    // Untagged, but not a diagram.
    expect(mermaidSource('', 'SELECT * FROM graph_nodes'), isNull);
    expect(mermaidSource('', 'print("flowchart")'), isNull);
    // A different language is never sniffed — an explicit tag is the author's
    // word and outranks any guess.
    expect(mermaidSource('python', 'flowchart TD\n A-->B'), isNull);
    expect(mermaidSource('', ''), isNull);
  });

  testWidgets('a platform without a webview shows the source, and says why',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark(),
      home: const Scaffold(
        body: MermaidDiagram(code: 'flowchart TD\n    A[Only text here]'),
      ),
    ));
    await tester.pump();
    // Never an empty panel: the source is what the user had before, so it is
    // the floor, not a failure state.
    expect(find.textContaining('Only text here'), findsOneWidget);
    expect(find.textContaining('macOS'), findsOneWidget);
  });

  test('supported matches the platforms that embed a webview', () {
    MermaidDiagram.debugSupportedOverride = null;
    expect(MermaidDiagram.supported, Platform.isMacOS || Platform.isWindows);
  });
}
