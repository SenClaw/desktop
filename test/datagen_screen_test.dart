// Datagen (desktop). Covers what the screen exists to do against a faked
// daemon: show a running job's progress and why candidates were rejected,
// cancel it, read a dataset's records, delete a dataset — that the form's
// line formats turn into the same job body the web page sends — and the
// source datasets: install from the catalog (asking first when its terms
// need it), import a URL through a preview, use a dataset as seeds.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:senclaw_desktop/core/config/app_config.dart';
import 'package:senclaw_desktop/core/transport/api_client.dart';
import 'package:senclaw_desktop/core/transport/connection.dart';
import 'package:senclaw_desktop/features/datagen/datagen_api.dart';
import 'package:senclaw_desktop/features/datagen/datagen_screen.dart';
import 'package:senclaw_desktop/theme/app_theme.dart';

class _FakeApi implements ApiClient {
  final calls = <String>[];

  @override
  void updateConfig(AppConfig config) {}

  @override
  void dispose() {}

  static const _running = {
    'jobId': 'abc123def456',
    'name': 'router-eval',
    'pipeline': 'expand_seeds',
    'state': 'running',
    'target': 12,
    'accepted': 4,
    'llmCalls': 3,
    'maxLlmCalls': 18,
    'rejected': {'label_mismatch': 2, 'too_similar': 1},
    'startedAt': 1,
  };

  static const _done = {
    'jobId': 'fff000fff000',
    'name': 'chat-export',
    'pipeline': 'export_logs',
    'state': 'done',
    'target': 3,
    'accepted': 2,
    'llmCalls': 0,
    'maxLlmCalls': 0,
    'rejected': {'interrupted': 1},
    'startedAt': 2,
  };

  static const _imported = {
    'jobId': 'aaa111bbb222',
    'name': 'senclaw-flows-vi',
    'pipeline': 'import',
    'state': 'done',
    'target': 20000,
    'accepted': 144,
    'attempts': 144,
    'llmCalls': 0,
    'maxLlmCalls': 0,
    'rejected': <String, int>{},
    'startedAt': 3,
    'provenance': {
      'kind': 'labeled_text',
      'license': 'MIT',
      'sourceRows': 144,
      'source': {'type': 'bundled', 'catalog': 'senclaw-flows-vi'},
    },
  };

  static const _catalog = [
    {
      'id': 'senclaw-flows-vi',
      'title': 'SenClaw flows (vi)',
      'description': '144 yêu cầu tiếng Việt',
      'kind': 'labeled_text',
      'lang': 'vi',
      'rows': 144,
      'license': 'MIT',
      'attribution': 'SenClaw',
      'flags': <String, bool>{},
      'needsConsent': false,
      'bundled': true,
      'installed': true,
      'dataset': 'senclaw-flows-vi',
    },
    {
      'id': 'xquad-vi',
      'title': 'XQuAD · tiếng Việt',
      'description': '1.190 câu hỏi kèm đoạn văn',
      'kind': 'qa_context',
      'lang': 'vi',
      'rows': 1190,
      'license': 'CC-BY-SA-4.0',
      'attribution': 'XQuAD, Google',
      'flags': {'shareAlike': true},
      'notice': 'CC BY-SA: dùng lại phải ghi nguồn.',
      'needsConsent': true,
      'bundled': false,
      'installed': false,
    },
    {
      'id': 'gsm8k',
      'title': 'GSM8K',
      'description': '1.319 bài toán',
      'kind': 'problem_answer',
      'lang': 'en',
      'rows': 1319,
      'license': 'MIT',
      'attribution': 'OpenAI',
      'flags': <String, bool>{},
      'needsConsent': false,
      'bundled': false,
      'installed': false,
    },
  ];

