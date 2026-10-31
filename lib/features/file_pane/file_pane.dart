import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/l10n.dart';
import '../../core/transport/api_client.dart';
import '../../theme/tokens.dart';
import '../chat/groups_provider.dart';
import 'file_markdown_view.dart';
import 'file_pane_provider.dart';
import 'file_source_view.dart';
import '../../widgets/browser_web_view.dart';
import 'file_view_controller.dart';
import 'markdown_outline.dart';

/// The files a chat opened, beside the conversation: a tab per file, the path
/// as a breadcrumb, and the file itself — rendered when it is Markdown, as text
/// otherwise. Reads through the daemon, like the dock's Files tab.
class FilePane extends ConsumerStatefulWidget {
  const FilePane({super.key, required this.jid, required this.canExpand});
  final String jid;

  /// False when the pane already covers the chat because the window is narrow.
  final bool canExpand;

  @override
  ConsumerState<FilePane> createState() => _FilePaneState();
}

class _FilePaneState extends ConsumerState<FilePane> {
  final _view = FileViewController();
  final _query = TextEditingController();
  final _queryFocus = FocusNode();
  final _activeTab = GlobalKey();
  bool _searching = false;

  /// Markdown files the person switched to their source.
  final _showingSource = <String>{};
  String? _revealedTab;

  // Parsed once per read: the build runs on every keystroke of a search.
  WorkspaceFile? _parsedFile;
  MdOutline? _outline;

  @override
  void dispose() {
    _view.dispose();
    _query.dispose();
    _queryFocus.dispose();
    super.dispose();
  }

  MdOutline _outlineOf(WorkspaceFile file) {
    if (!identical(file, _parsedFile)) {
      _parsedFile = file;
      _outline = parseMarkdown(file.content);
    }
    return _outline!;
  }

  void _openSearch() {
    setState(() => _searching = true);
    _queryFocus.requestFocus();
    _query.selection =
        TextSelection(baseOffset: 0, extentOffset: _query.text.length);
  }

  void _closeSearch() {
    setState(() => _searching = false);
    _query.clear();
    _view.search('');
  }

