import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:senclaw_desktop/core/config/app_config.dart';
import 'package:senclaw_desktop/core/transport/api_client.dart';
import 'package:senclaw_desktop/core/transport/connection.dart';
import 'package:senclaw_desktop/features/settings/decision_skills.dart';
import 'package:senclaw_desktop/theme/app_theme.dart';

Map<String, dynamic> _view({String mode = 'shadow', bool preTrigger = true}) => {
      'skills': {'mode': mode},
      'preTriggerSkill': preTrigger,
      'timeoutMs': 1500,
      'candidates': 8,
      'stats': {'total': 2, 'same': 1, 'legacyLoads': 2, 'routeLoads': 1, 'loadsWithheld': 1, 'fallbacks': 0},
      'log': [
        {
          'id': 2,
          'at': 1790000000000,
          'prompt': 'chào bạn, bạn khoẻ không?',
          'legacyName': 'weather-xem',
          'legacyForce': true,
          'routeName': 'weather-xem',
          'routeForce': false,
          'reason': 'the decision engine picked another skill → hint',
          'enginePick': 'x-browse',
          'engineP': 0.77,
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
    return {...view, 'skills': body};
  }

  @override
  Future<dynamic> post(String path, {Object? body, Duration? timeout}) async {
    sent.add(('POST $path', body));
    return {
      'legacy': {'name': 'clock-timer', 'force': true},
      'route': {'name': 'clock-timer', 'force': true},
      'reason': 'the keyword match and the decision engine agree → load',
      'candidates': [
        {'name': 'clock-timer', 'score': 110, 'phraseHit': true},
        {'name': 'schedule', 'score': 10, 'phraseHit': false},
      ],
      'enginePick': 'clock-timer',
      'engineP': 0.79,
      'model': 'multilingual',
      'latencyMs': 74.0,
      'fallback': null,
    };
  }

  @override
  Future<dynamic> patch(String path, {Object? body}) async => {};
  @override
  Future<dynamic> delete(String path, {Object? body}) async => {};
}

Future<_FakeApi> _pump(WidgetTester tester, Map<String, dynamic> view) async {
  tester.view.physicalSize = const Size(1400, 2000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final api = _FakeApi(view);
  await tester.pumpWidget(ProviderScope(
    overrides: [apiClientProvider.overrideWithValue(api)],
    child: MaterialApp(
      theme: AppTheme.dark(),
      home: const Scaffold(body: SingleChildScrollView(child: DecisionSkillsCard())),
    ),
  ));
  await tester.pumpAndSettle();
  return api;
}

void main() {
  testWidgets('each turn shows what the old way did next to the new one', (tester) async {
    await _pump(tester, _view());
    expect(find.text('chào bạn, bạn khoẻ không?'), findsOneWidget);
    expect(find.text('load · weather-xem'), findsOneWidget, reason: 'the old way loaded it');
    expect(find.text('hint · weather-xem'), findsOneWidget, reason: 'the new way only hints');
    expect(find.textContaining('x-browse'), findsOneWidget);
    expect(find.text('loads held back 1'), findsOneWidget);
  });

  testWidgets('a note says nothing loads while pre-trigger skill is off', (tester) async {
    await _pump(tester, _view(preTrigger: false));
    expect(find.textContaining('both ways only hint'), findsOneWidget);
  });

  testWidgets('saving sends only the mode, and a try shows both decisions', (tester) async {
    final api = await _pump(tester, _view());
    await tester.tap(find.text('On'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(api.sent.first.$1, 'PUT /api/decision/skills');
    expect(api.sent.first.$2, {'mode': 'on'});

    await tester.tap(find.widgetWithText(OutlinedButton, 'Pick a skill'));
    await tester.pumpAndSettle();
    expect(find.text('load · clock-timer'), findsNWidgets(2));
    expect(find.text('clock-timer 110'), findsOneWidget);
    expect(find.textContaining('agree → load'), findsOneWidget);
  });
}
