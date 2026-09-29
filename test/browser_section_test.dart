import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:senclaw_desktop/core/config/app_config.dart';
import 'package:senclaw_desktop/core/i18n/l10n.dart';
import 'package:senclaw_desktop/core/transport/api_client.dart';
import 'package:senclaw_desktop/core/transport/connection.dart';
import 'package:senclaw_desktop/features/settings/browser_section.dart';
import 'package:senclaw_desktop/theme/app_theme.dart';

Map<String, dynamic> _settingsView({String engine = 'legacy', bool runtimeInstalled = false}) => {
      'settings': {
        'engine': 'auto',
        'defaultDriver': 'managed',
        'decisionBackend': 'auto',
        'localModel': 'laya-browser',
        'hostedModel': null,
        'hostedDomains': <String>[],
        'sensitiveDomains': <String>[],
        'domainDrivers': <String, String>{},
        'textModel': null,
        'fallbackModel': null,
        'bandsLocal': {'act': 0.6, 'fallback': 0.2},
        'bandsHosted': {'act': 0.5, 'fallback': 0.25},
        'maxSteps': 40,
        'headless': true,
        'profile': 'default',
        'startUrl': 'https://duckduckgo.com/',
      },
      'engine': engine,
      'runtimeInstalled': runtimeInstalled,
    };

/// Serves the browser-agent endpoints and records what was sent.
class _FakeApi implements ApiClient {
  _FakeApi({
    this.engine = 'legacy',
    this.runtimeInstalled = false,
    this.pending = const [],
    this.paired = const [],
    this.connected,
    this.tabs,
    this.approvals = const [],
    this.approvalOutcome,
    this.approvalError,
  });
  final String engine;
  final bool runtimeInstalled;
  final List<Map<String, dynamic>> pending;
  final List<Map<String, dynamic>> paired;
  final Map<String, dynamic>? connected;
  final Map<String, dynamic>? tabs;
  final List<Map<String, dynamic>> approvals;

  /// What `POST /api/browser-agent/approvals/:id` answers with when it
  /// succeeds. Defaults to a task that ended.
  final Map<String, dynamic>? approvalOutcome;

  /// When set, the approvals POST throws this instead of answering — the
  /// way to fake a 404 ("already answered elsewhere") or any other daemon
  /// error.
  final ApiException? approvalError;

  final calls = <(String, Object?)>[];

  @override
  void updateConfig(AppConfig config) {}

  @override
  void dispose() {}

  @override
  Future<dynamic> get(String path, {Map<String, dynamic>? query, Duration? timeout}) async {
    calls.add(('GET $path', null));
    return switch (path) {
      '/api/browser-agent/settings' => _settingsView(engine: engine, runtimeInstalled: runtimeInstalled),
      '/api/browser-agent/extension' => {'connected': connected, 'pending': pending, 'paired': paired},
      '/api/browser-agent/tabs' => tabs ?? {'sessions': <Map<String, dynamic>>[], 'current': {}, 'extension': {}},
      '/api/browser-agent/approvals' => {'approvals': approvals},
      '/api/llm-config' => {'configs': <Map<String, dynamic>>[]},
      _ => <String, dynamic>{},
    };
  }

  @override
  Future<dynamic> put(String path, {Object? body}) async {
    calls.add(('PUT $path', body));
    final sent = (body as Map).cast<String, dynamic>();
    final merged = _settingsView(engine: engine, runtimeInstalled: runtimeInstalled);
    (merged['settings'] as Map<String, dynamic>).addAll(sent);
    return merged;
  }

  @override
  Future<dynamic> post(String path, {Object? body, Duration? timeout}) async {
    calls.add(('POST $path', body));
    const pairPrefix = '/api/browser-agent/extension/pairings/';
    if (path.startsWith(pairPrefix) && path.endsWith('/approve')) {
      final code = path.substring(pairPrefix.length, path.length - '/approve'.length);
      return {'paired': 'ext-$code'};
    }
    const approvalsPrefix = '/api/browser-agent/approvals/';
    if (path.startsWith(approvalsPrefix)) {
      if (approvalError != null) throw approvalError!;
      return approvalOutcome ?? {'task_id': 'task-1', 'status': 'done', 'message': 'done'};
    }
    return {'ok': true};
  }