  @override
  Future<dynamic> get(String path, {Map<String, dynamic>? query, Duration? timeout}) async {
    calls.add('GET $path${query == null ? '' : ' $query'}');
    if (path == '/api/datagen/jobs') return {'jobs': [_running]};
    if (path == '/api/datagen/datasets') {
      return {'root': '/scratch/datasets', 'datasets': [_running, _imported, _done]};
    }
    if (path == '/api/datagen/catalog') return {'entries': _catalog};
    if (path.endsWith('/records')) {
      return {
        'total': 1,
        'records': [
          {'instruction': 'viết lời chúc sinh nhật cho mẹ', 'output': 'Chúc mẹ tuổi mới vui vẻ!'}
        ],
      };
    }
    return {};
  }

  @override
  Future<dynamic> post(String path, {Object? body, Duration? timeout}) async {
    calls.add('POST $path ${jsonEncode(body ?? {})}');
    if (path == '/api/datagen/import/preview') {
      return {
        'columns': ['utterance', 'intent'],
        'rows': [
          {'utterance': 'nhắc tôi họp lúc 9 giờ', 'intent': 'calendar_set'},
          {'utterance': '', 'intent': 'x'},
        ],
        'total': 2,
        'format': 'csv',
        'suggested': {
          'kind': 'labeled_text',
          'mapping': {'text': 'utterance', 'label': 'intent'},
        },
        'records': [
          {
            'record': {'id': '1', 'text': 'nhắc tôi họp lúc 9 giờ', 'label': 'calendar_set'},
          },
          {'rejected': 'missing_text'},
        ],
      };
    }
    return {'ok': true};
  }

  @override
  Future<dynamic> put(String path, {Object? body}) async => {'ok': true};

  @override
  Future<dynamic> patch(String path, {Object? body}) async => {'ok': true};

  @override
  Future<dynamic> delete(String path, {Object? body}) async {
    calls.add('DELETE $path');
    return {'ok': true};
  }
}

Future<_FakeApi> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final api = _FakeApi();
  await tester.pumpWidget(ProviderScope(
    overrides: [apiClientProvider.overrideWithValue(api)],
    child: MaterialApp(theme: AppTheme.light(), home: const Scaffold(body: DatagenScreen())),
  ));
  await tester.pump();
  await tester.pump();
  return api;
}

