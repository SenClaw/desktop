import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:senclaw_desktop/core/config/app_config.dart';
import 'package:senclaw_desktop/core/i18n/l10n.dart';
import 'package:senclaw_desktop/core/i18n/locale_provider.dart';
import 'package:senclaw_desktop/core/prefs.dart';
import 'package:senclaw_desktop/core/transport/api_client.dart';
import 'package:senclaw_desktop/core/transport/connection.dart';
import 'package:senclaw_desktop/features/settings/code_autonomy_field.dart';
import 'package:senclaw_desktop/features/settings/settings_screen.dart';

/// Settings → General → Agent behavior → "Approvals in code sessions": the
/// three-way `codeAutonomy` selector. The daemon (`GET|POST /api/agent-behavior`)
/// is faked in memory; the live round trip is `tool/live/code_autonomy_live_test.dart`.

bool _fontsLoaded = false;

/// Vietnamese runs longer than English, and `flutter_test`'s default glyph
/// boxes report overflow that is not there — measure with the SDK's Roboto.
Future<void> _loadRealFont() async {
  if (_fontsLoaded) return;
  final root = Platform.environment['FLUTTER_ROOT'];
  final dir = Directory('$root/bin/cache/artifacts/material_fonts');
  final loader = FontLoader('Roboto');
  for (final weight in ['Regular', 'Medium', 'Bold']) {
    final f = File('${dir.path}/Roboto-$weight.ttf');
    if (f.existsSync()) {
      loader.addFont(Future.value(f.readAsBytesSync().buffer.asByteData()));
    }
  }
  await loader.load();
  _fontsLoaded = true;
}

/// An in-memory `/api/agent-behavior`; every other read answers `{}`.
class _FakeApi implements ApiClient {
  _FakeApi(this.behavior);
  Map<String, dynamic> behavior;
  final posts = <Map<String, dynamic>>[];
  Object? failWith;

  /// How long a read of `/api/agent-behavior` takes — a real daemon is not instant.
  Duration getDelay = Duration.zero;

  @override
  void updateConfig(AppConfig config) {}
  @override
  void dispose() {}

  @override
  Future<dynamic> get(String path,
      {Map<String, dynamic>? query, Duration? timeout}) async {
    if (getDelay > Duration.zero) await Future<void>.delayed(getDelay);
    return path == '/api/agent-behavior' ? {...behavior} : <String, dynamic>{};
  }

  @override
  Future<dynamic> post(String path, {Object? body, Duration? timeout}) async {
    if (path != '/api/agent-behavior') return <String, dynamic>{};
    final sent = (body as Map).cast<String, dynamic>();
    posts.add(sent);
    if (failWith != null) throw failWith!;
    behavior = {...behavior, ...sent};
    return {...behavior};
  }

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('${i.memberName}');
}

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  String lang = 'en',
  Size size = const Size(1280, 900),
  _FakeApi? api,
  bool scroll = true,
}) async {
  await _loadRealFont();
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  addTearDown(() => L10n.global = const L10n('en'));

  SharedPreferences.setMockInitialValues({'senclaw:app-language': lang});
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(overrides: [
    prefsProvider.overrideWithValue(prefs),
    if (api != null) apiClientProvider.overrideWithValue(api),
  ]);
  addTearDown(container.dispose);

  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      locale: Locale(container.read(localeCodeProvider)),
      supportedLocales: const [Locale('en'), Locale('vi')],
      localizationsDelegates: const [
        L10nDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(fontFamily: 'Roboto'),
      home: Scaffold(body: scroll ? SingleChildScrollView(child: child) : child),
    ),
  ));
  await tester.pumpAndSettle();
}

Set<String> _selected(WidgetTester tester) => tester
    .widget<SegmentedButton<String>>(find.byKey(const ValueKey('code-autonomy')))
    .selected;

