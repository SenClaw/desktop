// Kanban and projects (desktop): a board is created in a project from the
// dialogs, and then its folder is the project's root — shown, not editable;
// the board list narrows to one project, and the board says which project it
// belongs to and where its workers run.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:senclaw_desktop/core/transport/connection.dart';
import 'package:senclaw_desktop/features/kanban/kanban_dialogs.dart';
import 'package:senclaw_desktop/features/kanban/kanban_providers.dart';
import 'package:senclaw_desktop/features/kanban/kanban_screen.dart';
import 'package:senclaw_desktop/models/kanban_models.dart';
import 'package:senclaw_desktop/theme/app_theme.dart';

import 'support/fake_projects_api.dart';
import 'support/fake_ws.dart';

Map<String, dynamic> _board(int id, String title,
        {String? project, String? own, String? effective}) =>
    {
      'id': id,
      'title': title,
      'description': '',
      'workspace_dir': own,
      'project_id': project,
      'column_count': 5,
      'card_count': 2,
      'effective_workspace_dir': effective ?? own,
    };

Future<FakeProjectsApi> _pumpDialogs(WidgetTester tester,
    {List<Map<String, dynamic>>? projects}) async {
  tester.view.physicalSize = const Size(1200, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final api = FakeProjectsApi(
      projects: projects ??
          [
            FakeProjectsApi.project('prj_aaaa0001', 'Alpha', '/work/alpha'),
            FakeProjectsApi.project('prj_aaaa0003', 'Old', '/work/old',
                archivedAt: 1790000000000),
          ]);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      apiClientProvider.overrideWithValue(api),
      wsClientProvider.overrideWithValue(FakeWs()),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: Consumer(
          builder: (context, ref, _) => Column(children: [
            TextButton(
                onPressed: () => showNewBoardDialog(context, ref),
                child: const Text('open new')),
            TextButton(
                onPressed: () => showGenerateBoardDialog(context, ref),
                child: const Text('open ai')),
            TextButton(
                onPressed: () =>
                    showNewBoardDialog(context, ref, projectId: 'prj_aaaa0001'),
                child: const Text('open new in alpha')),
          ]),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return api;
}

Future<void> _pickProject(WidgetTester tester, String name) async {
  // The project picker is the dropdown showing "No project".
  await tester.tap(find.text('No project').first);
  await tester.pumpAndSettle();
  await tester.tap(find.text(name).last);
  await tester.pumpAndSettle();
}

void main() {
  group('new board dialog', () {
    testWidgets('without a project it asks for a workspace folder as before',
        (tester) async {
      final api = await _pumpDialogs(tester);
      await tester.tap(find.text('open new'));
      await tester.pumpAndSettle();
      expect(find.text('Workspace folder (optional)'), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextField, 'Title'), 'Plain');
      await tester.enterText(
          find.widgetWithText(TextField, '').last, '/tmp/outputs');
      await tester.tap(find.widgetWithText(FilledButton, 'Create'));
      await tester.pumpAndSettle();
      final body = api.calls('POST', '/api/kanban/boards').single.body as Map;
      expect(body['workspace_dir'], '/tmp/outputs');
      expect(body.containsKey('project_id'), isFalse);
    });

    testWidgets('choosing a project replaces the folder field by the root, '
        'read-only', (tester) async {
      final api = await _pumpDialogs(tester);
      await tester.tap(find.text('open new'));
      await tester.pumpAndSettle();
      await _pickProject(tester, 'Alpha');

      expect(find.text('Workspace folder (optional)'), findsNothing);
      expect(find.text('/work/alpha'), findsOneWidget);
      expect(find.text('Follows the project — change it in the project.'),
          findsOneWidget);
      expect(find.byIcon(Icons.lock_outline), findsOneWidget);
      // Archived projects are not offered.
      await tester.tap(find.text('Alpha').first);
      await tester.pumpAndSettle();
      expect(find.text('Old'), findsNothing);
      await tester.tap(find.text('Alpha').last);
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextField, 'Title'), 'Roadmap');
      await tester.tap(find.widgetWithText(FilledButton, 'Create'));
      await tester.pumpAndSettle();
      final body = api.calls('POST', '/api/kanban/boards').single.body as Map;
      expect(body['project_id'], 'prj_aaaa0001');
      // The folder is the project's: the dialog sends none of its own.
      expect(body.containsKey('workspace_dir'), isFalse);
    });

    testWidgets('a folder typed first is dropped once a project is chosen',
        (tester) async {
      final api = await _pumpDialogs(tester);
      await tester.tap(find.text('open new'));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.widgetWithText(TextField, '').last, '/tmp/outputs');
      await _pickProject(tester, 'Alpha');
      await tester.enterText(find.widgetWithText(TextField, 'Title'), 'Roadmap');
      await tester.tap(find.widgetWithText(FilledButton, 'Create'));
      await tester.pumpAndSettle();
      final body = api.calls('POST', '/api/kanban/boards').single.body as Map;
      expect(body.containsKey('workspace_dir'), isFalse);
    });

    testWidgets('opened from a project’s page the project is fixed',
        (tester) async {
      await _pumpDialogs(tester);
      await tester.tap(find.text('open new in alpha'));
      await tester.pumpAndSettle();
      expect(find.text('Alpha'), findsOneWidget);
      expect(find.text('/work/alpha'), findsOneWidget);
      await tester.tap(find.text('Alpha'));
      await tester.pumpAndSettle();
      // The picker is disabled: nothing opens.
      expect(find.text('No project'), findsNothing);
    });

    testWidgets('with no project to pick the dialog is the one it was',
        (tester) async {
      await _pumpDialogs(tester, projects: []);
      await tester.tap(find.text('open new'));
      await tester.pumpAndSettle();
      expect(find.text('Project'), findsNothing);
      expect(find.text('Workspace folder (optional)'), findsOneWidget);
    });
  });

  group('AI board dialog', () {
    testWidgets('sends the project, and no folder of its own', (tester) async {
      final api = await _pumpDialogs(tester);
      await tester.tap(find.text('open ai'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Goal'), 'Ship v2');
      await _pickProject(tester, 'Alpha');
      expect(find.text('/work/alpha'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Generate'));
      await tester.pumpAndSettle();
      final body = api.calls('POST', '/api/kanban/generate').single.body as Map;
      expect(body['project_id'], 'prj_aaaa0001');
      expect(body['goal'], 'Ship v2');
      expect(body.containsKey('workspace_dir'), isFalse);
    });

    testWidgets('without a project it sends the folder typed', (tester) async {
      final api = await _pumpDialogs(tester);
      await tester.tap(find.text('open ai'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Goal'), 'Ship v2');
      await tester.enterText(
          find.widgetWithText(TextField, '').last, '/tmp/outputs');
      await tester.tap(find.widgetWithText(FilledButton, 'Generate'));
      await tester.pumpAndSettle();
      final body = api.calls('POST', '/api/kanban/generate').single.body as Map;
      expect(body['workspace_dir'], '/tmp/outputs');
      expect(body.containsKey('project_id'), isFalse);
    });
  });

  group('board list', () {
    Future<FakeProjectsApi> pumpScreen(WidgetTester tester,
        {bool betaHasBoards = true}) async {
      tester.view.physicalSize = const Size(1300, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final api = FakeProjectsApi(projects: [
        FakeProjectsApi.project('prj_aaaa0001', 'Alpha', '/work/alpha'),
        FakeProjectsApi.project('prj_aaaa0002', 'Beta', '/work/beta'),
      ]);
      api.boards.addAll([
        _board(1, 'Roadmap', project: 'prj_aaaa0001', effective: '/work/alpha'),
        if (betaHasBoards)
          _board(2, 'Site', project: 'prj_aaaa0002', effective: '/work/beta/site',
              own: '/work/beta/site'),
        _board(3, 'Personal'),
      ]);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(api),
          wsClientProvider.overrideWithValue(FakeWs()),
        ],
        child: MaterialApp(
            theme: AppTheme.light(), home: const Scaffold(body: KanbanScreen())),
      ));
      await tester.pumpAndSettle();
      return api;
    }

    Future<void> filterBy(WidgetTester tester, String label) async {
      await tester.tap(find.text('All projects'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
    }

    testWidgets('shows every board, each with its project', (tester) async {
      await pumpScreen(tester);
      expect(find.text('Roadmap'), findsOneWidget);
      expect(find.text('Site'), findsOneWidget);
      expect(find.text('Personal'), findsOneWidget);
      // The board of a project names it; the other has no such line.
      expect(find.text('Alpha'), findsOneWidget);
      expect(find.text('Beta'), findsOneWidget);
    });

    testWidgets('narrows to one project', (tester) async {
      await pumpScreen(tester);
      await filterBy(tester, 'Alpha');
      expect(find.text('Roadmap'), findsOneWidget);
      expect(find.text('Site'), findsNothing);
      expect(find.text('Personal'), findsNothing);
    });

    testWidgets('narrows to the boards that have no project', (tester) async {
      await pumpScreen(tester);
      await filterBy(tester, 'No project');
      expect(find.text('Personal'), findsOneWidget);
      expect(find.text('Roadmap'), findsNothing);
      expect(find.text('Site'), findsNothing);
    });

    testWidgets('says so when no board is in the chosen project',
        (tester) async {
      await pumpScreen(tester, betaHasBoards: false);
      await filterBy(tester, 'Beta');
      expect(find.text('No board belongs to this project.'), findsOneWidget);
    });

    testWidgets('an open board names its project and where its workers run',
        (tester) async {
      final api = await pumpScreen(tester);
      await tester.tap(find.text('Roadmap'));
      await tester.pumpAndSettle();
      expect(find.text('Project: Alpha · Workspace: /work/alpha'), findsOneWidget);
      expect(api.calls('GET', '/api/kanban/board').isNotEmpty, isTrue);
    });
  });

  group('model', () {
    test('KanbanBoard reads the project and where its workers run', () {
      final b = KanbanBoard.fromJson(
          _board(1, 'Roadmap', project: 'prj_aaaa0001', effective: '/work/alpha'));
      expect(b.projectId, 'prj_aaaa0001');
      expect(b.effectiveWorkspaceDir, '/work/alpha');
      expect(b.workspaceDir, isNull);
      final plain = KanbanBoard.fromJson(_board(2, 'Plain', own: '/x'));
      expect(plain.projectId, isNull);
      expect(plain.effectiveWorkspaceDir, '/x');
    });

    test('the filter default is “every board”', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      expect(c.read(boardProjectFilterProvider), isNull);
      expect(kNoProjectFilter, isEmpty);
    });
  });
}
