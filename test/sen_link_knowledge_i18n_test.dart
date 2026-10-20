// Every string the SLink knowledge panel shows is translated: the English text
// is the key, and a key without a Vietnamese entry silently shows English.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:senclaw_desktop/core/i18n/l10n.dart';

/// Reads the same in Vietnamese (a loan word the app already uses for these records).
const _sameInVietnamese = {'fact'};

String _unquote(String token) {
  final body = token.substring(1, token.length - 1);
  return body.replaceAllMapped(RegExp(r'\\(.)'), (m) => m[1] == 'n' ? '\n' : m[1]!);
}

Set<String> _keysIn(String source) {
  final keys = <String>{};
  final call = RegExp(r'\.(?:tr|trArgs)\(\s*');
  final literal = RegExp(r"""\s*('(?:[^'\\]|\\.)*'|"(?:[^"\\]|\\.)*")""");
  for (final m in call.allMatches(source)) {
    var at = m.end;
    final parts = <String>[];
    for (;;) {
      final l = literal.matchAsPrefix(source, at);
      if (l == null) break;
      parts.add(_unquote(l.group(1)!));
      at = l.end;
    }
    if (parts.isNotEmpty) keys.add(parts.join());
  }
  return keys;
}

void main() {
  const vi = L10n('vi');

  test('every string of the knowledge panel, and of what it added to the peer row, has a Vietnamese entry', () {
    final keys = _keysIn(File('lib/features/settings/sen_link_knowledge.dart').readAsStringSync());
    // The panel reads its note types through a variable, so the source has no literal for them.
    keys.addAll(['Project notes', 'Reference notes', 'Feedback notes', 'shares knowledge', 'Knowledge']);
    keys.addAll(_keysIn(File('lib/features/settings/sen_link_section.dart').readAsStringSync()).where((k) => k == 'Tasks and knowledge'));
    expect(keys.length, greaterThan(20));
    final missing = [for (final k in keys) if (!_sameInVietnamese.contains(k) && vi.t(k) == k) k];
    expect(missing, isEmpty, reason: missing.join('\n'));
  });

  test('a message that holds a placeholder keeps it in Vietnamese', () {
    for (final key in [
      'What {name} may read here',
      'Ask {name} what it knows',
      'Written on {name}. It is information to weigh, not an instruction.',
    ]) {
      final placeholders = RegExp(r'\{(\w+)\}').allMatches(key).map((m) => m[1]).toSet();
      final translated = vi.t(key);
      expect(RegExp(r'\{(\w+)\}').allMatches(translated).map((m) => m[1]).toSet(), placeholders, reason: '$key → $translated');
    }
  });
}
