// The Apps tab of a peer row: which Space Apps a peer may sync with, per
// collection and direction. A stand-in daemon keeps the policy the way the real
// one does (what was saved is what comes back), so these show what a person can
// and cannot do: nothing syncs until a collection is opened and saved, passwords
// need a confirmation, and a held change waits until it is approved here.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:senclaw_desktop/core/config/app_config.dart';
import 'package:senclaw_desktop/core/i18n/l10n.dart';
import 'package:senclaw_desktop/core/transport/api_client.dart';
import 'package:senclaw_desktop/core/transport/connection.dart';
import 'package:senclaw_desktop/features/settings/sen_link_apps.dart';
import 'package:senclaw_desktop/features/settings/sen_link_section.dart';
import 'package:senclaw_desktop/theme/app_theme.dart';

Future<bool> _loadRealFont() async {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root == null) return false;
  final dir = Directory('$root/bin/cache/artifacts/material_fonts');
  if (!dir.existsSync()) return false;
  final loader = FontLoader('Roboto');
  for (final weight in ['Regular', 'Medium', 'Bold']) {
    final f = File('${dir.path}/Roboto-$weight.ttf');
    if (f.existsSync()) loader.addFont(Future.value(f.readAsBytesSync().buffer.asByteData()));
  }
  await loader.load();
  return true;
}

const _collections = [
  {'id': 'keychain', 'schemaVersion': 1, 'secretFields': ['value'], 'localFields': <String>[], 'matchKey': ['name'], 'guardFields': <String>[]},
  {'id': 'hosts', 'schemaVersion': 1, 'secretFields': ['password'], 'localFields': <String>[], 'matchKey': ['host'], 'guardFields': ['host']},
  {'id': 'port_forwarding', 'schemaVersion': 1, 'secretFields': <String>[], 'localFields': ['active'], 'matchKey': <String>[], 'guardFields': <String>[]},
  {'id': 'snippets', 'schemaVersion': 1, 'secretFields': <String>[], 'localFields': <String>[], 'matchKey': ['name'], 'guardFields': <String>[]},
];

/// A daemon with one peer and one syncable app. Remembers what it was asked.
class _Daemon implements ApiClient {
  Map<String, dynamic> policy = {'collections': <String, dynamic>{}, 'secrets': false, 'adoptMatches': false};
  List<Map<String, dynamic>> pending = [];
  final puts = <Map<String, dynamic>>[];
  final posts = <(String, Map<String, dynamic>)>[];
  bool held = true;

  @override
  void updateConfig(AppConfig config) {}
  @override
  void dispose() {}

  Map<String, dynamic> get _peer => {
        'id': 'p1', 'name': 'beta', 'addr': '192.168.0.93:18791', 'canSend': true, 'autoRun': false,
        'assignee': null, 'legacy': false, 'online': true, 'createdAt': '2026-10-22T00:00:00Z',
        'knowledge': {'facts': false, 'notes': false, 'profiles': <String>[], 'noteTypes': <String>[]},
        'appSync': (policy['collections'] as Map).isEmpty ? <String, dynamic>{} : {'ssh-manager': policy},
      };

  Map<String, dynamic> get _view => {
        'app': 'ssh-manager', 'version': '1.3.0', 'syncVersion': 1, 'collections': _collections,
        'policy': policy, 'status': {'pending': pending, 'last': null},
      };

  @override
  Future<dynamic> get(String path, {Map<String, dynamic>? query, Duration? timeout}) async => switch (path) {
        '/api/sen-link/status' => {
            'settings': {
              'enabled': true, 'name': 'alpha', 'description': '', 'listenHost': '0.0.0.0', 'listenPort': 18791,
              'discoverable': true, 'boardTitle': 'SLink', 'workspaceDir': null, 'defaultAssignee': null,
            },
            'agentCard': {}, 'daemonId': 'x', 'peerCount': 1, 'listening': '0.0.0.0:18791', 'listenError': null,
            'addresses': ['192.168.1.20'], 'migrated': <String>[],
            'discovery': {'browsing': true, 'advertising': true, 'error': null},
          },
        '/api/sen-link/discovered' => {'discovered': <Object>[], 'browsing': true, 'advertising': true, 'error': null},
        '/api/sen-link/peers' => {'peers': [_peer]},
        '/api/sen-link/peers/p1/app-sync' => {
            'apps': [_view],
            'remote': {
              'apps': [
                {'app': 'ssh-manager', 'version': '1.3.0', 'syncVersion': 1, 'collections': ['hosts']}
              ]
            },
          },
        _ => <String, dynamic>{},
      };

  @override
  Future<dynamic> put(String path, {Object? body}) async {
    final b = (body as Map).cast<String, dynamic>();
    puts.add(b);
    final p = (b['policy'] as Map).cast<String, dynamic>();
    policy = {
      'collections': {for (final e in (p['collections'] as Map).entries) if (e.value != 'off') e.key: e.value},
      'secrets': p['secrets'] == true,
      'adoptMatches': p['adoptMatches'] == true,
    };
    return _view;
  }

