// The running core's version, and the warning when the app adopted a daemon
// that is another build than the core in its own bundle.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:senclaw_desktop/core/config/app_config.dart';
import 'package:senclaw_desktop/core/daemon/core_version.dart';
import 'package:senclaw_desktop/core/daemon/daemon_provider.dart';
import 'package:senclaw_desktop/core/daemon/daemon_supervisor.dart';
import 'package:senclaw_desktop/core/i18n/l10n.dart';
import 'package:senclaw_desktop/core/transport/api_client.dart';
import 'package:senclaw_desktop/core/transport/connection.dart';
import 'package:senclaw_desktop/core/update/update_manifest.dart';
import 'package:senclaw_desktop/features/settings/core_version_card.dart';
import 'package:senclaw_desktop/theme/app_theme.dart';
import 'package:senclaw_desktop/widgets/core_mismatch_banner.dart';

import 'support/i18n_keys.dart';

/// A supervisor frozen in one phase; nothing is spawned or probed.
class _Supervisor extends DaemonSupervisor {
  _Supervisor(this._fixed);
  final DaemonPhase _fixed;
  @override
  DaemonPhase get phase => _fixed;
  @override
  bool get isUp => _fixed == DaemonPhase.running || _fixed == DaemonPhase.adopted;
}

/// Answers `/api/system/version` like a current daemon, or 404s it like one
/// from before the route.
class _Api implements ApiClient {
  _Api({this.system, this.configVersion = '0.2.5'});
  final Map<String, dynamic>? system;
  final String configVersion;
  final calls = <String>[];

  @override
  void updateConfig(AppConfig config) {}
  @override
  void dispose() {}
  @override
  Future<dynamic> get(String path,
      {Map<String, dynamic>? query, Duration? timeout}) async {
    calls.add(path);
    if (path == '/api/system/version') {
      if (system == null) throw ApiException(404, 'Not Found');
      return system;
    }
    if (path == '/api/config') return {'version': configVersion, 'wsPort': 18789};
    return {};
  }

  @override
  Future<dynamic> post(String path, {Object? body, Duration? timeout}) async => {};
  @override
  Future<dynamic> put(String path, {Object? body}) async => {};
  @override
  Future<dynamic> patch(String path, {Object? body}) async => {};
  @override
  Future<dynamic> delete(String path, {Object? body}) async => {};
}

const _bundled = CoreBuild(version: '0.2.9', gitHash: 'bbbbbbbbbbbb');
const _adopted = CoreBuild(
  version: '0.2.6',
  gitHash: 'aaaaaaaaaaaa',
  buildTarget: 'aarch64-apple-darwin',
  installKind: 'standalone',
  exePath: '/Users/me/.local/bin/senclaw',
);

Future<void> _pump(
  WidgetTester tester, {
  required DaemonPhase phase,
  CoreBuild? running,
  CoreBuild? bundled,
}) async {
  tester.view.physicalSize = const Size(1200, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      daemonSupervisorProvider.overrideWith((ref) => _Supervisor(phase)),
      runningCoreProvider.overrideWith((ref) async => running),
      bundledCoreProvider.overrideWith((ref) async => bundled),
    ],
    child: MaterialApp(
      theme: AppTheme.dark(),
      home: const Scaffold(
        body: Column(children: [
          CoreMismatchBanner(),
          Padding(padding: EdgeInsets.all(16), child: CoreVersionCard()),
        ]),
      ),
    ),
  ));
  await tester.pump();
  await tester.pump();
}

