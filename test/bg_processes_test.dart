// Processes an agent left running (desktop): the strip above the composer, the
// panel on the Background screen, and what Stop does. What must hold:
//
//  1. The strip shows THIS chat's running processes and only says how many
//     are running elsewhere — a stopped one or another chat's never takes a
//     row, so Stop cannot be pressed on the wrong chat's server.
//  2. Stop posts to the daemon and the list is read again (no optimistic
//     "gone": a refused stop must still show the process).
//  3. The panel hides finished entries until asked, and a finished one can be
//     dismissed, not stopped.
//  4. Vietnamese labels exist for every string and fit.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:senclaw_desktop/core/config/app_config.dart';
import 'package:senclaw_desktop/core/i18n/l10n.dart';
import 'package:senclaw_desktop/core/transport/api_client.dart';
import 'package:senclaw_desktop/core/transport/connection.dart';
import 'package:senclaw_desktop/features/background/bg_processes.dart';
import 'package:senclaw_desktop/theme/app_theme.dart';

Map<String, dynamic> _task(
  String id, {
  required String chat,
  String status = 'running',
  String description = '',
  String command = 'python3 -m http.server 5173',
  List<int> ports = const [],
}) =>
    {
      'id': id,
      'chatJid': chat,
      'description': description,
      'command': command,
      'cwd': '/tmp/x',
      'status': status,
      'origin': 'adopted',
      'isolation': 'seatbelt',
      'pid': 4242,
      'pids': [4242, 4243],
      'ports': ports,
      'uptimeSecs': 75,
      'exitCode': status == 'running' ? null : 143,
    };

/// Serves `/api/bg-tasks` from a mutable list and records every write.
class _FakeApi implements ApiClient {
  _FakeApi(this.tasks);
  final List<Map<String, dynamic>> tasks;
  final calls = <String>[];
  bool refuseStop = false;

  @override
  void updateConfig(AppConfig config) {}

  @override
  void dispose() {}

  @override
  Future<dynamic> get(String path,
      {Map<String, dynamic>? query, Duration? timeout}) async {
    calls.add('GET $path ${jsonEncode(query ?? {})}');
    if (path == '/api/bg-tasks') return {'tasks': tasks};
    if (path.startsWith('/api/bg-tasks/')) {
      return {
        'task': {...tasks.firstWhere((t) => path.endsWith(t['id'] as String)), 'output': 'Serving HTTP on port 5173'}
      };
    }
    return {};
  }

  @override
  Future<dynamic> post(String path, {Object? body, Duration? timeout}) async {
    calls.add('POST $path');
    final stop = RegExp(r'^/api/bg-tasks/([^/]+)/stop$').firstMatch(path);
    if (stop != null) {
      if (refuseStop) throw ApiException(409, 'did not exit; try again');
      tasks.firstWhere((t) => t['id'] == stop.group(1))['status'] = 'stopped';
    }
    if (path == '/api/bg-tasks/stop-all') {
      for (final t in tasks) {
        if (t['status'] == 'running') t['status'] = 'stopped';
      }
    }
    return {'success': true};
  }

  @override
  Future<dynamic> put(String path, {Object? body}) async => {};

  @override
  Future<dynamic> patch(String path, {Object? body}) async => {};

  @override
  Future<dynamic> delete(String path, {Object? body}) async {
    calls.add('DELETE $path');
    tasks.removeWhere((t) => path.endsWith(t['id'] as String));
    return {'success': true};
  }
}

