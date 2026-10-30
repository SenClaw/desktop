import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/tokens.dart';
import 'file_view_controller.dart';
import 'markdown_outline.dart';

/// Rows are built lazily at one fixed height, so a 512 KB file scrolls as easily
/// as a small one and a line number is a scroll offset.
const double _rowHeight = 20;

/// A minified file is one enormous line; it is cut into rows of this length so
/// that all of it can still be seen and laid out.
const int _maxRowChars = 2000;

const double _gutterGap = AppTokens.s12;

class _Row {
  const _Row(this.number, this.text);

  /// The source line, on the first row of that line only.
  final int? number;
  final String text;
}

class _Hit {
  const _Hit(this.row, this.start, this.end);
  final int row;
  final int start;
  final int end;
}

List<_Row> _rowsOf(String text) {
  final lines = text.split('\n');
  if (lines.length > 1 && lines.last.isEmpty) lines.removeLast();
  final rows = <_Row>[];
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i];
    if (line.endsWith('\r')) line = line.substring(0, line.length - 1);
    if (line.length <= _maxRowChars) {
      rows.add(_Row(i + 1, line));
      continue;
    }
    for (var at = 0; at < line.length; at += _maxRowChars) {
      rows.add(_Row(at == 0 ? i + 1 : null,
          line.substring(at, math.min(at + _maxRowChars, line.length))));
    }
  }
  return rows;
}

/// A file as text: line numbers, no wrapping, scrolls both ways.
class FileSourceView extends StatefulWidget {
  const FileSourceView({super.key, required this.text, required this.view});
  final String text;
  final FileViewController view;

  @override
  State<FileSourceView> createState() => _FileSourceViewState();
}

