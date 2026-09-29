import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:senclaw_desktop/core/config/app_config.dart';
import 'package:senclaw_desktop/core/i18n/l10n.dart';
import 'package:senclaw_desktop/core/transport/api_client.dart';
import 'package:senclaw_desktop/core/transport/connection.dart';
import 'package:senclaw_desktop/features/settings/runtime_models.dart' show RuntimeCandidate;
import 'package:senclaw_desktop/features/settings/runtime_section.dart';
import 'package:senclaw_desktop/theme/app_theme.dart';

Map<String, dynamic> _runtimes({bool autoUpdate = false, bool multiVersionGguf = false}) => {
      'platform': 'darwin-arm64',
      'settings': {
        'autoUpdate': autoUpdate,
        'channel': 'stable',
        'idleTimeoutSecs': {'service': 300, 'model': 900},
      },
      'slots': [
        {
          'slot': 'gguf',
          'label': 'GGUF',
          'kind': 'format',
          'selected': {'id': 'llama.cpp-metal', 'version': 'b11201', 'name': 'Metal llama.cpp'},
          'candidates': [
            {'id': 'llama.cpp-metal', 'version': 'b11201', 'name': 'Metal llama.cpp'},
            if (multiVersionGguf)
              {'id': 'llama.cpp-metal', 'version': 'b11100', 'name': 'Metal llama.cpp'},
          ],
        },
        {
          'slot': 'tts',
          'label': 'Text to speech',
          'kind': 'capability',
          'selected': null,
          'candidates': [
            {'id': 'sen-tts', 'version': '0.1.0', 'name': 'SenClaw TTS'},
          ],
        },
        {
          'slot': 'ocr',
          'label': 'OCR',
          'kind': 'capability',
          'selected': null,
          'candidates': <Map<String, dynamic>>[],
        },
        {
          'slot': 'browser',
          'label': 'Browser',
          'kind': 'capability',
          'selected': {'id': 'sen-browser', 'version': '0.1.0', 'name': 'SenClaw Browser Engine'},
          'candidates': [
            {'id': 'sen-browser', 'version': '0.1.0', 'name': 'SenClaw Browser Engine'},
          ],
        },
      ],
      'installed': [
        {
          'id': 'llama.cpp-metal',
          'name': 'Metal llama.cpp',
          'version': 'b11201',
          'versions': ['b11201'],
          'type': 'llm-engine',
          'slots': ['gguf'],
          'formats': ['gguf'],
          'capabilities': ['chat'],
          'platforms': ['darwin-arm64'],
          'accelerator': 'metal',
          'mode': 'model',
          'compatible': true,
          'source': 'index',
          'description': 'Metal-accelerated llama.cpp',
          'releaseNotesUrl': null,
          'warnings': <String>[],
        },
        {
          'id': 'sen-mlx',
          'name': 'SenClaw MLX',
          'version': '1.0.0',
          'versions': ['1.0.0'],
          'type': 'llm-engine',
          'slots': ['mlx'],
          'formats': ['mlx'],
          'capabilities': ['chat', 'vision'],
          'platforms': ['darwin-arm64'],
          'accelerator': 'metal',
          'mode': 'model',
          'compatible': true,
          'source': 'index',
          'description': 'MLX LLM runtime',
          'releaseNotesUrl': 'https://example.com/sen-mlx/notes',
          'warnings': <String>[],
        },
        {
          'id': 'sen-browser',
          'name': 'SenClaw Browser Engine',
          'version': '0.1.0',
          'versions': ['0.1.0'],
          'type': 'browser',
          'slots': ['browser'],
          'formats': <String>[],
          'capabilities': ['browser'],
          'platforms': ['darwin-arm64'],
          'accelerator': null,
          'mode': 'service',
          'compatible': true,
          'source': 'local',
          'description': 'Chrome over CDP for the browser engine',
          'releaseNotesUrl': null,
          'warnings': <String>[],
        },
      ],
      'processes': [
        {
          'key': 'model:gguf-qwen',
          'runtimeId': 'llama.cpp-metal',
          'version': 'b11201',
          'slot': 'gguf',
          'modelKey': 'gguf-qwen',
          'pid': 4321,
          'port': 41234,
          'state': 'ready',
          'startedAt': DateTime.now().subtract(const Duration(minutes: 5)).millisecondsSinceEpoch,
          'lastUsedAt': DateTime.now().millisecondsSinceEpoch,
          'launches': 1,
          'error': null,
        },
      ],
    };