  /// A tab opened past the end of the strip scrolls into sight.
  void _revealTab(String active) {
    if (_revealedTab == active) return;
    _revealedTab = active;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final tab = _activeTab.currentContext;
      if (tab != null) {
        Scrollable.ensureVisible(tab,
            duration: const Duration(milliseconds: 150));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final pane = ref.watch(filePaneProvider(widget.jid));
    final notifier = ref.read(filePaneProvider(widget.jid).notifier);
    final path = pane.active;
    if (path == null) return const SizedBox.shrink();
    _revealTab(path);

    final file = ref.watch(workspaceFileProvider(path));
    final data = file.valueOrNull;
    final parsed = isMarkdownPath(path) && data != null && !data.unreadable
        ? _outlineOf(data)
        : null;
    final outline = parsed != null && parsed.renderable ? parsed : null;
    final markdown = outline != null;
    final html = isHtmlPath(path) &&
        BrowserWebView.supported &&
        data != null &&
        !data.unreadable;
    final source = !(markdown || html) || _showingSource.contains(path);
    final workDir = ref
        .watch(groupsProvider)
        .where((g) => g.jid == widget.jid)
        .firstOrNull
        ?.workDir;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyF, meta: true): _openSearch,
        const SingleActivator(LogicalKeyboardKey.keyF, control: true):
            _openSearch,
      },
      child: Container(
        color: c.surface,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              // The chat header's height, so the two rules meet.
              height: 56,
              padding: const EdgeInsets.only(
                  left: AppTokens.s8, right: AppTokens.s4),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: c.border)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final p in pane.paths)
                            _FileTab(
                              key: p == path ? _activeTab : ValueKey(p),
                              label: tabLabel(p, pane.paths),
                              path: p,
                              active: p == path,
                              onTap: () => notifier.activate(p),
                              onClose: () => notifier.close(p),
                            ),
                        ],
                      ),
                    ),
                  ),
                  _ToolButton(
                    icon: Icons.search,
                    tooltip: context.tr('Search in file'),
                    selected: _searching,
                    onPressed: _searching ? _closeSearch : _openSearch,
                  ),
                  if (outline != null && outline.headings.isNotEmpty)
                    PopupMenuButton<MdHeading>(
                      tooltip: context.tr('Contents'),
                      icon: const Icon(Icons.toc, size: 18),
                      iconColor: c.textSecondary,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                          minWidth: 200, maxWidth: 340, maxHeight: 420),
                      onSelected: (h) => _view.onJump?.call(h),
                      itemBuilder: (_) => [
                        for (final h in outline.headings)
                          PopupMenuItem(
                            value: h,
                            height: 34,
                            child: Padding(
                              padding: EdgeInsets.only(
                                  left: (h.level - 1) * AppTokens.s12),
                              child: Text(h.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      color: c.textPrimary, fontSize: 13)),
                            ),
                          ),
                      ],
                    ),
                  if (widget.canExpand)
                    _ToolButton(
                      icon: pane.expanded
                          ? Icons.close_fullscreen
                          : Icons.open_in_full,
                      iconSize: 15,
                      tooltip: pane.expanded
                          ? context.tr('Shrink')
                          : context.tr('Expand'),
                      onPressed: notifier.toggleExpanded,
                    ),
                  _ToolButton(
                    icon: Icons.close,
                    tooltip: context.tr('Close'),
                    onPressed: notifier.hide,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppTokens.s16, AppTokens.s4, AppTokens.s4, AppTokens.s4),
              child: Row(
                children: [
                  Expanded(child: _Breadcrumb(path: path, workDir: workDir)),
                  if (markdown || html)
                    _ToolButton(
                      icon: Icons.code,
                      tooltip: source
                          ? context.tr('View rendered')
                          : context.tr('View source'),
                      selected: source,
                      onPressed: () => setState(() {
                        if (!_showingSource.remove(path)) {
                          _showingSource.add(path);
                        }
                      }),
                    ),
                ],
              ),
            ),
            if (_searching)
              _SearchBar(
                view: _view,
                query: _query,
                focus: _queryFocus,
                onClose: _closeSearch,
              ),
            Divider(height: 1, color: c.border),
            Expanded(
              child: file.when(
                loading: () => const Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
                error: (e, _) => _Problem(
                  icon: Icons.error_outline,
                  title: context.trArgs(
                      'Cannot open {name}', {'name': fileNameOf(path)}),
                  reason: _reasonFor(context, e),
                  path: path,
                  onRetry: () => ref.invalidate(workspaceFileProvider(path)),
                ),
                data: (f) => _body(context, path, f, source, outline),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(BuildContext context, String path, WorkspaceFile file,
      bool source, MdOutline? outline) {
    final c = context.colors;
    if (file.unreadable) {
      return _Problem(
        icon: Icons.block,
        title: context.trArgs('Cannot show {name}', {'name': fileNameOf(path)}),
        reason: file.truncated
            ? context.tr('This file is over 512 KB and could not be read as text.')
            : context.tr('This is a binary file, not text.'),
        path: path,
      );
    }
    if (file.content.isEmpty) {
      return Center(
        child: Text(context.tr('(empty file)'),
            style: TextStyle(color: c.textMuted, fontSize: 13)),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          // One state per file and view, each with its own place in the file:
          // the key is also what the scroll offset is stored under.
          child: KeyedSubtree(
            key: PageStorageKey('$path|$source'),
            child: source
                ? FileSourceView(text: file.content, view: _view)
                : outline != null
                    ? FileMarkdownView(outline: outline, view: _view)
                    : EmbeddedHtmlContent(
                        html: file.content, baseUrl: _htmlBaseUrl(path)),
          ),
        ),
        if (file.truncated)
          Container(
            padding: const EdgeInsets.all(AppTokens.s8),
            color: AppTokens.warning.withValues(alpha: 0.12),
            child: Text(context.tr('Truncated to 512 KB'),
                style: TextStyle(color: c.textMuted, fontSize: 11)),
          ),
      ],
    );
  }

  /// `file://…/` base for a single HTML file's relative links. See
  /// [EmbeddedHtmlContent] on why sibling assets still won't load.
  String? _htmlBaseUrl(String path) {
    final i = path.lastIndexOf('/');
    if (i < 0) return null;
    try {
      return Uri.directory(path.substring(0, i + 1)).toString();
    } catch (_) {
      return null;
    }
  }

  String _reasonFor(BuildContext context, Object error) {
    if (error is ApiTimeout) {
      return context.tr('SenClaw did not answer in time.');
    }
    if (error is ApiException) {
      return switch (error.message) {
        'not a file' =>
          context.tr('This file does not exist, or the path is a folder.'),
        'path must be absolute' => context
            .tr('The path is relative and this chat has no working folder.'),
        _ => error.message,
      };
    }
    return '$error';
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.iconSize = 18,
    this.selected = false,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final double iconSize;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return IconButton(
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      icon: Icon(icon,
          size: iconSize, color: selected ? c.accent : c.textSecondary),
      onPressed: onPressed,
    );
  }
}

