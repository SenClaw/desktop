// Projects in the session UI (desktop): choosing a project when a session is
// created — the folder then follows the project and cannot be edited, only chat
// and code sessions can join, the choice goes out on `register:group` — and the
// session list grouped by project with a group for the sessions that have none.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:senclaw_desktop/core/transport/connection.dart';
import 'package:senclaw_desktop/features/chat/groups_provider.dart';
import 'package:senclaw_desktop/features/chat/new_chat_dialog.dart';
import 'package:senclaw_desktop/features/projects/project_widgets.dart';
import 'package:senclaw_desktop/features/projects/projects_provider.dart';
import 'package:senclaw_desktop/models/group.dart';
import 'package:senclaw_desktop/theme/app_theme.dart';

import 'support/fake_projects_api.dart';
import 'support/fake_ws.dart';

Future<({FakeProjectsApi api, FakeWs ws, ProviderContainer container})> _pumpNewChat(
  WidgetTester tester, {
  FakeProjectsApi? api,
  String? preselect,
}) async {
  tester.view.physicalSize = const Size(1200, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final fake = api ??
      FakeProjectsApi(projects: [
        FakeProjectsApi.project('prj_aaaa0001', 'Alpha', '/work/alpha'),
        FakeProjectsApi.project('prj_aaaa0002', 'Beta', '/work/beta'),
        FakeProjectsApi.project('prj_aaaa0003', 'Old', '/work/old',
            archivedAt: 1790000000000),
      ]);
  final ws = FakeWs();
  final container = ProviderContainer(overrides: [
    apiClientProvider.overrideWithValue(fake),
    wsClientProvider.overrideWithValue(ws),
  ]);
  addTearDown(container.dispose);
  if (preselect != null) {
    container.read(newChatProjectProvider.notifier).state = preselect;
  }
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(body: NewChatScreen())),
  ));
  await tester.pumpAndSettle();
  return (api: fake, ws: ws, container: container);
}

Future<void> _chooseProject(WidgetTester tester, String name) async {
  await tester.tap(find.byType(ProjectPicker));
  await tester.pumpAndSettle();
  await tester.tap(find.text(name).last);
  await tester.pumpAndSettle();
}

Future<void> _chooseKind(WidgetTester tester, String label) async {
  await tester.tap(find.textContaining(label).first);
  await tester.pumpAndSettle();
}

Future<void> _send(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField).first, text);
  await tester.pump();
}

