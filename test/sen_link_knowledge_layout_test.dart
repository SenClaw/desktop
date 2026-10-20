// The knowledge panel in a peer row, rendered with a real font in both
// languages and at a narrow width: Vietnamese is longer than English, and a
// machine can have many profile folders (every scheduled chat has one).

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

/// A daemon with one peer that shares, forty profile folders and a long answer.
class _Api implements ApiClient {
  final profiles = ['main', 'other', for (var i = 0; i < 38; i++) 'schedule_${i}b2c3d4e5-6789-4abc-8def-0123456789ab'];

  @override
  void updateConfig(AppConfig config) {}
  @override
  void dispose() {}

  @override
  Future<dynamic> get(String path, {Map<String, dynamic>? query, Duration? timeout}) async => switch (path) {
        '/api/sen-link/status' => {
            'settings': {
              'enabled': true, 'name': 'SenClaw', 'description': '', 'listenHost': '0.0.0.0', 'listenPort': 18791,
              'discoverable': true, 'boardTitle': 'SLink', 'workspaceDir': null, 'defaultAssignee': null,
            },
            'agentCard': {}, 'daemonId': 'x', 'peerCount': 1, 'listening': '0.0.0.0:18791', 'listenError': null,
            'addresses': ['192.168.1.20'], 'migrated': <String>[],
            'discovery': {'browsing': true, 'advertising': true, 'error': null},
          },
        '/api/sen-link/discovered' => {'discovered': <Object>[], 'browsing': true, 'advertising': true, 'error': null},
        '/api/sen-link/peers' => {'peers': [_peer]},
        '/api/sen-link/peers/p1/knowledge' => {
            'policy': _peer['knowledge'],
            'preview': {
              'open': true,
              'profiles': [
                {
                  'profile': 'main', 'exists': true, 'facts': 12, 'notes': {'project': 4, 'reference': 30, 'feedback': 2},
                  'samples': ['Cách trả phí bến cảng hằng quý của văn phòng', 'Kế hoạch ra mắt quý bốn'],
                  'excluded': {'dailyLogs': 92, 'conversationSummaries': 126, 'aboutTheOwner': 3, 'writtenInOneChat': 11, 'otherTypes': 5},
                }
              ],
            },
            'profiles': profiles,
            'noteTypes': ['project', 'reference', 'feedback'],
          },
        _ => <String, dynamic>{},
      };

  static const Map<String, dynamic> _peer = {
    'id': 'p1', 'name': 'MacBook của Benji', 'addr': '192.168.0.93:18791', 'canSend': true, 'autoRun': true,
    'assignee': null, 'legacy': false, 'online': true, 'createdAt': '2026-10-20T00:00:00Z',
    'knowledge': {'facts': true, 'notes': true, 'profiles': ['main'], 'noteTypes': ['project', 'reference']},
  };

  @override
  Future<dynamic> post(String path, {Object? body, Duration? timeout}) async => {
        'v': 1, 'from': 'MacBook của Benji', 'untrusted': true, 'truncated': true,
        'hits': [
          {'kind': 'note', 'profile': 'main', 'title': 'Cách trả phí bến cảng hằng quý của văn phòng', 'type': 'reference', 'when': '2026-07-12', 'text': 'Phí bến cảng được trả hằng quý bởi quản lý văn phòng. ' * 8},
        ],
      };

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUpAll(() async {
    if (!await _loadRealFont()) fail('Roboto not found under FLUTTER_ROOT — cannot measure real layout');
  });

  for (final lang in ['en', 'vi']) {
    for (final width in [1100.0, 900.0]) {
      testWidgets('the knowledge panel lays out in $lang at ${width.toInt()}px', (tester) async {
        tester.view.physicalSize = Size(width, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(ProviderScope(
          overrides: [apiClientProvider.overrideWithValue(_Api())],
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
        await tester.tap(find.descendant(of: find.byKey(const ValueKey('sl-tabs-p1')), matching: find.text(lang == 'vi' ? 'Tri thức' : 'Knowledge')));
        await tester.pumpAndSettle();
        await tester.enterText(find.byKey(const Key('sl-k-question')), 'phí bến');
        await tester.tap(find.byKey(const Key('sl-k-ask')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byKey(const ValueKey('sl-k-hit-0')), findsOneWidget);
        expect(find.byKey(const ValueKey('sl-k-preview-main')), findsOneWidget);
        expect(find.byKey(const Key('sl-shares')), findsOneWidget);
        expect(find.text(lang == 'vi' ? 'Chia sẻ ghi chú' : 'Share notes'), findsOneWidget);
      });
    }
  }
}
