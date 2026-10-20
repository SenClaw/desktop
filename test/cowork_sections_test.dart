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
      'listenHost': '0.0.0.0',
      'listenPort': 18791,
      'discoverable': true,
      'boardTitle': 'SLink',
      'workspaceDir': null,
      'defaultAssignee': null,
    };

/// Serves `/api/sen-link/*`, recording what was sent.
class _FakeApi implements ApiClient {
  _FakeApi({this.linkEnabled = false, this.migrated = const [], this.listenError});
  bool linkEnabled;
  final List<String> migrated;
  final String? listenError;
  Map<String, dynamic> probeReply = {
    'ok': true,
    'code': 'ok',
    'addr': 'mac-mini.local:18791',
    'resolved': ['192.168.1.20'],
    'reachable': true,
    'hidden': false,
    'card': {'name': 'Mac mini', 'version': '0.2.0', 'daemonId': '6f1c-0a', 'pairable': true},
    'error': null,
  };
  final calls = <(String, Object?)>[];
  List<Map<String, dynamic>> peers = [
    {
      'id': 'p1',
      'name': 'SenClaw B',
      'addr': '192.168.1.9:18788',
      'canSend': true,
      'autoRun': false,
      'assignee': null,
      'legacy': true,
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
      '/api/sen-link/status' => {
          'settings': _slSettings(enabled: linkEnabled),
          'agentCard': {},
          'daemonId': '6f1c-aa',
          'peerCount': peers.length,
          'listening': linkEnabled && listenError == null ? '0.0.0.0:18791' : null,
          'listenError': listenError,
          'addresses': ['192.168.1.20', 'fd7a:115c:a1e0::5'],
          'migrated': migrated,
        },
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
      return {
        'code': 'K7MQ2XRP',
        'expiresAt': 1791600000,
        'port': 18791,
        'addresses': ['192.168.1.20', 'fd7a:115c:a1e0::5'],
        'listening': listenError == null,
        'listenError': listenError,
      };
    }
    if (path == '/api/sen-link/probe') return probeReply;
    if (path == '/api/sen-link/peers/pair') return {...peers.first, 'name': 'SenClaw C', 'addr': 'mac-mini.local:18791', 'legacy': false};
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
  testWidgets('SLink: invites need SLink on, and auto-run asks first', (tester) async {
    final fake = _FakeApi(linkEnabled: false);
    await _pump(tester, fake, const SenLinkSection());
    expect(find.text('Enable SLink and save first.'), findsOneWidget);
    final invite = tester.widget<OutlinedButton>(find.byKey(const Key('sl-invite')));
    expect(invite.onPressed, isNull);
    expect(find.text('SenClaw B'), findsOneWidget);
    expect(find.byKey(const Key('sl-legacy')), findsOneWidget, reason: 'a peer paired by an older version is marked');
    expect(find.byKey(const Key('sl-listening')), findsNothing, reason: 'off: no listening line');

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

  testWidgets('SLink: an enabled daemon shows where it listens and hands out an invite code with the address to type', (tester) async {
    final fake = _FakeApi(linkEnabled: true);
    await _pump(tester, fake, const SenLinkSection());
    expect(find.text('Listening on 0.0.0.0:18791'), findsOneWidget);
    // This machine's addresses, IPv6 in brackets.
    expect(find.text('192.168.1.20:18791'), findsOneWidget);
    expect(find.text('[fd7a:115c:a1e0::5]:18791'), findsOneWidget);

    await tester.tap(find.byKey(const Key('sl-invite')));
    await tester.pumpAndSettle();
    expect(find.text('K7MQ2XRP'), findsOneWidget);
    expect(find.text('Type this on the other SenClaw:'), findsOneWidget);
    expect(find.text('192.168.1.20:18791'), findsNWidgets(2), reason: 'once in settings, once beside the invite');
    await _unmount(tester);
  });

  testWidgets('SLink: a listener that failed says why, and the invite warns', (tester) async {
    final fake = _FakeApi(linkEnabled: true, listenError: 'cannot listen on 0.0.0.0:18791: port already in use');
    await _pump(tester, fake, const SenLinkSection());
    expect(find.text('cannot listen on 0.0.0.0:18791: port already in use'), findsOneWidget);
    await tester.tap(find.byKey(const Key('sl-invite')));
    await tester.pumpAndSettle();
    expect(find.text('cannot listen on 0.0.0.0:18791: port already in use'), findsNWidgets(2));
    await _unmount(tester);
  });

  testWidgets('SLink: a typed IP or name is checked, then paired with the code', (tester) async {
    final fake = _FakeApi(linkEnabled: true);
    await _pump(tester, fake, const SenLinkSection());

    // Pair needs both an address and a code; Check needs the address.
    expect(tester.widget<FilledButton>(find.byKey(const Key('sl-pair'))).onPressed, isNull);
    expect(tester.widget<OutlinedButton>(find.byKey(const Key('sl-check'))).onPressed, isNull);
    await tester.enterText(find.byKey(const Key('sl-pair-addr')), ' mac-mini.local ');
    await tester.pump();
    await tester.tap(find.byKey(const Key('sl-check')));
    await tester.pumpAndSettle();
    expect(fake.calls.lastWhere((c) => c.$1 == 'POST /api/sen-link/probe').$2, {'addr': 'mac-mini.local'});
    expect(find.textContaining('Found Mac mini at mac-mini.local:18791'), findsOneWidget);
    expect(find.textContaining('192.168.1.20'), findsWidgets);

    await tester.enterText(find.byKey(const Key('sl-pair-code')), 'K7MQ2XRP');
    await tester.pump();
    await tester.tap(find.byKey(const Key('sl-pair')));
    await tester.pumpAndSettle();
    final pair = fake.calls.lastWhere((c) => c.$1 == 'POST /api/sen-link/peers/pair');
    expect(pair.$2, {'addr': 'mac-mini.local', 'code': 'K7MQ2XRP'});
    expect(find.textContaining('Found Mac mini'), findsNothing, reason: 'the check result is cleared once paired');
    await _unmount(tester);
  });

  testWidgets('SLink: a check that fails shows the daemon\'s reason; a peer without an invite says so', (tester) async {
    final fake = _FakeApi(linkEnabled: true)
      ..probeReply = {
        'ok': false,
        'code': 'not_lan',
        'addr': '8.8.8.8:18791',
        'resolved': ['8.8.8.8'],
        'reachable': false,
        'hidden': false,
        'card': null,
        'error': '8.8.8.8:18791 points outside the LAN (8.8.8.8); SLink only talks to private-network addresses',
      };
    await _pump(tester, fake, const SenLinkSection());
    await tester.enterText(find.byKey(const Key('sl-pair-addr')), '8.8.8.8');
    await tester.pump();
    await tester.tap(find.byKey(const Key('sl-check')));
    await tester.pumpAndSettle();
    expect(find.textContaining('points outside the LAN'), findsOneWidget);

    fake.probeReply = {
      ...fake.probeReply,
      'ok': true,
      'code': 'ok',
      'reachable': true,
      'error': null,
      'card': {'name': 'Mac mini', 'version': '0.2.0', 'daemonId': '6f1c-0a', 'pairable': false},
    };
    await tester.tap(find.byKey(const Key('sl-check')));
    await tester.pumpAndSettle();
    expect(find.textContaining('It has no invite right now'), findsOneWidget);

    fake.probeReply = {...fake.probeReply, 'card': null, 'hidden': true};
    await tester.tap(find.byKey(const Key('sl-check')));
    await tester.pumpAndSettle();
    expect(find.textContaining('hides its name'), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('SLink: saving sends the listener settings and none of the hub-era keys', (tester) async {
    final fake = _FakeApi(linkEnabled: true);
    await _pump(tester, fake, const SenLinkSection());
    await tester.enterText(find.byKey(const Key('sl-listen-port')), '19000');
    await tester.tap(find.byKey(const Key('sl-discoverable')));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('sl-save')));
    await tester.tap(find.byKey(const Key('sl-save')));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    final put = fake.calls.lastWhere((c) => c.$1 == 'PUT /api/sen-link/settings').$2 as Map;
    expect(put['listenPort'], 19000);
    expect(put['listenHost'], '0.0.0.0');
    expect(put['discoverable'], false);
    expect(put['enabled'], true);
    expect(put.containsKey('publicUrl'), isFalse);
    expect(put.containsKey('hubUrl'), isFalse);
    expect(fake.calls.where((c) => c.$1 == 'GET /api/sen-link/status').length, 2, reason: 'the status is read again after the save');

    // A port that is not a port is refused on the spot, nothing is sent.
    ScaffoldMessenger.of(tester.element(find.byType(Scaffold).first)).clearSnackBars();
    await tester.pump(const Duration(milliseconds: 300));
    final before = fake.calls.where((c) => c.$1.startsWith('PUT')).length;
    await tester.enterText(find.byKey(const Key('sl-listen-port')), '70000');
    await tester.ensureVisible(find.byKey(const Key('sl-save')));
    await tester.tap(find.byKey(const Key('sl-save')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(fake.calls.where((c) => c.$1.startsWith('PUT')).length, before);
    expect(find.text('Listen port must be 1-65535.'), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('SLink: peers removed because only a hub reached them are announced, and the notice can be closed', (tester) async {
    final fake = _FakeApi(linkEnabled: true, migrated: ['Mac mini', 'Office PC']);
    await _pump(tester, fake, const SenLinkSection());
    expect(find.textContaining('Mac mini, Office PC'), findsOneWidget);
    await tester.tap(find.byKey(const Key('sl-migrated-close')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Mac mini, Office PC'), findsNothing);
    await _unmount(tester);
  });

  test('task states read as words', () {
    expect(taskStateLabel('TASK_STATE_INPUT_REQUIRED'), 'input required');
  });
}
