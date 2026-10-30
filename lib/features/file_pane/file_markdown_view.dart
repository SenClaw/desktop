import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../theme/tokens.dart';
import '../../widgets/app_markdown.dart';
import 'file_view_controller.dart';
import 'markdown_outline.dart';

const _padding = EdgeInsets.fromLTRB(
    AppTokens.s24, AppTokens.s12, AppTokens.s24, AppTokens.s32);

/// A Markdown file as a reader sees it.
///
/// Search looks at the text on screen, not at the source: it walks the
/// paragraphs the markdown package laid out, asks each where a match sits and
/// paints over it. Finding matches in the source could not mark them, since the
/// package offers no way to style a stretch of plain text, and it would count
/// words a reader cannot see, such as a link's address.
class FileMarkdownView extends StatefulWidget {
  const FileMarkdownView(
      {super.key, required this.outline, required this.view});
  final MdOutline outline;
  final FileViewController view;

  @override
  State<FileMarkdownView> createState() => _FileMarkdownViewState();
}

class _FileMarkdownViewState extends State<FileMarkdownView> {
  final _scroll = ScrollController();
  final _content = GlobalKey();
  late List<GlobalKey> _sections;

  /// One entry per match; a match that wraps has a box per line.
  List<List<Rect>> _hits = const [];
  String _query = '';
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _sections = _keysFor(widget.outline);
    _attach(widget.view);
    _query = widget.view.query;
    _index = widget.view.index;
    _collectAfterLayout(reveal: true);
  }

  @override
  void didUpdateWidget(FileMarkdownView old) {
    super.didUpdateWidget(old);
    if (old.view != widget.view) {
      _detach(old.view);
      _attach(widget.view);
    }
    if (old.outline != widget.outline) {
      _sections = _keysFor(widget.outline);
      _collectAfterLayout();
    }
  }

  @override
  void dispose() {
    _detach(widget.view);
    _scroll.dispose();
    super.dispose();
  }

  List<GlobalKey> _keysFor(MdOutline o) =>
      [for (final _ in o.sections) GlobalKey()];

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
      _collect(reveal: true);
    } else if (v.index != _index) {
      setState(() => _index = v.index);
      _reveal();
    }
  }

  void _jump(MdHeading h) {
    final context = _sections[h.section].currentContext;
    if (context == null) return;
    Scrollable.ensureVisible(context,
        duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
  }

  void _collectAfterLayout({bool reveal = false}) =>
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _collect(reveal: reveal);
      });

  void _collect({bool reveal = false}) {
    final root = _content.currentContext?.findRenderObject() as RenderBox?;
    final hits = <List<Rect>>[];
    if (root != null && _query.isNotEmpty) {
      final matcher = matcherFor(_query);
      void visit(RenderObject node) {
        if (node is RenderParagraph) {
          final toRoot = node.getTransformTo(root);
          for (final m in matcher.allMatches(node.text.toPlainText())) {
            final boxes = node.getBoxesForSelection(
                TextSelection(baseOffset: m.start, extentOffset: m.end));
            if (boxes.isEmpty) continue;
            hits.add([
              for (final b in boxes)
                MatrixUtils.transformRect(toRoot, b.toRect()),
            ]);
          }
        }
        node.visitChildren(visit);
      }

      visit(root);
    }
    setState(() => _hits = hits);
    widget.view.report(hits.length);
    if (reveal) _reveal();
  }

  void _reveal() {
    if (_hits.isEmpty || !_scroll.hasClients) return;
    final top = _hits[_index.clamp(0, _hits.length - 1)].first.top;
    final pos = _scroll.position;
    _scroll.jumpTo(
        (top - pos.viewportDimension * 0.3).clamp(0.0, pos.maxScrollExtent));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final style = TextStyle(color: c.textPrimary, fontSize: 14, height: 1.55);
    return SelectionArea(
      child: Scrollbar(
        controller: _scroll,
        child: SingleChildScrollView(
          controller: _scroll,
          padding: _padding,
          // A wrapped line or an image that arrives late moves every match.
          child: NotificationListener<SizeChangedLayoutNotification>(
            onNotification: (_) {
              if (_query.isNotEmpty) _collectAfterLayout();
              return true;
            },
            child: SizeChangedLayoutNotifier(
              child: CustomPaint(
                key: _content,
                foregroundPainter: _HitsPainter(_hits, _index),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < widget.outline.sections.length; i++)
                      Padding(
                        key: _sections[i],
                        padding: const EdgeInsets.only(bottom: AppTokens.s8),
                        child:
                            AppMarkdown(widget.outline.sections[i], style: style),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HitsPainter extends CustomPainter {
  _HitsPainter(this.hits, this.current);
  final List<List<Rect>> hits;
  final int current;

  @override
  void paint(Canvas canvas, Size size) {
    final other = Paint()..color = AppTokens.warning.withValues(alpha: 0.3);
    final strong = Paint()..color = AppTokens.warning.withValues(alpha: 0.6);
    for (var i = 0; i < hits.length; i++) {
      for (final r in hits[i]) {
        canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(2)),
            i == current ? strong : other);
      }
    }
  }

  @override
  bool shouldRepaint(_HitsPainter old) =>
      old.hits != hits || old.current != current;
}