class _FileTab extends StatelessWidget {
  const _FileTab({
    super.key,
    required this.label,
    required this.path,
    required this.active,
    required this.onTap,
    required this.onClose,
  });
  final String label;
  final String path;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(right: AppTokens.s4),
      child: Tooltip(
        message: path,
        waitDuration: const Duration(milliseconds: 600),
        child: Material(
          color: active ? c.accentSoft : Colors.transparent,
          borderRadius: BorderRadius.circular(AppTokens.rMd),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppTokens.rMd),
            child: Padding(
              padding: const EdgeInsets.only(
                  left: AppTokens.s12, right: AppTokens.s4),
              child: SizedBox(
                height: 30,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 180),
                      child: Text(label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: active ? c.textPrimary : c.textSecondary,
                            fontSize: 13,
                          )),
                    ),
                    const SizedBox(width: AppTokens.s4),
                    InkWell(
                      onTap: onClose,
                      borderRadius: BorderRadius.circular(AppTokens.rFull),
                      child: Tooltip(
                        message: context.tr('Close file'),
                        child: Padding(
                          padding: const EdgeInsets.all(AppTokens.s4),
                          child:
                              Icon(Icons.close, size: 14, color: c.textMuted),
                        ),
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
  }
}

/// `senclaw / plans / report.md`. Reads from the left, and a path too long for
/// the pane scrolls from its end: the file's own name is the part to keep in
/// sight.
class _Breadcrumb extends StatelessWidget {
  const _Breadcrumb({required this.path, required this.workDir});
  final String path;
  final String? workDir;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final crumbs = pathCrumbs(path, workDir);
    return Tooltip(
      message: path,
      waitDuration: const Duration(milliseconds: 600),
      child: LayoutBuilder(
        builder: (context, box) => SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          reverse: true,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: box.maxWidth),
            child: Text.rich(
              TextSpan(children: [
                for (var i = 0; i < crumbs.length; i++) ...[
                  if (i > 0)
                    TextSpan(
                        text: ' / ', style: TextStyle(color: c.textMuted)),
                  TextSpan(
                    text: crumbs[i],
                    style: TextStyle(
                        color: i == crumbs.length - 1
                            ? c.textPrimary
                            : c.textSecondary),
                  ),
                ],
              ]),
              maxLines: 1,
              softWrap: false,
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ),
      ),
    );
  }
}

class _SearchBar extends StatelessWidget {
  const _SearchBar({
    required this.view,
    required this.query,
    required this.focus,
    required this.onClose,
  });
  final FileViewController view;
  final TextEditingController query;
  final FocusNode focus;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppTokens.s12, 0, AppTokens.s4, AppTokens.s4),
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): onClose,
          const SingleActivator(LogicalKeyboardKey.enter, shift: true): () =>
              view.step(-1),
        },
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: query,
                focusNode: focus,
                autofocus: true,
                style: TextStyle(color: c.textPrimary, fontSize: 13),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: context.tr('Search in file'),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: AppTokens.s8, vertical: AppTokens.s6),
                ),
                onChanged: view.search,
                onSubmitted: (_) {
                  view.step(1);
                  focus.requestFocus();
                },
              ),
            ),
            ListenableBuilder(
              listenable: view,
              builder: (context, _) => Padding(
                padding: const EdgeInsets.only(left: AppTokens.s8),
                child: Text(
                  view.query.isEmpty
                      ? ''
                      : view.count == 0
                          ? context.tr('No results')
                          : '${view.index + 1}/${view.count}',
                  style: TextStyle(color: c.textMuted, fontSize: 12),
                ),
              ),
            ),
            _ToolButton(
              icon: Icons.keyboard_arrow_up,
              tooltip: context.tr('Previous match'),
              onPressed: () => view.step(-1),
            ),
            _ToolButton(
              icon: Icons.keyboard_arrow_down,
              tooltip: context.tr('Next match'),
              onPressed: () => view.step(1),
            ),
          ],
        ),
      ),
    );
  }
}

/// What stands in for a file that cannot be shown.
class _Problem extends StatelessWidget {
  const _Problem({
    required this.icon,
    required this.title,
    required this.reason,
    required this.path,
    this.onRetry,
  });
  final IconData icon;
  final String title;
  final String reason;
  final String path;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppTokens.s24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 28, color: c.textMuted),
            const SizedBox(height: AppTokens.s12),
            Text(title,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: AppTokens.s6),
            Text(reason,
                textAlign: TextAlign.center,
                style: TextStyle(color: c.textSecondary, fontSize: 13)),
            const SizedBox(height: AppTokens.s6),
            SelectableText(path,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: c.textMuted,
                    fontSize: 12,
                    fontFamily: AppTokens.fontMono)),
            if (onRetry != null) ...[
              const SizedBox(height: AppTokens.s12),
              OutlinedButton(
                  onPressed: onRetry, child: Text(context.tr('Retry'))),
            ],
          ],
        ),
      ),
    );
  }
}
