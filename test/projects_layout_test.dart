// Projects, in both languages, with a real font: Vietnamese runs longer than
// English, so a layout that fits in English can overflow once translated. This
// renders the project screens, the dialogs, the session list grouped by
// project and the app shell with its new Projects entry in each language and
// fails on any overflow.
//
// Measuring that needs a REAL font — `flutter_test`'s default draws every glyph
// as a box `fontSize` wide and reports overflow that does not exist (same
// helper as vietnamese_layout_test.dart).

import 'dart:async' show unawaited;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:senclaw_desktop/app/shell.dart';
import 'package:senclaw_desktop/core/i18n/l10n.dart';
import 'package:senclaw_desktop/core/i18n/locale_provider.dart';
import 'package:senclaw_desktop/core/prefs.dart';
import 'package:senclaw_desktop/core/transport/connection.dart';
import 'package:senclaw_desktop/features/chat/groups_provider.dart';
import 'package:senclaw_desktop/features/chat/new_chat_dialog.dart';
import 'package:senclaw_desktop/features/chat/session_list.dart';
import 'package:senclaw_desktop/features/kanban/kanban_dialogs.dart';
import 'package:senclaw_desktop/features/projects/project_dialogs.dart';
import 'package:senclaw_desktop/features/projects/projects_provider.dart';
import 'package:senclaw_desktop/features/projects/projects_screen.dart';
import 'package:senclaw_desktop/models/project.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_projects_api.dart';
import 'support/fake_ws.dart';

bool _fontsLoaded = false;

Future<bool> _loadRealFont() async {
  if (_fontsLoaded) return true;
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root == null) return false;
  final dir = Directory('$root/bin/cache/artifacts/material_fonts');
  if (!dir.existsSync()) return false;
  final loader = FontLoader('Roboto');
  for (final weight in ['Regular', 'Medium', 'Bold']) {
    final f = File('${dir.path}/Roboto-$weight.ttf');
    if (f.existsSync()) {
      loader.addFont(Future.value(f.readAsBytesSync().buffer.asByteData()));
    }
  }
  await loader.load();
  _fontsLoaded = true;
  return true;
}

class _Rig {
  _Rig(this.api, this.container, this.router);
  final FakeProjectsApi api;
  final ProviderContainer container;
  final GoRouter router;
}

FakeProjectsApi _api() {
  final api = FakeProjectsApi(projects: [
    FakeProjectsApi.project('prj_aaaa0001', 'Hệ thống thanh toán và hoá đơn',
        '/Users/nguyen/Projects/he-thong-thanh-toan-va-hoa-don',
        description: 'Dịch vụ thanh toán, đối soát và xuất hoá đơn điện tử cho khách hàng doanh nghiệp',
        chatCount: 12,
        hasClaudeMd: true),
    FakeProjectsApi.project('prj_aaaa0002', 'Old', '/work/old',
        archivedAt: 1790000000000, rootExists: false),
  ]);
  api.contextText = 'Dịch vụ thanh toán.\n' * 40;
  api.contextVersion = 2;
  api.facts.addAll([
    FakeProjectsApi.fact('f1',
        'Máy chủ thanh toán lắng nghe ở cổng 7421 và chỉ nhận kết nối từ mạng nội bộ của công ty',
        source: 'manual'),
    FakeProjectsApi.fact('f2', 'Việc triển khai đi qua pipeline xanh-lam', source: 'kanban'),
  ]);
  api.boards.add({
    'id': 1,
    'title': 'Lộ trình quý bốn',
    'project_id': 'prj_aaaa0001',
    'card_count': 7,
    'effective_workspace_dir': '/Users/nguyen/Projects/he-thong-thanh-toan-va-hoa-don',
  });
  api.chats.add({
    'jid': 'web:main:aa',
    'name': 'Sửa lỗi tổng tiền hoá đơn',
    'folder': 'main',
    'groupType': 'chat',
    'lastActive': '2026-10-18T09:30:00Z',
  });
  return api;
}

