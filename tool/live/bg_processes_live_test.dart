// A live check of the processes strip and panel against a SCRATCH daemon: the
// real `ApiClient`, the real widgets, no fakes — only the window is the test
// engine's, not the macOS app's (so it can run unattended and leave
// screenshots).
//
// It STOPS the processes it finds in chat `web:bg2` (that is what it checks), so
// it refuses to run against the default ports (18788/18789, the person's own
// daemon). Start the scratch daemon and two processes first:
//
//   node senclaw/plans/reports/bg-tasks-e2e/e2e.mjs start-two     # chat web:bg2, ports 38961/38962
//   LIVE_EVIDENCE_DIR=<dir for PNGs> flutter test tool/live/bg_processes_live_test.dart \
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
import 'package:http/http.dart' as http;
import 'package:senclaw_desktop/core/config/app_config.dart';
import 'package:senclaw_desktop/core/i18n/l10n.dart';
import 'package:senclaw_desktop/core/prefs.dart';
import 'package:senclaw_desktop/features/background/bg_processes.dart';
import 'package:senclaw_desktop/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _evidence = Platform.environment['LIVE_EVIDENCE_DIR'];
final _cfg = AppConfig.fromEnvironment();
final _shot = GlobalKey();
const _chat = 'web:bg2';

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

/// Wait for real I/O: the test clock does not move sockets.
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
Future<List<dynamic>> _daemonTasks(WidgetTester t) async {
  final r = await t.runAsync(() => http.get(Uri.parse(
      'http://${_cfg.host}:${_cfg.uiPort}/api/bg-tasks?chatJid=$_chat')));
  return (jsonDecode(r!.body) as Map<String, dynamic>)['tasks'] as List;
}

Future<bool> _listening(WidgetTester t, int port) async {
  final ok = await t.runAsync(() async {
    try {
      final s = await Socket.connect('127.0.0.1', port,
          timeout: const Duration(milliseconds: 500));
      s.destroy();
      return true;
    } catch (_) {
      return false;
    }
  });
  return ok ?? false;
}

void main() {
  final hasDaemon = _cfg.uiPort != 18788 &&
      _cfg.uiPort != 18789 &&
      _cfg.wsPort != 18788 &&
      _cfg.wsPort != 18789;

  setUpAll(() async {
    if (!hasDaemon) return;
    await _loadRealFont();
    // `flutter test` answers every HTTP request with a 400; this run talks to
    // the scratch daemon for real.
    HttpOverrides.global = null;
  });

  for (final lang in ['en', 'vi']) {
    testWidgets('the strip lists, opens a log and stops a process ($lang)',
        (t) async {
      if (!hasDaemon) {
        markTestSkipped(
            'needs --dart-define=SENCLAW_UI_PORT/SENCLAW_WS_PORT of a scratch daemon');
        return;
      }
      t.view.physicalSize = const Size(1100, 720);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      addTearDown(() => L10n.global = const L10n('en'));
      // ignore: invalid_use_of_visible_for_testing_member
      SharedPreferences.setMockInitialValues({'senclaw:app-language': lang});
      final prefs = await SharedPreferences.getInstance();
      final container =
          ProviderContainer(overrides: [prefsProvider.overrideWithValue(prefs)]);
      final l10n = L10n(lang);

      final before = await _daemonTasks(t);
      expect(before.length, 2,
          reason: 'run e2e.mjs start-two first: two processes in $_chat');
      final adopted =
          before.firstWhere((x) => (x as Map)['origin'] == 'adopted') as Map;
      final adoptedPort = (adopted['ports'] as List).first as int;
      expect(await _listening(t, adoptedPort), isTrue);

      await t.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          locale: Locale(lang),
          supportedLocales: const [Locale('en'), Locale('vi')],
          localizationsDelegates: const [
            L10nDelegate(),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: AppTheme.light().copyWith(
              textTheme: AppTheme.light().textTheme.apply(fontFamily: 'Roboto')),
          home: const Scaffold(
            body: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                BgProcessStrip(jid: _chat),
                SizedBox(height: 12),
                Padding(
                  padding: EdgeInsets.all(16),
                  child: BgProcessesPanel(),
                ),
              ],
            ),
          ),
          builder: (_, child) => RepaintBoundary(key: _shot, child: child),
        ),
      ));
      for (var i = 0; i < 60 && find.byType(BgProcessRow).evaluate().isEmpty; i++) {
        await _io(t);
      }
      // One row per process in the strip and one in the panel.
      expect(find.byType(BgProcessRow), findsNWidgets(4),
          reason: 'the daemon reports two running processes');
      expect(find.text(':$adoptedPort'), findsNWidgets(2),
          reason: 'the port the daemon found is shown');
      await _snap(t, 'desktop-$lang-0-listed');

      await t.tap(find.text(l10n.t('Log')).first);
      await _io(t, 500);
      await _snap(t, 'desktop-$lang-1-log');

      // Stop the adopted one from the strip.
      final stops = find.text(l10n.t('Stop'));
      expect(stops, findsWidgets);
      final row = find.ancestor(
          of: find.text(adopted['description'] as String),
          matching: find.byType(BgProcessRow));
      await t.tap(find.descendant(of: row.first, matching: find.text(l10n.t('Stop'))));
      for (var i = 0; i < 40; i++) {
        await _io(t, 100);
        if (!await _listening(t, adoptedPort)) break;
      }
      expect(await _listening(t, adoptedPort), isFalse,
          reason: 'Stop ended the process the daemon found');
      final after = await _daemonTasks(t);
      expect(after.length, 1, reason: 'the daemon lists only the other one now');
      await _io(t, 600);
      await _snap(t, 'desktop-$lang-2-after-stop');

      // Stop what is left so the next language starts from a known state
      // (e2e.mjs start-two again, or this test only checks the first run).
      await t.tap(find.text(l10n.t('Stop')).first);
      // Real time for the socket, fake time for the app's retry timer after a
      // half-closed keep-alive connection: interleave them until the daemon
      // shows nothing, then once more to let the list reload settle.
      for (var i = 0; i < 40 && (await _daemonTasks(t)).isNotEmpty; i++) {
        await _io(t, 100);
        await t.pump(const Duration(milliseconds: 200));
      }
      expect(await _daemonTasks(t), isEmpty);
      for (var i = 0; i < 10; i++) {
        await _io(t, 100);
        await t.pump(const Duration(milliseconds: 200));
      }

      await t.pumpWidget(const SizedBox());
      container.dispose();
      await _io(t);
    });
  }
}