  @override
  Future<dynamic> patch(String path, {Object? body}) async => {'ok': true};

  @override
  Future<dynamic> delete(String path, {Object? body}) async {
    calls.add(('DELETE $path', body));
    return {'revoked': true};
  }

  Map<String, dynamic> lastBody(String call) => (calls.lastWhere((c) => c.$1 == call).$2 as Map).cast<String, dynamic>();
  bool called(String call) => calls.any((c) => c.$1 == call);
  int callCount(String call) => calls.where((c) => c.$1 == call).length;
}

Map<String, dynamic> _approvalJson({
  String approvalId = 'appr-1',
  String taskId = 'task-1',
  String chat = 'chat:123',
  String goal = 'Buy the blue mug in my cart',
  String action = 'Place order',
  String operation = 'CLICK',
  String? text,
  String driver = 'managed',
  String? url = 'https://example.com/checkout.html',
  int? waitingSecs = 65,
}) =>
    {
      'approval_id': approvalId,
      'task_id': taskId,
      'chat': chat,
      'goal': goal,
      'action': action,
      'operation': operation,
      'text': text,
      'driver': driver,
      'url': url,
      'waiting_secs': waitingSecs,
    };

Future<_FakeApi> _pump(WidgetTester tester, {_FakeApi? api}) async {
  // Tall enough that the lazy settings list builds every card.
  tester.view.physicalSize = const Size(1400, 6000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final fake = api ?? _FakeApi();
  await tester.pumpWidget(ProviderScope(
    overrides: [apiClientProvider.overrideWithValue(fake)],
    child: MaterialApp(
      theme: AppTheme.dark(),
      locale: const Locale('en'),
      supportedLocales: const [Locale('en'), Locale('vi')],
      localizationsDelegates: const [
        L10nDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const Scaffold(body: BrowserSection()),
    ),
  ));
  await tester.pumpAndSettle();
  return fake;
}

void main() {
  testWidgets('shows engine status, the runtime-missing warning, and a disabled Save', (tester) async {
    await _pump(tester);
    expect(tester.takeException(), isNull);

    expect(find.text('Browser engine'), findsOneWidget);
    expect(find.text('Engine in use: '), findsOneWidget);
    expect(find.text('Legacy (extension scripts)'), findsOneWidget);
    expect(find.text('The Browser runtime is not installed.'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Open Runtime settings'), findsOneWidget);

    expect(find.text('Settings'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Save')).onPressed, isNull,
        reason: 'nothing edited yet: nothing to save');

    expect(find.text('Chrome extension'), findsOneWidget);
    expect(find.text('Not connected'), findsOneWidget);
    expect(find.text('Activity'), findsOneWidget);
  });

  testWidgets('a pending pairing code renders with an Approve button that connects it', (tester) async {
    final api = await _pump(
      tester,
      api: _FakeApi(pending: const [
        {'code': 'ABCD1234', 'ext_id': 'ext-abcd1234', 'age_secs': 5},
      ]),
    );

    expect(find.text('Waiting to pair'), findsOneWidget);
    expect(find.text('ABCD1234'), findsOneWidget);
    final approve = find.widgetWithText(FilledButton, 'Approve');
    expect(approve, findsOneWidget);

    await tester.tap(approve);
    await tester.pumpAndSettle();

    expect(api.called('POST /api/browser-agent/extension/pairings/ABCD1234/approve'), isTrue);
    expect(find.text('Connected ext-ABCD1234'), findsOneWidget);
  });

  testWidgets('paired browsers show a Remove button that confirms before revoking', (tester) async {
    final api = await _pump(
      tester,
      api: _FakeApi(paired: const [
        {'ext_id': 'ext-paired-1', 'paired_at': '2026-09-29T00:00:00Z'},
      ]),
    );

    expect(find.text('Paired browsers'), findsOneWidget);
    // Two "Remove" buttons exist on screen: the row action and (after tapping)
    // the confirm dialog's — disambiguate the row one via its OutlinedButton type.
    await tester.tap(find.widgetWithText(OutlinedButton, 'Remove'));
    await tester.pumpAndSettle();

    // The dialog joins the ext id and the warning into one Text (same
    // pattern as pairing_section.dart's own confirm dialog), so match the
    // warning as a substring rather than the whole combined string.
    expect(find.textContaining('This browser will need to pair again.'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
    await tester.pumpAndSettle();

    expect(api.called('DELETE /api/browser-agent/extension/paired/ext-paired-1'), isTrue);
  });

  testWidgets('Save sends only the field that was actually changed', (tester) async {
    final api = await _pump(tester);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Save')).onPressed, isNotNull);

    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(api.lastBody('PUT /api/browser-agent/settings'), {'headless': false});
    expect(find.text('Settings saved'), findsOneWidget);
  });

  testWidgets('Activity never fetches on its own — only the button starts it, and shows the tabs it gets back',
      (tester) async {
    final api = await _pump(
      tester,
      api: _FakeApi(tabs: {
        'sessions': [
          {
            'id': 's1',
            'driver': 'managed',
            'profile': 'default',
            'headless': true,
            'tabs': [
              {
                'id': 't1',
                'owner': 'chat:123',
                'driver': 'managed',
                'url': 'https://example.com/',
                'hold': 'none',
                'closed': false,
              },
            ],
          },
        ],
        'current': <String, dynamic>{},
        'extension': <String, dynamic>{},
      }),
    );

    expect(api.called('GET /api/browser-agent/tabs'), isFalse,
        reason: 'GET tabs starts the browser runtime; it must never run on mount or a timer');

    await tester.tap(find.widgetWithText(FilledButton, 'Show open tabs'));
    await tester.pumpAndSettle();

    expect(api.called('GET /api/browser-agent/tabs'), isTrue);
    expect(find.text('chat:123'), findsOneWidget);
    expect(find.text('https://example.com/'), findsOneWidget);
  });

  testWidgets('a v2 engine with the runtime installed shows no warning, and a connected extension',
      (tester) async {
    await _pump(
      tester,
      api: _FakeApi(
        engine: 'v2',
        runtimeInstalled: true,
        connected: const {'ext_id': 'ext-live', 'version': '0.4.0', 'chrome': '129.0', 'piped': true},
      ),
    );

    expect(find.text('New (Jev + LLM)'), findsOneWidget);
    expect(find.text('The Browser runtime is not installed.'), findsNothing);
    expect(find.widgetWithText(OutlinedButton, 'Open Runtime settings'), findsNothing);
    expect(find.text('Connected'), findsOneWidget);
    expect(find.textContaining('ext-live'), findsOneWidget);
  });

  testWidgets('the approvals card is hidden when the list is empty', (tester) async {
    await _pump(tester);
    expect(find.text('Waiting for your approval'), findsNothing);
  });

  testWidgets('a pending approval lists its action, operation, goal, url, chat and waiting time', (tester) async {
    await _pump(tester, api: _FakeApi(approvals: [_approvalJson()]));

    expect(find.text('Waiting for your approval'), findsOneWidget);
    expect(find.text('Place order'), findsOneWidget);
    expect(find.text('Click'), findsOneWidget); // CLICK's friendly operation label
    expect(find.text('Goal: '), findsOneWidget);
    expect(find.text('Buy the blue mug in my cart'), findsOneWidget);
    expect(find.text('https://example.com/checkout.html'), findsOneWidget);
    expect(find.text('chat:123'), findsOneWidget);
    expect(find.text('Waiting 1m'), findsOneWidget); // 65s -> 1m
    expect(
        find.text('A browser task paused before this action. Approve only if you want SenClaw to do it.'),
        findsOneWidget);
  });

  testWidgets('an unrecognized operation is shown as is', (tester) async {
    await _pump(tester, api: _FakeApi(approvals: [_approvalJson(operation: 'SCROLL')]));
    expect(find.text('SCROLL'), findsOneWidget);
  });

  testWidgets('Approve confirms first, then POSTs approve:true and toasts the outcome', (tester) async {
    final api = await _pump(
      tester,
      api: _FakeApi(
        approvals: [_approvalJson()],
        approvalOutcome: {'task_id': 'task-1', 'status': 'done', 'message': 'Order placed'},
      ),
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Approve'));
    await tester.pumpAndSettle();
    expect(find.text('SenClaw will do this in the browser now.'), findsOneWidget);
    expect(api.called('POST /api/browser-agent/approvals/appr-1'), isFalse,
        reason: 'not sent until the confirm dialog itself is accepted');

    // Two "Approve" buttons exist once the dialog is open: the row's and the
    // dialog's — scope the tap to the dialog so it cannot hit the row one.
    await tester.tap(find.descendant(
        of: find.byType(AlertDialog), matching: find.widgetWithText(FilledButton, 'Approve')));
    await tester.pumpAndSettle();

    expect(api.called('POST /api/browser-agent/approvals/appr-1'), isTrue);
    expect(api.lastBody('POST /api/browser-agent/approvals/appr-1'), {'approve': true});
    expect(find.text('The task went on: done — Order placed'), findsOneWidget);
    expect(api.callCount('GET /api/browser-agent/approvals'), greaterThanOrEqualTo(2),
        reason: 'the list reloads afterwards');
  });

  testWidgets('Approve cancelled at the confirm dialog sends nothing', (tester) async {
    final api = await _pump(tester, api: _FakeApi(approvals: [_approvalJson()]));

    await tester.tap(find.widgetWithText(FilledButton, 'Approve'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(api.called('POST /api/browser-agent/approvals/appr-1'), isFalse);
  });

  testWidgets('Decline needs no confirm dialog; a decline that ends the task toasts Declined', (tester) async {
    final api = await _pump(
      tester,
      api: _FakeApi(
        approvals: [_approvalJson()],
        approvalOutcome: {'task_id': 'task-1', 'status': 'cancelled', 'message': 'stopped'},
      ),
    );

    await tester.tap(find.widgetWithText(OutlinedButton, 'Decline'));
    await tester.pumpAndSettle();

    expect(api.lastBody('POST /api/browser-agent/approvals/appr-1'), {'approve': false});
    expect(find.text('Declined'), findsOneWidget);
  });

  testWidgets('a decline the task survives (still needs_approval) shows the status message, not Declined',
      (tester) async {
    await _pump(
      tester,
      api: _FakeApi(
        approvals: [_approvalJson()],
        approvalOutcome: {'task_id': 'task-1', 'status': 'needs_approval', 'message': 'trying another way'},
      ),
    );

    await tester.tap(find.widgetWithText(OutlinedButton, 'Decline'));
    await tester.pumpAndSettle();

    expect(find.text('Declined'), findsNothing);
    expect(find.text('The task went on: needs_approval — trying another way'), findsOneWidget);
  });

  testWidgets('a decline after which the task waits for the person shows that status, not Declined', (tester) async {
    await _pump(
      tester,
      api: _FakeApi(
        approvals: [_approvalJson()],
        approvalOutcome: {'task_id': 'task-1', 'status': 'needs_user', 'message': 'a sign-in is needed'},
      ),
    );

    await tester.tap(find.widgetWithText(OutlinedButton, 'Decline'));
    await tester.pumpAndSettle();

    expect(find.text('Declined'), findsNothing);
    expect(find.text('The task went on: needs_user — a sign-in is needed'), findsOneWidget);
  });

  testWidgets('a POST error (e.g. 404 already answered) shows the daemon message and reloads', (tester) async {
    final api = await _pump(
      tester,
      api: _FakeApi(
        approvals: [_approvalJson()],
        approvalError: ApiException(404, 'Someone already answered this.', code: 'no_approval'),
      ),
    );

    await tester.tap(find.widgetWithText(OutlinedButton, 'Decline'));
    await tester.pumpAndSettle();

    expect(find.text('Someone already answered this.'), findsOneWidget);
    expect(api.callCount('GET /api/browser-agent/approvals'), greaterThanOrEqualTo(2));
  });
}