void main() {
  group('the field on its own', () {
    testWidgets('shows the level the daemon reports and what each one does',
        (tester) async {
      await _pump(tester, CodeAutonomyField(level: 'auto', onChanged: (_) async {}));

      expect(_selected(tester), {'auto'});
      expect(find.text('Approvals in code sessions'), findsOneWidget);
      for (final level in ['Ask', 'Auto', 'Full']) {
        expect(find.text(level), findsWidgets);
      }
      expect(find.textContaining('Every command and every file edit asks first'),
          findsOneWidget);
      expect(find.textContaining('still asks, and the card says why'),
          findsOneWidget);
      expect(find.textContaining('Nothing asks'), findsOneWidget);
      // The scope: auto/full are only for places a checkpoint can undo.
      expect(find.textContaining('only in code sessions and in folders that are git repositories'),
          findsOneWidget);
      expect(find.textContaining('checkpoint can undo the change'), findsOneWidget);
    });

    testWidgets('choosing a level hands exactly that value to onChanged',
        (tester) async {
      final chosen = <String>[];
      await _pump(
          tester,
          CodeAutonomyField(
              level: 'auto', onChanged: (v) async => chosen.add(v)));

      await tester.tap(find.descendant(
          of: find.byKey(const ValueKey('code-autonomy')),
          matching: find.text('Full')));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(
          of: find.byKey(const ValueKey('code-autonomy')),
          matching: find.text('Ask')));
      await tester.pumpAndSettle();

      expect(chosen, ['full', 'ask']);
    });

    testWidgets('a failed save puts the old level back and says why',
        (tester) async {
      await _pump(
          tester,
          CodeAutonomyField(
              level: 'auto', onChanged: (_) async => throw 'HTTP 400'));

      await tester.tap(find.descendant(
          of: find.byKey(const ValueKey('code-autonomy')),
          matching: find.text('Full')));
      await tester.pumpAndSettle();

      expect(_selected(tester), {'auto'});
      expect(find.textContaining('Could not change the approval level: HTTP 400'),
          findsOneWidget);
    });

    for (final width in [1280.0, 420.0]) {
      testWidgets('reads in Vietnamese and fits at ${width.toInt()}px',
          (tester) async {
        await _pump(tester,
            CodeAutonomyField(level: 'full', onChanged: (_) async {}),
            lang: 'vi', size: Size(width, 900));

        expect(tester.takeException(), isNull);
        expect(find.text('Duyệt trong phiên code'), findsOneWidget);
        expect(find.text('Hỏi'), findsWidgets);
        expect(find.text('Tự động'), findsWidgets);
        expect(find.text('Toàn quyền'), findsWidgets);
        expect(find.textContaining('chỉ có hiệu lực trong phiên code'),
            findsOneWidget);
        // No English left over: every sentence has a Vietnamese entry.
        expect(find.textContaining('Every command'), findsNothing);
        expect(find.textContaining('Nothing asks'), findsNothing);
        expect(find.textContaining('git repositories'), findsNothing);
      });
    }
  });

  group('in Settings → General', () {
    Future<_FakeApi> openGeneral(WidgetTester tester,
        {Map<String, dynamic>? behavior}) async {
      final api = _FakeApi(behavior ??
          {
            'preTriggerSkill': false,
            'preCognitive': true,
            'memoryRecall': false,
            'afterProcess': false,
            'contextCompression': true,
            'codeAutonomy': 'auto',
          });
      await _pump(tester, const SettingsScreen(), api: api, scroll: false);
      return api;
    }

    testWidgets('a pick is POSTed with the other settings and shown after the reload',
        (tester) async {
      final api = await openGeneral(tester);
      await tester.ensureVisible(find.byKey(const ValueKey('code-autonomy')));
      await tester.pumpAndSettle();
      expect(_selected(tester), {'auto'});

      api.getDelay = const Duration(milliseconds: 300);
      await tester.tap(find.descendant(
          of: find.byKey(const ValueKey('code-autonomy')),
          matching: find.text('Full')));
      // From the tap to the reload landing, the screen shows the new level —
      // never the old one while the daemon is being asked again.
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 60));
        expect(_selected(tester), {'full'}, reason: 'frame $i');
      }
      api.getDelay = Duration.zero;
      await tester.pumpAndSettle();

      expect(api.posts, hasLength(1));
      expect(api.posts.single['codeAutonomy'], 'full');
      // Same shape as the switches beside it: the whole object goes back.
      expect(api.posts.single['contextCompression'], true);
      expect(_selected(tester), {'full'});
    });

    testWidgets('a daemon that does not report codeAutonomy gets no control',
        (tester) async {
      await openGeneral(tester, behavior: {
        'preTriggerSkill': false,
        'preCognitive': false,
        'memoryRecall': false,
        'afterProcess': false,
      });
      expect(find.text('Agent behavior'), findsOneWidget);
      expect(find.byKey(const ValueKey('code-autonomy')), findsNothing);
    });
  });
}
