// Projects (desktop): the list, creating a project, and the Overview tab —
// against a faked daemon. What the screens exist to do: show the projects (the
// archived ones only on request), create one only from a folder the daemon
// accepts and say why when it does not, change the settings it was given, and
// archive, restore or delete it — the delete after saying what goes with it.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:senclaw_desktop/features/projects/projects_provider.dart';

import 'support/fake_projects_api.dart';
import 'support/projects_harness.dart';

/// Types into the field with the given label (`Name`, `Description`).
Future<void> _type(WidgetTester tester, String label, String text) async {
  await tester.enterText(find.widgetWithText(TextField, label), text);
  await tester.pump();
}

Future<void> _typeRoot(WidgetTester tester, String text) async {
  await tester.enterText(find.byKey(const ValueKey('project-root-field')), text);
  await tester.pump();
}

/// Lets the debounced folder check run and its answer arrive.
Future<void> _checked(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump();
}

bool _enabled(WidgetTester tester, Finder f) =>
    tester.widget<FilledButton>(f).onPressed != null;

void main() {
  group('list', () {
    testWidgets('shows active projects; archived ones only on request',
        (tester) async {
      final api = FakeProjectsApi(projects: [
        FakeProjectsApi.project('prj_aaaa0001', 'Alpha', '/work/alpha',
            description: 'The billing service', chatCount: 3),
        FakeProjectsApi.project('prj_aaaa0002', 'Old', '/work/old',
            archivedAt: 1790000000000),
      ]);
      await pumpProjects(tester, api: api);

      expect(find.text('Alpha'), findsOneWidget);
      expect(find.text('The billing service'), findsOneWidget);
      expect(find.text('/work/alpha'), findsOneWidget);
      expect(find.text('3 sessions'), findsOneWidget);
      expect(find.text('Old'), findsNothing);
      // One request fetches everything; the toggle only filters it.
      expect(api.calls('GET', '/api/projects').first.body,
          {'archived': 'all'});

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(find.text('Old'), findsOneWidget);
      expect(find.text('Archived'), findsOneWidget);
    });

    testWidgets('a missing folder is flagged on the tile', (tester) async {
      final api = FakeProjectsApi(projects: [
        FakeProjectsApi.project('prj_aaaa0001', 'Alpha', '/work/alpha',
            rootExists: false),
      ]);
      await pumpProjects(tester, api: api);
      expect(find.text('Folder missing'), findsOneWidget);
    });

    testWidgets('with no project it offers to create one', (tester) async {
      await pumpProjects(tester, api: FakeProjectsApi(projects: []));
      expect(find.text('No projects yet'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'New project'), findsWidgets);
    });

    testWidgets('opening a tile shows the project with its five tabs',
        (tester) async {
      await pumpProjects(tester);
      await tester.tap(find.text('Alpha'));
      await tester.pumpAndSettle();
      for (final tab in ['Overview', 'Context', 'Project facts', 'Boards', 'Sessions']) {
        expect(find.widgetWithText(Tab, tab), findsOneWidget, reason: tab);
      }
      expect(find.byTooltip('Back to projects'), findsOneWidget);
    });
  });

  group('create', () {
    Future<void> openDialog(WidgetTester tester) async {
      await tester.tap(find.widgetWithText(FilledButton, 'New project').first);
      await tester.pumpAndSettle();
    }

    testWidgets('a refused folder says why and blocks Create', (tester) async {
      final h = await pumpProjects(tester);
      await openDialog(tester);
      await _type(tester, 'Name', 'Beta');
      final create = find.widgetWithText(FilledButton, 'Create');
      expect(_enabled(tester, create), isFalse);

      await _typeRoot(tester, '/');
      await _checked(tester);
      expect(find.text('The top of the filesystem cannot be a project folder.'),
          findsOneWidget);
      expect(_enabled(tester, create), isFalse);

      await _typeRoot(tester, '/Users/me');
      await _checked(tester);
      expect(
          find.text(
              'The home folder is too broad for a project; pick a folder inside it.'),
          findsOneWidget);
      expect(_enabled(tester, create), isFalse);

      await _typeRoot(tester, '/nope');
      await _checked(tester);
      expect(find.text('That folder does not exist.'), findsOneWidget);
      expect(_enabled(tester, create), isFalse);

      // Nothing was created by any of this.
      expect(h.api.calls('POST', '/api/projects').where((c) => c.path == '/api/projects'),
          isEmpty);
    });

    testWidgets('a folder another project uses names that project',
        (tester) async {
      await pumpProjects(tester);
      await openDialog(tester);
      await _typeRoot(tester, '/work/alpha');
      await _checked(tester);
      expect(find.text('The project “Alpha” already uses this folder.'),
          findsOneWidget);
    });

    testWidgets('the folder is checked once typing pauses, not on every key',
        (tester) async {
      final h = await pumpProjects(tester);
      await openDialog(tester);
      await _typeRoot(tester, '/w');
      await tester.pump(const Duration(milliseconds: 100));
      await _typeRoot(tester, '/wo');
      await tester.pump(const Duration(milliseconds: 100));
      await _typeRoot(tester, '/work/beta');
      await _checked(tester);
      final checks = h.api.calls('POST', '/api/projects/validate-root');
      expect(checks, hasLength(1));
      expect((checks.single.body as Map)['path'], '/work/beta');
    });

    testWidgets('a good folder enables Create, which sends the choices made',
        (tester) async {
      final h = await pumpProjects(tester);
      await openDialog(tester);
      await _type(tester, 'Name', 'Beta');
      await _typeRoot(tester, '/work/beta');
      await _checked(tester);
      expect(find.text('The folder can be used.'), findsOneWidget);

      // Facts kept per chat, and the agent's common facts left out.
      await tester.tap(find.text('Kept per chat'));
      await tester.pump();
      await tester.tap(find.byType(SwitchListTile));
      await tester.pump();

      final create = find.widgetWithText(FilledButton, 'Create');
      expect(_enabled(tester, create), isTrue);
      await tester.tap(create);
      await tester.pumpAndSettle();

      final sent = h.api.calls('POST').firstWhere((c) => c.path == '/api/projects');
      expect(sent.body, {
        'name': 'Beta',
        'root': '/work/beta',
        'factsWrite': 'chat',
        'inheritCommon': false,
      });
      // The new project opens, on its own page.
      expect(h.container.read(openProjectProvider), isNotNull);
      expect(find.widgetWithText(Tab, 'Overview'), findsOneWidget);
    });

    testWidgets('Browse fills the folder and proposes its name', (tester) async {
      await pumpProjects(tester, picked: '/work/gamma');
      await openDialog(tester);
      await tester.tap(find.widgetWithText(OutlinedButton, 'Browse…'));
      await _checked(tester);
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TextField, 'gamma'), findsOneWidget);
      expect(find.text('/work/gamma'), findsWidgets);
      expect(find.text('The folder can be used.'), findsOneWidget);
    });

    testWidgets('Browse keeps a name the person already typed', (tester) async {
      await pumpProjects(tester, picked: '/work/gamma');
      await openDialog(tester);
      await _type(tester, 'Name', 'Mine');
      await tester.tap(find.widgetWithText(OutlinedButton, 'Browse…'));
      await _checked(tester);
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, 'Mine'), findsOneWidget);
    });

    testWidgets('cancelling the folder chooser changes nothing', (tester) async {
      await pumpProjects(tester);
      await openDialog(tester);
      await tester.tap(find.widgetWithText(OutlinedButton, 'Browse…'));
      await tester.pumpAndSettle();
      expect(find.text('Checking the folder…'), findsNothing);
      expect(find.text('The folder can be used.'), findsNothing);
    });
  });

  group('overview', () {
    testWidgets('renaming sends only the name', (tester) async {
      final h = await pumpProjects(tester, open: 'prj_aaaa0001');
      await _type(tester, 'Name', 'Alpha 2');
      await tester.tap(find.widgetWithText(FilledButton, 'Save changes'));
      await tester.pumpAndSettle();
      expect(h.api.calls('PATCH').single.body, {'name': 'Alpha 2'});
      expect(h.api.byId('prj_aaaa0001')!['name'], 'Alpha 2');
    });

    testWidgets('Save is off until something changed, and Revert undoes it',
        (tester) async {
      await pumpProjects(tester, open: 'prj_aaaa0001');
      final save = find.widgetWithText(FilledButton, 'Save changes');
      expect(_enabled(tester, save), isFalse);
      await _type(tester, 'Description', 'Billing');
      expect(_enabled(tester, save), isTrue);
      await tester.tap(find.widgetWithText(TextButton, 'Revert'));
      await tester.pump();
      expect(_enabled(tester, save), isFalse);
    });

    testWidgets('a new folder must pass the check before Save, and its own '
        'current folder needs none', (tester) async {
      final h = await pumpProjects(tester, open: 'prj_aaaa0001');
      // The unchanged folder is not asked about.
      await tester.pump(const Duration(milliseconds: 400));
      expect(h.api.calls('POST', '/api/projects/validate-root'), isEmpty);

      final save = find.widgetWithText(FilledButton, 'Save changes');
      await _typeRoot(tester, '/nope');
      await _checked(tester);
      expect(find.text('That folder does not exist.'), findsOneWidget);
      expect(_enabled(tester, save), isFalse);

      await _typeRoot(tester, '/work/alpha2');
      await _checked(tester);
      expect(_enabled(tester, save), isTrue);
      expect(
          find.textContaining('A session that is already running keeps the folder'),
          findsOneWidget);
      // Editing a project's root passes its id, so its own root is not "in use".
      expect(
          (h.api.calls('POST', '/api/projects/validate-root').last.body as Map)['projectId'],
          'prj_aaaa0001');

      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(h.api.calls('PATCH').single.body, {'root': '/work/alpha2'});
    });

    testWidgets('facts_write and inherit_common are saved when changed',
        (tester) async {
      final h = await pumpProjects(tester, open: 'prj_aaaa0001');
      await tester.scrollUntilVisible(find.text('Not kept'), 200,
          scrollable: find.byType(Scrollable).first);
      await tester.tap(find.text('Not kept'));
      await tester.pump();
      await tester.tap(find.byType(SwitchListTile));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Save changes'));
      await tester.pumpAndSettle();
      expect(h.api.calls('PATCH').single.body,
          {'factsWrite': 'off', 'inheritCommon': false});
    });

    testWidgets('archiving and restoring send archived true and false',
        (tester) async {
      final h = await pumpProjects(tester, open: 'prj_aaaa0001');
      await tester.scrollUntilVisible(find.text('Archive project'), 200,
          scrollable: find.byType(Scrollable).first);
      await tester.tap(find.text('Archive project'));
      await tester.pumpAndSettle();
      expect(h.api.calls('PATCH').last.body, {'archived': true});
      // The page now says so, and offers the way back.
      expect(find.textContaining('This project is archived'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Restore project'), 200,
          scrollable: find.byType(Scrollable).first);
      await tester.tap(find.text('Restore project'));
      await tester.pumpAndSettle();
      expect(h.api.calls('PATCH').last.body, {'archived': false});
      expect(find.textContaining('This project is archived'), findsNothing);
    });
  });

  group('delete for good', () {
    Future<void> openPurge(WidgetTester tester) async {
      await tester.scrollUntilVisible(find.text('Delete permanently…'), 200,
          scrollable: find.byType(Scrollable).first);
      await tester.tap(find.text('Delete permanently…'));
      await tester.pumpAndSettle();
    }

    FakeProjectsApi withContent() {
      final api = FakeProjectsApi(projects: [
        FakeProjectsApi.project('prj_aaaa0001', 'Alpha', '/work/alpha',
            chatCount: 4),
      ]);
      api.boards.addAll([
        {'id': 1, 'title': 'Roadmap', 'project_id': 'prj_aaaa0001', 'card_count': 2},
        {'id': 2, 'title': 'Bugs', 'project_id': 'prj_aaaa0001', 'card_count': 0},
      ]);
      api.facts.addAll([
        FakeProjectsApi.fact('f1', 'The API listens on port 7421'),
        FakeProjectsApi.fact('f2', 'Deploys go through the blue pipeline'),
        FakeProjectsApi.fact('f3', 'Old port', supersededBy: 'f1'),
      ]);
      api.chats.addAll([
        {'jid': 'web:main:a', 'name': 'One'},
        {'jid': 'web:main:b', 'name': 'Two'},
      ]);
      return api;
    }

    testWidgets('names how many sessions, boards and facts go with it, and '
        'warns that a big bank is slow', (tester) async {
      await pumpProjects(tester, api: withContent(), open: 'prj_aaaa0001');
      await openPurge(tester);

      expect(find.text('Delete “Alpha” for good?'), findsOneWidget);
      expect(find.textContaining('4 sessions leave the project'), findsOneWidget);
      expect(find.textContaining('2 boards leave the project'), findsOneWidget);
      // Replaced facts are not counted: they were already out of sight.
      expect(find.textContaining('2 facts of the project are deleted'),
          findsOneWidget);
      expect(find.text('The project context is deleted.'), findsOneWidget);
      expect(find.textContaining('about 23 seconds for 20,000 facts'),
          findsOneWidget);
      expect(find.textContaining('Nothing inside the project folder is touched'),
          findsOneWidget);
    });

    testWidgets('Cancel deletes nothing', (tester) async {
      final h = await pumpProjects(tester, api: withContent(), open: 'prj_aaaa0001');
      await openPurge(tester);
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();
      expect(h.api.calls('DELETE'), isEmpty);
      expect(h.api.byId('prj_aaaa0001'), isNotNull);
      expect(find.widgetWithText(Tab, 'Overview'), findsOneWidget);
    });

    testWidgets('confirming deletes with ?purge=true and returns to the list',
        (tester) async {
      final h = await pumpProjects(tester, api: withContent(), open: 'prj_aaaa0001');
      await openPurge(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Delete permanently'));
      await tester.pumpAndSettle();

      expect(h.api.calls('DELETE').single.path, '/api/projects/prj_aaaa0001?purge=true');
      expect(h.api.byId('prj_aaaa0001'), isNull);
      expect(h.container.read(openProjectProvider), isNull);
      expect(find.text('No projects yet'), findsOneWidget);
      expect(find.textContaining('3 facts removed, 2 sessions detached'),
          findsOneWidget);
    });
  });
}
