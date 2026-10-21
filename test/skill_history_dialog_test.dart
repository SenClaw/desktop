// Plugins → Skills → History (desktop). What it exists to communicate, all of
// them daemon decisions the UI must not soften:
//
//  1. A revision that cannot be restored says why and offers no live button
//     (the current one, a removal, a pruned one, a skill that is not managed).
//  2. A skill that replaces a bundled one says so, in the list and in History.
//  3. What the security scan found is shown with the revision, and a restore
//     goes to the daemon only after a confirmation.
//  4. Every string is translated.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:senclaw_desktop/core/config/app_config.dart';
import 'package:senclaw_desktop/core/i18n/l10n.dart';
import 'package:senclaw_desktop/core/transport/api_client.dart';
import 'package:senclaw_desktop/core/transport/connection.dart';
import 'package:senclaw_desktop/features/plugins/plugins_screen.dart';
import 'package:senclaw_desktop/features/plugins/skill_history_dialog.dart';
import 'package:senclaw_desktop/theme/app_theme.dart';

final _now = DateTime.now().millisecondsSinceEpoch;

Map<String, dynamic> _rev(
  String id,
  String origin, {
  String hash = 'aaa',
  bool hasSnapshot = true,
  String? shadows,
  Map<String, dynamic>? scan,
  int agoMs = 0,
  String summary = '1 changed (+1 -1)',
  String actor = 'api:readme',
}) => {
  'id': id,
  'skillKey': 'demo',
  'skillName': 'demo',
  'source': 'clawhub-managed',
  'parentId': null,
  'generation': 1,
  'origin': origin,
  'actor': actor,
  'contentHash': hash.padRight(64, '0'),
  'fileCount': 2,
  'bytes': 900,
  'truncated': false,
  'hasSnapshot': hasSnapshot,
  'restoredFrom': null,
  'changeSummary': summary,
  'shadows': shadows,
  'scan': scan,
  'createdAt': _now - agoMs,
};

final _warn = {
  'verdict': 'warn',
  'maxSeverity': 'high',
  'riskScore': 25,
  'findings': [
    {
      'rule': 'INJ001',
      'severity': 'high',
      'title': 'Instruction-override text in an agent prompt',
      'file': 'SKILL.md',
      'line': 8,
    },
  ],
};

/// Serves one skill's history and records every mutation.
class _FakeApi implements ApiClient {
  final calls = <String>[];
  late final revisions = [
    _rev('rev_3', 'ROLLBACK', hash: 'aaa', agoMs: 60 * 1000),
    _rev('rev_2', 'MANUAL', hash: 'bbb', agoMs: 3 * 3600 * 1000, scan: _warn),
    _rev(
      'rev_1',
      'IMPORTED',
      hash: 'ccc',
      agoMs: 80 * 3600 * 1000,
      shadows: 'bundled',
    ),
    _rev(
      'rev_0',
      'BASELINE',
      hash: 'ddd',
      hasSnapshot: false,
      agoMs: 9e9.toInt(),
    ),
  ];

  @override
  void updateConfig(AppConfig config) {}

  @override
  void dispose() {}

  @override
  Future<dynamic> get(
    String path, {
    Map<String, dynamic>? query,
    Duration? timeout,
  }) async {
    calls.add('GET $path');
    if (path == '/api/skills/demo/history') {
      return {
        'skill': 'demo',
        'source': 'clawhub-managed',
        'key': 'demo',
        'revisions': revisions,
      };
    }
    final m = RegExp(r'^/api/skills/demo/history/(.+)$').firstMatch(path);
    if (m != null) {
      final r = revisions.firstWhere((x) => x['id'] == m[1]);
      return {
        'revision': {
          ...r,
          'diff':
              '--- a/SKILL.md\n+++ b/SKILL.md\n@@ -1,2 +1,2 @@\n keep\n-old line\n+new line\n',
        },
      };
    }
    if (path == '/api/skill-usage/summary') {
      return {
        'days': 30,
        'skills': [
          {
            'source': 'clawhub-managed',
            'key': 'demo',
            'versions': [
              {
                'contentHash': 'bbb'.padRight(64, '0'),
                'loads': 5,
                'fallbackRate': 0.6,
                'toolFailureRate': 0.4,
              },
            ],
          },
        ],
      };
    }
    return {};
  }

