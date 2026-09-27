import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:senclaw_desktop/core/config/app_config.dart';
import 'package:senclaw_desktop/core/i18n/l10n.dart';
import 'package:senclaw_desktop/core/transport/api_client.dart';
import 'package:senclaw_desktop/core/transport/connection.dart';
import 'package:senclaw_desktop/core/transport/runtime_missing.dart';
import 'package:senclaw_desktop/features/settings/decision_section.dart';
import 'package:senclaw_desktop/features/settings/settings_screen.dart';
import 'package:senclaw_desktop/theme/app_theme.dart';
import 'package:senclaw_desktop/widgets/runtime_missing_banner.dart';

/// The full `SettingsScreen` includes its fixed-width sidebar
/// (`_SectionItem`'s Row has no overflow handling — see
/// vietnamese_layout_test.dart). `flutter_test`'s default font renders every
/// glyph as a box exactly `fontSize` wide, which reports phantom overflow a
/// real (proportional) font never would; load Roboto before pumping it, same
/// as that test does.
bool _fontsLoaded = false;
Future<bool> _loadRealFont() async {
  if (_fontsLoaded) return true;
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root == null) return false;
  final dir = Directory('$root/bin/cache/artifacts/material_fonts');
  if (!dir.existsSync()) return false;
  final loader = FontLoader('Roboto');
  for (final weight in ['Regular', 'Medium', 'Bold']) {
    final f = File('${dir.path}/Roboto-$weight.ttf');
    if (f.existsSync()) {
      loader.addFont(Future.value(f.readAsBytesSync().buffer.asByteData()));
    }
  }
  await loader.load();
  _fontsLoaded = true;
  return true;
}

/// Always answers the legacy namespaces (`/api/ocr|tts|whisper|decision/*`)
/// with the 503 runtime-missing shape a client sees when the slot's runtime
/// isn't installed/selected/startable (runtime-protocol.md §5.2).
class _RuntimeMissingApi implements ApiClient {
  _RuntimeMissingApi(this.code, this.message, this.slot);
  final String code;
  final String message;
  final String slot;

  @override
  void updateConfig(AppConfig config) {}
  @override
  void dispose() {}

  @override
  Future<dynamic> get(String path, {Map<String, dynamic>? query, Duration? timeout}) async {
    // The decision control-plane routes stay in the daemon and answer with no
    // sen-sysone at all (runtime-protocol.md §5.2) — only the slot-proxied
    // routes (here, the model list) 503. Both view classes default safely
    // from an empty map, so this doubles as their "nothing configured yet"
    // fixture.
    if (path == '/api/decision/gate' || path == '/api/decision/skills') {
      return <String, dynamic>{};
    }
    throw ApiException(503, message, code: code, slot: slot);
  }

  @override
  Future<dynamic> put(String path, {Object? body}) async => {'ok': true};
  @override
  Future<dynamic> post(String path, {Object? body, Duration? timeout}) async => {'ok': true};
  @override
  Future<dynamic> patch(String path, {Object? body}) async => {'ok': true};
  @override
  Future<dynamic> delete(String path, {Object? body}) async => {'ok': true};
}

