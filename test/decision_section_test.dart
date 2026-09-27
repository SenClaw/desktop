import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:senclaw_desktop/core/config/app_config.dart';
import 'package:senclaw_desktop/core/i18n/l10n.dart';
import 'package:senclaw_desktop/core/transport/api_client.dart';
import 'package:senclaw_desktop/core/transport/connection.dart';
import 'package:senclaw_desktop/features/settings/decision_models.dart';
import 'package:senclaw_desktop/features/settings/decision_section.dart';
import 'package:senclaw_desktop/theme/app_theme.dart';

Map<String, dynamic> _models({String backend = 'local'}) => {
      'compiled': true,
      'root': '/models/laya',
      'backend': backend,
      'local': {'defaultModel': 'multilingual', 'threads': 2, 'autoLoad': true, 'idleUnloadMinutes': 15},
      'models': [
        {
          'id': 'multilingual',
          'label': 'Laya Multilingual',
          'description': 'mmBERT',
          'kind': 'multilingual',
          'catalog': true,
          'source': {'type': 'folder', 'path': '/src/multilingual'},
          'approx_size_mb': 1300,
          'size_bytes': 1320000000,
          'installed': true,
          'path': '/models/laya/multilingual',
          'job': null,
          'loading': false,
          'loaded': {
            'kind': 'multilingual',
            'load_ms': 2480,
            'loaded_at': 0,
            'batch': 'dynamic',
            'act_output': 'act_logits',
            'max_len': 512,
            'head_max_len': 256,
            'threads': 2,
            'asks': 3,
            'idle_secs': 300,
            'on_demand': true,
          },
        },
        {
          'id': 'english',
          'label': 'Laya English',
          'description': 'ModernBERT',
          'kind': 'english',
          'catalog': true,
          'source': null,
          'approx_size_mb': 1600,
          'size_bytes': 1580000000,
          'installed': true,
          'path': '/models/laya/english',
          'job': null,
          'loading': false,
          'loaded': null,
        },
      ],
    };

Map<String, dynamic> _settingsView({bool hasKey = false, String backend = 'local'}) => {
      'compiled': true,
      'settings': {
        'backend': backend,
        'local': {'defaultModel': 'multilingual', 'threads': 2, 'autoLoad': true, 'idleUnloadMinutes': 15},
        'online': {
          'provider': 'typesafe',
          'url': '',
          'apiKey': '',
          'hasApiKey': hasKey,
          'model': '',
          'accountId': '',
          'timeoutSecs': 30,
        },
      },
      'providers': ['typesafe', 'cloudflare', 'custom'],
      'defaults': {
        'threads': 8,
        'maxThreads': 64,
        'idleUnloadMinutes': 15,
        'typesafeUrl': 'https://api.typesafe.ai/v1/systemone',
        'typesafeModel': 'jev-1.13.0',
        'cloudflareModel': 'typesafe/jev',
      },
    };

/// Serves the three decision endpoints and records what was sent.
class _FakeApi implements ApiClient {
  _FakeApi({this.hasKey = false});
  final bool hasKey;
  final calls = <(String, Object?)>[];

  @override
  void updateConfig(AppConfig config) {}

  @override
  void dispose() {}

  @override
  Future<dynamic> get(String path, {Map<String, dynamic>? query, Duration? timeout}) async {
    calls.add(('GET $path', null));
    return switch (path) {
      '/api/decision/models' => _models(),
      '/api/decision/settings' => _settingsView(hasKey: hasKey),
      _ => <String, dynamic>{},
    };
  }

  @override
  Future<dynamic> put(String path, {Object? body}) async {
    calls.add(('PUT $path', body));
    final sent = (body as Map).cast<String, dynamic>();
    final view = _settingsView(hasKey: hasKey && sent['clearApiKey'] != true);
    (view['settings'] as Map)['backend'] = sent['backend'];
    return {...view, 'ok': true};
  }

  @override
  Future<dynamic> post(String path, {Object? body, Duration? timeout}) async {
    calls.add(('POST $path', body));
    if (path == '/api/decision/ask') {
      // An online backend's answers, passed through as it sent them: one
      // without a confidence, one in a shape none of the three types match.
      return {
        'model': 'jev-1.13.0',
        'engine': 'online:typesafe',
        'answers': {
          'is_spam': {'type': 'noul', 'noul': 0.9},
          'extra': {'verdict': 'odd'},
        },
        'usage': {'input_tokens': 42, 'output_tokens': 0},
        'latency_ms': 180.0,
        'runs': 1,
        'routing': {'model': 'jev-1.13.0', 'reason': 'online backend (typesafe)'},
      };
    }
    return {'ok': true};
  }

  @override
  Future<dynamic> patch(String path, {Object? body}) async => {'ok': true};

  @override
  Future<dynamic> delete(String path, {Object? body}) async {
    calls.add(('DELETE $path', body));
    return {'ok': true};
  }

  Map<String, dynamic> lastBody(String call) =>
      (calls.lastWhere((c) => c.$1 == call).$2 as Map).cast<String, dynamic>();
}

