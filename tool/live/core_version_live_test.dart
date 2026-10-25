// A live check of the SenClaw Core card and the adopted-core warning against a
// SCRATCH daemon: the real `DaemonSupervisor` (which adopts the daemon already
// answering on the port), the real `ApiClient`, the real widgets. Only the
// window is the test engine's, so it runs unattended and leaves screenshots.
//
// "The core in this app" is whatever `SENCLAW_BIN` names — point it at a build
// other than the scratch daemon's to see the warning. The last step presses
// "Use bundled core": that STOPS the scratch daemon and starts `SENCLAW_BIN`
// on the same port with this process's environment, so it refuses to run on
// the default ports (18788/18789, the person's own daemon) and the environment
// must carry a scratch `SENCLAW_HOME`:
//
//   SENCLAW_HOME=<scratch>/bundled-home SENCLAW_BIN=<other senclaw build> \
//   LIVE_EVIDENCE_DIR=<dir for PNGs> flutter test tool/live/core_version_live_test.dart \
//     --dart-define=SENCLAW_UI_PORT=38788 --dart-define=SENCLAW_WS_PORT=38789
//
// It is not part of `flutter test` (that runs test/ only).

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:senclaw_desktop/core/config/app_config.dart';
import 'package:senclaw_desktop/core/daemon/core_version.dart';
import 'package:senclaw_desktop/core/daemon/daemon_provider.dart';
import 'package:senclaw_desktop/core/daemon/daemon_supervisor.dart';
import 'package:senclaw_desktop/core/i18n/l10n.dart';
import 'package:senclaw_desktop/core/transport/api_client.dart';
import 'package:senclaw_desktop/core/transport/connection.dart';
import 'package:senclaw_desktop/features/settings/core_version_card.dart';
import 'package:senclaw_desktop/theme/app_theme.dart';
import 'package:senclaw_desktop/widgets/core_mismatch_banner.dart';

final _evidence = Platform.environment['LIVE_EVIDENCE_DIR'];
final _cfg = AppConfig.fromEnvironment();
final _shot = GlobalKey();

Future<void> _loadRealFont() async {
  final root = Platform.environment['FLUTTER_ROOT'];
  final dir = Directory('$root/bin/cache/artifacts/material_fonts');
  for (final family in ['Roboto', 'AntUi', 'SFMono-Regular', 'Ahem']) {
    final loader = FontLoader(family);
    for (final w in ['Regular', 'Medium', 'Bold']) {
      final f = File('${dir.path}/Roboto-$w.ttf');
      if (f.existsSync()) {
        loader.addFont(Future.value(f.readAsBytesSync().buffer.asByteData()));
      }
    }
    await loader.load();
  }
  final icons = File('${dir.path}/MaterialIcons-Regular.otf');
  if (icons.existsSync()) {
    await (FontLoader('MaterialIcons')
          ..addFont(Future.value(icons.readAsBytesSync().buffer.asByteData())))
        .load();
  }
}

/// Wait for real I/O: the test clock does not move sockets or processes.
Future<void> _io(WidgetTester t, [int ms = 150]) async {
  await t.runAsync(() => Future<void>.delayed(Duration(milliseconds: ms)));
  await t.pump(const Duration(milliseconds: 50));
}

Future<void> _snap(WidgetTester t, String name) async {
  await _io(t, 200);
  if (_evidence == null) return;
  final boundary = t.renderObject<RenderRepaintBoundary>(find.byKey(_shot));
  final bytes = await t.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1.0);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  });
  File('$_evidence/$name.png')
    ..createSync(recursive: true)
    ..writeAsBytesSync(bytes!);
}

/// What the daemon itself says, not what the screen shows.
Future<Map<String, dynamic>> _systemVersion(WidgetTester t) async =>
    (await t.runAsync(() async {
      final c = HttpClient();
      try {
        final req = await c.getUrl(
            Uri.parse('http://${_cfg.host}:${_cfg.uiPort}/api/system/version'));
        final res = await req.close();
        return jsonDecode(await res.transform(utf8.decoder).join())
            as Map<String, dynamic>;
      } finally {
        c.close(force: true);
      }
    }))!;

