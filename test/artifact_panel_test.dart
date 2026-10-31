import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:senclaw_desktop/features/browser/artifact_panel.dart';
import 'package:senclaw_desktop/features/dock/workbench_provider.dart';
import 'package:senclaw_desktop/theme/app_theme.dart';

Widget _host(Widget child) => MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(body: child),
    );

void main() {
  testWidgets('a static artifact lists its files and opens one as text',
      (t) async {
    final read = <String>[];
    await t.pumpWidget(_host(ArtifactFiles(
      files: const ['index.html', 'notes.md'],
      readFile: (path) async {
        read.add(path);
        return 'content of $path';
      },
    )));
    expect(find.text('index.html'), findsOneWidget);
    expect(find.text('notes.md'), findsOneWidget);

    await t.tap(find.text('notes.md'));
    await t.pumpAndSettle();
    expect(read, ['notes.md']);
    expect(find.text('content of notes.md'), findsOneWidget);

    await t.tap(find.byIcon(Icons.arrow_back));
    await t.pumpAndSettle();
    expect(find.text('index.html'), findsOneWidget);
  });

  testWidgets('the header names the artifact and closes it', (t) async {
    var closed = 0;
    await t.pumpWidget(_host(ArtifactHeader(
      artifact: const WorkbenchArtifact(
          id: 'a1', title: 'Report', mode: 'static', files: ['r.md']),
      onClose: () => closed++,
    )));
    expect(find.text('Report'), findsOneWidget);
    await t.tap(find.byIcon(Icons.close));
    expect(closed, 1);
  });

  testWidgets('Open shows only when the pane did not show the artifact itself',
      (t) async {
    const art = WorkbenchArtifact(
        id: 'a1', title: 'Local', mode: 'web', files: [], url: 'http://127.0.0.1:3000/');
    var opened = 0;
    await t.pumpWidget(_host(ArtifactHeader(
        artifact: art, onClose: () {}, onOpen: () => opened++)));
    await t.tap(find.text('Open'));
    expect(opened, 1);

    await t.pumpWidget(_host(ArtifactHeader(artifact: art, onClose: () {})));
    expect(find.text('Open'), findsNothing);
  });
}
