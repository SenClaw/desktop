// Export the desktop app's Vietnamese dictionary as JSON for the web UI.
//
// The two clients share one dictionary and one convention: **the English
// string is the key**. Keeping a second, hand-maintained copy for the web
// would drift the moment either side edited a sentence, and a drifted
// dictionary shows English in half a dialog.
//
// This imports the real `vi/*.dart` maps rather than parsing them, so what
// the web receives is exactly what the desktop renders — Dart's adjacent
// string concatenation included, which a text parser gets wrong.
//
// Run from the repo root:
//
//   dart run tool/i18n_export.dart
//
// Writes ../web/src/i18n/vi.json. A test in the web app fails when that file
// is missing, so the export is not something to remember by hand.

import 'dart:convert';
import 'dart:io';

import 'package:senclaw_desktop/core/i18n/vi/background.dart';
import 'package:senclaw_desktop/core/i18n/vi/chat_main.dart';
import 'package:senclaw_desktop/core/i18n/vi/chat_misc.dart';
import 'package:senclaw_desktop/core/i18n/vi/chat_widgets.dart';
import 'package:senclaw_desktop/core/i18n/vi/cognitive_wiki.dart';
import 'package:senclaw_desktop/core/i18n/vi/common.dart';
import 'package:senclaw_desktop/core/i18n/vi/dashboard_usage.dart';
import 'package:senclaw_desktop/core/i18n/vi/decision.dart';
import 'package:senclaw_desktop/core/i18n/vi/dock_cowork.dart';
import 'package:senclaw_desktop/core/i18n/vi/kanban.dart';
import 'package:senclaw_desktop/core/i18n/vi/plugins_misc.dart';
import 'package:senclaw_desktop/core/i18n/vi/plugins_screen.dart';
import 'package:senclaw_desktop/core/i18n/vi/settings_misc.dart';
import 'package:senclaw_desktop/core/i18n/vi/settings_screen.dart';
import 'package:senclaw_desktop/core/i18n/vi/shell_misc.dart';
import 'package:senclaw_desktop/core/i18n/vi/space.dart';
import 'package:senclaw_desktop/core/i18n/vi/workflow.dart';

void main(List<String> args) {
  // Same merge order as L10n._vi, so a key defined twice resolves the same
  // way on both clients.
  final merged = <String, String>{
    ...viCommon,
    ...viShellMisc,
    ...viSettingsScreen,
    ...viSettingsMisc,
    ...viDecision,
    ...viPluginsScreen,
    ...viPluginsMisc,
    ...viChatMain,
    ...viChatMisc,
    ...viChatWidgets,
    ...viSpace,
    ...viWorkflow,
    ...viBackground,
    ...viKanban,
    ...viDashboardUsage,
    ...viCognitiveWiki,
    ...viDockCowork,
  };

  // Sorted so a re-export produces a reviewable diff instead of a reshuffle.
  final sorted = Map.fromEntries(
    merged.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
  );

  final out = File(args.isNotEmpty ? args.first : '../web/src/i18n/vi.json');
  out.parent.createSync(recursive: true);
  out.writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(sorted)}\n');
  stdout.writeln('wrote ${sorted.length} strings to ${out.path}');
}