void main() {
  group('CoreBuild', () {
    test('reads `senclaw --version`', () {
      final b = CoreBuild.fromVersionLine('senclaw 0.2.8 (a05948a5c2e7)\n',
          exePath: '/x/senclaw')!;
      expect(b.version, '0.2.8');
      expect(b.gitHash, 'a05948a5c2e7');
      expect(b.label, '0.2.8 (a05948a5c2e7)');
      expect(CoreBuild.fromVersionLine('command not found'), isNull);
    });

    test('reads /api/system/version and refuses a body with no version', () {
      final b = CoreBuild.fromSystemVersion({
        'version': '0.2.10',
        'gitHash': 'c501cee12345',
        'installKind': 'desktop-bundle',
        'exePath': '/Applications/SenClaw Desktop.app/Contents/Resources/senclaw',
        'bundlePath': null,
      })!;
      expect(b.installKind, 'desktop-bundle');
      expect(CoreBuild.fromSystemVersion({'gitHash': 'x'}), isNull);
      expect(CoreBuild.fromSystemVersion('nope'), isNull);
    });

    test('the same release with an unknown hash is the same build', () {
      expect(const CoreBuild(version: '0.2.9').sameBuildAs(_bundled), isTrue);
      expect(
          const CoreBuild(version: '0.2.9', gitHash: 'cccccccccccc')
              .sameBuildAs(_bundled),
          isFalse,
          reason: 'a dev tree rebuilt between runs keeps its version');
      expect(_adopted.sameBuildAs(_bundled), isFalse);
    });

    test('a release manifest names the core it carries', () {
      final m = UpdateManifest.tryParse(
          '{"version":"0.2.12","coreVersion":"0.2.10","assets":{}}')!;
      expect(m.coreVersion, '0.2.10');
      expect(UpdateManifest.tryParse('{"version":"0.2.11","assets":{}}')!
          .coreVersion, isNull);
    });
  });

  group('runningCoreProvider', () {
    Future<CoreBuild?> read(_Api api) async {
      final c = ProviderContainer(overrides: [
        apiClientProvider.overrideWithValue(api),
        daemonSupervisorProvider
            .overrideWith((ref) => _Supervisor(DaemonPhase.adopted)),
      ]);
      addTearDown(c.dispose);
      return c.read(runningCoreProvider.future);
    }

    test('reads the full identity from /api/system/version', () async {
      final api = _Api(system: {'version': '0.2.10', 'gitHash': 'c501cee12345'});
      final b = await read(api);
      expect(b?.label, '0.2.10 (c501cee12345)');
      expect(api.calls, ['/api/system/version']);
    });

    test('falls back to /api/config on a daemon from before the route',
        () async {
      final api = _Api(configVersion: '0.2.5');
      final b = await read(api);
      expect(b?.version, '0.2.5');
      expect(b?.gitHash, isNull);
      expect(api.calls, ['/api/system/version', '/api/config']);
    });
  });

  testWidgets('an adopted daemon of another build is flagged, and can be dismissed',
      (tester) async {
    await _pump(tester,
        phase: DaemonPhase.adopted, running: _adopted, bundled: _bundled);

    expect(
        find.text('This app is connected to SenClaw core 0.2.6 (aaaaaaaaaaaa), '
            'which it did not start. The core in this app is 0.2.9 (bbbbbbbbbbbb).'),
        findsOneWidget);
    // Banner and card both offer the way back.
    expect(find.widgetWithText(FilledButton, 'Use bundled core'), findsNWidgets(2));
    expect(find.text('Running from /Users/me/.local/bin/senclaw'), findsOneWidget);
    expect(find.text('Core in this app: 0.2.9 (bbbbbbbbbbbb)'), findsOneWidget);
    expect(find.text('Standalone install'), findsOneWidget);

    await tester.tap(find.byTooltip('Close'));
    await tester.pump();
    expect(find.textContaining('which it did not start'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Use bundled core'), findsOneWidget,
        reason: 'the card keeps saying so after the banner is closed');
    expect(tester.takeException(), isNull);
  });

  testWidgets('switching asks first and names what it stops', (tester) async {
    await _pump(tester,
        phase: DaemonPhase.adopted, running: _adopted, bundled: _bundled);

    await tester.tap(find.widgetWithText(FilledButton, 'Use bundled core').first);
    await tester.pumpAndSettle();
    expect(find.text('Switch to the core in this app?'), findsOneWidget);
    expect(find.textContaining('on port 18788 is stopped'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Switch to the core in this app?'), findsNothing);
  });

  testWidgets('an adopted daemon of the same build raises nothing',
      (tester) async {
    await _pump(tester,
        phase: DaemonPhase.adopted,
        running: const CoreBuild(version: '0.2.9', gitHash: 'bbbbbbbbbbbb'),
        bundled: _bundled);

    expect(find.textContaining('which it did not start'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Use bundled core'), findsNothing);
    expect(
        find.text(
            'Already running when this app started — this app did not start it.'),
        findsOneWidget);
  });

  testWidgets('a daemon the app started is its own core, never flagged',
      (tester) async {
    await _pump(tester,
        phase: DaemonPhase.running,
        running: const CoreBuild(
            version: '0.2.9',
            gitHash: 'bbbbbbbbbbbb',
            buildTarget: 'aarch64-apple-darwin',
            installKind: 'desktop-bundle'),
        bundled: _adopted);

    expect(find.textContaining('which it did not start'), findsNothing);
    expect(find.text('Version 0.2.9 · bbbbbbbbbbbb · aarch64-apple-darwin'),
        findsOneWidget);
    expect(find.text('Started by this app from its own bundle.'), findsOneWidget);
    expect(find.text('App bundle'), findsOneWidget);
  });

  test('every string of the core card and the banner has a Vietnamese entry',
      () {
    const vi = L10n('vi');
    final missing = <String>[];
    for (final path in [
      'lib/features/settings/core_version_card.dart',
      'lib/widgets/core_mismatch_banner.dart',
    ]) {
      for (final key in trKeysIn(File(path).readAsStringSync())) {
        final translated = vi.t(key);
        if (translated == key) {
          missing.add('$path: $key');
          continue;
        }
        Set<String?> holes(String s) =>
            RegExp(r'\{(\w+)\}').allMatches(s).map((m) => m[1]).toSet();
        expect(holes(translated), holes(key), reason: '$key → $translated');
      }
    }
    for (final key in ['It brings SenClaw core {v}.']) {
      if (vi.t(key) == key) missing.add(key);
    }
    expect(missing, isEmpty, reason: missing.join('\n'));
  });
}