class _FileSourceViewState extends State<FileSourceView> {
  final _vertical = ScrollController();
  final _horizontal = ScrollController();
  late List<_Row> _rows;
  double? _textWidth;
  List<_Hit> _hits = const [];
  Map<int, List<int>> _hitsOfRow = const {};
  String _query = '';
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _rows = _rowsOf(widget.text);
    _attach(widget.view);
    _query = widget.view.query;
    _index = widget.view.index;
    _find();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.view.report(_hits.length);
      _reveal();
    });
  }

  @override
  void didUpdateWidget(FileSourceView old) {
    super.didUpdateWidget(old);
    if (old.view != widget.view) {
      _detach(old.view);
      _attach(widget.view);
    }
    if (old.text != widget.text) {
      _rows = _rowsOf(widget.text);
      _textWidth = null;
      _find();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.view.report(_hits.length);
      });
    }
  }

  @override
  void dispose() {
    _detach(widget.view);
    _vertical.dispose();
    _horizontal.dispose();
    super.dispose();
  }

  void _attach(FileViewController view) {
    view.addListener(_onView);
    view.onJump = _jump;
  }

  void _detach(FileViewController view) {
    view.removeListener(_onView);
    if (view.onJump == _jump) view.onJump = null;
  }

  void _onView() {
    final v = widget.view;
    if (v.query != _query) {
      _query = v.query;
      _index = v.index;
      setState(_find);
      v.report(_hits.length);
      _reveal();
    } else if (v.index != _index) {
      setState(() => _index = v.index);
      _reveal();
    }
  }

  void _find() {
    final hits = <_Hit>[];
    final byRow = <int, List<int>>{};
    if (_query.isNotEmpty) {
      final matcher = matcherFor(_query);
      for (var r = 0; r < _rows.length; r++) {
        for (final m in matcher.allMatches(_rows[r].text)) {
          (byRow[r] ??= []).add(hits.length);
          hits.add(_Hit(r, m.start, m.end));
        }
      }
    }
    _hits = hits;
    _hitsOfRow = byRow;
  }

  void _scrollToRow(int row) {
    if (!_vertical.hasClients) return;
    final pos = _vertical.position;
    _vertical.jumpTo((row * _rowHeight - pos.viewportDimension * 0.3)
        .clamp(0.0, pos.maxScrollExtent));
  }

  void _jump(MdHeading h) {
    final row = _rows.indexWhere((r) => r.number == h.line + 1);
    if (row >= 0) _scrollToRow(row);
  }

  void _reveal() {
    if (_hits.isEmpty) return;
    final hit = _hits[_index.clamp(0, _hits.length - 1)];
    _scrollToRow(hit.row);
    if (!_horizontal.hasClients) return;
    final before = TextPainter(
      text: TextSpan(
          text: _rows[hit.row].text.substring(0, hit.start),
          style: _textStyle(context)),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final x = _gutterWidth + before.width;
    before.dispose();
    final pos = _horizontal.position;
    if (x < pos.pixels || x > pos.pixels + pos.viewportDimension - 48) {
      _horizontal.jumpTo(
          (x - pos.viewportDimension * 0.3).clamp(0.0, pos.maxScrollExtent));
    }
  }

  TextStyle _textStyle(BuildContext context) => TextStyle(
        color: context.colors.textPrimary,
        fontFamily: AppTokens.fontMono,
        // Flutter cannot find SF Mono by name on macOS, and code in a
        // proportional font loses its columns.
        fontFamilyFallback: const ['Menlo', 'Consolas', 'DejaVu Sans Mono'],
        fontSize: 12.5,
        height: 1.3,
      );

  double get _gutterWidth =>
      '${_rows.length}'.length * 8.0 + AppTokens.s12 + _gutterGap;

  /// Measured from the row with the most characters. Only that one: the point of
  /// this view is not laying every line out.
  double _measureText(TextStyle style) {
    var longest = '';
    for (final r in _rows) {
      if (r.text.length > longest.length) longest = r.text;
    }
    final p = TextPainter(
      text: TextSpan(text: longest, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final width = p.width;
    p.dispose();
    return width;
  }

  /// The trailing newline is what a copy across rows joins them with; selection
  /// puts nothing between two `Text`s.
  TextSpan _rowSpan(int r, TextStyle style) {
    final text = _rows[r].text;
    final hits = _hitsOfRow[r];
    if (hits == null) return TextSpan(text: '$text\n');
    final spans = <TextSpan>[];
    var at = 0;
    for (final i in hits) {
      final h = _hits[i];
      if (h.start > at) spans.add(TextSpan(text: text.substring(at, h.start)));
      spans.add(TextSpan(
        text: text.substring(h.start, h.end),
        style: TextStyle(
            backgroundColor: AppTokens.warning
                .withValues(alpha: i == _index ? 0.6 : 0.3)),
      ));
      at = h.end;
    }
    spans.add(TextSpan(text: '${text.substring(at)}\n'));
    return TextSpan(children: spans);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final style = _textStyle(context);
    final numbers = style.copyWith(color: c.textMuted);
    final textWidth = _textWidth ??= _measureText(style);
    final gutter = _gutterWidth;
    return LayoutBuilder(builder: (context, box) {
      final width = math.max(
          box.maxWidth, gutter + textWidth + AppTokens.s24);
      return SelectionArea(
        child: Scrollbar(
          controller: _horizontal,
          child: SingleChildScrollView(
            controller: _horizontal,
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: width,
              height: box.maxHeight,
              child: Scrollbar(
                controller: _vertical,
                notificationPredicate: (n) => n.depth == 0,
                child: ListView.builder(
                  controller: _vertical,
                  padding: const EdgeInsets.symmetric(vertical: AppTokens.s8),
                  itemExtent: _rowHeight,
                  itemCount: _rows.length,
                  itemBuilder: (context, r) => Row(
                    children: [
                      SizedBox(
                        width: gutter - _gutterGap,
                        child: SelectionContainer.disabled(
                          child: Text(
                            '${_rows[r].number ?? ''}',
                            textAlign: TextAlign.right,
                            style: numbers,
                          ),
                        ),
                      ),
                      const SizedBox(width: _gutterGap),
                      Expanded(
                        child: Text.rich(
                          _rowSpan(r, style),
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.clip,
                          style: style,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    });
  }
}