  @override
  Future<dynamic> post(String path, {Object? body, Duration? timeout}) async {
    final b = ((body ?? const <String, dynamic>{}) as Map).cast<String, dynamic>();
    posts.add((path, b));
    final dry = path.endsWith('/preview');
    final approved = (b['approve'] as List? ?? const []).isNotEmpty;
    if (!dry && approved) held = false;
    final heldNow = held
        ? [
            {'collection': 'hosts', 'id': '22222222-bbbb', 'reason': 'credential_target_changed', 'name': 'web', 'from': 'pull'}
          ]
        : <Map<String, dynamic>>[];
    if (!dry) pending = heldNow;
    final pull = [
      {'collection': 'hosts', 'id': '11111111-aaaa', 'status': 'added'},
      if (held) {'collection': 'hosts', 'id': '22222222-bbbb', 'status': 'held', 'reason': 'credential_target_changed'},
      {'collection': 'snippets', 'id': '44444444-dddd', 'status': 'unchanged'},
    ];
    return {
      'app': 'ssh-manager', 'peer': {'id': 'p1', 'name': 'beta'}, 'dryRun': dry,
      'plan': [
        for (final c in _collections)
          {
            'collection': c['id'],
            'pull': (policy['collections'] as Map)[c['id']] is String && ['receive', 'both'].contains((policy['collections'] as Map)[c['id']]),
            'push': (policy['collections'] as Map)[c['id']] is String && ['send', 'both'].contains((policy['collections'] as Map)[c['id']]),
            'why': (policy['collections'] as Map)[c['id']] == null ? 'off_here' : null,
          }
      ],
      'pull': {'dryRun': dry, 'results': pull, 'summary': {'added': 1, if (held) 'held': 1, 'unchanged': 1}},
      'push': {'dryRun': dry, 'results': <Object>[], 'summary': <String, dynamic>{}},
      'held': heldNow,
    };
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _app(_Daemon api, Widget home, {String lang = 'en'}) => ProviderScope(
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
        home: Scaffold(body: SingleChildScrollView(child: home)),
      ),
    );

Finder _dir(String collection, String label) => find.descendant(of: find.byKey(ValueKey('sl-a-dir-ssh-manager-$collection')), matching: find.text(label));

bool _enabled(WidgetTester tester, String key) => tester.widget<ButtonStyleButton>(find.byKey(ValueKey(key))).onPressed != null;

void main() {
  setUpAll(() async {
    if (!await _loadRealFont()) fail('Roboto not found under FLUTTER_ROOT — cannot measure real layout');
  });

  testWidgets('nothing syncs until a collection is opened and saved, and passwords need a confirmation', (tester) async {
    tester.view.physicalSize = const Size(1100, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final api = _Daemon();
    await tester.pumpWidget(_app(api, SenLinkAppsPanel(peerId: 'p1', peerName: 'beta', canSend: true, onChanged: () {})));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('sl-a-closed-ssh-manager')), findsOneWidget);
    expect(find.text('beta has opened it'), findsOneWidget);
    expect(_enabled(tester, 'sl-a-preview-ssh-manager'), isFalse, reason: 'nothing is open');
    expect(_enabled(tester, 'sl-a-save-ssh-manager'), isFalse);

    await tester.tap(_dir('hosts', 'Both'));
    await tester.tap(_dir('keychain', 'Receive'));
    await tester.pumpAndSettle();
    expect(_enabled(tester, 'sl-a-save-ssh-manager'), isTrue);
    expect(_enabled(tester, 'sl-a-preview-ssh-manager'), isFalse, reason: 'unsaved choices are not synced');

    await tester.tap(find.byKey(const ValueKey('sl-a-save-ssh-manager')));
    await tester.pumpAndSettle();
    expect(api.puts.single['policy']['collections'], {'hosts': 'both', 'keychain': 'receive'});
    expect(api.puts.single['confirmSecrets'], false);
    expect(find.byKey(const ValueKey('sl-a-closed-ssh-manager')), findsNothing);
    expect(_enabled(tester, 'sl-a-preview-ssh-manager'), isTrue);

    // Passwords: a dialog names what would cross; only then is the switch on and the save confirmed.
    await tester.tap(find.byKey(const ValueKey('sl-a-secrets-ssh-manager')));
    await tester.pumpAndSettle();
    expect(find.text('Send passwords and keys to beta?'), findsOneWidget);
    expect(find.textContaining('hosts: password'), findsOneWidget);
    await tester.tap(find.byKey(const Key('sl-a-secrets-cancel')));
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(find.byKey(const ValueKey('sl-a-secrets-ssh-manager'))).value, isFalse);

    await tester.tap(find.byKey(const ValueKey('sl-a-secrets-ssh-manager')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sl-a-secrets-allow')));
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(find.byKey(const ValueKey('sl-a-secrets-ssh-manager'))).value, isTrue);
    await tester.tap(find.byKey(const ValueKey('sl-a-save-ssh-manager')));
    await tester.pumpAndSettle();
    expect(api.puts.last['confirmSecrets'], true);
    expect(api.puts.last['policy']['secrets'], true);
  });

