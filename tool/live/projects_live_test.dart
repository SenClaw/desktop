// A live check of the Projects screens against a SCRATCH daemon: the real
// `ApiClient` and `WsClient`, the real widgets, no fakes — only the window is
// the test engine's, not the macOS app's (so it can run unattended and leave
// screenshots).
//
// It creates, edits and deletes projects, so it refuses to run against the
// default ports (18788/18789, the person's own daemon) and needs the scratch
// daemon's:
//
//   LIVE_WORK_DIR=<dir holding alpha/ beta/ gamma/> LIVE_EVIDENCE_DIR=<dir for PNGs> \
//   flutter test tool/live/projects_live_test.dart \
//     --dart-define=SENCLAW_UI_PORT=52788 --dart-define=SENCLAW_WS_PORT=52789
//
// Start the daemon with its own HOME, SENCLAW_HOME and cwd (see CLAUDE.md,
// "Run against a dev daemon"). It is not part of `flutter test` (that runs
// test/ only).

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show FontLoader, MethodChannel;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:senclaw_desktop/core/config/app_config.dart';
import 'package:senclaw_desktop/core/i18n/l10n.dart';
import 'package:senclaw_desktop/core/prefs.dart';
import 'package:senclaw_desktop/core/transport/api_client.dart';
import 'package:senclaw_desktop/core/transport/connection.dart';
import 'package:senclaw_desktop/core/transport/ws_client.dart';
import 'package:senclaw_desktop/features/chat/agents_provider.dart';
import 'package:senclaw_desktop/features/chat/groups_provider.dart';
import 'package:senclaw_desktop/features/chat/new_chat_dialog.dart';
import 'package:senclaw_desktop/features/chat/session_list.dart';
import 'package:senclaw_desktop/features/cognitive/facts_panel.dart';
import 'package:senclaw_desktop/features/kanban/kanban_providers.dart';
import 'package:senclaw_desktop/features/kanban/kanban_screen.dart';
import 'package:senclaw_desktop/features/projects/project_context_tab.dart';
import 'package:senclaw_desktop/features/projects/projects_provider.dart';
import 'package:senclaw_desktop/features/projects/projects_screen.dart';
import 'package:senclaw_desktop/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _evidence = Platform.environment['LIVE_EVIDENCE_DIR'];
final _work = Platform.environment['LIVE_WORK_DIR'];

/// What the run saw, for the report.
final _notes = <String>[];
void _note(String s) {
  _notes.add(s);
  // ignore: avoid_print
  print('NOTE: $s');
}

Future<void> _loadRealFont() async {
  final root = Platform.environment['FLUTTER_ROOT'];
  final dir = Directory('$root/bin/cache/artifacts/material_fonts');
  // The app's own families (UI and monospace) are system fonts the test engine
  // does not have; stand Roboto in for them so text is measured and drawn as
  // letters, not boxes.
  // 'Ahem' is what the test engine draws a style with no family in (the box
  // letters), e.g. the text of a dropdown.
  for (final family in ['Roboto', 'AntUi', 'SFMono-Regular', 'Ahem']) {
    final loader = FontLoader(family);
    for (final w in ['Regular', 'Medium', 'Bold']) {
      final f = File('${dir.path}/Roboto-$w.ttf');
      if (f.existsSync()) {
        loader.addFont(Future.value(f.readAsBytesSync().buffer.asByteData()));
      }
    }
    await loader.load();
  }
  final icons = File('${dir.path}/MaterialIcons-Regular.otf');
  if (icons.existsSync()) {
    final loader = FontLoader('MaterialIcons')
      ..addFont(Future.value(icons.readAsBytesSync().buffer.asByteData()));
    await loader.load();
  }
}

final _shot = GlobalKey();
final _cfg = AppConfig.fromEnvironment();

/// Wait for real I/O: the test clock does not move sockets.
Future<void> _io(WidgetTester t, [int ms = 120]) async {
  await t.runAsync(() => Future<void>.delayed(Duration(milliseconds: ms)));
  await t.pump(const Duration(milliseconds: 50));
}

Future<void> _until(WidgetTester t, bool Function() ok, String what,
    {int tries = 80}) async {
  for (var i = 0; i < tries; i++) {
    await _io(t);
    if (ok()) return;
  }
  final seen = find
      .byType(Text)
      .evaluate()
      .map((e) => (e.widget as Text).data ?? '')
      .where((x) => x.isNotEmpty)
      .take(40)
      .toList();
  await _snap(t, 'timeout-${what.replaceAll(RegExp(r'[^a-z0-9]+'), '-')}');
  fail('timed out waiting for: $what\nvisible: $seen');
}

