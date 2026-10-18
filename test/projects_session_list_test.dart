// The session list grouped by project (desktop): a collapsible group per
// project, the sessions that belong to none in a group of their own and last;
// the agent grouping keeps working as it did, with a marker on the sessions
// that are in a project; the choice survives a restart and an older stored
// choice still means what it meant.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:senclaw_desktop/core/prefs.dart';
import 'package:senclaw_desktop/core/transport/connection.dart';
import 'package:senclaw_desktop/features/chat/groups_provider.dart';
import 'package:senclaw_desktop/features/chat/session_list.dart';
import 'package:senclaw_desktop/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_projects_api.dart';
import 'support/fake_ws.dart';

Map<String, dynamic> _g(String jid, String name, String folder,
        {String? project, int activity = 1790000000000}) =>
    {
      'jid': jid,
      'name': name,
      'folder': folder,
      'groupType': 'chat',
      'lastActivity': activity,
      'projectId': ?project,
    };

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  Map<String, Object> prefs = const {},
  List<Map<String, dynamic>>? groups,
}) async {
  tester.view.physicalSize = const Size(420, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues(prefs);
  final sp = await SharedPreferences.getInstance();
  final api = FakeProjectsApi(projects: [
    FakeProjectsApi.project('prj_aaaa0001', 'Alpha', '/work/alpha'),
    FakeProjectsApi.project('prj_aaaa0002', 'Beta', '/work/beta'),
  ]);
  final ws = FakeWs();
  final container = ProviderContainer(overrides: [
    prefsProvider.overrideWithValue(sp),
    apiClientProvider.overrideWithValue(api),
    wsClientProvider.overrideWithValue(ws),
  ]);
  addTearDown(container.dispose);
  container.read(groupsProvider);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(body: SessionList(onNewChat: () {})),
    ),
  ));
  ws.emit({
    'type': 'groups',
    'groups': groups ??
        [
          _g('web:main:1', 'Invoice bug', 'main', project: 'prj_aaaa0001'),
          _g('web:main:2', 'Landing page', 'main', project: 'prj_aaaa0002', activity: 1790000005000),
          _g('web:main:3', 'Api refactor', 'dev', project: 'prj_aaaa0001', activity: 1790000003000),
          _g('web:main:4', 'Loose chat', 'main', activity: 1790000009000),
        ],
  });
  await tester.pumpAndSettle();
  return container;
}

/// Where each text sits from the top, to read the order of the groups.
double _y(WidgetTester tester, String text) =>
    tester.getTopLeft(find.text(text).first).dy;

void main() {
  group('grouped by project', () {
    const byProject = {'senclaw:sessionlist-organize': 'projects'};

    testWidgets('a group per project, the sessions with none last',
        (tester) async {
      await _pump(tester, prefs: byProject);
      expect(find.text('ALPHA'), findsOneWidget);
      expect(find.text('BETA'), findsOneWidget);
      expect(find.text('NO PROJECT'), findsOneWidget);
      // A project with more recent activity comes first; the sessions that
      // belong to none come after every project, however recent they are.
      expect(_y(tester, 'BETA'), lessThan(_y(tester, 'ALPHA')));
      expect(_y(tester, 'ALPHA'), lessThan(_y(tester, 'NO PROJECT')));
      expect(_y(tester, 'Landing page'), lessThan(_y(tester, 'Invoice bug')));
      expect(_y(tester, 'NO PROJECT'), lessThan(_y(tester, 'Loose chat')));
    });

    testWidgets('counts the sessions of each group', (tester) async {
      await _pump(tester, prefs: byProject);
      // Alpha has two sessions, Beta one, and the loose one stands alone.
      expect(find.text('2'), findsOneWidget);
      expect(find.text('1'), findsNWidgets(2));
    });

    testWidgets('a group collapses and opens again', (tester) async {
      await _pump(tester, prefs: byProject);
      expect(find.text('Invoice bug'), findsOneWidget);
      await tester.tap(find.text('ALPHA'));
      await tester.pumpAndSettle();
      expect(find.text('Invoice bug'), findsNothing);
      expect(find.text('Api refactor'), findsNothing);
      // The others are untouched.
      expect(find.text('Landing page'), findsOneWidget);
      await tester.tap(find.text('ALPHA'));
      await tester.pumpAndSettle();
      expect(find.text('Invoice bug'), findsOneWidget);
    });

    testWidgets('the “No project” group collapses on its own', (tester) async {
      await _pump(tester, prefs: byProject);
      await tester.tap(find.text('NO PROJECT'));
      await tester.pumpAndSettle();
      expect(find.text('Loose chat'), findsNothing);
      expect(find.text('Invoice bug'), findsOneWidget);
    });

    testWidgets('a session of a project that is gone is grouped under its id',
        (tester) async {
      await _pump(tester, prefs: byProject, groups: [
        _g('web:main:1', 'Orphan', 'main', project: 'prj_dead0001'),
      ]);
      expect(find.text('PRJ_DEAD0001'), findsOneWidget);
      expect(find.text('Orphan'), findsOneWidget);
    });

    testWidgets('names sort the groups A–Z when sorting by name',
        (tester) async {
      await _pump(tester, prefs: {
        ...byProject,
        'senclaw:sessionlist-sort': 'name',
      });
      expect(_y(tester, 'ALPHA'), lessThan(_y(tester, 'BETA')));
    });

    testWidgets('the choice is made from the Group & sort menu and kept',
        (tester) async {
      final c = await _pump(tester);
      expect(c.read(groupModeProvider), GroupMode.agent);
      await tester.tap(find.byTooltip('Group & sort'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Project').last);
      await tester.pumpAndSettle();
      expect(c.read(groupModeProvider), GroupMode.project);
      expect(find.text('NO PROJECT'), findsOneWidget);
      expect(
          c.read(prefsHelperProvider).string('senclaw:sessionlist-organize', ''),
          'projects');
    });
  });

  group('grouped by agent (as before)', () {
    testWidgets('keeps the agent buckets and marks the sessions in a project',
        (tester) async {
      await _pump(tester);
      expect(find.text('MAIN'), findsOneWidget);
      expect(find.text('DEV'), findsOneWidget);
      expect(find.text('NO PROJECT'), findsNothing);
      // Three of the four sessions are in a project; each carries its marker.
      expect(find.byIcon(Icons.folder_special_outlined), findsNWidgets(3));
    });

    testWidgets('a stored choice from before the project axis means the agent '
        'axis', (tester) async {
      final c = await _pump(tester, prefs: {'senclaw:sessionlist-organize': 'project'});
      expect(c.read(groupModeProvider), GroupMode.agent);
      final legacy =
          await _pump(tester, prefs: {'senclaw:sessionlist-organize': 'project-recent'});
      expect(legacy.read(groupModeProvider), GroupMode.agent);
    });
  });
}