Future<_Rig> _pump(
  WidgetTester tester,
  Widget Function(GoRouter router) home, {
  required String lang,
  required Size size,
  String? open,
  String location = '/',
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({'senclaw:app-language': lang});
  final prefs = await SharedPreferences.getInstance();
  final api = _api();
  final container = ProviderContainer(overrides: [
    prefsProvider.overrideWithValue(prefs),
    apiClientProvider.overrideWithValue(api),
    wsClientProvider.overrideWithValue(FakeWs()),
    folderPickerProvider.overrideWithValue((_) async => null),
  ]);
  addTearDown(container.dispose);
  addTearDown(() => L10n.global = const L10n('en'));
  if (open != null) container.read(openProjectProvider.notifier).state = open;
  late final GoRouter router;
  router = GoRouter(initialLocation: location, routes: [
    GoRoute(path: '/', builder: (_, _) => home(router)),
    ShellRoute(
      builder: (_, _, child) => AppShell(child: child),
      routes: [
        GoRoute(path: '/projects', builder: (_, _) => const SizedBox.shrink()),
      ],
    ),
  ]);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp.router(
      locale: Locale(container.read(localeCodeProvider)),
      supportedLocales: const [Locale('en'), Locale('vi')],
      localizationsDelegates: const [
        L10nDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(fontFamily: 'Roboto'),
      routerConfig: router,
    ),
  ));
  await tester.pumpAndSettle();
  return _Rig(api, container, router);
}