Future<void> _untilFound(WidgetTester t, Finder f, String what) =>
    _until(t, () => f.evaluate().isNotEmpty, what);

Future<void> _snap(WidgetTester t, String name) async {
  await _io(t, 200);
  if (_evidence == null) return;
  final boundary = t.renderObject<RenderRepaintBoundary>(find.byKey(_shot));
  final bytes = await t.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1.0);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  });
  File('$_evidence/$name.png')
    ..createSync(recursive: true)
    ..writeAsBytesSync(bytes!);
}

class _Rig {
  _Rig(this.container, this.api);
  final ProviderContainer container;
  final ApiClient api;
}

/// The app's theme with the stand-in font everywhere. A button's text style
/// names no family, which the real app resolves to the system font and the test
/// engine to its box letters.
ThemeData _themed() {
  final base = AppTheme.light();
  ButtonStyle withFont(ButtonStyle? s, double size, FontWeight w) =>
      (s ?? const ButtonStyle()).copyWith(
          textStyle: WidgetStatePropertyAll(
              TextStyle(fontFamily: 'Roboto', fontSize: size, fontWeight: w)));
  return base.copyWith(
    textTheme: base.textTheme.apply(fontFamily: 'Roboto'),
    filledButtonTheme: FilledButtonThemeData(
        style: withFont(base.filledButtonTheme.style, 14, FontWeight.w500)),
    outlinedButtonTheme: OutlinedButtonThemeData(
        style: withFont(base.outlinedButtonTheme.style, 14, FontWeight.w400)),
    textButtonTheme: TextButtonThemeData(
        style: withFont(base.textButtonTheme.style, 14, FontWeight.w400)),
  );
}

/// The app around one screen: Vietnamese, the real font, and a router with the
/// pages the screens navigate to (their content does not matter here).
Future<void> _show(WidgetTester t, ProviderContainer c, Widget home) async {
  final router = GoRouter(routes: [
    GoRoute(path: '/', builder: (_, _) => Scaffold(body: home)),
    GoRoute(path: '/kanban', builder: (_, _) => const Text('kanban page')),
    GoRoute(path: '/chat', builder: (_, _) => const Text('chat page')),
  ]);
  await t.pumpWidget(UncontrolledProviderScope(
    container: c,
    child: MaterialApp.router(
      debugShowCheckedModeBanner: false,
      locale: const Locale('vi'),
      supportedLocales: const [Locale('en'), Locale('vi')],
      localizationsDelegates: const [
        L10nDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: _themed(),
      routerConfig: router,
      // Above the Navigator, so a dialog is in the picture.
      builder: (_, child) => RepaintBoundary(key: _shot, child: child),
    ),
  ));
  await _io(t);
}

Future<_Rig> _mount(WidgetTester t, Widget home,
    {Size size = const Size(1280, 860)}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues({'senclaw:app-language': 'vi'});
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(overrides: [
    prefsProvider.overrideWithValue(prefs),
    folderPickerProvider.overrideWithValue((_) async => null),
  ]);
  addTearDown(() => L10n.global = const L10n('en'));
  await _show(t, container, home);
  return _Rig(container, ApiClient(_cfg));
}

/// Taps a tab of the project page and lets the page finish sliding in (tapping
/// or typing mid-slide would hit the page that is leaving).
Future<void> _openTab(WidgetTester t, String label) async {
  await t.tap(find.widgetWithText(Tab, label));
  // The slide starts on a frame after the tap and needs a second one to end.
  await t.pump();
  await t.pump(const Duration(milliseconds: 500));
  await t.pump(const Duration(milliseconds: 500));
  await _io(t, 250);
}

/// Presses a button by calling its handler. A snackbar can still be fading out
/// over the bottom-right corner, where these buttons are; the point of this run
/// is the traffic to the daemon, not pointer routing (the widget tests cover it).
Future<void> _press(WidgetTester t, Finder button) async {
  final b = t.widget<ButtonStyleButton>(button);
  expect(b.onPressed, isNotNull, reason: 'the button is disabled');
  b.onPressed!();
  await t.pump();
}

/// A snackbar sits over the buttons at the bottom right until it has gone.
Future<void> _clearSnack(WidgetTester t) async {
  await t.pump(const Duration(seconds: 6));
  await t.pump();
  await t.pump(const Duration(milliseconds: 500));
  await t.pump(const Duration(milliseconds: 500));
}

Finder get _contextEditor => find.descendant(
    of: find.byType(ProjectContextTab), matching: find.byType(TextField));

Finder _field(String label) => find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.labelText == label);
Finder _hint(String startsWith) => find.byWidgetPredicate((w) =>
    w is TextField && (w.decoration?.hintText ?? '').startsWith(startsWith));

