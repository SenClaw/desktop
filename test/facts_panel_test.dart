// Facts (desktop). What the panel exists to do against a faked daemon: list the
// agents that have facts and one agent's facts with their dates and evidence,
// search and show replaced facts through the same query the web page sends,
// forget one fact under the agent that owns it, and say so when the fact store
// has not started. `spanLabel` reads a stored span at the precision it was
// said at, in UTC.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:senclaw_desktop/core/config/app_config.dart';
import 'package:senclaw_desktop/core/transport/api_client.dart';
import 'package:senclaw_desktop/core/transport/connection.dart';
import 'package:senclaw_desktop/features/cognitive/facts_panel.dart';
import 'package:senclaw_desktop/theme/app_theme.dart';

int _utc(int y, int m, int d) => DateTime.utc(y, m, d).millisecondsSinceEpoch ~/ 1000;

class _FakeApi implements ApiClient {
  _FakeApi({this.notStarted = false});
  final bool notStarted;
  final calls = <String>[];
  var forgotten = <String>{};

  Map<String, dynamic> _fact(String id, String text,
          {int? start, int? end, int proof = 1, String? replacedBy, String kind = 'world'}) =>
      {
        'id': id,
        'kind': kind,
        'text': text,
        'occurredStart': start,
        'occurredEnd': end,
        'mentionedAt': 1790000000,
        'entities': ['emily'],
        'proofCount': proof,
        'supersededBy': replacedBy,
        'origin': text.contains('Hue') ? 'web:a' : '',
      };

  @override
  void updateConfig(AppConfig config) {}

  @override
  void dispose() {}

  @override
  Future<dynamic> get(String path, {Map<String, dynamic>? query, Duration? timeout}) async {
    calls.add('GET $path${query == null ? '' : ' $query'}');
    if (notStarted) throw ApiException(503, 'fact_store_not_started');
    if (path == '/api/memory/facts/banks') {
      return {
        'banks': [
          {'bank': 'main', 'current': 2, 'replaced': 1, 'lastMentionedAt': 1790000000},
          {'bank': 'ssh', 'current': 1, 'replaced': 0, 'lastMentionedAt': 1780000000},
        ]
      };
    }
    if (path == '/api/memory/facts') {
      if (query?['bank'] == 'ssh') {
        return {'facts': [_fact('s1', 'The jump host is bastion-2')]};
      }
      final history = query?['history'] == 'true';
      return {
        'facts': [
          _fact('f1', 'Emily moved to Hue', start: _utc(2026, 3, 1), end: _utc(2026, 4, 1), proof: 3),
          _fact('f2', 'Sen prefers dark mode'),
          if (history) _fact('f0', 'Sen prefers light mode', replacedBy: 'f2'),
        ].where((f) => !forgotten.contains(f['id'])).toList()
      };
    }
    return {};
  }

  @override
  Future<dynamic> post(String path, {Object? body, Duration? timeout}) async => {'ok': true};

  @override
  Future<dynamic> put(String path, {Object? body}) async => {'ok': true};

  @override
  Future<dynamic> patch(String path, {Object? body}) async => {'ok': true};

  @override
  Future<dynamic> delete(String path, {Object? body}) async {
    calls.add('DELETE $path');
    final id = path.split('/').last.split('?').first;
    forgotten = {...forgotten, id};
    return {'deleted': id};
  }
}

Future<_FakeApi> _pump(WidgetTester tester, {bool notStarted = false}) async {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final api = _FakeApi(notStarted: notStarted);
  await tester.pumpWidget(ProviderScope(
    overrides: [apiClientProvider.overrideWithValue(api)],
    child: MaterialApp(theme: AppTheme.light(), home: const Scaffold(body: FactsPanel())),
  ));
  await tester.pumpAndSettle();
  return api;
}

void main() {
  group('spanLabel', () {
    test('reads a span at the precision it was said at', () {
      expect(spanLabel(_utc(2026, 3, 9), _utc(2026, 3, 10)), '2026-03-09');
      expect(spanLabel(_utc(2026, 3, 1), _utc(2026, 4, 1)), '2026-03');
      expect(spanLabel(_utc(2026, 1, 1), _utc(2027, 1, 1)), '2026');
      // A month that ends in the next year.
      expect(spanLabel(_utc(2026, 12, 1), _utc(2027, 1, 1)), '2026-12');
      // Several days is not a whole month.
      expect(spanLabel(_utc(2026, 3, 1), _utc(2026, 3, 15)), '2026-03-01');
    });

    test('an undated fact reads as the day it was said', () {
      final f = MemoryFact.fromJson({
        'id': 'x',
        'text': 't',
        'mentionedAt': 1790000000,
        'occurredStart': null,
        'occurredEnd': null,
      });
      final w = factWhen(f);
      expect(w.dated, isFalse);
      expect(w.label, matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
    });
  });

  testWidgets('lists the most recent agent first with dates, evidence and replaced count', (tester) async {
    final api = await _pump(tester);
    expect(find.text('Emily moved to Hue'), findsOneWidget);
    expect(find.text('Sen prefers dark mode'), findsOneWidget);
    expect(find.text('2026-03'), findsOneWidget); // the month it happened
    expect(find.text('×3'), findsOneWidget); // said three times
    expect(find.text('web:a'), findsOneWidget); // the chat it was said in
    expect(find.textContaining('main · 2 (+1)'), findsOneWidget);
    expect(api.calls, contains('GET /api/memory/facts/banks'));
    // The listing is scoped to the agent.
    expect(api.calls.any((c) => c.startsWith('GET /api/memory/facts ') && c.contains('bank: main')), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('show replaced asks for history and strikes the replaced fact through', (tester) async {
    final api = await _pump(tester);
    expect(find.text('Sen prefers light mode'), findsNothing);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(find.text('Sen prefers light mode'), findsOneWidget);
    expect(find.text('replaced'), findsOneWidget);
    expect(api.calls.any((c) => c.contains('history: true')), isTrue);
  });

  testWidgets('forgetting a fact confirms first, then deletes it under its own agent', (tester) async {
    final api = await _pump(tester);
    await tester.tap(find.byTooltip('Forget').first);
    await tester.pumpAndSettle();
    expect(find.text('Forget this fact?'), findsOneWidget);
    // Declining deletes nothing.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(api.calls.where((c) => c.startsWith('DELETE')), isEmpty);

    await tester.tap(find.byTooltip('Forget').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Forget'));
    await tester.pumpAndSettle();
    expect(api.calls, contains('DELETE /api/memory/facts/f1?bank=main'));
    expect(find.text('Emily moved to Hue'), findsNothing);
    expect(find.text('Sen prefers dark mode'), findsOneWidget);
  });

  testWidgets('searching sends the words and switching agent starts a fresh listing', (tester) async {
    final api = await _pump(tester);
    await tester.enterText(find.byType(TextField), 'emily');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(api.calls.any((c) => c.contains('q: emily')), isTrue);

    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('ssh · 1').last);
    await tester.pumpAndSettle();
    expect(find.text('The jump host is bastion-2'), findsOneWidget);
    // The search belongs to the agent it was typed under.
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, isEmpty);
  });

  testWidgets('says so when the fact store has not started', (tester) async {
    await _pump(tester, notStarted: true);
    expect(find.textContaining('has not started yet'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