Map<String, dynamic> _catalog() => {
      'channel': 'stable',
      'fetchedAt': 0,
      'source': 'https://example.com/index.json',
      'error': null,
      'entries': [
        {
          'id': 'llama.cpp-metal',
          'name': 'Metal llama.cpp',
          'description': 'Metal build',
          'type': 'llm-engine',
          'slots': ['gguf'],
          'formats': ['gguf'],
          'capabilities': ['chat'],
          'accelerator': 'metal',
          'platforms': ['darwin-arm64'],
          'compatible': true,
          'available': true,
          'latestVersion': 'b11201',
          'installedVersion': 'b11201',
          'updateAvailable': false,
          'releaseNotesUrl': 'https://example.com/notes',
          'downloadSize': 100,
        },
        {
          'id': 'sen-mlx',
          'name': 'SenClaw MLX',
          'description': 'MLX LLM runtime',
          'type': 'llm-engine',
          'slots': ['mlx'],
          'formats': ['mlx'],
          'capabilities': ['chat', 'vision'],
          'accelerator': 'metal',
          'platforms': ['darwin-arm64'],
          'compatible': true,
          'available': true,
          'latestVersion': '1.1.0',
          'installedVersion': '1.0.0',
          'updateAvailable': true,
          'releaseNotesUrl': 'https://example.com/sen-mlx/notes',
          'downloadSize': 200,
        },
        {
          'id': 'sen-ocr',
          'name': 'SenClaw OCR',
          'description': 'PaddleOCR PP-OCRv4/v5',
          'type': 'ocr',
          'slots': ['ocr'],
          'formats': <String>[],
          'capabilities': ['ocr'],
          'accelerator': 'metal',
          'platforms': ['darwin-arm64'],
          'compatible': true,
          'available': true,
          'latestVersion': '0.1.0',
          'installedVersion': null,
          'updateAvailable': false,
          'releaseNotesUrl': null,
          'downloadSize': 18000000,
        },
        {
          'id': 'sen-tts',
          'name': 'SenClaw TTS',
          'description': 'VieNeu + macOS say',
          'type': 'tts',
          'slots': ['tts'],
          'formats': <String>[],
          'capabilities': ['tts'],
          'accelerator': null,
          'platforms': ['darwin-arm64'],
          'compatible': true,
          'available': false,
          'latestVersion': '',
          'installedVersion': null,
          'updateAvailable': false,
          'releaseNotesUrl': null,
          'downloadSize': null,
        },
        {
          // Installed from a local package before any release was published.
          'id': 'sen-browser',
          'name': 'SenClaw Browser Engine',
          'description': 'Chrome over CDP for the browser engine',
          'type': 'browser',
          'slots': ['browser'],
          'formats': <String>[],
          'capabilities': ['browser'],
          'accelerator': null,
          'platforms': ['darwin-arm64'],
          'compatible': true,
          'available': false,
          'latestVersion': '0.1.0',
          'installedVersion': '0.1.0',
          'updateAvailable': false,
          'releaseNotesUrl': null,
          'downloadSize': null,
        },
        {
          'id': 'sen-whisper-x86',
          'name': 'SenClaw Whisper (x86)',
          'description': 'ASR, x86 only',
          'type': 'asr',
          'slots': ['asr'],
          'formats': <String>[],
          'capabilities': ['asr'],
          'accelerator': null,
          'platforms': ['linux-x64'],
          'compatible': false,
          'available': true,
          'latestVersion': '0.1.0',
          'installedVersion': null,
          'updateAvailable': false,
          'releaseNotesUrl': null,
          'downloadSize': 1000,
        },
      ],
    };

/// Serves the runtime endpoints and records what was sent.
class _FakeApi implements ApiClient {
  _FakeApi({this.multiVersionGguf = false});
  final bool multiVersionGguf;
  final calls = <(String, Object?)>[];

  @override
  void updateConfig(AppConfig config) {}

  @override
  void dispose() {}

  @override
  Future<dynamic> get(String path, {Map<String, dynamic>? query, Duration? timeout}) async {
    calls.add(('GET $path', query));
    return switch (path) {
      '/api/runtimes' => _runtimes(multiVersionGguf: multiVersionGguf),
      '/api/runtimes/catalog' => _catalog(),
      _ => <String, dynamic>{},
    };
  }

  @override
  Future<dynamic> put(String path, {Object? body}) async {
    calls.add(('PUT $path', body));
    return {'ok': true};
  }

  @override
  Future<dynamic> post(String path, {Object? body, Duration? timeout}) async {
    calls.add(('POST $path', body));
    if (path == '/api/runtimes/install') {
      final b = (body as Map).cast<String, dynamic>();
      return {'jobId': 'job-1', 'id': b['id'], 'version': b['version'] ?? '9.9.9'};
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

  (String, Object?) lastCall(String prefix) => calls.lastWhere((c) => c.$1.startsWith(prefix));
}

Future<_FakeApi> _pump(WidgetTester tester, {String lang = 'en'}) async {
  tester.view.physicalSize = const Size(1400, 2200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final api = _FakeApi();
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
      home: const Scaffold(body: RuntimeSection()),
    ),
  ));
  await tester.pumpAndSettle();
  return api;
}

