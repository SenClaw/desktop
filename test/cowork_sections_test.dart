import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:senclaw_desktop/core/config/app_config.dart';
import 'package:senclaw_desktop/core/i18n/l10n.dart';
import 'package:senclaw_desktop/core/transport/api_client.dart';
import 'package:senclaw_desktop/core/transport/connection.dart';
import 'package:senclaw_desktop/features/settings/sen_link_section.dart';
import 'package:senclaw_desktop/theme/app_theme.dart';

Map<String, dynamic> _slSettings({bool enabled = false}) => {
      'enabled': enabled,
      'name': 'SenClaw',
      'description': 'A SenClaw personal agent',
      'publicUrl': null,
      'boardTitle': 'sen-link',
      'workspaceDir': null,
      'defaultAssignee': null,
    };

/// Serves `/api/sen-link/*`, recording what was sent.
class _FakeApi implements ApiClient {
  _FakeApi({this.linkEnabled = false, this.hub = false});
  final bool hub;
  bool linkEnabled;
  final calls = <(String, Object?)>[];
  List<Map<String, dynamic>> peers = [
    {
      'id': 'p1',
      'name': 'SenClaw B',
      'url': 'http://100.64.0.3:18788',
      'canSend': true,
      'autoRun': false,
      'assignee': null,
      'createdAt': '2026-10-10T00:00:00Z',
    }
  ];

  @override
  void updateConfig(AppConfig config) {}

  @override
  void dispose() {}

  @override
  Future<dynamic> get(String path, {Map<String, dynamic>? query, Duration? timeout}) async {
    calls.add(('GET $path', null));
    return switch (path) {
      '/api/sen-link/status' => {'settings': _slSettings(enabled: linkEnabled), 'agentCard': {}, 'peerCount': peers.length},
      '/api/sen-link/peers' => {'peers': peers},
      _ => <String, dynamic>{},
    };
  }

  @override
  Future<dynamic> put(String path, {Object? body}) async {
    calls.add(('PUT $path', body));
    return body;
  }

  @override
  Future<dynamic> patch(String path, {Object? body}) async {
    calls.add(('PATCH $path', body));
    final p = {...peers.first, ...(body as Map).cast<String, dynamic>()};
    peers = [p];
    return p;
  }

  @override
  Future<dynamic> post(String path, {Object? body, Duration? timeout}) async {
    calls.add(('POST $path', body));
    if (path == '/api/sen-link/invites') {
      return {'code': 'K7MQ2XRP', 'expiresAt': 1791600000, 'url': null, 'connect': hub ? 'senlink:eyJodWIiOiJodHRw' : null};
    }
    if (path == '/api/sen-link/peers/pair') return {...peers.first, 'name': 'SenClaw C', 'viaRelay': true};
    return <String, dynamic>{};
  }

  @override
  Future<dynamic> delete(String path, {Object? body}) async {
    calls.add(('DELETE $path', body));
    return null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pump(WidgetTester tester, _FakeApi fake, Widget section) async {
  tester.view.physicalSize = const Size(1400, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
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
      home: Scaffold(body: section),
    ),
  ));
  await tester.pumpAndSettle();
}

/// Unmount at the end of each test.
Future<void> _unmount(WidgetTester tester) => tester.pumpWidget(const SizedBox());

void main() {
  testWidgets('sen-link: invites need sen-link on, and auto-run asks first', (tester) async {
    final fake = _FakeApi(linkEnabled: false);
    await _pump(tester, fake, const SenLinkSection());
    expect(find.text('Enable sen-link and save first.'), findsOneWidget);
    final invite = tester.widget<OutlinedButton>(find.byKey(const Key('sl-invite')));
    expect(invite.onPressed, isNull);
    expect(find.text('SenClaw B'), findsOneWidget);

    // Turning auto-run on is confirmed, then PATCHed.
    await tester.tap(find.byType(Switch).last);
    await tester.pumpAndSettle();
    expect(find.textContaining('shell on this machine'), findsOneWidget);
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    final patch = fake.calls.lastWhere((c) => c.$1.startsWith('PATCH'));
    expect(patch.$1, 'PATCH /api/sen-link/peers/p1');
    expect((patch.$2 as Map)['autoRun'], true);
    await _unmount(tester);
  });

  testWidgets('sen-link: an enabled daemon hands out an invite code', (tester) async {
    final fake = _FakeApi(linkEnabled: true);
    await _pump(tester, fake, const SenLinkSection());
    await tester.tap(find.byKey(const Key('sl-invite')));
    await tester.pumpAndSettle();
    expect(find.text('K7MQ2XRP'), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('sen-link: a hub invite shows its connection string, and one pairs a peer', (tester) async {
    final fake = _FakeApi(linkEnabled: true, hub: true);
    await _pump(tester, fake, const SenLinkSection());
    await tester.tap(find.byKey(const Key('sl-invite')));
    await tester.pumpAndSettle();
    expect(find.text('senlink:eyJodWIiOiJodHRw'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('sl-connect')), 'senlink:abc');
    await tester.tap(find.byKey(const Key('sl-pair-hub')));
    await tester.pumpAndSettle();
    final pair = fake.calls.lastWhere((c) => c.$1 == 'POST /api/sen-link/peers/pair');
    expect(pair.$2, {'connect': 'senlink:abc'});
    await _unmount(tester);
  });

  test('task states read as words', () {
    expect(taskStateLabel('TASK_STATE_INPUT_REQUIRED'), 'input required');
  });
}