void main() {
  group('buildDatagenBody', () {
    test('labelled seeds and label descriptions', () {
      final b = buildDatagenBody('expand_seeds', {
        'name': ' eval ',
        'seeds': 'browser | find a cheap flight\n\nplain request here\n',
        'labels': 'browser: open web pages\nnot a description',
        'mode': 'new',
        'checkLabel': 'auto',
        'target': '12',
        'maxLlmCalls': '',
      });
      expect(b, {
        'pipeline': 'expand_seeds',
        'name': 'eval',
        'seeds': [
          {'label': 'browser', 'text': 'find a cheap flight'},
          'plain request here',
        ],
        'labels': {'browser': 'open web pages'},
        'mode': 'new',
        'target': 12,
      });
    });

    test('a dataset picked instead of lines becomes seedsFrom / problemsFrom', () {
      expect(buildDatagenBody('expand_seeds', {'seeds': 'ignored | x', 'seedsFrom': 'massive-vi', 'perLabel': '3'}), {
        'pipeline': 'expand_seeds',
        'seedsFrom': {'dataset': 'massive-vi', 'perLabel': 3},
      });
      expect(buildDatagenBody('reasoning_traces', {'problemsFrom': 'gsm8k'}), {
        'pipeline': 'reasoning_traces',
        'problemsFrom': {'dataset': 'gsm8k'},
      });
    });

    test('problems with answers, documents split by ---, export chats', () {
      expect(buildDatagenBody('reasoning_traces', {'problems': '17*3 || 51\nwhy is the sky blue?', 'threshold': '0.8'}), {
        'pipeline': 'reasoning_traces',
        'problems': [
          {'problem': '17*3', 'answer': '51'},
          'why is the sky blue?',
        ],
        'threshold': 0.8,
      });
      final d = buildDatagenBody('doc_qa', {'texts': 'first doc\n---\nsecond doc', 'paths': '', 'verify': false});
      expect(d['texts'], ['first doc', 'second doc']);
      expect(d['verify'], false);
      final e = buildDatagenBody('export_logs', {'chats': '*', 'format': 'alpaca', 'language': 'vi'});
      expect(e, {'pipeline': 'export_logs', 'chats': ['*'], 'format': 'alpaca'}, reason: 'export calls no model');
    });
  });

  testWidgets('a running job shows progress, calls and rejection reasons', (tester) async {
    await _pump(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('router-eval'), findsNWidgets(2), reason: 'in the job list and as a dataset');
    expect(find.text('4/12'), findsNWidgets(2));
    expect(find.text('LLM calls: 3/18'), findsNWidgets(2));
    expect(find.text('Rejected: 2 label_mismatch, 1 too_similar'), findsNWidgets(2));
    expect(find.text('/scratch/datasets'), findsOneWidget);
  });

  testWidgets('cancel posts to that job only', (tester) async {
    final api = await _pump(tester);
    await tester.tap(find.byTooltip('Cancel'));
    await tester.pump();
    expect(api.calls.where((c) => c.startsWith('POST /api/datagen/jobs/abc123def456/cancel')), hasLength(1));
  });

  testWidgets('records open in a dialog, a page at a time', (tester) async {
    final api = await _pump(tester);
    await tester.tap(find.byTooltip('View records').last);
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('viết lời chúc sinh nhật cho mẹ'), findsOneWidget);
    expect(find.text('1–1 of 1'), findsOneWidget);
    expect(api.calls.any((c) => c.startsWith('GET /api/datagen/datasets/chat-export/records {offset: 0, limit: 10}')), isTrue);
  });

  testWidgets('delete asks first, then removes the dataset', (tester) async {
    final api = await _pump(tester);
    await tester.tap(find.byTooltip('Delete').last);
    await tester.pump();
    expect(find.text('Delete this dataset?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pump();
    expect(api.calls, contains('DELETE /api/datagen/datasets/chat-export'));
  });

  testWidgets('switching pipeline drops the last pipeline\'s values', (tester) async {
    final api = await _pump(tester);
    await tester.tap(find.text('New job'));
    await tester.pump();
    await tester.pump();
    // expand_seeds opens with Target 50; reasoning_traces must not inherit it.
    await tester.tap(find.text('expand_seeds').last);
    await tester.pump();
    await tester.pump();
    await tester.tap(find.text('reasoning_traces').last);
    await tester.pump();
    await tester.pump();
    await tester.enterText(find.widgetWithText(TextField, 'Problems'), '17*3 || 51');
    await tester.tap(find.widgetWithText(FilledButton, 'Start'));
    await tester.pump();
    await tester.pump();
    final sent = api.calls.firstWhere((c) => c.startsWith('POST /api/datagen/jobs '));
    final body = jsonDecode(sent.substring('POST /api/datagen/jobs '.length)) as Map<String, dynamic>;
    expect(body['pipeline'], 'reasoning_traces');
    expect(body.containsKey('target'), isFalse, reason: 'no hidden Target from the previous pipeline');
    expect(body['maxIterations'], 3);
  });

  testWidgets('the new job dialog sends the body built from its fields', (tester) async {
    final api = await _pump(tester);
    await tester.tap(find.text('New job'));
    await tester.pump();
    await tester.pump();
    await tester.enterText(find.widgetWithText(TextField, 'Example requests'), 'browser | find a cheap flight');
    await tester.tap(find.widgetWithText(FilledButton, 'Start'));
    await tester.pump();
    await tester.pump();
    final sent = api.calls.firstWhere((c) => c.startsWith('POST /api/datagen/jobs '));
    final body = jsonDecode(sent.substring('POST /api/datagen/jobs '.length)) as Map<String, dynamic>;
    expect(body['pipeline'], 'expand_seeds');
    expect(body['seeds'], [
      {'label': 'browser', 'text': 'find a cheap flight'}
    ]);
    expect(body['target'], 50);
  });

  testWidgets('an imported dataset shows where it came from and feeds a new job', (tester) async {
    final api = await _pump(tester);
    expect(find.text('144 rows'), findsOneWidget, reason: 'an import counts what it kept, not of a ceiling');
    expect(find.text('MIT'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Use as seeds').last);
    await tester.pump();
    await tester.pump();
    expect(find.text('senclaw-flows-vi'), findsWidgets, reason: 'the dataset is preselected');
    await tester.tap(find.widgetWithText(FilledButton, 'Start'));
    await tester.pump();
    await tester.pump();
    final sent = api.calls.firstWhere((c) => c.startsWith('POST /api/datagen/jobs '));
    final body = jsonDecode(sent.substring('POST /api/datagen/jobs '.length)) as Map<String, dynamic>;
    expect(body['pipeline'], 'expand_seeds');
    expect(body['seedsFrom'], {'dataset': 'senclaw-flows-vi'});
    expect(body.containsKey('seeds'), isFalse);
  });

  testWidgets('the catalog installs at once, or after agreeing to the terms', (tester) async {
    final api = await _pump(tester);
    await tester.tap(find.text('Source datasets'));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('XQuAD · tiếng Việt'), findsOneWidget);
    expect(find.text('Installed'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Download').last);
    await tester.pump();
    final gsm = api.calls.lastWhere((c) => c.startsWith('POST /api/datagen/jobs '));
    expect(jsonDecode(gsm.substring('POST /api/datagen/jobs '.length)), {
      'pipeline': 'import',
      'source': {'catalog': 'gsm8k'},
    });

    await tester.tap(find.widgetWithText(FilledButton, 'Download').first);
    await tester.pump();
    expect(find.text('Install XQuAD · tiếng Việt?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'I agree, install'));
    await tester.pump();
    final xquad = api.calls.lastWhere((c) => c.startsWith('POST /api/datagen/jobs '));
    expect(jsonDecode(xquad.substring('POST /api/datagen/jobs '.length)), {
      'pipeline': 'import',
      'source': {'catalog': 'xquad-vi'},
      'acceptLicense': true,
    });
  });

  testWidgets('a URL import previews, then sends kind, mapping and license', (tester) async {
    final api = await _pump(tester);
    await tester.tap(find.text('Import file / URL…'));
    await tester.pump();
    await tester.tap(find.text('URL').first);
    await tester.pump();
    await tester.enterText(find.byType(TextField).first, 'https://example.org/intents.csv');
    await tester.tap(find.text('Preview'));
    await tester.pump();
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('missing_text'), findsOneWidget);
    expect(find.textContaining('nhắc tôi họp lúc 9 giờ'), findsOneWidget);
    final preview = api.calls.firstWhere((c) => c.startsWith('POST /api/datagen/import/preview '));
    expect(jsonDecode(preview.substring('POST /api/datagen/import/preview '.length)), {
      'source': {'url': 'https://example.org/intents.csv'},
    });

    await tester.tap(find.widgetWithText(FilledButton, 'Import'));
    await tester.pump();
    expect(find.text('Say the license, or private / unknown'), findsOneWidget, reason: 'no license, no import');
    await tester.enterText(find.widgetWithText(TextField, 'License *'), 'private');
    await tester.tap(find.widgetWithText(FilledButton, 'Import'));
    await tester.pump();
    await tester.pump();
    final sent = api.calls.lastWhere((c) => c.startsWith('POST /api/datagen/jobs '));
    expect(jsonDecode(sent.substring('POST /api/datagen/jobs '.length)), {
      'pipeline': 'import',
      'source': {'url': 'https://example.org/intents.csv'},
      'kind': 'labeled_text',
      'mapping': {'text': 'utterance', 'label': 'intent'},
      'license': 'private',
    });
  });
}
