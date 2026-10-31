// A live check that leaving the dock's Terminal tab keeps its shell alive,
// against a SCRATCH daemon: the real dock, the real socket and the daemon's real
// PTY. The evidence is the shell process itself, not the screen. Unmounting the
// tab closes the socket and the daemon kills the shell, which no fake can show.
//
//   LIVE_DAEMON_PID=<pid of the scratch daemon> \
//     flutter test tool/live/dock_terminal_live_test.dart \
//     --dart-define=SENCLAW_UI_PORT=<ui> --dart-define=SENCLAW_WS_PORT=<ws>
//
// It refuses the default ports (18788/18789, the person's own daemon). It is not
// part of `flutter test` (that runs test/ only).

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:senclaw_desktop/core/config/app_config.dart';
import 'package:senclaw_desktop/core/prefs.dart';
import 'package:senclaw_desktop/features/dock/right_dock.dart';
import 'package:senclaw_desktop/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _cfg = AppConfig.fromEnvironment();
final _daemonPid = Platform.environment['LIVE_DAEMON_PID'];

Future<void> _io(WidgetTester t, [int ms = 1500]) async {
  await t.runAsync(() => Future<void>.delayed(Duration(milliseconds: ms)));
  await t.pump(const Duration(milliseconds: 50));
}

/// The daemon's direct children, as the OS reports them.
Future<Set<String>> _children(WidgetTester t) async {
  final r = await t.runAsync(() => Process.run('pgrep', ['-P', _daemonPid!]));
  return '${r!.stdout}'.split('\n').where((l) => l.trim().isNotEmpty).toSet();
}

void main() {
  final hasDaemon = _daemonPid != null &&
      _cfg.uiPort != 18788 &&
      _cfg.uiPort != 18789 &&
      _cfg.wsPort != 18788 &&
      _cfg.wsPort != 18789;

  testWidgets('leaving the Terminal tab does not kill its shell', (t) async {
    if (!hasDaemon) {
      markTestSkipped('needs LIVE_DAEMON_PID and the ports of a scratch daemon');
      return;
    }
    // `flutter test` answers every HTTP request with a 400.
    HttpOverrides.global = null;
    t.view.physicalSize = const Size(1200, 800);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container =
        ProviderContainer(overrides: [prefsProvider.overrideWithValue(prefs)]);
    container.read(dockTabProvider.notifier).state = 4;

    final before = await _children(t);
    await t.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: const Scaffold(body: Row(children: [
          Spacer(),
          RightDock(jid: 'web:terminal-live'),
        ])),
      ),
    ));
    await _io(t);

    final shells = (await _children(t)).difference(before);
    expect(shells.length, 1, reason: 'opening the tab starts one shell');

    for (final tab in [1, 0, 2, 5, 4, 1]) {
      container.read(dockTabProvider.notifier).state = tab;
      await t.pump();
      await _io(t);
      expect((await _children(t)).containsAll(shells), isTrue,
          reason: 'the shell died on the way to tab $tab');
    }

    // Leaving the dock for good still ends it: nothing is left running.
    await t.pumpWidget(const SizedBox.shrink());
    await _io(t);
    expect((await _children(t)).intersection(shells), isEmpty,
        reason: 'the shell outlived the dock');

    // Other tabs left polling timers; end them inside the test's clock.
    container.dispose();
    await t.pump(const Duration(minutes: 1));
  });
}
