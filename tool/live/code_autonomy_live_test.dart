// A live check of Settings → General → "Approvals in code sessions" against a
// SCRATCH daemon: the real `ApiClient`, the real `SettingsScreen`, no fakes —
// only the window is the test engine's, not the macOS app's (so it can run
// unattended and leave screenshots).
//
// It changes `codeAutonomy` (and puts it back), so it refuses to run against
// the default ports (18788/18789, the person's own daemon) and needs the
// scratch daemon's:
//
//   LIVE_EVIDENCE_DIR=<dir for PNGs> flutter test tool/live/code_autonomy_live_test.dart \
//     --dart-define=SENCLAW_UI_PORT=38788 --dart-define=SENCLAW_WS_PORT=38789
//
// Start the daemon with its own HOME, SENCLAW_HOME and cwd (see CLAUDE.md,
// "Run against a dev daemon"). It is not part of `flutter test` (that runs
// test/ only).

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
import 'package:senclaw_desktop/features/settings/code_autonomy_field.dart';
import 'package:senclaw_desktop/features/settings/settings_screen.dart';
import 'package:senclaw_desktop/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _evidence = Platform.environment['LIVE_EVIDENCE_DIR'];
final _cfg = AppConfig.fromEnvironment();
final _shot = GlobalKey();
const _field = ValueKey('code-autonomy');

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
Future<Map<String, dynamic>> _daemon(WidgetTester t, String path) async {
  final r = await t.runAsync(
      () => http.get(Uri.parse('http://${_cfg.host}:${_cfg.uiPort}$path')));
  return jsonDecode(r!.body) as Map<String, dynamic>;
}

Set<String> _selected(WidgetTester t) =>
    t.widget<SegmentedButton<String>>(find.byKey(_field)).selected;

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
    testWidgets('the selector round-trips against the daemon ($lang)',
        (t) async {
      if (!hasDaemon) {
        markTestSkipped(
            'needs --dart-define=SENCLAW_UI_PORT/SENCLAW_WS_PORT of a scratch daemon');
        return;
      }
      t.view.physicalSize = const Size(1280, 860);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      addTearDown(() => L10n.global = const L10n('en'));
      // ignore: invalid_use_of_visible_for_testing_member
      SharedPreferences.setMockInitialValues({'senclaw:app-language': lang});
      final prefs = await SharedPreferences.getInstance();
      final container =
          ProviderContainer(overrides: [prefsProvider.overrideWithValue(prefs)]);

      final l10n = L10n(lang);
      String tr(String en) => l10n.t(en);

      final start = (await _daemon(t, '/api/agent-behavior'))['codeAutonomy'];
      expect(kCodeAutonomyLevels, contains(start),
          reason: 'the scratch daemon must serve codeAutonomy (feat/code-v3)');

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
          home: const Scaffold(body: SettingsScreen()),
          builder: (_, child) => RepaintBoundary(key: _shot, child: child),
        ),
      ));
      // The panels load over the socket; wait until the control is on screen.
      for (var i = 0; i < 60 && find.byKey(_field).evaluate().isEmpty; i++) {
        await _io(t);
      }
      expect(find.byKey(_field), findsOneWidget,
          reason: 'the daemon reports codeAutonomy, so the control must show');
      await t.ensureVisible(find.byKey(_field));
      await t.pumpAndSettle();
      expect(_selected(t), {start}, reason: 'the screen shows what the daemon says');
      await _snap(t, 'desktop-$lang-0-start-$start');

      Future<void> choose(String level, String en) async {
        await t.tap(find.descendant(
            of: find.byKey(_field), matching: find.text(tr(en))));
        // The POST goes over a real socket, then the provider reloads.
        for (var i = 0; i < 40; i++) {
          await _io(t, 40);
          // Never the old level on the way: not while saving, not while reloading.
          expect(_selected(t), {level}, reason: 'between the tap and the reload');
          if ((await _daemon(t, '/api/agent-behavior'))['codeAutonomy'] == level &&
              i >= 5) {
            break;
          }
        }
        final seen = await _daemon(t, '/api/agent-behavior');
        expect(seen['codeAutonomy'], level, reason: 'the daemon recorded it');
        expect((await _daemon(t, '/api/code/autonomy'))['level'], level);
        expect(_selected(t), {level}, reason: 'the screen shows the new level');
        // The neighbouring settings went back untouched, as for the switches.
        expect(seen['contextCompression'], isA<bool>());
        await _snap(t, 'desktop-$lang-$level');
      }

      await choose('full', 'Full');
      await choose('ask', 'Ask');
      await choose('auto', 'Auto');
      // And back to what the daemon had before this run.
      if (start != 'auto') await choose(start as String, _levelEn(start));

      // Let the reload that follows the last save finish, then close the app's
      // HTTP client before the test ends: a request still in flight retries on
      // a timer, and its idle connections hold a keep-alive one, which the test
      // binding counts as leaks.
      await _io(t, 800);
      await t.pumpWidget(const SizedBox());
      container.dispose();
      await _io(t);
    });
  }
}

String _levelEn(String level) => {'ask': 'Ask', 'auto': 'Auto', 'full': 'Full'}[level]!;
