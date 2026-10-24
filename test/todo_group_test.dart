// The Console's agent todos: each one must say whether it is running, waiting
// or done. They used to differ only by a one-character glyph (`↻` / `–` / `✓`)
// in near-identical grey, under a heading that was the chat's raw id.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:senclaw_desktop/core/config/app_config.dart';
import 'package:senclaw_desktop/core/i18n/l10n.dart';
import 'package:senclaw_desktop/core/prefs.dart';
import 'package:senclaw_desktop/core/transport/connection.dart';
import 'package:senclaw_desktop/core/transport/ws_client.dart';
import 'package:senclaw_desktop/features/dock/right_dock.dart';
import 'package:senclaw_desktop/features/dock/todo_group.dart';
import 'package:senclaw_desktop/features/dock/todos_provider.dart';
import 'package:senclaw_desktop/theme/app_theme.dart';

class _FakeWs extends WsClient {
  _FakeWs() : super(const AppConfig(host: 'x', uiPort: 0, wsPort: 0));
  final _ec = StreamController<WsEvent>.broadcast();
  @override
  Stream<WsEvent> get events => _ec.stream;
  @override
  Stream<WsStatus> get statusStream => const Stream<WsStatus>.empty();
  @override
  void send(Map<String, dynamic> msg) {}
  @override
  void dispose() => _ec.close();
  void emit(WsEvent e) => _ec.add(e);
}

/// The dock's 320px minimum less its 12px side padding.
const _narrowestDock = 296.0;

const _todos = [
  AgentTodo('Install dependencies', 'completed', ''),
  AgentTodo('Define types and the useTodos hook', 'in_progress',
      'Defining types and the useTodos hook'),
  AgentTodo('Build the UI components', 'pending', ''),
  AgentTodo('Wire up App.tsx and run the build', 'pending', ''),
];

Future<void> _pumpGroup(WidgetTester tester, Widget child,
    {double width = 296, bool realFont = false}) async {
  tester.view.physicalSize = const Size(900, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light().copyWith(
        textTheme: realFont
            ? AppTheme.light().textTheme.apply(fontFamily: 'Roboto')
            : null),
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(width: width, child: SingleChildScrollView(child: child)),
      ),
    ),
  ));
  // The running row's spinner never settles — one frame is enough.
  await tester.pump();
}

Future<void> _loadRoboto() async {
  final root = Platform.environment['FLUTTER_ROOT'];
  final dir = Directory('$root/bin/cache/artifacts/material_fonts');
  final loader = FontLoader('Roboto');
  for (final w in ['Regular', 'Medium', 'Bold']) {
    final f = File('${dir.path}/Roboto-$w.ttf');
    if (f.existsSync()) {
      loader.addFont(Future.value(f.readAsBytesSync().buffer.asByteData()));
    }
  }
  await loader.load();
}

