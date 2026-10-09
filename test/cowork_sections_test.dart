import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:senclaw_desktop/core/config/app_config.dart';
import 'package:senclaw_desktop/core/i18n/l10n.dart';
import 'package:senclaw_desktop/core/transport/api_client.dart';
import 'package:senclaw_desktop/core/transport/connection.dart';
import 'package:senclaw_desktop/features/settings/claude_code_section.dart';
import 'package:senclaw_desktop/features/settings/sen_link_section.dart';
import 'package:senclaw_desktop/theme/app_theme.dart';

Map<String, dynamic> _ccSettings() => {
      'binary': 'claude',
      'model': null,
      'permissionMode': 'acceptEdits',
      'allowedTools': ['Bash', 'Read'],
      'maxTurns': 80,
      'maxBudgetUsd': 2.5,
      'verifyCommand': null,
      'verifyTimeoutSecs': 900,
      'maxStopBlocks': 3,
      'review': true,
      'maxFixRounds': 2,
      'mcpChatJid': null,
    };

Map<String, dynamic> _slSettings({bool enabled = false}) => {
      'enabled': enabled,
      'name': 'SenClaw',
      'description': 'A SenClaw personal agent',
      'publicUrl': null,
      'boardTitle': 'sen-link',
      'workspaceDir': null,
      'defaultAssignee': null,
    };

/// Serves `/api/claude-code/*` and `/api/sen-link/*`, recording what was sent.
class _FakeApi implements ApiClient {
  _FakeApi({this.installed = true, this.linkEnabled = false});
  final bool installed;
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
      '/api/claude-code/status' => {
          'binary': 'claude',
          'installed': installed,
          'version': installed ? '2.1.243 (Claude Code)' : null,
          'assignee': 'claude-code',
          'mcp': {
            'endpoints': ['http://127.0.0.1:18788/mcp/core'],
            'tokenFile': '/home/u/.senclaw/api_token',
            'addCommands': ['claude mcp add --transport http senclaw-core http://127.0.0.1:18788/mcp/core'],
          },
        },
      '/api/claude-code/settings' => _ccSettings(),
      '/api/claude-code/runs' => {
          'runs': [
            {'runId': 'r1', 'itemId': '7', 'phase': 'blocked', 'lastActivity': 'tool: Bash', 'costUsd': 0.42, 'fixRound': 2},
          ]
        },
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
    if (path == '/api/sen-link/invites') return {'code': 'K7MQ2XRP', 'expiresAt': 1791600000, 'url': null};
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

/// Unmount so the section's poll timer is cancelled before the test ends.
Future<void> _unmount(WidgetTester tester) => tester.pumpWidget(const SizedBox());

void main() {
  testWidgets('Claude Code: status, MCP commands, runs, and a save that keeps hidden fields', (tester) async {
    final fake = _FakeApi();
    await _pump(tester, fake, const ClaudeCodeSection());
    expect(tester.takeException(), isNull);
    expect(find.textContaining('2.1.243 (Claude Code)'), findsOneWidget);
    expect(find.textContaining('claude mcp add --transport http senclaw-core'), findsOneWidget);
    expect(find.text('#7'), findsOneWidget);
    expect(find.text('blocked'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('cc-verify')), 'cargo test');
    await tester.tap(find.byKey(const Key('cc-save')));
    await tester.pumpAndSettle();
    final put = fake.calls.lastWhere((c) => c.$1 == 'PUT /api/claude-code/settings').$2 as Map;
    expect(put['verifyCommand'], 'cargo test');
    // Not on the form, still sent back unchanged (PUT replaces the block).
    expect(put['maxBudgetUsd'], 2.5);
    expect(put['maxStopBlocks'], 3);
    await _unmount(tester);
  });

  testWidgets('Claude Code: a missing binary says how to install it', (tester) async {
    await _pump(tester, _FakeApi(installed: false), const ClaudeCodeSection());
    expect(find.textContaining('Install Claude Code'), findsOneWidget);
    await _unmount(tester);
  });

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

  test('task states read as words', () {
    expect(taskStateLabel('TASK_STATE_INPUT_REQUIRED'), 'input required');
  });
}
