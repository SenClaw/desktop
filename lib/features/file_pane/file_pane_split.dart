import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/prefs.dart';
import '../../theme/tokens.dart';
import 'file_pane.dart';
import 'file_pane_provider.dart';

const double _gripWidth = 5;

/// A chat and its [FilePane], side by side while there is room for both. With
/// too little room, or expanded, the pane covers the chat; closing it brings the
/// chat back.
///
/// The chat is positioned, never reparented: it stays mounted in the same place
/// through all of this, so a half-typed message and the scroll position survive
/// the pane opening, expanding and closing.
class FilePaneSplit extends ConsumerWidget {
  const FilePaneSplit({super.key, required this.jid, required this.chat});
  final String jid;
  final Widget chat;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pane = ref.watch(filePaneProvider(jid));
    final dragged = ref.watch(filePaneWidthProvider);
    return LayoutBuilder(builder: (context, box) {
      final width = box.maxWidth;
      final open = pane.isOpen;
      final roomForBoth = width >= kMinChatWidth + kMinFilePaneWidth;
      final covered = open && (pane.expanded || !roomForBoth);
      final paneWidth = !open
          ? 0.0
          : covered
              ? width
              : (dragged ?? width / 2)
                  .clamp(kMinFilePaneWidth, width - kMinChatWidth);
      return Stack(
        children: [
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            // Keeps its own width under the pane: squeezed to nothing, a
            // hidden chat would still lay every message out at that width.
            width: open && !covered ? width - paneWidth : width,
            child: ExcludeFocus(
              excluding: covered,
              child: Visibility(
                visible: !covered,
                maintainState: true,
                child: chat,
              ),
            ),
          ),
          if (open)
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              width: paneWidth,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!covered)
                    _Grip(
                      min: kMinFilePaneWidth,
                      max: width - kMinChatWidth,
                      current: paneWidth,
                    ),
                  Expanded(
                    child: FilePane(
                      key: ValueKey(jid),
                      jid: jid,
                      canExpand: roomForBoth,
                    ),
                  ),
                ],
              ),
            ),
        ],
      );
    });
  }
}

/// The pane's left edge: drag left to widen it, like the dock's.
class _Grip extends ConsumerWidget {
  const _Grip({required this.min, required this.max, required this.current});
  final double min;
  final double max;
  final double current;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragUpdate: (d) {
          final from = ref.read(filePaneWidthProvider) ?? current;
          ref.read(filePaneWidthProvider.notifier).state =
              (from - d.delta.dx).clamp(min, max);
        },
        onHorizontalDragEnd: (_) {
          final w = ref.read(filePaneWidthProvider);
          if (w == null) return;
          ref
              .read(prefsHelperProvider)
              .setString('chat:filePaneWidth', w.toStringAsFixed(0));
        },
        child: Container(
          width: _gripWidth,
          color: Colors.transparent,
          alignment: Alignment.center,
          child: Container(width: 1, color: c.border),
        ),
      ),
    );
  }
}