void main() {
  testWidgets('counts and labels say how many are running, waiting and done',
      (tester) async {
    await _pumpGroup(
        tester, const TodoGroup(title: 'Todo app', todos: _todos));

    expect(find.text('Todo app'), findsOneWidget);
    expect(find.text('1/4'), findsOneWidget);
    expect(find.text('1 Running'), findsOneWidget);
    expect(find.text('2 Waiting'), findsOneWidget);
    expect(find.text('1 Done'), findsOneWidget);
    // One trailing label per row.
    expect(find.text('Running'), findsOneWidget);
    expect(find.text('Waiting'), findsNWidgets(2));
    expect(find.text('Done'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('rows differ by icon, and the running one is -ing and bold',
      (tester) async {
    await _pumpGroup(
        tester, const TodoGroup(title: 'Todo app', todos: _todos));

    expect(find.byIcon(Icons.check_circle), findsOneWidget); // done
    expect(find.byIcon(Icons.radio_button_unchecked), findsNWidgets(2));
    // The spinner is the running row's icon and nothing else spins.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    // Running shows the agent's "-ing" wording instead of the imperative.
    expect(find.text('Defining types and the useTodos hook'), findsOneWidget);
    expect(find.text('Define types and the useTodos hook'), findsNothing);

    TextStyle styleOf(String text) =>
        tester.widget<Text>(find.text(text)).style!;
    expect(styleOf('Install dependencies').decoration,
        TextDecoration.lineThrough);
    expect(styleOf('Build the UI components').decoration, isNull);
    expect(styleOf('Defining types and the useTodos hook').fontWeight,
        FontWeight.w600);
  });

  testWidgets('a status it does not know reads as waiting', (tester) async {
    expect(todoPhase(const AgentTodo('x', 'blocked', '')), TodoPhase.waiting);
    expect(todoPhase(const AgentTodo('x', '', '')), TodoPhase.waiting);
  });

  testWidgets('with nothing running there is no spinner', (tester) async {
    await _pumpGroup(
        tester,
        const TodoGroup(title: 't', todos: [
          AgentTodo('a', 'completed', ''),
          AgentTodo('b', 'pending', ''),
        ]));
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('0 Running'), findsOneWidget);
  });

  group('at the narrowest dock', () {
    setUpAll(_loadRoboto);
    tearDown(() => L10n.global = const L10n('en'));

    for (final lang in ['en', 'vi']) {
      testWidgets('lays out in $lang without overflowing', (tester) async {
        L10n.global = L10n(lang);
        await _pumpGroup(
            tester,
            const TodoGroup(title: 'phân tích dự án, phát triển ứng dụng todo bằng React', todos: [
              AgentTodo(
                  'Cài đặt dependencies và tạo index.html, cấu trúc src/ cho dự án',
                  'in_progress',
                  'Đang cài đặt dependencies và tạo index.html, cấu trúc src/'),
              AgentTodo('Xây dựng các thành phần UI Todo bằng Ant Design',
                  'pending', ''),
              AgentTodo('Tích hợp vào App.tsx với theme Ant Design và build kiểm tra',
                  'completed', ''),
            ]),
            width: _narrowestDock,
            realFont: true);
        expect(tester.takeException(), isNull);
        // The labels really are in the language under test.
        expect(find.text(lang == 'vi' ? 'Đang chạy' : 'Running'), findsOneWidget);
        expect(find.text(lang == 'vi' ? 'Đang chờ' : 'Waiting'), findsOneWidget);
        expect(find.text(lang == 'vi' ? 'Xong' : 'Done'), findsOneWidget);
      });
    }
  });

  testWidgets('the Console titles a list by the chat, not its raw id',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({'chat:dockWidth': '760'});
    final sp = await SharedPreferences.getInstance();
    final ws = _FakeWs();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        prefsProvider.overrideWithValue(sp),
        wsClientProvider.overrideWithValue(ws),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(body: RightDock(jid: 'web:main:abc')),
      ),
    ));
    ws.emit({
      'type': 'groups',
      'groups': [
        {'jid': 'web:main:abc', 'name': 'Phân tích dự án'},
      ],
    });
    ws.emit({
      'type': 'agent:todos',
      'agentJid': 'web:main:abc',
      'todos': [
        {'content': 'One', 'status': 'in_progress', 'activeForm': 'Doing one'},
        {'content': 'Two', 'status': 'pending'},
      ],
    });
    // A chat with no group row falls back to the last segment of its jid.
    ws.emit({
      'type': 'agent:todos',
      'agentJid': 'web:main:zzz999',
      'todos': [
        {'content': 'Orphan', 'status': 'pending'},
      ],
    });
    await tester.pump();
    await tester.pump();

    expect(find.text('Phân tích dự án'), findsOneWidget);
    expect(find.text('zzz999'), findsOneWidget);
    expect(find.text('abc'), findsNothing);
    expect(find.text('Doing one'), findsOneWidget);
  });
}