/// Up to [seconds] of real time for [ok] to hold, pumping in between.
Future<void> _until(WidgetTester t, bool Function() ok, {int seconds = 60}) async {
  for (var i = 0; i < seconds * 4 && !ok(); i++) {
    await _io(t, 250);
  }
}

void main() {
  testWidgets('the adopted core is shown, flagged, and replaced by the bundled one',
      (tester) async {
    // The test binding answers every request with 400 unless this is undone.
    HttpOverrides.global = null;
    expect(_cfg.uiPort, isNot(18788), reason: 'run against a scratch daemon');
    expect(Platform.environment['SENCLAW_HOME'], isNotNull,
        reason: 'the bundled core this test starts needs a scratch home');
    await tester.runAsync(_loadRealFont);
    tester.view.physicalSize = const Size(1100, 520);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final sup = DaemonSupervisor(
        host: _cfg.host, uiPort: _cfg.uiPort, wsPort: _cfg.wsPort);
    await tester.runAsync(sup.start);
    expect(sup.phase, DaemonPhase.adopted,
        reason: 'the scratch daemon must already be answering');
    final before = await _systemVersion(tester);

    final lang = ValueNotifier('en');
    await tester.pumpWidget(ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(ApiClient(_cfg)),
        daemonSupervisorProvider.overrideWith((ref) => sup),
      ],
      child: ValueListenableBuilder<String>(
        valueListenable: lang,
        builder: (_, code, _) => MaterialApp(
          theme: AppTheme.dark(),
          locale: Locale(code),
          supportedLocales: const [Locale('en'), Locale('vi')],
          localizationsDelegates: const [
            L10nDelegate(),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: RepaintBoundary(
            key: _shot,
            child: const Scaffold(
              body: Column(children: [
                CoreMismatchBanner(),
                Padding(padding: EdgeInsets.all(24), child: CoreVersionCard()),
              ]),
            ),
          ),
        ),
      ),
    ));
    final container =
        ProviderScope.containerOf(tester.element(find.byType(CoreVersionCard)));
    await _until(tester, () =>
        container.read(runningCoreProvider).hasValue &&
        container.read(bundledCoreProvider).hasValue);

    final running = container.read(runningCoreProvider).value!;
    final bundled = container.read(bundledCoreProvider).value!;
    expect(running.version, before['version']);
    expect(running.gitHash, before['gitHash']);
    expect(find.textContaining('Version ${before['version']}'), findsOneWidget);
    expect(find.text('Running from ${before['exePath']}'), findsOneWidget);
    expect(running.sameBuildAs(bundled), isFalse,
        reason: 'SENCLAW_BIN must name another build than the scratch daemon');
    expect(find.textContaining('which it did not start'), findsOneWidget);
    await _snap(tester, '01-adopted-other-build-en');

    lang.value = 'vi';
    await _io(tester);
    expect(find.textContaining('do nơi khác khởi động'), findsOneWidget);
    await _snap(tester, '02-adopted-other-build-vi');
    lang.value = 'en';
    await _io(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Use bundled core').first);
    await _io(tester);
    expect(find.textContaining('on port ${_cfg.uiPort} is stopped'), findsOneWidget);
    await _snap(tester, '03-confirm');
    await tester.tap(find.widgetWithText(FilledButton, 'Use bundled core').last);

    await _until(tester, () => sup.phase == DaemonPhase.running, seconds: 90);
    expect(sup.phase, DaemonPhase.running, reason: sup.lastError ?? '');
    await _until(tester, () {
      final b = container.read(runningCoreProvider).valueOrNull;
      return b != null && b.sameBuildAs(bundled);
    });
    expect(container.read(runningCoreProvider).value!.sameBuildAs(bundled), isTrue);
    expect(find.textContaining('which it did not start'), findsNothing);
    expect(find.text('Started by this app from its own bundle.'), findsOneWidget);
    await _snap(tester, '04-bundled-core-running');

    await tester.runAsync(sup.stop);
  });
}
