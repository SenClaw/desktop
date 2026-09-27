import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:senclaw_desktop/core/config/app_config.dart';
import 'package:senclaw_desktop/core/i18n/l10n.dart';
import 'package:senclaw_desktop/core/transport/api_client.dart';
import 'package:senclaw_desktop/core/transport/connection.dart';
import 'package:senclaw_desktop/features/settings/local_models_section.dart';
import 'package:senclaw_desktop/theme/app_theme.dart';

Map<String, dynamic> _localModels({bool failedDownload = false}) => {
      'root': '/Users/x/.senclaw/local-models',
      'models': [
        {
          'key': 'gguf-qwen2-5-7b-instruct-q4-k-m-1a2b3c4d',
          'name': 'Qwen2.5 7B Instruct Q4_K_M',
          'format': 'gguf',
          'path': '/models/gguf/qwen.gguf',
          'sizeBytes': 4500000000,
          'capabilities': ['chat', 'vision'],
          'vision': true,
          'embedding': false,
          'mmprojPath': '/models/gguf/mmproj-qwen.gguf',
          'quant': 'Q4_K_M',
          'repo': 'Qwen/Qwen2.5-7B-Instruct-GGUF',
          'contextLength': 8192,
          'runtime': {
            'slot': 'gguf',
            'selected': {'id': 'llama.cpp-metal', 'version': 'b11201', 'name': 'Metal llama.cpp'},
          },
          'process': {
            'key': 'model:gguf-qwen',
            'runtimeId': 'llama.cpp-metal',
            'version': 'b11201',
            'slot': 'gguf',
            'modelKey': 'gguf-qwen2-5-7b-instruct-q4-k-m-1a2b3c4d',
            'pid': 111,
            'port': 41234,
            'state': 'ready',
            'startedAt': 0,
            'lastUsedAt': 0,
            'launches': 1,
            'error': null,
          },
        },
        {
          'key': 'mlx-org__repo-abcd1234',
          'name': 'Some MLX embedding model',
          'format': 'mlx',
          'path': '/models/org__repo',
          'sizeBytes': 900000000,
          'capabilities': ['embedding'],
          'vision': false,
          'embedding': true,
          'mmprojPath': null,
          'quant': null,
          'repo': 'org/repo',
          'contextLength': null,
          'runtime': {'slot': 'mlx', 'selected': null},
          'process': null,
        },
      ],
      'downloads': [
        if (failedDownload)
          {
            'downloadId': 'dl-1',
            'repo': 'org/bad-repo',
            'files': <String>[],
            'format': 'gguf',
            'state': 'failed',
            'receivedBytes': 1024,
            'totalBytes': 0,
            'percent': null,
            'error': 'connection reset',
          },
      ],
    };

/// Serves the local-models endpoints and records what was sent.
class _FakeApi implements ApiClient {
  _FakeApi({this.failedDownload = false});
  final bool failedDownload;
  final calls = <(String, Object?)>[];

  @override
  void updateConfig(AppConfig config) {}

  @override
  void dispose() {}

  @override
  Future<dynamic> get(String path, {Map<String, dynamic>? query, Duration? timeout}) async {
    calls.add(('GET $path', query));
    if (path == '/api/local-models') return _localModels(failedDownload: failedDownload);
    if (path == '/api/local-models/hf-files') {
      if (query?['repo'] == 'org/unknown-repo') {
        return {'repo': query?['repo'], 'format': 'unknown', 'files': <Map<String, dynamic>>[]};
      }
      return {
        'repo': query?['repo'],
        'format': 'gguf',
        'files': [
          {'name': 'model-Q4_K_M.gguf', 'size': 4500000000, 'quant': 'Q4_K_M', 'mmproj': false},
          {'name': 'mmproj-model.gguf', 'size': 900000000, 'quant': null, 'mmproj': true},
        ],
      };
    }
    if (path == '/api/local-models/settings') {
      return {
        'defaultContextLength': 8192,
        'engine': {'temperature': 0.7, 'top_k': 40, 'unknown_future_field': 'keep-me'},
      };
    }
    return <String, dynamic>{};
  }

  @override
  Future<dynamic> put(String path, {Object? body}) async {
    calls.add(('PUT $path', body));
    return {'ok': true};
  }

  @override
  Future<dynamic> post(String path, {Object? body, Duration? timeout}) async {
    calls.add(('POST $path', body));
    return {'ok': true};
  }

  @override
  Future<dynamic> patch(String path, {Object? body}) async => {'ok': true};

  @override
  Future<dynamic> delete(String path, {Object? body}) async {
    calls.add(('DELETE $path', body));
    if (path.contains('gguf-qwen') && !path.contains('force=1')) {
      throw ApiException(409, 'It is loaded — pass force=1 to unload and delete it.');
    }
    return {'ok': true};
  }

  (String, Object?) lastCall(String prefix) => calls.lastWhere((c) => c.$1.startsWith(prefix));
}

Future<_FakeApi> _pump(WidgetTester tester, {String lang = 'en', bool failedDownload = false}) async {
  tester.view.physicalSize = const Size(1400, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final api = _FakeApi(failedDownload: failedDownload);
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
      home: const Scaffold(body: LocalModelsSection()),
    ),
  ));
  await tester.pumpAndSettle();
  return api;
}

