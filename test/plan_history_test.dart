// Plan history: what the daemon really sends for `plan:list` / `plan:get`
// (`approval` as a word, `createdAt` as an RFC 3339 string) must reach the
// dialog. The first version read `status` and cast `createdAt` to a number, so
// the cast threw inside the WS listener and the list never loaded — the dialog
// always said "No plans yet" while the daemon held the plans.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:senclaw_desktop/core/config/app_config.dart';
import 'package:senclaw_desktop/core/transport/connection.dart';
import 'package:senclaw_desktop/core/transport/ws_client.dart';
import 'package:senclaw_desktop/features/chat/plan_history_dialog.dart';
import 'package:senclaw_desktop/features/chat/plan_history_provider.dart';
import 'package:senclaw_desktop/theme/app_theme.dart';

/// A WsClient whose event stream the test drives and whose sends it records.
class _FakeWs extends WsClient {
  _FakeWs() : super(const AppConfig(host: 'x', uiPort: 0, wsPort: 0));
  final _ec = StreamController<WsEvent>.broadcast();
  final sent = <Map<String, dynamic>>[];

  /// Plays the daemon: called with every message the client sends.
  void Function(Map<String, dynamic> msg)? onSend;
  @override
  Stream<WsEvent> get events => _ec.stream;
  @override
  Stream<WsStatus> get statusStream => const Stream<WsStatus>.empty();
  @override
  void send(Map<String, dynamic> msg) {
    sent.add(msg);
    onSend?.call(msg);
  }
  @override
  void dispose() => _ec.close();
  void emit(WsEvent e) => _ec.add(e);
}

/// One row exactly as `handle_plan_list` serializes it.
Map<String, dynamic> _row(String id,
        {String title = 'Kế hoạch phát triển',
        String approval = 'startEditing',
        String createdAt = '2026-10-23T20:58:16.578266+00:00'}) =>
    {
      'id': id,
      'chatJid': 'web:main:abc',
      'agentId': 'main',
      'title': title,
      'filePath': '/Users/x/.senclaw/plans/$id.md',
      'approval': approval,
      'createdAt': createdAt,
      'approvedAt': '2026-10-23T20:58:21.568349+00:00',
    };

({ProviderContainer c, _FakeWs ws}) _setup() {
  final ws = _FakeWs();
  final c = ProviderContainer(overrides: [wsClientProvider.overrideWithValue(ws)]);
  addTearDown(c.dispose);
  addTearDown(ws.dispose);
  c.read(planHistoryProvider); // subscribe, as the dialog's first read does
  return (c: c, ws: ws);
}

Future<void> _tick() => Future<void>.delayed(Duration.zero);

void main() {
  test("a daemon plans:list reaches the state with approval and date",
      () async {
    final s = _setup();
    s.ws.emit({
      'type': 'plans:list',
      'groupJid': 'web:main:abc',
      'plans': [_row('p1'), _row('p2', approval: 'pending')],
    });
    await _tick();

    final list = s.c.read(planHistoryProvider).forJid('web:main:abc');
    expect(list.map((p) => p.id), ['p1', 'p2']);
    expect(list[0].approval, 'startEditing');
    expect(list[1].approval, 'pending');
    expect(list[0].createdAt, DateTime.utc(2026, 10, 23, 20, 58, 16, 578, 266));
  });

  test('one malformed row is skipped, not the whole list', () async {
    final s = _setup();
    s.ws.emit({
      'type': 'plans:list',
      'groupJid': 'web:main:abc',
      'plans': [
        _row('p1'),
        {'id': 'bad', 'createdAt': ['not', 'a', 'date']},
        _row('p3'),
      ],
    });
    await _tick();

    final ids =
        s.c.read(planHistoryProvider).forJid('web:main:abc').map((p) => p.id);
    expect(ids, containsAll(['p1', 'p3']));
  });

  test("another chat's list never replaces this chat's", () async {
    final s = _setup();
    s.ws.emit({
      'type': 'plans:list',
      'groupJid': 'web:main:abc',
      'plans': [_row('p1')],
    });
    s.ws.emit({'type': 'plans:list', 'groupJid': 'web:main:other', 'plans': []});
    await _tick();

    final st = s.c.read(planHistoryProvider);
    expect(st.forJid('web:main:abc').map((p) => p.id), ['p1']);
    expect(st.forJid('web:main:other'), isEmpty);
  });

  test('plans:get stores the markdown under its id', () async {
    final s = _setup();
    s.ws.emit({
      'type': 'plans:get',
      'plan': {..._row('p1'), 'contentMd': '# Plan\n\n- step 1'},
    });
    await _tick();

    expect(s.c.read(planHistoryProvider).contentById['p1'], '# Plan\n\n- step 1');
  });

  test('a plan decision refreshes that chat\'s list', () async {
    final s = _setup();
    s.ws.emit({
      'type': 'plan:exit:response',
      'groupJid': 'web:main:abc',
      'selected': 'startEditing',
    });
    await _tick();

    expect(s.ws.sent,
        anyElement(equals({'type': 'plan:list', 'groupJid': 'web:main:abc'})));
  });

  group('the dialog', () {
    Future<_FakeWs> open(WidgetTester tester,
        {required bool daemonAnswers}) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final ws = _FakeWs();
      if (daemonAnswers) {
        // The daemon answers a request on a later turn, as a socket would.
        ws.onSend = (m) => Future<void>.microtask(() {
              if (m['type'] == 'plan:list') {
                ws.emit({
                  'type': 'plans:list',
                  'groupJid': m['groupJid'],
                  'plans': [
                    _row('p1', title: 'Kế hoạch Todo app'),
                    _row('p2', title: 'Plan B', approval: 'pending'),
                  ],
                });
              } else if (m['type'] == 'plan:get') {
                ws.emit({
                  'type': 'plans:get',
                  'plan': {..._row('${m['id']}'), 'contentMd': 'Step one body'},
                });
              }
            });
      }
      await tester.pumpWidget(ProviderScope(
        overrides: [wsClientProvider.overrideWithValue(ws)],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: PlanHistoryDialog(jid: 'web:main:abc')),
        ),
      ));
      return ws;
    }

    testWidgets('lists the plans the daemon holds, with their decision',
        (tester) async {
      await open(tester, daemonAnswers: true);
      await tester.pump(); // request → answer
      await tester.pump();

      expect(find.text('No plans yet'), findsNothing);
      expect(find.text('Kế hoạch Todo app'), findsOneWidget);
      expect(find.text('Plan B'), findsOneWidget);
      expect(find.text('Approved'), findsOneWidget);
      expect(find.text('Awaiting approval'), findsOneWidget);
      // The date is shown (local time, minutes), not the raw RFC 3339 string.
      expect(find.textContaining('2026-10-2'), findsNWidgets(2));
      expect(find.textContaining('T20:58'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('opening a plan fetches and shows its content',
        (tester) async {
      final ws = await open(tester, daemonAnswers: true);
      await tester.pump();
      await tester.pump();

      await tester.tap(find.text('Plan B'));
      await tester.pump();
      await tester.pump();

      expect(ws.sent, anyElement(equals({'type': 'plan:get', 'id': 'p2'})));
      expect(find.textContaining('Step one body', findRichText: true),
          findsOneWidget);
    });

    testWidgets('waits for the daemon instead of claiming there are no plans',
        (tester) async {
      await open(tester, daemonAnswers: false);
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('No plans yet'), findsNothing);

      // Still nothing after the timeout: say so, and offer another try.
      await tester.pump(const Duration(seconds: 8));
      expect(find.text('Could not load plans'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });
  });
}