  @override
  Future<dynamic> post(String path, {Object? body, Duration? timeout}) async {
    calls.add('POST $path');
    return {'ok': true, 'revision': 'rev_4'};
  }

  @override
  Future<dynamic> put(String path, {Object? body}) async => {'ok': true};

  @override
  Future<dynamic> patch(String path, {Object? body}) async => {'ok': true};

  @override
  Future<dynamic> delete(String path, {Object? body}) async => {'ok': true};
}

Future<_FakeApi> _open(
  WidgetTester tester, {
  bool canRollback = true,
  VoidCallback? onRestored,
}) async {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final api = _FakeApi();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [apiClientProvider.overrideWithValue(api)],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showSkillHistory(
                context,
                name: 'demo',
                source: 'clawhub-managed',
                canRollback: canRollback,
                onRestored: onRestored,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return api;
}

OutlinedButton _restoreButton(WidgetTester tester) =>
    tester.widget<OutlinedButton>(
      find.byKey(const ValueKey('skill-history-restore')),
    );

void main() {
  group('models', () {
    test('a revision and its scan are read from the daemon JSON', () {
      final r = SkillRevision.fromJson(_rev('r', 'MANUAL', scan: _warn));
      expect((r.origin, r.generation, r.hasSnapshot), ('MANUAL', 1, true));
      expect(r.scan!.verdict, 'warn');
      expect(r.scan!.findings.single.rule, 'INJ001');
      expect(r.scan!.findings.single.line, 8);
      expect(SkillRevision.fromJson(_rev('r', 'MANUAL')).scan, isNull);
    });

    test('why a revision cannot be restored, most specific first', () {
      SkillRevision rev(
        String origin, {
        bool snap = true,
        bool truncated = false,
      }) => SkillRevision.fromJson({
        ..._rev('r1', origin, hasSnapshot: snap),
        'truncated': truncated,
      });
      String? why(SkillRevision r, {bool managed = true}) =>
          r.restoreBlockedReason(canRollback: managed, currentId: 'cur');
      expect(why(rev('MANUAL')), isNull);
      expect(
        SkillRevision.fromJson(
          _rev('cur', 'MANUAL'),
        ).restoreBlockedReason(canRollback: true, currentId: 'cur'),
        'This is the current revision.',
      );
      expect(why(rev('REMOVED')), contains('removal'));
      expect(why(rev('MANUAL', truncated: true)), contains('size cap'));
      expect(why(rev('MANUAL', snap: false)), contains('newest 30'));
      expect(why(rev('MANUAL'), managed: false), contains('managed'));
    });

    test('usage is keyed by content hash for one skill only', () {
      final u = usageByHash(
        {
          'skills': [
            {
              'source': 'clawhub-managed',
              'key': 'demo',
              'versions': [
                {
                  'contentHash': 'h1',
                  'loads': 3,
                  'fallbackRate': 0.333,
                  'toolFailureRate': null,
                },
                {'contentHash': null, 'loads': 1},
              ],
            },
            {
              'source': 'bundled',
              'key': 'demo',
              'versions': [
                {'contentHash': 'h2', 'loads': 9},
              ],
            },
          ],
        },
        'clawhub-managed',
        'demo',
      );
      expect(u.keys, ['h1']);
      expect(u['h1']!.loads, 3);
      expect(pct(u['h1']!.fallbackRate), '33%');
      expect(pct(u['h1']!.toolFailureRate), '–');
    });

    test('diff lines are classified for tinting', () {
      expect(diffLineKind('+++ b/SKILL.md'), DiffLineKind.header);
      expect(diffLineKind('--- a/SKILL.md'), DiffLineKind.header);
      expect(diffLineKind('+new'), DiffLineKind.added);
      expect(diffLineKind('-old'), DiffLineKind.removed);
      expect(diffLineKind('@@ -1 +1 @@'), DiffLineKind.hunk);
      expect(diffLineKind(' same'), DiffLineKind.context);
    });

    test('SkillInfo reads the sources a skill replaces', () {
      final s = SkillInfo.fromJson({
        'name': 'web-research',
        'source': 'clawhub-managed',
        'shadows': ['bundled'],
      });
      expect(s.shadows, ['bundled']);
      expect(
        SkillInfo.fromJson({'name': 'x', 'source': 'bundled'}).shadows,
        isEmpty,
      );
    });
  });

  group('dialog', () {
    testWidgets('lists revisions with their kind, scan result and numbers', (
      tester,
    ) async {
      await _open(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('Restored'), findsWidgets);
      expect(find.text('current'), findsOneWidget);
      expect(find.text('Edited'), findsOneWidget);
      expect(find.text('scan: 1'), findsOneWidget);
      expect(find.text('overrides the bundled skill'), findsOneWidget);
      expect(
        find.text('5 loads · fallback 60% · tool failures 40%'),
        findsOneWidget,
      );
    });

    testWidgets('the current revision cannot be restored and says why', (
      tester,
    ) async {
      await _open(tester);
      expect(_restoreButton(tester).onPressed, isNull);
      expect(find.byTooltip('This is the current revision.'), findsOneWidget);
    });

    testWidgets(
      'an older revision shows its diff and findings and can be restored',
      (tester) async {
        var restored = 0;
        final api = await _open(tester, onRestored: () => restored++);
        await tester.tap(find.text('Edited'));
        await tester.pumpAndSettle();

        expect(find.textContaining('INJ001'), findsOneWidget);
        expect(find.text('-old line'), findsOneWidget);
        expect(find.text('+new line'), findsOneWidget);
        expect(_restoreButton(tester).onPressed, isNotNull);

        await tester.tap(find.byKey(const ValueKey('skill-history-restore')));
        await tester.pumpAndSettle();
        // Nothing is sent until the person confirms.
        expect(api.calls.where((c) => c.startsWith('POST')), isEmpty);
        await tester.tap(find.widgetWithText(FilledButton, 'Restore'));
        await tester.pumpAndSettle();

        expect(api.calls.where((c) => c.startsWith('POST')), [
          'POST /api/skills/demo/rollback/rev_2',
        ]);
        expect(restored, 1);
      },
    );

    testWidgets('a revision whose content was dropped offers no restore', (
      tester,
    ) async {
      await _open(tester);
      await tester.tap(find.text('First seen'));
      await tester.pumpAndSettle();
      expect(_restoreButton(tester).onPressed, isNull);
      expect(
        find.byTooltip(
          'Its content was dropped: only the newest 30 revisions keep it.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('a skill outside the managed directory cannot be restored', (
      tester,
    ) async {
      await _open(tester, canRollback: false);
      await tester.tap(find.text('Edited'));
      await tester.pumpAndSettle();
      expect(_restoreButton(tester).onPressed, isNull);
      expect(
        find.byTooltip(
          'Only skills in the managed skills directory can be restored.',
        ),
        findsOneWidget,
      );
    });
  });

  group('skills list', () {
    testWidgets(
      'a skill that replaces a bundled one says so and has a History button',
      (tester) async {
        tester.view.physicalSize = const Size(1400, 1000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              apiClientProvider.overrideWithValue(_FakeApi()),
              pluginsSectionProvider.overrideWith((ref) => 'skills'),
              skillsProvider.overrideWith(
                (ref) async => [
                  const SkillInfo(
                    'web-research',
                    'Mine',
                    true,
                    false,
                    'clawhub-managed',
                    shadows: ['bundled'],
                  ),
                  const SkillInfo('wiki', 'Built in', true, true, 'bundled'),
                  const SkillInfo('crm-helper', 'From an app', true, true, 'app:crm'),
                ],
              ),
            ],
            child: MaterialApp(
              theme: AppTheme.light(),
              home: const Scaffold(body: PluginsScreen()),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        expect(find.byKey(const ValueKey('skill-shadow-chip')), findsOneWidget);
        expect(find.text('overrides the bundled skill'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('skill-history-web-research')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('skill-history-wiki')),
          findsOneWidget,
        );
        // An app's skill changes with the app; there is no history to open.
        expect(
          find.byKey(const ValueKey('skill-history-crm-helper')),
          findsNothing,
        );
      },
    );
  });

  group('translation', () {
    const vi = L10n('vi');

    // Strings the dialog looks up through a variable, so the source has no
    // literal to read: revision kinds and their hints, the reasons a restore
    // is unavailable, the names of the skill a revision replaces.
    const dynamicKeys = [
      'Edited',
      'Installed',
      'Restored',
      'Removed',
      'Changed outside SenClaw',
      'First seen',
      'Written through SenClaw: created, overwritten or saved in the editor.',
      'Installed from ClawHub.',
      'Put back to an earlier revision.',
      'The skill was removed. Its last content is still restorable.',
      'Found different on disk: a CLI install, a kit, or a text editor. Also used to keep what was there just before SenClaw overwrote it.',
      'The first time SenClaw saw this skill; nothing earlier is known.',
      'the bundled skill',
      'the global skill',
      'This is the current revision.',
      'A removal has no content of its own; pick the revision before it.',
      'This revision hit a size cap, so its content is incomplete.',
      'Its content was dropped: only the newest 30 revisions keep it.',
      'Only skills in the managed skills directory can be restored.',
    ];

    Set<String> keysIn(String source) {
      final keys = <String>{};
      final call = RegExp(r'\.(?:tr|trArgs|trPlural)\(\s*(?:[a-z0-9_.]+,\s*)?');
      final literal = RegExp(r"""\s*('(?:[^'\\]|\\.)*'|"(?:[^"\\]|\\.)*")""");
      for (final m in call.allMatches(source)) {
        var at = m.end;
        final parts = <String>[];
        for (;;) {
          final l = literal.matchAsPrefix(source, at);
          if (l == null) break;
          final tok = l.group(1)!;
          parts.add(
            tok
                .substring(1, tok.length - 1)
                .replaceAllMapped(RegExp(r'\\(.)'), (x) => x[1]!),
          );
          at = l.end;
        }
        if (parts.isNotEmpty) keys.add(parts.join());
      }
      return keys;
    }

    test(
      'every string of the dialog and the row chip has a Vietnamese entry',
      () {
        final src = File(
          'lib/features/plugins/skill_history_dialog.dart',
        ).readAsStringSync();
        // The extractor must find the dialog's strings, or a pass means nothing.
        expect(keysIn(src).length, greaterThan(20));
        expect(keysIn(src), contains('Restore this revision?'));
        final missing = [
          for (final k in {...keysIn(src), ...dynamicKeys})
            if (vi.t(k) == k) k,
        ];
        expect(missing, isEmpty, reason: missing.join('\n'));
      },
    );

    test('a message that holds a placeholder keeps it in Vietnamese', () {
      for (final key in [
        'overrides {what}',
        '{n} loads · fallback {f} · tool failures {t}',
        'Security scan: {n} findings (risk {r}/100)',
        'This skill replaces {what} with the same name.',
        'Replaces {what} with the same name; that one is hidden while this exists.',
        '{n} min ago',
      ]) {
        final ph = RegExp(
          r'\{(\w+)\}',
        ).allMatches(key).map((m) => m[1]).toSet();
        final out = vi.t(key);
        expect(
          RegExp(r'\{(\w+)\}').allMatches(out).map((m) => m[1]).toSet(),
          ph,
          reason: '$key → $out',
        );
      }
    });
  });
}