Future<void> _pump(WidgetTester tester, _FakeApi api, Widget child,
    {String lang = 'en'}) async {
  tester.view.physicalSize = const Size(1200, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  addTearDown(() => L10n.global = const L10n('en'));
  await tester.pumpWidget(ProviderScope(
    overrides: [apiClientProvider.overrideWithValue(api)],
    child: MaterialApp(
      locale: Locale(lang),
      supportedLocales: const [Locale('en'), Locale('vi')],
      localizationsDelegates: const [
        L10nDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: AppTheme.light(),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  ));
  await tester.pumpAndSettle();
}

/// Dispose the tree so the provider's poll timer is cancelled before the test ends.
Future<void> _end(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the strip shows this chat\'s running processes and counts the others',
      (tester) async {
    final api = _FakeApi([
      _task('bash-00001', chat: 'web:a', description: 'Start the dev server', ports: [5173]),
      _task('bash-00002', chat: 'web:b'),
      _task('bash-00003', chat: 'web:a', status: 'stopped', description: 'old server'),
    ]);
    await _pump(tester, api, const BgProcessStrip(jid: 'web:a'));

    expect(find.text('Start the dev server'), findsOneWidget);
    expect(find.text(':5173'), findsOneWidget, reason: 'the port is a link');
    expect(find.text('old server'), findsNothing, reason: 'finished ones are not in the strip');
    expect(find.text('1 more running in other chats'), findsOneWidget);
    expect(find.text('Stop'), findsOneWidget, reason: 'only this chat\'s process has a Stop');
    expect(tester.takeException(), isNull);
    await _end(tester);
  });

  testWidgets('nothing running anywhere draws nothing', (tester) async {
    final api = _FakeApi([_task('bash-00001', chat: 'web:a', status: 'stopped')]);
    await _pump(tester, api, const BgProcessStrip(jid: 'web:a'));
    expect(find.byType(BgProcessRow), findsNothing);
    expect(find.text('Manage'), findsNothing);
    await _end(tester);
  });

  testWidgets('Stop posts to the daemon and reads the list again', (tester) async {
    final api = _FakeApi([_task('bash-00001', chat: 'web:a', description: 'dev server')]);
    await _pump(tester, api, const BgProcessStrip(jid: 'web:a'));
    final readsBefore = api.calls.where((c) => c.startsWith('GET /api/bg-tasks')).length;

    await tester.tap(find.text('Stop'));
    await tester.pumpAndSettle();

    expect(api.calls, contains('POST /api/bg-tasks/bash-00001/stop'));
    expect(api.calls.where((c) => c.startsWith('GET /api/bg-tasks')).length,
        greaterThan(readsBefore));
    expect(find.text('dev server'), findsNothing, reason: 'it is no longer running');
    await _end(tester);
  });

  testWidgets('a refused stop leaves the process on screen and says why', (tester) async {
    final api = _FakeApi([_task('bash-00001', chat: 'web:a', description: 'stubborn')])
      ..refuseStop = true;
    await _pump(tester, api, const BgProcessStrip(jid: 'web:a'));
    await tester.tap(find.text('Stop'));
    await tester.pumpAndSettle();
    expect(find.text('stubborn'), findsOneWidget);
    await _end(tester);
  });

  testWidgets('the log opens in place', (tester) async {
    final api = _FakeApi([_task('bash-00001', chat: 'web:a', description: 'dev server')]);
    await _pump(tester, api, const BgProcessStrip(jid: 'web:a'));
    await tester.tap(find.text('Log'));
    await tester.pumpAndSettle();
    expect(find.text('Serving HTTP on port 5173'), findsOneWidget);
    await _end(tester);
  });

  testWidgets('the panel hides finished entries until asked; a finished one is dismissed, not stopped',
      (tester) async {
    final api = _FakeApi([
      _task('bash-00001', chat: 'web:a', description: 'one'),
      _task('bash-00002', chat: 'web:b', description: 'two'),
      _task('bash-00003', chat: 'web:a', status: 'stopped', description: 'gone'),
    ]);
    await _pump(tester, api, const BgProcessesPanel());

    expect(find.text('Processes (2 running)'), findsOneWidget);
    expect(find.text('gone'), findsNothing);
    expect(find.text('Stop all'), findsOneWidget, reason: 'more than one is running');

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(find.text('gone'), findsOneWidget);
    expect(find.byTooltip('Remove from the list'), findsOneWidget);

    await tester.tap(find.byTooltip('Remove from the list'));
    await tester.pumpAndSettle();
    expect(api.calls, contains('DELETE /api/bg-tasks/bash-00003'));
    expect(find.text('gone'), findsNothing);

    await tester.tap(find.text('Stop all'));
    await tester.pumpAndSettle();
    expect(api.calls, contains('POST /api/bg-tasks/stop-all'));
    expect(find.text('Processes (0 running)'), findsOneWidget);
    // They moved to "finished": still listed while that switch is on, gone when off.
    expect(find.text('one'), findsOneWidget);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(find.text('one'), findsNothing);
    expect(find.text('Nothing is running in the background'), findsOneWidget);
    await _end(tester);
  });

  testWidgets('every label is translated and nothing overflows in Vietnamese',
      (tester) async {
    final api = _FakeApi([
      _task('bash-00001', chat: 'web:a', description: 'Khởi chạy máy chủ dev', ports: [5173]),
      _task('bash-00002', chat: 'web:b'),
    ]);
    await _pump(tester, api, const BgProcessStrip(jid: 'web:a'), lang: 'vi');
    expect(find.text('Dừng'), findsOneWidget);
    expect(find.text('Nhật ký'), findsOneWidget);
    expect(find.text('1 tiến trình khác đang chạy ở các chat khác'), findsOneWidget);
    expect(find.text('Quản lý'), findsOneWidget);
    await _end(tester);

    await _pump(tester, api, const BgProcessesPanel(), lang: 'vi');
    expect(find.text('Tiến trình (2 đang chạy)'), findsOneWidget);
    expect(find.text('Hiện mục đã kết thúc'), findsOneWidget);
    expect(find.text('Dừng tất cả'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _end(tester);
  });

  test('uptime and command helpers', () {
    expect(bgUptime(42), '42s');
    expect(bgUptime(185), '3m 05s');
    expect(bgUptime(3720), '1h 02m');
    expect(bgCommandLine('\n  nohup npx vite &\nsleep 2', max: 40), 'nohup npx vite &');
    expect(bgCommandLine('x' * 100, max: 10).length, 10);
  });
}
