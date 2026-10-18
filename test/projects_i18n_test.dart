// Every string the project screens show is translated: the English text is the
// key, and a key without a Vietnamese entry silently shows English. This reads
// the source of the project screens, collects what they pass to `tr` /
// `trArgs`, and checks each has an entry — a new string added without its
// translation fails here instead of shipping half-translated.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:senclaw_desktop/core/i18n/l10n.dart';

/// Strings that read the same in Vietnamese (a product term or a loan word).
const _sameInVietnamese = {'Context', 'Agent', 'Code', 'kanban'};

/// Keys the screens look up through a variable, so the source has no literal
/// to read: the Overview rows, and the banner names.
const _dynamic = [
  'Archive',
  'Restore',
  'Archive project',
  'Restore project',
  'Delete for good',
  'Project archived',
  'Project restored',
  'Overview',
  'Boards',
  'Sessions',
  'Project facts',
];

/// The strings the other screens gained for projects (the rest of those files
/// is not this feature's to vouch for).
const _elsewhere = [
  'Agents',
  'No project',
  'Project: {name}',
  'All projects',
  'No board belongs to this project.',
  'Project: {name} · Workspace: {dir}',
  'Follows the project — change it in the project.',
  'The folder follows the project',
  'In the project “{name}” — it works in the project folder.',
  'The session could not be created: {error}',
  'This project has no facts.',
  'typed',
  'Typed by hand; what a conversation says never replaces it.',
  'Kept from a kanban card that a worker finished.',
];

String _unquote(String token) {
  final body = token.substring(1, token.length - 1);
  return body.replaceAllMapped(
      RegExp(r'\\(.)'), (m) => m[1] == 'n' ? '\n' : m[1]!);
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

  test('every string of the project screens has a Vietnamese entry', () {
    final files = Directory('lib/features/projects')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList();
    expect(files, isNotEmpty);
    final missing = <String>[];
    for (final f in files) {
      for (final key in _keysIn(f.readAsStringSync())) {
        if (_sameInVietnamese.contains(key)) continue;
        if (vi.t(key) == key) missing.add('${f.uri.pathSegments.last}: $key');
      }
    }
    expect(missing, isEmpty, reason: missing.join('\n'));
  });

  test('so do the strings projects added to the other screens', () {
    final missing = [
      for (final key in [..._dynamic, ..._elsewhere])
        if (!_sameInVietnamese.contains(key) && vi.t(key) == key) key,
    ];
    expect(missing, isEmpty, reason: missing.join('\n'));
  });

  test('the extractor reads adjacent literals and escapes', () {
    expect(
        _keysIn("""Text(context.tr('One '
            'two'));
        context.trArgs("Say \\"hi\\" {n}", {})"""),
        {'One two', 'Say "hi" {n}'});
  });

  test('a message that holds a placeholder keeps it in Vietnamese', () {
    for (final key in [
      '{n} sessions',
      'Delete “{name}” for good?',
      '{n} / {max} characters',
      'Could not check the folder: {error}',
      'The project “{name}” already uses this folder.',
      'Project deleted — {facts} facts removed, {chats} sessions detached.',
    ]) {
      final placeholders =
          RegExp(r'\{(\w+)\}').allMatches(key).map((m) => m[1]).toSet();
      final translated = vi.t(key);
      expect(
          RegExp(r'\{(\w+)\}').allMatches(translated).map((m) => m[1]).toSet(),
          placeholders,
          reason: '$key → $translated');
    }
  });
}