String vi(String en) => const L10n('vi').t(en);

void main() {
  final hasDaemon = _work != null &&
      _cfg.uiPort != 18788 &&
      _cfg.uiPort != 18789 &&
      _cfg.wsPort != 18788 &&
      _cfg.wsPort != 18789;

  setUpAll(() async {
    if (!hasDaemon) return;
    await _loadRealFont();
    // `flutter test` answers every HTTP request with a 400; this run talks to
    // the scratch daemon for real.
    HttpOverrides.global = null;
    // The New Session page creates a microphone recorder; no plugin here.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('com.llfbandit.record/messages'), (_) async => null);
  });

  tearDownAll(() {
    if (_evidence != null && hasDaemon) {
      File('$_evidence/notes.txt').writeAsStringSync(_notes.join('\n'));
    }
  });

  // Skipped unless LIVE_WORK_DIR is set and the ports are not the defaults
  // (see the header for how to run it).
  testWidgets('projects, end to end on a scratch daemon', (t) async {
    final alpha = '$_work/alpha';
    final gamma = '$_work/gamma';
    final rig = await _mount(t, const ProjectsScreen());
    final api = rig.api;
    Future<dynamic> get(String p) => t.runAsync(() => api.get(p)).then((v) => v);
    final c = rig.container;

    // ── 1. The empty list ────────────────────────────────────────────────
    await _untilFound(t, find.text(vi('No projects yet')), 'empty state');
    await _snap(t, '01-list-empty');

    // ── 2. Create: a refused folder, then a good one ─────────────────────
    await t.tap(find.widgetWithText(FilledButton, vi('New project')).first);
    await _io(t, 250);
    await t.enterText(_field(vi('Name')), 'Alpha');
    await t.enterText(find.byKey(const ValueKey('project-root-field')), '/');
    await t.pump(const Duration(milliseconds: 400));
    await _untilFound(
        t,
        find.text(vi('The top of the filesystem cannot be a project folder.')),
        'filesystem_root reason');
    await _snap(t, '02-create-refused-root');

    await t.enterText(find.byKey(const ValueKey('project-root-field')), alpha);
    await t.pump(const Duration(milliseconds: 400));
    await _untilFound(t, find.text(vi('The folder can be used.')), 'valid root');
    await _snap(t, '03-create-valid-root');
    await t.tap(find.widgetWithText(FilledButton, vi('Create')));
    await _untilFound(
        t, find.widgetWithText(Tab, vi('Overview')), 'project page after create');
    final projects = ((await get('/api/projects?archived=all'))['projects'] as List);
    expect(projects, hasLength(1));
    final alphaId = projects.single['id'] as String;
    expect(projects.single['root'], contains('/alpha'));
    expect(c.read(openProjectProvider), alphaId);
    await _snap(t, '04-overview');

    // ── 3. A second project whose folder has a CLAUDE.md ─────────────────
    c.read(openProjectProvider.notifier).state = null;
    await _io(t);
    await t.tap(find.widgetWithText(FilledButton, vi('New project')).first);
    await _io(t, 250);
    await t.enterText(_field(vi('Name')), 'Gamma');
    await t.enterText(find.byKey(const ValueKey('project-root-field')), alpha);
    await t.pump(const Duration(milliseconds: 400));
    await _untilFound(
        t,
        find.textContaining('“Alpha”'),
        'root_in_use names the owner');
    await _snap(t, '05-create-root-in-use');
    await t.enterText(find.byKey(const ValueKey('project-root-field')), gamma);
    await t.pump(const Duration(milliseconds: 400));
    await _untilFound(
        t, find.textContaining('CLAUDE.md'), 'CLAUDE.md hint for gamma');
    await t.tap(find.text(vi('Kept per chat')));
    await t.pump();
    await t.tap(find.widgetWithText(FilledButton, vi('Create')));
    await _untilFound(
        t, find.widgetWithText(Tab, vi('Overview')), 'gamma page');
    final gammaRow = ((await get('/api/projects?archived=all'))['projects'] as List)
        .firstWhere((p) => p['name'] == 'Gamma') as Map;
    expect(gammaRow['factsWrite'], 'chat');
    expect(gammaRow['hasClaudeMd'], true);
    final gammaId = gammaRow['id'] as String;
    c.read(openProjectProvider.notifier).state = alphaId;
    // The page of the project just left is still up until Alpha's has loaded:
    // its folder in the header says which one this is.
    await _untilFound(t, find.textContaining('/alpha'), 'alpha page again');
    await _untilFound(
        t, find.widgetWithText(Tab, vi('Overview')), 'alpha tabs again');

    // ── 4. Context: save, then lose a race ───────────────────────────────
    await _openTab(t, vi('Context'));
    await _until(t, () => _contextEditor.evaluate().isNotEmpty, 'editor');
    await t.enterText(_contextEditor,
        '# Alpha\nDịch vụ thanh toán. Máy chủ API chạy ở cổng 7421.');
    await t.pump();
    await _untilFound(
        t, find.widgetWithText(FilledButton, vi('Save context')), 'save button');
    await _press(t, find.widgetWithText(FilledButton, vi('Save context')));
    await _until(t, () => find.textContaining(vi('Saved — sessions of the project read it from their next turn.')).evaluate().isNotEmpty, 'saved snackbar');
    var ctx = await get('/api/projects/$alphaId/context') as Map;
    expect(ctx['content'], contains('cổng 7421'));
    final v1 = ctx['updatedAt'];
    await _snap(t, '06-context-saved');
    await _clearSnack(t);

    // Someone else saves meanwhile.
    final other = await t.runAsync(() => api.put('/api/projects/$alphaId/context',
        body: {'content': '# Alpha (nơi khác)\nBản sửa từ cửa sổ khác.', 'updatedAt': v1}));
    expect((other as Map)['updatedAt'], isNot(v1));
    await t.enterText(_contextEditor, '# Alpha\nBản sửa của tôi.');
    await t.pump();
    await _press(t, find.widgetWithText(FilledButton, vi('Save context')));
    await _untilFound(t, find.text(vi('The context changed elsewhere')), '409 dialog');
    expect(find.textContaining('Bản sửa từ cửa sổ khác.'), findsWidgets);
    await _snap(t, '07-context-conflict');
    await _press(t, find.widgetWithText(FilledButton, vi('Overwrite with mine')));
    await _until(t, () => find.text(vi('The context changed elsewhere')).evaluate().isEmpty, 'dialog closed');
    await _io(t, 400);
    ctx = await get('/api/projects/$alphaId/context') as Map;
    expect(ctx['content'], contains('Bản sửa của tôi.'));
    await _clearSnack(t);

    // ── 5. Facts: typed in by hand, a secret refused ─────────────────────
    await _openTab(t, vi('Project facts'));
    await _untilFound(t, find.text(vi('This project has no facts.')), 'no facts yet');
    await t.enterText(_hint('Một fact là một câu'),
        'Máy chủ API của Alpha lắng nghe ở cổng 7421.');
    await t.pump();
    await _press(t, find.widgetWithText(FilledButton, vi('Add fact')));
    await _untilFound(t, find.text(vi('typed')), 'typed fact in the list');
    await _clearSnack(t);
    await t.enterText(_hint('Một fact là một câu'),
        'Khoá API là sk-ant-api03-abcdefghijklmnopqrstuvwxyz0123456789ABCDEF');
    await t.pump();
    await _press(t, find.widgetWithText(FilledButton, vi('Add fact')));
    final refused = find.textContaining('nên không được lưu');
    for (var i = 0; i < 30 && refused.evaluate().isEmpty; i++) {
      await _io(t);
    }
    if (refused.evaluate().isNotEmpty) {
      _note('secret fact: refused by the daemon and shown in Vietnamese');
    } else {
      _note('secret fact: NOT refused (the daemon stored it) — see screenshot 08');
    }
    await _snap(t, '08-facts-typed-and-secret');
    final facts = await get('/api/projects/$alphaId/facts') as Map;
    _note('facts after the two adds: total=${facts['total']}');

    // ── 6. A board in the project, made from the dialog ──────────────────
    await _openTab(t, vi('Boards'));
    await _untilFound(t, find.text(vi('This project has no boards yet.')), 'no boards');
    await t.tap(find.widgetWithText(FilledButton, vi('New board')));
    await _io(t, 250);
    await t.enterText(_field(vi('Title')), 'Lộ trình Alpha');
    await _snap(t, '09-new-board-in-project');
    await t.tap(find.widgetWithText(FilledButton, vi('Create')));
    await _until(
        t,
        () => c.read(openBoardProvider) != null,
        'board created and opened');
    final boards = (await get('/api/projects/$alphaId/boards') as Map)['boards'] as List;
    expect(boards, hasLength(1));
    expect(boards.single['project_id'], alphaId);
    expect(boards.single['workspace_dir'], isNull);
    expect(boards.single['effective_workspace_dir'], contains('/alpha'));
    await _io(t, 300);
    await _snap(t, '10-boards-tab');

    // ── 7. Sessions: created in the project through the real WebSocket ───
    final ws = c.read(wsClientProvider);
    ws.connect();
    await _until(t, () => ws.status == WsStatus.connected, 'ws connected');
    c.read(groupsProvider);
    c.read(agentsProvider);
    await _io(t, 400);
    t.view.physicalSize = const Size(1280, 860);
    c.read(openProjectProvider.notifier).state = null;
    c.read(newChatProjectProvider.notifier).state = alphaId;
    await _show(
        t,
        c,
        Row(children: [
          SizedBox(width: 300, child: SessionList(onNewChat: () {})),
          const Expanded(child: NewChatScreen()),
        ]));
    await _untilFound(t, find.textContaining('/alpha'), 'project folder on New Session');
    await _snap(t, '11-new-session-in-project');
    await t.enterText(find.byType(TextField).last, 'Chào, đây là phiên trong dự án Alpha');
    await t.pump();
    await t.tap(find.byIcon(Icons.arrow_upward).last);
    await _until(t, () => c.read(groupsProvider).any((g) => g.projectId == alphaId),
        'group:registered with projectId');
    final chats = (await get('/api/projects/$alphaId/chats') as Map)['chats'] as List;
    expect(chats, hasLength(1));
    final jid = chats.single['jid'] as String;
    final group = c.read(groupsProvider).firstWhere((g) => g.jid == jid);
    expect(group.projectId, alphaId);
    _note('session $jid registered; allowedWorkDirs → ${group.workDir}');
    expect(group.workDir, contains('/alpha'));

    // The session list grouped by project.
    c.read(groupModeProvider.notifier).set(GroupMode.project);
    await _io(t, 400);
    await _snap(t, '12-session-list-by-project');

    // The daemon refuses to move a session: nothing in the UI offers it, so
    // ask the daemon directly and say what it answered.
    ws.send({'type': 'update:group', 'jid': jid, 'projectId': gammaId});
    await _io(t, 500);
    final chatsAfter = (await get('/api/projects/$alphaId/chats') as Map)['chats'] as List;
    expect(chatsAfter, hasLength(1), reason: 'the session stays in its project');
    _note('update:group projectId=<other> → session still in Alpha (${chatsAfter.length} chat)');

    // ── 8. A registration the daemon refuses comes back to the form ──────
    await t.runAsync(() => api.patch('/api/projects/$gammaId', body: {'archived': true}));
    c.read(groupsProvider.notifier).createChat(
        folder: 'main', name: 'Phiên vào dự án đã lưu trữ', isCode: false, projectId: gammaId);
    await _until(t, () => c.read(registerRefusalProvider) != null, 'refusal');
    _note('register:group into an archived project → "${c.read(registerRefusalProvider)!.message}"');
    await t.runAsync(() => api.patch('/api/projects/$gammaId', body: {'archived': false}));

    // ── 9. Knowledge → Facts shows the project by name ───────────────────
    await _show(t, c, const FactsPanel());
    await _untilFound(t, find.textContaining('Dự án: Alpha'), 'project bank label');
    await t.tap(find.byType(DropdownButton<String>));
    await _io(t, 250);
    await t.tap(find.textContaining('Dự án: Alpha').last);
    await _untilFound(
        t, find.textContaining('lắng nghe ở cổng 7421'), 'project fact in the global panel');
    await _snap(t, '13-facts-panel-project-bank');

    // Forgetting through the global panel's route, under the project's bank.
    await t.tap(find.byTooltip(vi('Forget')).first);
    await _io(t, 250);
    await t.tap(find.widgetWithText(FilledButton, vi('Forget')));
    await _io(t, 600);
    final afterForget = await get('/api/projects/$alphaId/facts') as Map;
    _note('forget via /api/memory/facts/:id?bank=project:… → project facts total=${afterForget['total']}');

    // ── 10. Kanban: filter by project, project on the card and the header ─
    await _show(t, c, const KanbanScreen());
    c.read(openBoardProvider.notifier).state = null;
    await _untilFound(t, find.text('Lộ trình Alpha'), 'board in the list');
    // A board with no project, to filter against.
    await t.runAsync(() => api.post('/api/kanban/boards', body: {'title': 'Việc cá nhân'}));
    c.invalidate(kanbanBoardsProvider);
    await _untilFound(t, find.text('Việc cá nhân'), 'plain board');
    await _snap(t, '14-kanban-list');
    await t.tap(find.text(vi('All projects')));
    await _io(t, 250);
    await t.tap(find.text('Alpha').last);
    await _io(t, 250);
    expect(find.text('Việc cá nhân'), findsNothing);
    expect(find.text('Lộ trình Alpha'), findsOneWidget);
    await _snap(t, '15-kanban-filtered');
    await t.tap(find.text('Lộ trình Alpha'));
    await _until(t, () => find.textContaining('Dự án: Alpha · Thư mục làm việc:').evaluate().isNotEmpty, 'board header');
    await _snap(t, '16-kanban-board-header');

    // ── 11. Back on the Projects page: archive, restore, delete ──────────
    await _show(t, c, const ProjectsScreen());
    c.read(openProjectProvider.notifier).state = null;
    await _untilFound(t, find.text('Gamma'), 'list with two projects');
    await _snap(t, '17-list-two-projects');
    c.read(openProjectProvider.notifier).state = alphaId;
    await _untilFound(t, find.textContaining('/alpha'), 'alpha page');
    await t.scrollUntilVisible(find.text(vi('Archive project')), 200,
        scrollable: find.byType(Scrollable).first);
    await t.tap(find.text(vi('Archive project')));
    await _untilFound(t, find.textContaining(vi('This project is archived: it takes no new sessions or boards. Restore it in Overview.').substring(0, 30)), 'archived banner');
    await _snap(t, '18-archived');
    await t.scrollUntilVisible(find.text(vi('Restore project')), 200,
        scrollable: find.byType(Scrollable).first);
    await t.tap(find.text(vi('Restore project')));
    await _until(t, () => find.textContaining(vi('This project is archived: it takes no new sessions or boards. Restore it in Overview.').substring(0, 30)).evaluate().isEmpty, 'restored');

    await t.scrollUntilVisible(find.text(vi('Delete permanently…')), 200,
        scrollable: find.byType(Scrollable).first);
    await t.tap(find.text(vi('Delete permanently…')));
    await _untilFound(t, find.textContaining('rời dự án'), 'purge dialog');
    await _io(t, 500);
    await _snap(t, '19-purge-dialog');
    final sw = Stopwatch()..start();
    await t.tap(find.widgetWithText(FilledButton, vi('Delete permanently')));
    await _until(t, () => c.read(openProjectProvider) == null, 'purge finished');
    _note('purge of Alpha took ${sw.elapsedMilliseconds} ms (incl. UI polling)');
    final left = ((await get('/api/projects?archived=all'))['projects'] as List)
        .map((p) => p['name'])
        .toList();
    expect(left, ['Gamma']);
    // The session left the project but is still there; the board too.
    await _until(
        t,
        () => c.read(groupsProvider).where((g) => g.jid == jid).every((g) => g.projectId == null),
        'sidebar refreshed after purge');
    final groups = (c.read(groupsProvider)).where((g) => g.jid == jid).toList();
    _note('after purge the session ${groups.isEmpty ? "is gone" : "stays (projectId=${groups.single.projectId})"}');
    final allBoards = await get('/api/kanban/boards') as List;
    final alphaBoard = allBoards.firstWhere((b) => b['title'] == 'Lộ trình Alpha') as Map;
    _note('after purge the board has project_id=${alphaBoard['project_id']} workspace_dir=${alphaBoard['workspace_dir']}');
    expect(alphaBoard['project_id'], isNull);
    expect(alphaBoard['workspace_dir'], contains('/alpha'));
    await _snap(t, '20-list-after-purge');

    // Clean up what this run made so the daemon is as it was.
    await t.runAsync(() => api.delete('/api/projects/$gammaId?purge=true'));
    for (final b in allBoards) {
      await t.runAsync(() => api.post('/api/kanban/board/delete', body: {'id': b['id']}));
    }
    ws.send({'type': 'unregister:group', 'jid': jid});
    await _io(t, 300);
    await t.pumpWidget(const SizedBox.shrink());
    c.dispose();
    await t.pump(const Duration(seconds: 20));
  }, skip: !hasDaemon, timeout: const Timeout(Duration(minutes: 5)));
}

