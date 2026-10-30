/// A heading of a Markdown file, in the contents list.
class MdHeading {
  const MdHeading({
    required this.level,
    required this.title,
    required this.line,
    required this.section,
  });
  final int level;
  final String title;

  /// Zero-based line of the source, for the source view.
  final int line;

  /// Index into [MdOutline.sections], for the rendered view.
  final int section;
}

/// A Markdown file cut at its headings. Each section renders as its own widget,
/// which gives the contents list something to scroll to.
class MdOutline {
  const MdOutline({
    required this.sections,
    required this.headings,
    required this.renderable,
  });
  final List<String> sections;
  final List<MdHeading> headings;

  /// False when a section stayed too long to render: the markdown package blocks
  /// the UI thread for a time that grows faster than the text does.
  final bool renderable;
}

/// A section longer than this ends at its next blank line. The markdown package
/// took a minute on 256 KB without a heading and seconds on the same text cut up
/// (debug build), so what matters is the longest section, not the file.
const _softSectionChars = 4 * 1024;

/// A section with no blank line in it ends at any line, unless that is the
/// inside of a table, which would lose its header.
const _hardSectionChars = 16 * 1024;

/// One line this long, or a table, cannot be cut at all.
const _maxSectionChars = 32 * 1024;

final _fence = RegExp(r'^ {0,3}(`{3,}|~{3,})');
final _heading = RegExp(r'^ {0,3}(#{1,6}) +(.+?)(?: +#*)? *$');
final _link = RegExp(r'\[([^\]]*)\]\([^)]*\)');

/// Headings are read line by line, not with one pattern over the file: a `#`
/// inside a code fence is a comment, not a heading, and that takes knowing where
/// the fences are. Comments on lines of their own are dropped, as every Markdown
/// renderer does; the markdown package here would print them.
MdOutline parseMarkdown(String source) {
  final sections = <String>[];
  final headings = <MdHeading>[];
  final current = <String>[];
  var chars = 0;
  var renderable = true;
  String? fence;
  var inComment = false;

  void flush() {
    if (current.isEmpty) return;
    sections.add(current.join('\n'));
    current.clear();
    if (chars > _maxSectionChars) renderable = false;
    chars = 0;
  }

  void keep(String line) {
    current.add(line);
    chars += line.length + 1;
  }

  final lines = source.split('\n');
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i].endsWith('\r')
        ? lines[i].substring(0, lines[i].length - 1)
        : lines[i];
    if (fence != null) {
      keep(line);
      if (line.trimLeft().startsWith(fence)) fence = null;
      continue;
    }
    final trimmed = line.trim();
    if (inComment) {
      inComment = !trimmed.endsWith('-->');
      continue;
    }
    if (trimmed.startsWith('<!--')) {
      inComment = !trimmed.endsWith('-->');
      continue;
    }
    final open = _fence.firstMatch(line);
    if (open != null) {
      fence = open[1]![0] * 3;
      keep(line);
      continue;
    }
    final h = _heading.firstMatch(line);
    if (h != null) {
      flush();
      headings.add(MdHeading(
        level: h[1]!.length,
        title: _plain(h[2]!),
        line: i,
        section: sections.length,
      ));
    } else if (chars > _softSectionChars && trimmed.isEmpty ||
        chars > _hardSectionChars && !trimmed.startsWith('|')) {
      flush();
    }
    keep(line);
  }
  flush();
  return MdOutline(
    sections: sections,
    headings: headings,
    renderable: renderable,
  );
}

/// A heading's words without its inline marks.
String _plain(String title) => title
    .replaceAllMapped(_link, (m) => m[1]!)
    .replaceAll(RegExp(r'[*`]'), '')
    .trim();