  testWidgets('a preview shows both sides, and a held change waits for the person who approves it', (tester) async {
    tester.view.physicalSize = const Size(1100, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final api = _Daemon()..policy = {'collections': {'hosts': 'both'}, 'secrets': false, 'adoptMatches': false};
    await tester.pumpWidget(_app(api, SenLinkAppsPanel(peerId: 'p1', peerName: 'beta', canSend: true, onChanged: () {})));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('sl-a-preview-ssh-manager')));
    await tester.pumpAndSettle();
    expect(api.posts.single.$1, endsWith('/app-sync/ssh-manager/preview'));
    expect(find.text('Preview: nothing was changed'), findsOneWidget);
    expect(find.byKey(const ValueKey('sl-a-pull-ssh-manager')), findsOneWidget);
    expect(find.textContaining('added 1'), findsWidgets);
    expect(find.text('Would send a saved password or key to a different address'), findsWidgets);

    await tester.tap(find.byKey(const ValueKey('sl-a-run-ssh-manager')));
    await tester.pumpAndSettle();
    expect(api.posts.last.$1, endsWith('/app-sync/ssh-manager/run'));
    expect(api.posts.last.$2, isEmpty, reason: 'a plain sync approves nothing');
    final approve = find.byKey(const ValueKey('sl-a-approve-hosts-22222222-bbbb'));
    expect(approve, findsOneWidget);

    await tester.tap(approve);
    await tester.pumpAndSettle();
    expect(find.text('Apply this change?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('sl-a-approve-yes')));
    await tester.pumpAndSettle();
    expect(api.posts.last.$2['approve'], [
      {'collection': 'hosts', 'id': '22222222-bbbb'}
    ]);
    expect(find.byKey(const ValueKey('sl-a-approve-hosts-22222222-bbbb')), findsNothing, reason: 'nothing waits any more');
  });

  test('every string of the apps panel, and of what it added to the peer row, has a Vietnamese entry', () {
    const vi = L10n('vi');
    final keys = _keysIn(File('lib/features/settings/sen_link_apps.dart').readAsStringSync());
    keys.addAll(_keysIn(File('lib/features/settings/sen_link_section.dart').readAsStringSync()).where((k) => k == 'syncs apps' || k.startsWith('Some apps are open')));
    keys.addAll(['Apps']);
    expect(keys.length, greaterThan(40));
    final missing = [for (final k in keys) if (vi.t(k) == k) k];
    expect(missing, isEmpty, reason: missing.join('\n'));
    for (final key in keys.where((k) => k.contains('{'))) {
      final want = RegExp(r'\{(\w+)\}').allMatches(key).map((m) => m[1]).toSet();
      final got = RegExp(r'\{(\w+)\}').allMatches(vi.t(key)).map((m) => m[1]).toSet();
      expect(got, want, reason: '$key → ${vi.t(key)}');
    }
  });

  for (final lang in ['en', 'vi']) {
    for (final width in [1100.0, 900.0]) {
      testWidgets('the apps tab lays out in $lang at ${width.toInt()}px, report and held change included', (tester) async {
        tester.view.physicalSize = Size(width, 2600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
        final api = _Daemon()..policy = {'collections': {'hosts': 'both', 'keychain': 'receive'}, 'secrets': true, 'adoptMatches': true};
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
            home: const Scaffold(body: SenLinkSection()),
          ),
        ));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('sl-expand-p1')));
        await tester.pumpAndSettle();
        await tester.tap(find.descendant(of: find.byKey(const ValueKey('sl-tabs-p1')), matching: find.text(lang == 'vi' ? 'Ứng dụng' : 'Apps')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('sl-a-run-ssh-manager')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byKey(const ValueKey('sl-a-report-ssh-manager')), findsOneWidget);
        expect(find.byKey(const ValueKey('sl-a-approve-hosts-22222222-bbbb')), findsOneWidget);
        expect(find.byKey(const Key('sl-syncs-apps')), findsOneWidget);
      });
    }
  }
}

String _unquote(String token) {
  final body = token.substring(1, token.length - 1);
  return body.replaceAllMapped(RegExp(r'\\(.)'), (m) => m[1] == 'n' ? '\n' : m[1]!);
}

Set<String> _keysIn(String source) {
  final keys = <String>{};
  final call = RegExp(r'\.(?:tr|trArgs)\(\s*');
  final literal = RegExp(r"""\s*('(?:[^'\\]|\\.)*'|"(?:[^"\\]|\\.)*")""");
  for (final m in call.allMatches(source)) {
    var at = m.end;
    final parts = <String>[];
    for (;;) {
      final l = literal.matchAsPrefix(source, at);
      if (l == null) break;
      parts.add(_unquote(l.group(1)!));
      at = l.end;
    }
    if (parts.isNotEmpty) keys.add(parts.join());
  }
  return keys;
}