void main() {
  group('New Session', () {
    testWidgets('offers the project picker with the open projects only',
        (tester) async {
      await _pumpNewChat(tester);
      expect(find.text('Project'), findsOneWidget);
      await tester.tap(find.byType(ProjectPicker));
      await tester.pumpAndSettle();
      expect(find.text('No project'), findsWidgets);
      expect(find.text('Alpha'), findsWidgets);
      expect(find.text('Beta'), findsWidgets);
      // An archived project takes no new session.
      expect(find.text('Old'), findsNothing);
    });

    testWidgets('is not offered when there is no project to pick',
        (tester) async {
      await _pumpNewChat(tester, api: FakeProjectsApi(projects: []));
      expect(find.byType(ProjectPicker), findsNothing);
    });

    testWidgets('choosing a project shows its folder, locked', (tester) async {
      await _pumpNewChat(tester);
      expect(find.text('/work/alpha'), findsNothing);
      await _chooseProject(tester, 'Alpha');
      expect(find.text('/work/alpha'), findsOneWidget);
      expect(find.byIcon(Icons.lock_outline), findsWidgets);
      expect(find.textContaining('In the project “Alpha”'), findsOneWidget);
    });

    testWidgets('a chat session in a project is registered with its projectId',
        (tester) async {
      final h = await _pumpNewChat(tester);
      await _chooseProject(tester, 'Alpha');
      await _send(tester, 'Fix the invoice total');
      await tester.tap(find.byIcon(Icons.arrow_upward).last);
      await tester.pump();

      final reg = h.ws.sentOf('register:group').single;
      expect(reg['projectId'], 'prj_aaaa0001');
      expect(reg['groupType'], 'chat');
      // The daemon puts a project session in the project's root itself.
      expect(reg['allowedWorkDirs'], isNull);
    });

    testWidgets('a code session in a project works in the root, which cannot '
        'be changed', (tester) async {
      final h = await _pumpNewChat(tester);
      await _chooseKind(tester, 'Code');
      await _chooseProject(tester, 'Beta');
      // The folder pill shows the project's folder and ignores taps.
      expect(find.text('beta'), findsOneWidget);
      await tester.tap(find.text('beta'));
      await tester.pumpAndSettle();
      expect(find.text('Start from scratch'), findsNothing,
          reason: 'the folder chooser must not open for a project session');

      await _send(tester, 'Refactor the api');
      await tester.tap(find.byIcon(Icons.arrow_upward).last);
      await tester.pump();
      final reg = h.ws.sentOf('register:group').single;
      expect(reg['projectId'], 'prj_aaaa0002');
      expect(reg['groupType'], 'code');
      expect(reg['allowedWorkDirs'], ['/work/beta']);
    });

    testWidgets('without a project nothing about projects is sent',
        (tester) async {
      final h = await _pumpNewChat(tester);
      await _send(tester, 'Hello there');
      await tester.tap(find.byIcon(Icons.arrow_upward).last);
      await tester.pump();
      expect(h.ws.sentOf('register:group').single.containsKey('projectId'),
          isFalse);
    });

    testWidgets('going back to “No project” frees the folder again',
        (tester) async {
      final h = await _pumpNewChat(tester);
      await _chooseKind(tester, 'Code');
      await _chooseProject(tester, 'Beta');
      await _chooseProject(tester, 'No project');
      await _send(tester, 'Refactor the api');
      await tester.tap(find.byIcon(Icons.arrow_upward).last);
      await tester.pump();
      final reg = h.ws.sentOf('register:group').single;
      expect(reg.containsKey('projectId'), isFalse);
      expect(reg['allowedWorkDirs'], isNull);
    });

    testWidgets('the project is not offered to a Cowork team', (tester) async {
      await _pumpNewChat(tester);
      await _chooseProject(tester, 'Alpha');
      await _chooseKind(tester, 'Cowork');
      expect(find.byType(ProjectPicker), findsNothing);
      expect(find.text('/work/alpha'), findsNothing);
    });

    testWidgets('“New session here” opens on that project, once',
        (tester) async {
      final h = await _pumpNewChat(tester, preselect: 'prj_aaaa0002');
      expect(find.text('/work/beta'), findsOneWidget);
      // The request is used up: opening the page again starts empty.
      expect(h.container.read(newChatProjectProvider), isNull);
    });

    testWidgets('a preselected project that was archived since reads as none',
        (tester) async {
      final h = await _pumpNewChat(tester, preselect: 'prj_aaaa0003');
      await _send(tester, 'Hello there');
      await tester.tap(find.byIcon(Icons.arrow_upward).last);
      await tester.pump();
      expect(h.ws.sentOf('register:group').single.containsKey('projectId'),
          isFalse);
    });
  });

  group('groups', () {
    test('GroupInfo reads projectId, and empty means none', () {
      expect(GroupInfo.fromJson({'jid': 'a', 'projectId': 'prj_aaaa0001'}).projectId,
          'prj_aaaa0001');
      expect(GroupInfo.fromJson({'jid': 'a'}).projectId, isNull);
      expect(GroupInfo.fromJson({'jid': 'a', 'projectId': ''}).projectId, isNull);
      // A refresh of the activity time keeps the project.
      expect(
          GroupInfo.fromJson({'jid': 'a', 'projectId': 'prj_aaaa0001'})
              .copyWith(lastActivity: 5)
              .projectId,
          'prj_aaaa0001');
    });

    test('the groups event carries projectId into the list', () async {
      final ws = FakeWs();
      final c = ProviderContainer(overrides: [wsClientProvider.overrideWithValue(ws)]);
      addTearDown(c.dispose);
      c.read(groupsProvider);
      ws.emit({
        'type': 'groups',
        'groups': [
          {'jid': 'web:main:1', 'name': 'In', 'projectId': 'prj_aaaa0001'},
          {'jid': 'web:main:2', 'name': 'Out'},
        ]
      });
      await Future<void>.delayed(Duration.zero);
      final list = c.read(groupsProvider);
      expect(list.map((g) => g.projectId), ['prj_aaaa0001', null]);
    });

    test('a refused registration is surfaced, other errors are not', () async {
      final ws = FakeWs();
      final c = ProviderContainer(overrides: [wsClientProvider.overrideWithValue(ws)]);
      addTearDown(c.dispose);
      c.read(groupsProvider);
      ws.emit({'type': 'error', 'message': 'something else failed'});
      await Future<void>.delayed(Duration.zero);
      expect(c.read(registerRefusalProvider), isNull);
      ws.emit({
        'type': 'error',
        'message': 'register:group failed: project is archived'
      });
      await Future<void>.delayed(Duration.zero);
      expect(c.read(registerRefusalProvider)!.message, 'project is archived');
    });
  });
}