Future<_FakeApi> _pump(WidgetTester tester, {bool hasKey = false, String lang = 'en'}) async {
  // Tall enough that the lazy settings list builds every card.
  tester.view.physicalSize = const Size(1400, 6000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final api = _FakeApi(hasKey: hasKey);
  await tester.pumpWidget(ProviderScope(
    overrides: [apiClientProvider.overrideWithValue(api)],
    child: MaterialApp(
      theme: AppTheme.dark(),
      locale: Locale(lang),
      supportedLocales: const [Locale('en'), Locale('vi')],
      localizationsDelegates: const [
        L10nDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const Scaffold(body: DecisionSection()),
    ),
  ));
  await tester.pumpAndSettle();
  return api;
}

void main() {
  testWidgets('shows how it runs, the default model and a hot-loaded row', (tester) async {
    await _pump(tester);

    expect(find.text('How it runs'), findsOneWidget);
    expect(find.text('On this machine — Laya'), findsWidgets);
    expect(find.text('Online — Jev API'), findsWidgets);
    expect(find.text('default'), findsOneWidget, reason: 'the default model is marked');
    expect(find.text('on demand'), findsOneWidget, reason: 'a request loaded it, not the button');
    expect(find.textContaining('2 threads'), findsOneWidget);
    // 15 min limit, idle for 5 → about 10 left.
    expect(find.text('unloads in ~10 min if unused'), findsOneWidget);
    // Nothing edited yet: nothing to save.
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Save').first).onPressed, isNull);
  });

  testWidgets('saving sends the whole form with the chosen backend', (tester) async {
    final api = await _pump(tester);

    await tester.tap(find.text('Online — Jev API').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save').first);
    await tester.pumpAndSettle();

    final body = api.lastBody('PUT /api/decision/settings');
    expect(body['backend'], 'online');
    expect(body['local'], {'defaultModel': 'multilingual', 'threads': 2, 'autoLoad': true, 'idleUnloadMinutes': 15});
    expect((body['online'] as Map)['apiKey'], '', reason: 'an empty key means keep the stored one');
    expect(body.containsKey('clearApiKey'), isFalse);
    expect(find.text('Saved how decisions run'), findsOneWidget);
  });

  testWidgets('a stored key is never shown and is removed only on request', (tester) async {
    final api = await _pump(tester, hasKey: true);

    expect(find.text('A key is saved (it is never shown again). Leave empty to keep it.'), findsOneWidget);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Delete key'));
    await tester.pumpAndSettle();
    expect(find.text('The saved key is deleted when you press Save.'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Save').first);
    await tester.pumpAndSettle();

    expect(api.lastBody('PUT /api/decision/settings')['clearApiKey'], isTrue);
  });

  testWidgets('a key saved for one provider is not offered for another', (tester) async {
    await _pump(tester, hasKey: true);

    await tester.tap(find.byWidgetPredicate((w) => w is DropdownButtonFormField<String> && w.initialValue == 'typesafe'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Custom — any /v1/systemone URL').last);
    await tester.pumpAndSettle();

    expect(
      find.text('The saved key belongs to another provider or URL and is not sent here — enter a key for this choice.'),
      findsOneWidget,
    );
    expect(find.text('A key is saved (it is never shown again). Leave empty to keep it.'), findsNothing);
  });

  testWidgets('asking online sends the backend and shows what came back', (tester) async {
    final api = await _pump(tester, hasKey: true);

    await tester.tap(find.byWidgetPredicate((w) => w is DropdownButtonFormField<String> && w.initialValue == 'settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Online — Jev API').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Ask'));
    await tester.pumpAndSettle();

    final body = api.lastBody('POST /api/decision/ask');
    expect(body['backend'], 'online');
    expect(body.containsKey('model'), isFalse, reason: 'the local model picker does not apply online');
    expect(find.text('online:typesafe'), findsOneWidget);
    expect(find.text('→ yes'), findsOneWidget);
    expect(find.textContaining('"verdict": "odd"'), findsOneWidget, reason: 'an unknown shape is shown as sent');
  });

  testWidgets('reads in Vietnamese', (tester) async {
    await _pump(tester, lang: 'vi');

    expect(find.text('Cách chạy'), findsOneWidget);
    expect(find.text('Tự nạp khi cần'), findsOneWidget);
    expect(find.text('tự gỡ sau ~10 phút nếu không dùng'), findsOneWidget);
    expect(find.text('Thử hỏi'), findsOneWidget);
  });

  test('online answers: the type is inferred, an unknown shape is kept raw', () {
    final a = DecisionAnswer.fromJson('q', {'choice': 'billing', 'probabilities': {'billing': 0.9, 'sales': 0.1}});
    expect(a.type, 'choice');
    expect(a.confidence, isNull);
    expect([for (final (l, _) in a.probabilities) l], ['billing', 'sales']);

    final odd = DecisionAnswer.fromJson('q', {'type': 'choice', 'label': 'x'});
    expect(odd.known, isFalse, reason: 'a declared type without its field is not drawn as that type');
    expect(jsonEncode(odd.raw), contains('"label":"x"'));
  });

  test('settings equality ignores nothing that is sent', () {
    final a = DecisionRunSettings.fromJson(_settingsView()['settings'] as Map<String, dynamic>);
    final b = a.copyWith(local: a.local.copyWith(threads: () => null));
    expect(a == DecisionRunSettings.fromJson(_settingsView()['settings'] as Map<String, dynamic>), isTrue);
    expect(a == b, isFalse);
    expect(b.toJson()['local'], isNot(contains('threads')), reason: 'automatic threads are omitted, not zero');
  });
}