void main() {
  group('runtimeMissingFrom / decodeRuntimeMissingBody', () {
    test('recognizes each of the three runtime-missing codes on a 503 ApiException', () {
      for (final code in runtimeMissingCodes) {
        final e = ApiException(503, 'No OCR runtime is installed.', code: code, slot: 'ocr');
        final missing = runtimeMissingFrom(e);
        expect(missing, isNotNull, reason: '$code must be recognized');
        expect(missing!.code, code);
        expect(missing.slot, 'ocr');
      }
    });

    test('ignores a matching code on a non-503 status, and any other status/code combination', () {
      expect(runtimeMissingFrom(ApiException(500, 'x', code: 'runtime_not_installed')), isNull);
      expect(runtimeMissingFrom(ApiException(503, 'x', code: 'some_other_code')), isNull);
      expect(runtimeMissingFrom(ApiException(503, 'x')), isNull);
      expect(runtimeMissingFrom(Exception('unrelated')), isNull);
    });

    test('passes an already-decoded RuntimeMissingException through unchanged', () {
      const e = RuntimeMissingException('runtime_start_failed', 'boom', slot: 'tts');
      expect(identical(runtimeMissingFrom(e), e), isTrue);
    });

    test('decodeRuntimeMissingBody parses the daemon JSON body and ignores anything else', () {
      final ok = decodeRuntimeMissingBody(503, '{"error":"No ASR runtime.","code":"runtime_not_selected","slot":"asr"}');
      expect(ok, isNotNull);
      expect(ok!.code, 'runtime_not_selected');
      expect(ok.slot, 'asr');
      expect(ok.message, 'No ASR runtime.');

      expect(decodeRuntimeMissingBody(200, '{"code":"runtime_not_installed"}'), isNull);
      expect(decodeRuntimeMissingBody(503, 'not json'), isNull);
      expect(decodeRuntimeMissingBody(503, '{"code":"unrelated"}'), isNull);
    });
  });

  group('RuntimeMissingBanner widget', () {
    testWidgets('shows the daemon message and an action that opens Runtime settings',
        (tester) async {
      const error = RuntimeMissingException(
          'runtime_not_installed', 'No OCR runtime is installed. Install one in Settings → Runtime.',
          slot: 'ocr');
      String? settingsSection;
      final router = GoRouter(initialLocation: '/', routes: [
        GoRoute(
          path: '/',
          builder: (context, state) =>
              const Scaffold(body: RuntimeMissingBanner(error: error)),
        ),
        GoRoute(
          path: '/settings',
          builder: (context, state) => Consumer(builder: (context, ref, _) {
            settingsSection = ref.watch(settingsSectionProvider);
            return const Scaffold(body: Text('Settings screen'));
          }),
        ),
      ]);

      await tester.pumpWidget(ProviderScope(
        child: MaterialApp.router(
          theme: AppTheme.dark(),
          routerConfig: router,
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.textContaining('No OCR runtime is installed'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Open Runtime settings'), findsOneWidget);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Open Runtime settings'));
      await tester.pumpAndSettle();

      expect(find.text('Settings screen'), findsOneWidget);
      expect(settingsSection, 'runtime');
    });
  });

  group('wired into real settings sections', () {
    setUpAll(() async {
      // Two of the tests below pump the whole SettingsScreen, sidebar
      // included — see the font note above.
      if (!await _loadRealFont()) {
        fail('Roboto not found under FLUTTER_ROOT — cannot measure real layout');
      }
    });

    Future<void> pumpApp(WidgetTester tester, Widget child, {String lang = 'en'}) async {
      tester.view.physicalSize = const Size(1400, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(fontFamily: 'Roboto'),
        locale: Locale(lang),
        supportedLocales: const [Locale('en'), Locale('vi')],
        localizationsDelegates: const [
          L10nDelegate(),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(body: child),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('Decision (Laya) settings shows the banner instead of a raw error, '
        'and drops the old "not compiled" messaging', (tester) async {
      final api = _RuntimeMissingApi('runtime_not_installed',
          'No decision runtime is installed. Install one in Settings → Runtime.', 'decision');
      await pumpApp(
        tester,
        ProviderScope(
          overrides: [apiClientProvider.overrideWithValue(api)],
          child: const DecisionSection(),
        ),
      );

      expect(find.textContaining('No decision runtime is installed'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Open Runtime settings'), findsOneWidget);
      expect(find.textContaining('not compiled'), findsNothing);
      expect(find.text('This build has no Laya engine'), findsNothing);
    });

    testWidgets('OCR settings (via the Settings screen) shows the banner on a 503', (tester) async {
      final api = _RuntimeMissingApi(
          'runtime_not_selected', 'No OCR runtime is selected. Choose one in Settings → Runtime.', 'ocr');
      await pumpApp(
        tester,
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(api),
            settingsSectionProvider.overrideWith((ref) => 'ocr'),
          ],
          child: const SettingsScreen(),
        ),
      );

      expect(find.textContaining('No OCR runtime is selected'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Open Runtime settings'), findsOneWidget);
    });

    testWidgets('reads in Vietnamese', (tester) async {
      final api = _RuntimeMissingApi(
          'runtime_start_failed', 'The TTS runtime failed to start.', 'tts');
      await pumpApp(
        tester,
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(api),
            settingsSectionProvider.overrideWith((ref) => 'tts'),
          ],
          child: const SettingsScreen(),
        ),
        lang: 'vi',
      );

      expect(find.text('Mở Cài đặt Runtime'), findsOneWidget);
    });
  });
}
