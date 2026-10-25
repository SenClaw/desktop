// The strings a source file passes to `tr` / `trArgs`, read from its text: the
// English text is the lookup key, so a key without a Vietnamese entry silently
// shows English. Adjacent literals are joined the way Dart joins them.

String _unquote(String token) {
  final body = token.substring(1, token.length - 1);
  return body.replaceAllMapped(
      RegExp(r'\\(.)'), (m) => m[1] == 'n' ? '\n' : m[1]!);
}

Set<String> trKeysIn(String source) {
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