Future<_FakeApi> _pumpWithMultiVersionSlot(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1400, 2200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final api = _FakeApi(multiVersionGguf: true);
  await tester.pumpWidget(ProviderScope(
    overrides: [apiClientProvider.overrideWithValue(api)],
    child: MaterialApp(
      theme: AppTheme.dark(),
      supportedLocales: const [Locale('en'), Locale('vi')],
      localizationsDelegates: const [
        L10nDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const Scaffold(body: RuntimeSection()),
    ),
  ));
  await tester.pumpAndSettle();
  return api;
}

void main() {
  testWidgets('slot rows show the selected candidate, an unselected one, and an empty one',
      (tester) async {
    await _pump(tester);

    // gguf: selected candidate shows its name and version chip.
    expect(find.text('GGUF'), findsOneWidget);
    expect(find.text('Metal llama.cpp'), findsWidgets); // slot row + catalog row
    expect(find.text('b11201'), findsWidgets);

    // tts: candidates exist but none selected → the dropdown hint shows.
    expect(find.text('None selected'), findsOneWidget);

    // ocr: no candidates at all.
    expect(find.text('No compatible engine installed'), findsOneWidget);
  });

  testWidgets(
      'picking a candidate with only one version sends version: null (track newest)',
      (tester) async {
    final api = await _pump(tester);

    // Open the tts slot's dropdown (the second slot with candidates — gguf's
    // is first) and pick its only candidate. Tapping the widget itself,
    // rather than its hint text, avoids a flaky hit-test miss on the glyph.
    await tester.tap(find.byType(DropdownButton<RuntimeCandidate>).at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('SenClaw TTS').last);
    await tester.pumpAndSettle();

    final call = api.lastCall('PUT /api/runtimes/selections');
    final body = (call.$2 as Map).cast<String, dynamic>();
    expect(body['slot'], 'tts');
    expect(body['id'], 'sen-tts');
    expect(body['version'], isNull,
        reason: 'picking the only candidate for an id is not pinning a version');
  });

  testWidgets(
      'picking one of several versions of the same id sends that explicit version',
      (tester) async {
    final api = await _pumpWithMultiVersionSlot(tester);

    // gguf has two candidates for llama.cpp-metal (b11201 newest, b11100
    // older) — picking the older one must pin it explicitly.
    await tester.tap(find.byType(DropdownButton<RuntimeCandidate>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('b11100').last);
    await tester.pumpAndSettle();

    final call = api.lastCall('PUT /api/runtimes/selections');
    final body = (call.$2 as Map).cast<String, dynamic>();
    expect(body['slot'], 'gguf');
    expect(body['id'], 'llama.cpp-metal');
    expect(body['version'], 'b11100');
  });

  testWidgets('toggling auto-update saves runtime settings with autoUpdate true', (tester) async {
    final api = await _pump(tester);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    final call = api.lastCall('PUT /api/runtimes/settings');
    final body = (call.$2 as Map).cast<String, dynamic>();
    expect(body['autoUpdate'], isTrue);
    expect(body['channel'], 'stable');
  });

  testWidgets('catalog rows show latest / update / install / not-published / incompatible',
      (tester) async {
    await _pump(tester);

    expect(find.text('✓ Latest version'), findsOneWidget, reason: 'llama.cpp-metal is up to date');
    expect(find.widgetWithText(FilledButton, 'Update'), findsOneWidget, reason: 'sen-mlx has an update');
    expect(find.text('1.1.0'), findsOneWidget, reason: 'the target version of the update is shown');
    expect(find.widgetWithText(FilledButton, 'Install'), findsOneWidget, reason: 'sen-ocr is not installed');
    expect(find.text('Not published yet'), findsOneWidget, reason: 'sen-tts has no package yet');
    expect(find.text('Incompatible'), findsOneWidget, reason: 'sen-whisper-x86 does not run on this platform');
    expect(find.text('Installed'), findsOneWidget, reason: 'sen-browser came from a local package, none published');
  });

  testWidgets('the browser engine has its own slot row', (tester) async {
    await _pump(tester);

    expect(find.text('Browser'), findsWidgets);
    expect(find.text('SenClaw Browser Engine'), findsWidgets);
  });

  testWidgets('tapping Install sends the install request for that runtime', (tester) async {
    final api = await _pump(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Install'));
    await tester.pump();

    final call = api.lastCall('POST /api/runtimes/install');
    expect((call.$2 as Map)['id'], 'sen-ocr');

    // The row now polls its job on a periodic timer — replace the tree so
    // the card disposes and cancels it before the test ends.
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the Running list shows the process and a working Stop button', (tester) async {
    final api = await _pump(tester);

    expect(find.text('llama.cpp-metal · b11201'), findsOneWidget);
    expect(find.textContaining('port 41234'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Stop'));
    await tester.pumpAndSettle();

    final call = api.lastCall('POST /api/runtimes/processes/');
    expect(call.$1, 'POST /api/runtimes/processes/model%3Agguf-qwen/stop');
  });

  testWidgets('reads in Vietnamese', (tester) async {
    await _pump(tester, lang: 'vi');

    expect(find.text('Thời gian chạy'), findsOneWidget);
    expect(find.text('Lựa chọn Runtime'), findsOneWidget);
    expect(find.text('Ổn định'), findsOneWidget);
    expect(find.text('✓ Bản mới nhất'), findsOneWidget);
  });
}
