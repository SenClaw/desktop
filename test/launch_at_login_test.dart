import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:senclaw_desktop/core/i18n/l10n.dart';
import 'package:senclaw_desktop/core/startup/launch_at_login.dart';
import 'package:senclaw_desktop/core/startup/launch_at_login_linux.dart';
import 'package:senclaw_desktop/core/startup/launch_at_login_macos.dart';
import 'package:senclaw_desktop/core/startup/launch_at_login_windows.dart'
    show approvedFlagIsOff, windowsRunCommand;
import 'package:senclaw_desktop/core/startup/launch_origin.dart';
import 'package:senclaw_desktop/features/settings/settings_screen.dart';
import 'package:senclaw_desktop/theme/app_theme.dart';

/// "Launch at login": one entry per platform, plus the Settings switch and the
/// hidden start that goes with it. The registry and Login Items themselves
/// cannot run in a unit test; what is checked here is everything around them —
/// what gets written, how the answer is read, and what the person sees.
void main() {
  group('Linux autostart entry', () {
    late Directory home;

    setUp(
      () => home = Directory.systemTemp.createTempSync('senclaw-autostart'),
    );
    tearDown(() => home.deleteSync(recursive: true));

    File entry() => File('${home.path}/autostart/senclaw-desktop.desktop');

    test(
      'enable writes an entry that starts hidden; disable removes it',
      () async {
        final svc = LinuxLaunchAtLogin(
          executable: '/opt/senclaw/senclaw_desktop',
          configHome: home,
        );
        expect(await svc.state(), LaunchAtLoginState.disabled);

        await svc.setEnabled(true);
        expect(await svc.state(), LaunchAtLoginState.enabled);
        final text = entry().readAsStringSync();
        expect(
          text,
          contains('Exec=/opt/senclaw/senclaw_desktop --autostart\n'),
        );
        expect(text, contains('Type=Application'));

        await svc.setEnabled(false);
        expect(entry().existsSync(), isFalse);
        expect(await svc.state(), LaunchAtLoginState.disabled);
        // Already off is not an error.
        await svc.setEnabled(false);
      },
    );

    test('a path with spaces is quoted, a percent sign is doubled', () {
      expect(
        desktopEntry('/home/a b/senclaw_desktop'),
        contains('Exec="/home/a b/senclaw_desktop" --autostart\n'),
      );
      expect(
        desktopEntry('/opt/100%/senclaw_desktop'),
        contains('Exec=/opt/100%%/senclaw_desktop --autostart\n'),
      );
      // Quote and backslash take the two escaping layers of the format.
      expect(
        desktopEntry(r'/o"pt/x y'),
        contains(r'Exec="/o\\"pt/x y" --autostart'),
      );
    });

    test(
      'an entry the desktop environment switched off reads as off',
      () async {
        final svc = LinuxLaunchAtLogin(
          executable: '/opt/senclaw/senclaw_desktop',
          configHome: home,
        );
        await svc.setEnabled(true);
        entry().writeAsStringSync('${entry().readAsStringSync()}Hidden=true\n');
        expect(await svc.state(), LaunchAtLoginState.disabled);

        // Switching it on again rewrites the entry, so the flag is gone.
        await svc.setEnabled(true);
        expect(await svc.state(), LaunchAtLoginState.enabled);
      },
    );
  });

  group('Windows Run entry', () {
    test('the command quotes the path and carries the autostart flag', () {
      expect(
        windowsRunCommand(r'C:\Program Files\SenClaw\senclaw_desktop.exe'),
        r'"C:\Program Files\SenClaw\senclaw_desktop.exe" --autostart',
      );
    });

    test('Explorer StartupApproved: odd first byte = switched off', () {
      expect(approvedFlagIsOff(null), isFalse);
      expect(approvedFlagIsOff(const []), isFalse);
      expect(approvedFlagIsOff([2, 0, 0, 0]), isFalse);
      expect(approvedFlagIsOff([6, 0, 0, 0]), isFalse);
      expect(approvedFlagIsOff([3, 0, 0, 0]), isTrue);
      expect(approvedFlagIsOff([7, 0, 0, 0]), isTrue);
    });
  });

  group('macOS login item bridge', () {
    const channel = MethodChannel('test/senclaw-app');
    final calls = <MethodCall>[];
    String? status;

    setUp(() {
      calls.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return call.method == 'loginItemStatus' ? status : null;
          });
    });
    tearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    test('maps the native status', () async {
      final svc = MacLaunchAtLogin(channel);
      for (final (native, expected) in [
        ('enabled', LaunchAtLoginState.enabled),
        ('disabled', LaunchAtLoginState.disabled),
        ('requiresApproval', LaunchAtLoginState.needsApproval),
        ('unsupported', LaunchAtLoginState.unsupported),
        (null, LaunchAtLoginState.unsupported),
      ]) {
        status = native;
        expect(await svc.state(), expected, reason: '$native');
      }
    });

    test('setEnabled sends the choice', () async {
      await MacLaunchAtLogin(channel).setEnabled(true);
      await MacLaunchAtLogin(channel).setEnabled(false);
      expect(calls.map((c) => c.method), ['setLoginItem', 'setLoginItem']);
      expect(calls.map((c) => c.arguments), [
        {'enabled': true},
        {'enabled': false},
      ]);
    });
  });

  group('launched at login', () {
    const channel = MethodChannel('test/senclaw-launch');
    Object? nativeAnswer;
    var asked = 0;

    setUp(() {
      asked = 0;
      nativeAnswer = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            asked++;
            if (nativeAnswer is Exception) throw nativeAnswer!;
            return nativeAnswer;
          });
    });
    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('the autostart flag is enough, on any platform', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      expect(await launchedAtLogin([kAutostartArg], channel: channel), isTrue);
      expect(asked, 0);
    });

    test('Windows and Linux without the flag are a normal launch', () async {
      for (final p in [TargetPlatform.windows, TargetPlatform.linux]) {
        debugDefaultTargetPlatformOverride = p;
        expect(await launchedAtLogin(const [], channel: channel), isFalse);
      }
      expect(asked, 0, reason: 'only macOS has a native answer to ask for');
    });

    test('macOS asks the native side', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      nativeAnswer = true;
      expect(await launchedAtLogin(const [], channel: channel), isTrue);
      nativeAnswer = false;
      expect(await launchedAtLogin(const [], channel: channel), isFalse);
    });

    test('a runner that cannot answer opens the window', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      nativeAnswer = MissingPluginException('no handler');
      expect(await launchedAtLogin(const [], channel: channel), isFalse);
    });
  });

  group('Settings → General → Startup', () {
    Future<_FakeLaunchAtLogin> pump(
      WidgetTester tester, {
      required LaunchAtLoginState state,
      Object? failWith,
      bool noPlatformSupport = false,
      String lang = 'en',
    }) async {
      final fake = _FakeLaunchAtLogin(state, failWith: failWith);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            launchAtLoginProvider.overrideWithValue(
              noPlatformSupport ? null : fake,
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            locale: Locale(lang),
            supportedLocales: const [Locale('en'), Locale('vi')],
            localizationsDelegates: const [
              L10nDelegate(),
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: const Scaffold(
              body: SingleChildScrollView(child: LaunchAtLoginField()),
            ),
          ),
        ),
      );
      await tester.pump();
      return fake;
    }

    testWidgets('is a switch that reflects and changes the state', (
      tester,
    ) async {
      final fake = await pump(tester, state: LaunchAtLoginState.disabled);

      expect(find.text('Launch at login'), findsOneWidget);
      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);

      await tester.tap(find.byType(Switch));
      await tester.pump();
      await tester.pump();

      expect(fake.requests, [true]);
      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);

      await tester.tap(find.byType(Switch));
      await tester.pump();
      await tester.pump();
      expect(fake.requests, [true, false]);
      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    });

    testWidgets('shows nothing where the platform cannot do it', (
      tester,
    ) async {
      await pump(tester, state: LaunchAtLoginState.unsupported);
      expect(find.text('Launch at login'), findsNothing);
      expect(find.text('Startup'), findsNothing);

      await pump(
        tester,
        state: LaunchAtLoginState.disabled,
        noPlatformSupport: true,
      );
      expect(find.text('Launch at login'), findsNothing);
    });

    testWidgets('a login item macOS has switched off points to Settings', (
      tester,
    ) async {
      await pump(tester, state: LaunchAtLoginState.needsApproval);

      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
      expect(
        find.textContaining('Only you can turn it back on'),
        findsOneWidget,
      );
      expect(find.text('Open System Settings'), findsOneWidget);
    });

    testWidgets('reads in Vietnamese, including the macOS approval hint', (
      tester,
    ) async {
      addTearDown(() => L10n.global = const L10n('en'));
      await pump(tester, state: LaunchAtLoginState.needsApproval, lang: 'vi');

      expect(find.text('Khởi động'), findsOneWidget);
      expect(find.text('Khởi động cùng hệ thống'), findsOneWidget);
      expect(
        find.textContaining('Tự mở SenClaw khi bạn đăng nhập'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Chỉ bạn mới bật lại được ở đó'),
        findsOneWidget,
      );
      expect(find.text('Mở Cài đặt hệ thống'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a refused change says so and leaves the switch where it was', (
      tester,
    ) async {
      final fake = await pump(
        tester,
        state: LaunchAtLoginState.disabled,
        failWith: PlatformException(code: 'login_item', message: 'denied'),
      );

      await tester.tap(find.byType(Switch));
      await tester.pump();
      await tester.pump();

      expect(fake.requests, [true]);
      expect(find.textContaining('denied'), findsOneWidget);
      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
      expect(tester.takeException(), isNull);
    });
  });
}

class _FakeLaunchAtLogin implements LaunchAtLogin {
  _FakeLaunchAtLogin(this._state, {this.failWith});

  LaunchAtLoginState _state;
  final Object? failWith;
  final requests = <bool>[];

  @override
  Future<LaunchAtLoginState> state() async => _state;

  @override
  Future<void> setEnabled(bool enabled) async {
    requests.add(enabled);
    final e = failWith;
    if (e != null) throw e;
    _state = enabled ? LaunchAtLoginState.enabled : LaunchAtLoginState.disabled;
  }
}