Future<void> _tab(WidgetTester tester, String label) async {
  await tester.tap(find.widgetWithText(Tab, label));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    if (!await _loadRealFont()) {
      fail('Roboto not found under FLUTTER_ROOT — cannot measure real layout');
    }
  });

  for (final lang in ['en', 'vi']) {
    final vi = lang == 'vi';
    String t(String en, String viText) => vi ? viText : en;

    group('in $lang', () {
      testWidgets('the project list lays out at 1100 and at 800 px',
          (tester) async {
        await _pump(tester, (_) => const Scaffold(body: ProjectsScreen()),
            lang: lang, size: const Size(1100, 700));
        expect(tester.takeException(), isNull);
        expect(find.text(t('Projects', 'Dự án')), findsWidgets);
        expect(find.text('Hệ thống thanh toán và hoá đơn'), findsOneWidget);
        expect(find.text(t('12 sessions', '12 phiên')), findsOneWidget);

        tester.view.physicalSize = const Size(800, 600);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.tap(find.byType(Switch));
        await tester.pumpAndSettle();
        expect(find.text(t('Folder missing', 'Thiếu thư mục')), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      for (final entry in {
        'Overview': ('Tổng quan', 0),
        'Context': ('Context', 1),
        'Project facts': ('Fact của dự án', 2),
        'Boards': ('Bảng', 3),
        'Sessions': ('Phiên', 4),
      }.entries) {
        testWidgets('the ${entry.key} tab lays out at 900 px', (tester) async {
          await _pump(tester, (_) => const Scaffold(body: ProjectsScreen()),
              lang: lang, size: const Size(900, 650), open: 'prj_aaaa0001');
          await _tab(tester, t(entry.key, entry.value.$1));
          expect(tester.takeException(), isNull);
        });
      }

      testWidgets('the Overview tab, scrolled to its archive and delete rows',
          (tester) async {
        await _pump(tester, (_) => const Scaffold(body: ProjectsScreen()),
            lang: lang, size: const Size(900, 650), open: 'prj_aaaa0001');
        await tester.scrollUntilVisible(
            find.text(t('Delete permanently…', 'Xoá vĩnh viễn…')), 300,
            scrollable: find.byType(Scrollable).first);
        expect(tester.takeException(), isNull);
      });

      testWidgets('the create dialog shows a refused folder without overflow',
          (tester) async {
        await _pump(tester, (_) => const Scaffold(body: ProjectsScreen()),
            lang: lang, size: const Size(900, 650));
        await tester.tap(find.widgetWithText(FilledButton, t('New project', 'Dự án mới')).first);
        await tester.pumpAndSettle();
        await tester.enterText(
            find.byKey(const ValueKey('project-root-field')), '/Users/me');
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(
            find.text(t(
                'The home folder is too broad for a project; pick a folder inside it.',
                'Thư mục home quá rộng cho một dự án; hãy chọn một thư mục bên trong nó.')),
            findsOneWidget);
      });

      testWidgets('the delete dialog lays out', (tester) async {
        final rig = await _pump(
            tester, (_) => const Scaffold(body: SizedBox.expand()),
            lang: lang, size: const Size(900, 650));
        final p = Project.fromJson(rig.api.projects.first);
        unawaited(showPurgeProjectDialog(
            tester.element(find.byType(SizedBox).first), p));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.textContaining('12 '), findsWidgets);
      });

      testWidgets('the context conflict dialog lays out', (tester) async {
        final rig = await _pump(tester, (_) => const Scaffold(body: ProjectsScreen()),
            lang: lang, size: const Size(1000, 700), open: 'prj_aaaa0001');
        await _tab(tester, t('Context', 'Context'));
        await tester.enterText(find.byType(TextField).first, 'Bản của tôi');
        await tester.pump();
        rig.api.saveElsewhere('Bản ở nơi khác\n' * 30);
        await tester.tap(find.widgetWithText(
            FilledButton, t('Save context', 'Lưu context')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text(t('The context changed elsewhere', 'Context đã đổi ở nơi khác')),
            findsOneWidget);
      });

      testWidgets('the session list grouped by project lays out in a 264 px '
          'sidebar', (tester) async {
        SharedPreferences.setMockInitialValues({});
        final rig = await _pump(tester, (_) => Scaffold(
              body: SizedBox(width: 264, child: SessionList(onNewChat: () {})),
            ),
            lang: lang, size: const Size(600, 700));
        rig.container.read(groupModeProvider.notifier).set(GroupMode.project);
        rig.container.read(groupsProvider);
        (rig.container.read(wsClientProvider) as FakeWs).emit({
          'type': 'groups',
          'groups': [
            {'jid': 'web:main:1', 'name': 'Sửa lỗi tổng tiền hoá đơn điện tử', 'folder': 'main', 'projectId': 'prj_aaaa0001', 'lastActivity': 1790000000000},
            {'jid': 'web:main:2', 'name': 'Chat ngoài dự án', 'folder': 'main', 'lastActivity': 1790000001000},
          ],
        });
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text(t('NO PROJECT', 'KHÔNG CÓ DỰ ÁN')), findsOneWidget);
        expect(find.text('HỆ THỐNG THANH TOÁN VÀ HOÁ ĐƠN'), findsOneWidget);

        await tester.tap(find.byTooltip(t('Group & sort', 'Nhóm & sắp xếp')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text(t('Agent', 'Agent')), findsOneWidget);
        expect(find.text(t('Project', 'Dự án')), findsWidgets);
      });

      testWidgets('New Session with a project lays out narrow and wide',
          (tester) async {
        await _pump(tester, (_) => const Scaffold(body: NewChatScreen()),
            lang: lang, size: const Size(1000, 760));
        await tester.tap(find.byType(DropdownButton<String?>).first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Hệ thống thanh toán và hoá đơn').last);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        tester.view.physicalSize = const Size(520, 760);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });

      testWidgets('the new-board dialog with a project lays out',
          (tester) async {
        await _pump(tester, (_) => Scaffold(
              body: Consumer(
                  builder: (context, ref, _) => TextButton(
                      onPressed: () => showNewBoardDialog(context, ref,
                          projectId: 'prj_aaaa0001'),
                      child: const Text('open'))),
            ),
            lang: lang, size: const Size(900, 650));
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text(t('Follows the project — change it in the project.',
                'Theo dự án — muốn đổi thì đổi ở dự án.')),
            findsOneWidget);
      });

      testWidgets('the app shell has the Projects entry and lays out short '
          'and narrow', (tester) async {
        await _pump(tester, (_) => const SizedBox.shrink(),
            lang: lang, size: const Size(900, 420), location: '/projects');
        expect(tester.takeException(), isNull);
        expect(find.byTooltip(t('Projects', 'Dự án')), findsOneWidget);
        expect(find.byIcon(Icons.folder_special_outlined), findsOneWidget);
      });
    });
  }
}
