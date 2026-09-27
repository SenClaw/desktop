import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:senclaw_desktop/core/config/app_config.dart';
import 'package:senclaw_desktop/core/transport/api_client.dart';
import 'package:senclaw_desktop/core/transport/connection.dart';
import 'package:senclaw_desktop/features/settings/decision_gate.dart';
import 'package:senclaw_desktop/theme/app_theme.dart';

Map<String, dynamic> _view({String mode = 'shadow', int refused = 0}) => {
      'gate': {'mode': mode, 'approveAt': 0.9, 'questions': 'auto'},
      'backend': 'local',
      'questionSet': 'laya',
      'timeoutSecs': 8,
      'samples': ['git status', 'rm -rf node_modules'],
      'stats': {
        'total': 3,
        'wouldAllow': 2,
        'applied': 0,
        'risky': 1,
        'errors': 0,
        'answered': 3,
        'allowAgreed': 2 - refused,
        'allowRefused': refused,
        'askApproved': 0,
        'askRefused': 1,
      },
      'log': [
        {
          'id': 3,
          'at': 1790000000000,
          'command': 'bun test src/utils/date.test.ts',
          'outcome': 'allow',
          'applied': false,
          'stage': 'engine',
          'reason': 'reversible=0.97 ≥ 0.9',
          'p': 0.97,
          'choice': 'test',
          'human': 'agree',
        },
        {
          'id': 2,
          'at': 1790000000000,
          'command': 'rm -rf node_modules',
          'outcome': 'ask',
          'applied': false,
          'stage': 'risky',
          'reason': 'matches the list of dangerous commands: `rm -rf node_modules`',
          'human': 'refuse',
        },
      ],
    };

class _FakeApi implements ApiClient {
  _FakeApi(this.view);
  final Map<String, dynamic> view;
  final sent = <(String, Object?)>[];

  @override
  void updateConfig(AppConfig config) {}
  @override
  void dispose() {}

  @override
  Future<dynamic> get(String path, {Map<String, dynamic>? query, Duration? timeout}) async => view;

  @override
  Future<dynamic> put(String path, {Object? body}) async {
    sent.add(('PUT $path', body));
    return {...view, 'gate': body, 'ok': true};
  }

  @override
  Future<dynamic> post(String path, {Object? body, Duration? timeout}) async {
    sent.add(('POST $path', body));
    final commands = ((body as Map)['commands'] as List).cast<String>();
    return {
      'verdicts': [
        for (final c in commands)
          c.startsWith('rm')
              ? {'command': c, 'outcome': 'ask', 'stage': 'risky', 'reason': 'matches the list of dangerous commands', 'checks': []}
              : {
                  'command': c,
                  'outcome': 'allow',
                  'stage': 'engine',
                  'reason': 'reversible=0.99 ≥ 0.9',
                  'choice': 'read',
                  'checks': [
                    {'name': 'reversible', 'p': 0.99, 'how': 'P(read) + P(test) + P(edit)'}
                  ],
                  'latencyMs': 41.0,
                  'model': 'multilingual',
                  'state': 'Command: $c',
                  'asked': {},
                  'answers': {},
                },
      ],
    };
  }

  @override
  Future<dynamic> patch(String path, {Object? body}) async => {};
  @override
  Future<dynamic> delete(String path, {Object? body}) async => {};
}

Future<_FakeApi> _pump(WidgetTester tester, Map<String, dynamic> view) async {
  tester.view.physicalSize = const Size(1400, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final api = _FakeApi(view);
  await tester.pumpWidget(ProviderScope(
    overrides: [apiClientProvider.overrideWithValue(api)],
    child: MaterialApp(
      theme: AppTheme.dark(),
      home: const Scaffold(body: SingleChildScrollView(child: DecisionGateCard())),
    ),
  ));
  await tester.pumpAndSettle();
  return api;
}

void main() {
  testWidgets('shows the log with what the gate said and what you answered', (tester) async {
    await _pump(tester, _view());
    // In the log, and as the try box's starting text.
    expect(find.text('bun test src/utils/date.test.ts'), findsNWidgets(2));
    expect(find.text('would run'), findsOneWidget);
    expect(find.text('danger list'), findsOneWidget);
    expect(find.text('you approved'), findsOneWidget);
    expect(find.text('you refused'), findsOneWidget);
    expect(find.textContaining('you refused 0'), findsOneWidget);
  });

  testWidgets('a refused allow is called out before anyone turns the gate on', (tester) async {
    await _pump(tester, _view(refused: 1));
    expect(find.textContaining('were refused by you'), findsOneWidget);
  });

  testWidgets('switching the mode saves only the gate', (tester) async {
    final api = await _pump(tester, _view(mode: 'off'));
    await tester.tap(find.text('On'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(api.sent.single.$1, 'PUT /api/decision/gate');
    expect(api.sent.single.$2, {'mode': 'on', 'approveAt': 0.9, 'questions': 'auto'});
  });

  testWidgets('trying commands shows each verdict without saving', (tester) async {
    final api = await _pump(tester, _view());
    await tester.tap(find.widgetWithText(OutlinedButton, 'Check'));
    await tester.pumpAndSettle();
    expect(find.textContaining('reversible = 0.99'), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Run the 2 sample commands'));
    await tester.pumpAndSettle();
    expect(find.text('1 would run · 1 held by the danger list · 0 errors'), findsOneWidget);
    expect(api.sent.where((c) => c.$1.startsWith('PUT')), isEmpty);
  });
}