void main() {
  testWidgets('a loaded GGUF model shows its format badge, vision chip and Loaded state',
      (tester) async {
    await _pump(tester);

    expect(find.text('Qwen2.5 7B Instruct Q4_K_M'), findsOneWidget);
    expect(find.text('GGUF'), findsOneWidget);
    expect(find.text('vision'), findsOneWidget);
    expect(find.text('Q4_K_M'), findsOneWidget);
    expect(find.text('Loaded'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Unload'), findsOneWidget);
  });

  testWidgets('a model with no runtime selected for its format shows the hint and disables Load',
      (tester) async {
    await _pump(tester);

    expect(find.text('Some MLX embedding model'), findsOneWidget);
    expect(find.text('MLX'), findsOneWidget);
    expect(find.text('embedding'), findsOneWidget);
    expect(
        find.textContaining('No runtime selected for MLX'),
        findsOneWidget);

    final loadButton = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Load'));
    expect(loadButton.onPressed, isNull, reason: 'Load must be disabled with no runtime for the format');
  });

  testWidgets('unloading a loaded model posts to its unload endpoint', (tester) async {
    final api = await _pump(tester);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Unload'));
    await tester.pumpAndSettle();

    final call = api.lastCall('POST /api/local-models/');
    expect(call.$1,
        'POST /api/local-models/gguf-qwen2-5-7b-instruct-q4-k-m-1a2b3c4d/unload');
  });

  testWidgets('the download dialog looks up HF files and starts a GGUF download', (tester) async {
    final api = await _pump(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Download'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Hugging Face repo'), 'org/new-model');
    await tester.tap(find.widgetWithText(OutlinedButton, 'Look up'));
    await tester.pumpAndSettle();

    expect(find.text('GGUF file'), findsOneWidget);
    expect(find.text('Vision projector (optional)'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Download').last);
    await tester.pumpAndSettle();

    final call = api.lastCall('POST /api/local-models/download');
    final body = (call.$2 as Map).cast<String, dynamic>();
    expect(body['repo'], 'org/new-model');
    expect(body['file'], 'model-Q4_K_M.gguf');
  });

  testWidgets('default engine settings round-trip an unknown field untouched', (tester) async {
    final api = await _pump(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Save').last);
    await tester.pumpAndSettle();

    final call = api.lastCall('PUT /api/local-models/settings');
    final body = (call.$2 as Map).cast<String, dynamic>();
    final engine = (body['engine'] as Map).cast<String, dynamic>();
    expect(engine['unknown_future_field'], 'keep-me',
        reason: 'a field this form does not render must survive a save');
    expect(engine['temperature'], 0.7);
    expect(engine.containsKey('enable_thinking'), isFalse,
        reason: 'never inject enable_thinking:false for a model that never set it');
  });

  testWidgets(
      'the download dialog disables Download until a lookup succeeds, and for an unknown format',
      (tester) async {
    await _pump(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Download'));
    await tester.pumpAndSettle();

    // Before any lookup at all.
    var downloadButton = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Download').last);
    expect(downloadButton.onPressed, isNull, reason: 'nothing has been looked up yet');

    await tester.enterText(find.widgetWithText(TextField, 'Hugging Face repo'), 'org/unknown-repo');
    await tester.tap(find.widgetWithText(OutlinedButton, 'Look up'));
    await tester.pumpAndSettle();

    downloadButton = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Download').last);
    expect(downloadButton.onPressed, isNull, reason: 'an unknown format can never be downloaded');

    // Editing the repo after a successful lookup invalidates it again.
    await tester.enterText(find.widgetWithText(TextField, 'Hugging Face repo'), 'org/new-model');
    await tester.tap(find.widgetWithText(OutlinedButton, 'Look up'));
    await tester.pumpAndSettle();
    downloadButton = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Download').last);
    expect(downloadButton.onPressed, isNotNull, reason: 'a successful gguf lookup enables it');

    await tester.enterText(find.widgetWithText(TextField, 'Hugging Face repo'), 'org/new-model-2');
    await tester.pump();
    downloadButton = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Download').last);
    expect(downloadButton.onPressed, isNull,
        reason: 'editing the repo after a lookup must require a fresh lookup');
  });

  testWidgets('deleting a loaded model offers a force retry on 409', (tester) async {
    final api = await _pump(tester);

    // The GGUF model (first row) is loaded; its Delete button stays enabled
    // so the unload-and-delete flow below is reachable.
    await tester.tap(find.byTooltip('Delete').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(find.text('Unload and delete?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Unload and delete'));
    await tester.pumpAndSettle();

    final call = api.lastCall('DELETE /api/local-models/');
    expect(call.$1, contains('force=1'));
  });

  testWidgets('a failed download shows an error row instead of silently vanishing', (tester) async {
    await _pump(tester, failedDownload: true);

    expect(find.text('org/bad-repo'), findsOneWidget);
    expect(find.textContaining('Download failed: connection reset'), findsOneWidget);
  });

  testWidgets('reads in Vietnamese', (tester) async {
    await _pump(tester, lang: 'vi');

    expect(find.text('Model cục bộ'), findsOneWidget);
    expect(find.text('thị giác'), findsOneWidget);
    expect(find.textContaining('Chưa chọn runtime cho MLX'), findsOneWidget);
  });
}
