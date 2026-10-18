// A project's Context, Facts, Boards and Sessions tabs, against a faked daemon.
//
// Context: the counter warns from 5,000 characters and flags what goes past
// 8,000; a write carries the version it was edited from, and when the daemon
// answers 409 the person sees the copy it holds and picks which one wins.
// Facts: listed, typed in without a model, refused when too short or when the
// daemon says it holds a secret, forgotten after a confirmation, with the
// project's two rules about personal facts and the common facts said out loud.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:senclaw_desktop/features/projects/projects_provider.dart';

import 'support/fake_projects_api.dart';
import 'support/projects_harness.dart';

Future<void> _openTab(WidgetTester tester, String tab) async {
  await tester.tap(find.widgetWithText(Tab, tab));
  await tester.pumpAndSettle();
}

Finder get _editor => find.byType(TextField).first;

String _text(int n) => List.filled(n, 'a').join();

void main() {
  group('context', () {
    Future<ProjectsHarness> open(WidgetTester tester, {String text = 'Billing service.'}) async {
      final api = FakeProjectsApi()
        ..contextText = text
        ..contextVersion = 3;
      final h = await pumpProjects(tester, api: api, open: 'prj_aaaa0001');
      await _openTab(tester, 'Context');
      return h;
    }

    testWidgets('loads the text and counts its characters', (tester) async {
      await open(tester);
      expect(find.text('Billing service.'), findsOneWidget);
      expect(find.text('16 / 8000 characters'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Save context'), findsOneWidget);
    });

    testWidgets('warns from 5,000 characters and flags what goes past 8,000',
        (tester) async {
      await open(tester);
      final save = find.widgetWithText(FilledButton, 'Save context');

      await tester.enterText(_editor, _text(4999));
      await tester.pump();
      expect(find.textContaining('Getting long'), findsNothing);
      expect(find.textContaining('Past the limit'), findsNothing);

      await tester.enterText(_editor, _text(5000));
      await tester.pump();
      expect(find.textContaining('Getting long'), findsOneWidget);
      expect(find.textContaining('Past the limit'), findsNothing);

      await tester.enterText(_editor, _text(8001));
      await tester.pump();
      expect(find.text('8001 / 8000 characters'), findsOneWidget);
      expect(find.textContaining('Past the limit'), findsOneWidget);
      // Over the limit is still saved: the daemon cuts the end for the prompt.
      expect(tester.widget<FilledButton>(save).onPressed, isNotNull);
    });

    testWidgets('the count ignores surrounding whitespace, as the daemon does',
        (tester) async {
      await open(tester);
      await tester.enterText(_editor, '   abc   \n\n');
      await tester.pump();
      expect(find.text('3 / 8000 characters'), findsOneWidget);
    });

    testWidgets('saving sends the text with the version it was edited from',
        (tester) async {
      final h = await open(tester);
      await tester.enterText(_editor, 'Billing service v2.');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Save context'));
      await tester.pumpAndSettle();

      final put = h.api.calls('PUT').single;
      expect(put.path, '/api/projects/prj_aaaa0001/context');
      expect(put.body, {'content': 'Billing service v2.', 'updatedAt': 3});
      expect(h.api.contextText, 'Billing service v2.');
      // Saved: nothing left to save, and a second save would use the new version.
      expect(
          tester
              .widget<FilledButton>(find.widgetWithText(FilledButton, 'Save context'))
              .onPressed,
          isNull);
      // The "Saved" snackbar sits over the button for a few seconds.
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();
      await tester.enterText(_editor, 'v3');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Save context'));
      await tester.pumpAndSettle();
      expect((h.api.calls('PUT').last.body as Map)['updatedAt'], 4);
    });

    testWidgets('a 409 shows the daemon’s copy next to the edit',
        (tester) async {
      final h = await open(tester);
      await tester.enterText(_editor, 'My edit');
      await tester.pump();
      h.api.saveElsewhere('Edited in another window');
      await tester.tap(find.widgetWithText(FilledButton, 'Save context'));
      await tester.pumpAndSettle();

      expect(find.text('The context changed elsewhere'), findsOneWidget);
      expect(find.text('On the daemon now'), findsOneWidget);
      expect(find.text('Edited in another window'), findsOneWidget);
      expect(find.text('Your edit'), findsOneWidget);
      expect(find.text('My edit'), findsWidgets);
      // Nothing was overwritten by the refused write.
      expect(h.api.contextText, 'Edited in another window');
    });

    testWidgets('after a 409, “Use the daemon’s copy” drops the edit',
        (tester) async {
      final h = await open(tester);
      await tester.enterText(_editor, 'My edit');
      await tester.pump();
      h.api.saveElsewhere('Edited in another window');
      await tester.tap(find.widgetWithText(FilledButton, 'Save context'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use the daemon’s copy'));
      await tester.pumpAndSettle();

      expect(find.text('The context changed elsewhere'), findsNothing);
      expect(find.widgetWithText(TextField, 'Edited in another window'),
          findsOneWidget);
      expect(h.api.calls('PUT'), hasLength(1));
      // The editor now matches the daemon: nothing to save.
      expect(
          tester
              .widget<FilledButton>(find.widgetWithText(FilledButton, 'Save context'))
              .onPressed,
          isNull);
    });

    testWidgets('after a 409, “Overwrite with mine” writes against the version '
        'just seen', (tester) async {
      final h = await open(tester);
      await tester.enterText(_editor, 'My edit');
      await tester.pump();
      h.api.saveElsewhere('Edited in another window');
      final seen = h.api.contextVersion;
      await tester.tap(find.widgetWithText(FilledButton, 'Save context'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Overwrite with mine'));
      await tester.pumpAndSettle();

      final puts = h.api.calls('PUT');
      expect(puts, hasLength(2));
      expect(puts.last.body, {'content': 'My edit', 'updatedAt': seen});
      expect(h.api.contextText, 'My edit');
    });

    testWidgets('after a 409, “Keep editing” keeps the edit and says so',
        (tester) async {
      final h = await open(tester);
      await tester.enterText(_editor, 'My edit');
      await tester.pump();
      h.api.saveElsewhere('Edited in another window');
      await tester.tap(find.widgetWithText(FilledButton, 'Save context'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TextField, 'My edit'), findsOneWidget);
      expect(find.textContaining('changed elsewhere while you were editing'),
          findsOneWidget);
      expect(h.api.contextText, 'Edited in another window');
    });

    testWidgets('a copy that changed meanwhile replaces an untouched editor, '
        'but not an edited one', (tester) async {
      final h = await open(tester);
      h.api.saveElsewhere('Edited in another window');
      h.container.invalidate(projectContextProvider('prj_aaaa0001'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, 'Edited in another window'),
          findsOneWidget);

      await tester.enterText(_editor, 'My edit');
      await tester.pump();
      h.api.saveElsewhere('Edited again');
      h.container.invalidate(projectContextProvider('prj_aaaa0001'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, 'My edit'), findsOneWidget);
      expect(find.textContaining('changed elsewhere while you were editing'),
          findsOneWidget);
    });

    testWidgets('says when the folder already has a CLAUDE.md', (tester) async {
      final api = FakeProjectsApi(projects: [
        FakeProjectsApi.project('prj_aaaa0001', 'Alpha', '/work/alpha',
            hasClaudeMd: true),
      ]);
      await pumpProjects(tester, api: api, open: 'prj_aaaa0001');
      await _openTab(tester, 'Context');
      expect(find.textContaining('already has a CLAUDE.md'), findsOneWidget);
    });
  });

  group('facts', () {
    Future<ProjectsHarness> open(WidgetTester tester,
        {FakeProjectsApi? api}) async {
      final fake = api ?? FakeProjectsApi();
      if (api == null) {
        fake.facts.addAll([
          FakeProjectsApi.fact('f1', 'The API listens on port 7421',
              source: 'manual'),
          FakeProjectsApi.fact('f2', 'Deploys go through the blue pipeline'),
          FakeProjectsApi.fact('f0', 'The API listens on port 80',
              supersededBy: 'f1'),
        ]);
      }
      final h = await pumpProjects(tester, api: fake, open: 'prj_aaaa0001');
      await _openTab(tester, 'Project facts');
      return h;
    }

    testWidgets('lists the project’s facts, marks the typed ones, hides the '
        'replaced', (tester) async {
      final h = await open(tester);
      expect(find.text('The API listens on port 7421'), findsOneWidget);
      expect(find.text('Deploys go through the blue pipeline'), findsOneWidget);
      expect(find.text('The API listens on port 80'), findsNothing);
      expect(find.text('typed'), findsOneWidget);
      expect(find.text('2 facts'), findsOneWidget);
      final get = h.api.calls('GET', '/api/projects/prj_aaaa0001/facts').first;
      expect(get.body, {'limit': 100});
    });

    testWidgets('says personal facts stay in the project’s bank', (tester) async {
      await open(tester);
      expect(
          find.textContaining(
              'Personal facts you mention in a chat of this project stay in this bank'),
          findsOneWidget);
    });

    testWidgets('says when chats of the project do not write here, or the '
        'common facts are not read', (tester) async {
      final api = FakeProjectsApi(projects: [
        FakeProjectsApi.project('prj_aaaa0001', 'Alpha', '/work/alpha',
            factsWrite: 'chat', inheritCommon: false),
      ]);
      await open(tester, api: api);
      expect(find.textContaining('keep their own facts'), findsOneWidget);
      expect(find.textContaining('common facts are not read'), findsOneWidget);
    });

    testWidgets('searching sends the words as the daemon’s q', (tester) async {
      final h = await open(tester);
      await tester.enterText(
          find.byWidgetPredicate((w) =>
              w is TextField && w.decoration?.hintText == 'Search facts…'),
          'pipeline');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(h.api.calls('GET', '/api/projects/prj_aaaa0001/facts').last.body,
          {'limit': 100, 'q': 'pipeline'});
      expect(find.text('Deploys go through the blue pipeline'), findsOneWidget);
      expect(find.text('The API listens on port 7421'), findsNothing);
    });

    testWidgets('adding a fact posts it as typed and shows it', (tester) async {
      final h = await open(tester);
      await tester.enterText(
          find.byWidgetPredicate((w) =>
              w is TextField &&
              (w.decoration?.hintText ?? '').startsWith('A fact as a full')),
          'Releases are cut on Fridays');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Add fact'));
      await tester.pumpAndSettle();

      final post = h.api.calls('POST', '/api/projects/prj_aaaa0001/facts').single;
      expect(post.body, {'text': 'Releases are cut on Fridays'});
      expect(find.text('Releases are cut on Fridays'), findsOneWidget);
      expect(find.text('Fact added'), findsOneWidget);
    });

    testWidgets('kind and date are sent only when set', (tester) async {
      final h = await open(tester);
      await tester.enterText(
          find.byWidgetPredicate((w) =>
              w is TextField &&
              (w.decoration?.hintText ?? '').startsWith('A fact as a full')),
          'The migration finished last spring');
      await tester.enterText(
          find.byWidgetPredicate((w) =>
              w is TextField &&
              (w.decoration?.hintText ?? '').startsWith('When (optional)')),
          '2026-03');
      await tester.tap(find.text('About the project or the world'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Something the agent did').last);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Add fact'));
      await tester.pumpAndSettle();
      expect(h.api.calls('POST', '/api/projects/prj_aaaa0001/facts').single.body, {
        'text': 'The migration finished last spring',
        'kind': 'experience',
        'when': '2026-03',
      });
    });

    testWidgets('a fact under 8 characters is refused here, with the limits named',
        (tester) async {
      final h = await open(tester);
      await tester.enterText(
          find.byWidgetPredicate((w) =>
              w is TextField &&
              (w.decoration?.hintText ?? '').startsWith('A fact as a full')),
          'tiny');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Add fact'));
      await tester.pumpAndSettle();
      expect(h.api.calls('POST', '/api/projects/prj_aaaa0001/facts'), isEmpty);
      expect(find.text('A fact is 8 to 600 characters long.'), findsOneWidget);
    });

    testWidgets('a fact the daemon takes for a secret is not kept, and the '
        'text stays to be fixed', (tester) async {
      final h = await open(tester);
      await tester.enterText(
          find.byWidgetPredicate((w) =>
              w is TextField &&
              (w.decoration?.hintText ?? '').startsWith('A fact as a full')),
          'The admin password is hunter2');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Add fact'));
      await tester.pumpAndSettle();
      expect(
          find.text(
              'That text looks like it holds a secret (password), so it was not saved.'),
          findsOneWidget);
      expect(find.text('The admin password is hunter2'), findsWidgets);
      expect(h.api.facts.where((f) => '${f['text']}'.contains('hunter2')), isEmpty);
    });

    testWidgets('the same words as a fact already there say so',
        (tester) async {
      await open(tester);
      await tester.enterText(
          find.byWidgetPredicate((w) =>
              w is TextField &&
              (w.decoration?.hintText ?? '').startsWith('A fact as a full')),
          'Deploys go through the blue pipeline');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Add fact'));
      await tester.pumpAndSettle();
      expect(find.textContaining('was already there'), findsOneWidget);
    });

    testWidgets('forgetting asks first, then deletes under the project',
        (tester) async {
      final h = await open(tester);
      await tester.tap(find.byTooltip('Forget').first);
      await tester.pumpAndSettle();
      expect(find.text('Forget this fact?'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();
      expect(h.api.calls('DELETE'), isEmpty);

      await tester.tap(find.byTooltip('Forget').first);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Forget'));
      await tester.pumpAndSettle();
      expect(h.api.calls('DELETE').single.path,
          '/api/projects/prj_aaaa0001/facts/f1');
      expect(find.text('The API listens on port 7421'), findsNothing);
    });
  });

  group('boards and sessions', () {
    testWidgets('boards list the folder their workers run in and open the board',
        (tester) async {
      final api = FakeProjectsApi();
      api.boards.addAll([
        {
          'id': 4,
          'title': 'Roadmap',
          'project_id': 'prj_aaaa0001',
          'card_count': 7,
          'workspace_dir': null,
          'effective_workspace_dir': '/work/alpha',
        },
        {
          'id': 5,
          'title': 'API work',
          'project_id': 'prj_aaaa0001',
          'card_count': 1,
          'workspace_dir': '/work/alpha/api',
          'effective_workspace_dir': '/work/alpha/api',
        },
        {'id': 6, 'title': 'Elsewhere', 'project_id': 'prj_other', 'card_count': 0},
      ]);
      final h = await pumpProjects(tester, api: api, open: 'prj_aaaa0001');
      await _openTab(tester, 'Boards');

      expect(find.text('Roadmap'), findsOneWidget);
      expect(find.text('Runs in /work/alpha'), findsOneWidget);
      expect(find.text('API work'), findsOneWidget);
      expect(find.text('Runs in /work/alpha/api'), findsOneWidget);
      expect(find.text('7 cards'), findsOneWidget);
      expect(find.text('Elsewhere'), findsNothing);

      await tester.tap(find.text('Roadmap'));
      await tester.pumpAndSettle();
      expect(h.location, '/kanban');
    });

    testWidgets('a new board from the page is created in the project',
        (tester) async {
      final h = await pumpProjects(tester, open: 'prj_aaaa0001');
      await _openTab(tester, 'Boards');
      await tester.tap(find.widgetWithText(FilledButton, 'New board'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Title'), 'Launch');
      await tester.tap(find.widgetWithText(FilledButton, 'Create'));
      await tester.pumpAndSettle();

      final post =
          h.api.calls('POST').firstWhere((c) => c.path == '/api/kanban/boards');
      expect((post.body as Map)['project_id'], 'prj_aaaa0001');
      expect((post.body as Map).containsKey('workspace_dir'), isFalse);
      expect(h.location, '/kanban');
    });

    testWidgets('sessions list the project’s chats and open one',
        (tester) async {
      final api = FakeProjectsApi();
      api.chats.addAll([
        {'jid': 'web:main:aa', 'name': 'Fix the invoice', 'folder': 'main', 'groupType': 'chat', 'lastActive': '2026-10-18T09:30:00Z'},
        {'jid': 'web:main:bb', 'name': 'Refactor api', 'folder': 'main', 'groupType': 'code'},
      ]);
      final h = await pumpProjects(tester, api: api, open: 'prj_aaaa0001');
      await _openTab(tester, 'Sessions');

      expect(find.text('Fix the invoice'), findsOneWidget);
      expect(find.text('Chat · main'), findsOneWidget);
      expect(find.text('Code · main'), findsOneWidget);

      await tester.tap(find.text('Fix the invoice'));
      await tester.pumpAndSettle();
      expect(h.location, '/chat');
    });

    testWidgets('“New session here” asks the New Session page for this project',
        (tester) async {
      final h = await pumpProjects(tester, open: 'prj_aaaa0001');
      await _openTab(tester, 'Sessions');
      await tester.tap(find.widgetWithText(FilledButton, 'New session here'));
      await tester.pumpAndSettle();
      expect(h.container.read(newChatProjectProvider), 'prj_aaaa0001');
      expect(h.location, '/chat');
    });

    testWidgets('an archived project takes no new session or board',
        (tester) async {
      final api = FakeProjectsApi(projects: [
        FakeProjectsApi.project('prj_aaaa0001', 'Alpha', '/work/alpha',
            archivedAt: 1790000000000),
      ]);
      await pumpProjects(tester, api: api, open: 'prj_aaaa0001');
      await _openTab(tester, 'Sessions');
      expect(
          tester
              .widget<FilledButton>(
                  find.widgetWithText(FilledButton, 'New session here'))
              .onPressed,
          isNull);
      await _openTab(tester, 'Boards');
      expect(
          tester
              .widget<FilledButton>(find.widgetWithText(FilledButton, 'New board'))
              .onPressed,
          isNull);
    });
  });
}
