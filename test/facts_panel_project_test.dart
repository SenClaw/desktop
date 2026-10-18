// Knowledge → Facts with projects: the bank of a project is listed under the
// project’s name (not its id), its facts show who wrote them, and forgetting
// one goes through the same route as for an agent, under the project’s bank.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:senclaw_desktop/core/transport/connection.dart';
import 'package:senclaw_desktop/features/cognitive/facts_panel.dart';
import 'package:senclaw_desktop/models/project.dart';
import 'package:senclaw_desktop/theme/app_theme.dart';

import 'support/fake_projects_api.dart';

Future<FakeProjectsApi> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final api = FakeProjectsApi(projects: [
    FakeProjectsApi.project('prj_aaaa0001', 'Alpha', '/work/alpha'),
  ]);
  api.banks.addAll([
    {'bank': 'main', 'current': 3, 'replaced': 0, 'lastMentionedAt': 1790000100},
    {'bank': 'project:prj_aaaa0001', 'current': 2, 'replaced': 1, 'lastMentionedAt': 1790000000},
    {'bank': 'project:prj_gone0001', 'current': 1, 'replaced': 0, 'lastMentionedAt': 1780000000},
  ]);
  api.bankFacts['main'] = [FakeProjectsApi.fact('m1', 'Sen prefers dark mode')];
  api.bankFacts['project:prj_aaaa0001'] = [
    FakeProjectsApi.fact('p1', 'The API listens on port 7421', source: 'manual'),
    FakeProjectsApi.fact('p2', 'Task "ship" completed: blue pipeline', source: 'kanban'),
  ];
  api.bankFacts['project:prj_gone0001'] = [FakeProjectsApi.fact('g1', 'An orphan fact')];
  await tester.pumpWidget(ProviderScope(
    overrides: [apiClientProvider.overrideWithValue(api)],
    child: MaterialApp(
        theme: AppTheme.light(), home: const Scaffold(body: FactsPanel())),
  ));
  await tester.pumpAndSettle();
  return api;
}

void main() {
  test('projectIdOfBank reads a project bank and leaves an agent’s alone', () {
    expect(projectIdOfBank('project:prj_aaaa0001'), 'prj_aaaa0001');
    expect(projectIdOfBank('main'), isNull);
    expect(projectIdOfBank('projects'), isNull);
  });

  testWidgets('a project’s bank is listed by the project’s name',
      (tester) async {
    await _pump(tester);
    // The agent's own bank comes first and keeps its folder name.
    expect(find.textContaining('main · 3'), findsOneWidget);
    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    expect(find.textContaining('Project: Alpha · 2 (+1)'), findsOneWidget);
    // A bank whose project is gone falls back to the id rather than hiding.
    expect(find.textContaining('Project: prj_gone0001 · 1'), findsOneWidget);
    expect(find.textContaining('project:prj_aaaa0001'), findsNothing);
  });

  testWidgets('opening it lists the project’s facts with who wrote them',
      (tester) async {
    final api = await _pump(tester);
    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Project: Alpha').last);
    await tester.pumpAndSettle();

    expect(find.text('The API listens on port 7421'), findsOneWidget);
    expect(find.text('typed'), findsOneWidget);
    expect(find.text('kanban'), findsOneWidget);
    final get = api.calls('GET', '/api/memory/facts').lastWhere(
        (c) => c.path == '/api/memory/facts');
    expect((get.body as Map)['bank'], 'project:prj_aaaa0001');
  });

  testWidgets('forgetting a project fact names the project’s bank',
      (tester) async {
    final api = await _pump(tester);
    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Project: Alpha').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Forget').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Forget'));
    await tester.pumpAndSettle();
    expect(api.calls('DELETE').single.path,
        '/api/memory/facts/p1?bank=project%3Aprj_aaaa0001');
  });

  testWidgets('an empty project bank says it is the project that has none',
      (tester) async {
    final api = await _pump(tester);
    api.bankFacts['project:prj_aaaa0001'] = [];
    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Project: Alpha').last);
    await tester.pumpAndSettle();
    expect(find.text('This project has no facts.'), findsOneWidget);
  });
}
