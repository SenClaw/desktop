import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/prefs.dart';
import '../../core/transport/connection.dart';

/// Below these a column stops being usable, so [FilePaneSplit] lets the pane
/// cover the chat rather than crush both. 360 is what the composer's short row
/// needs with the model's name cut to nothing.
const double kMinChatWidth = 360;
const double kMinFilePaneWidth = 300;

/// What the daemon answers in place of text for a file it will not decode
/// (`read_file` in the daemon's `ui_server/workspace.rs`).
const _binaryNotice = '(binary file — cannot display)';

class WorkspaceFile {
  const WorkspaceFile({required this.content, this.truncated = false});
  final String content;

  /// The daemon cut the file at 512 KB.
  final bool truncated;

  /// No text to show. With [truncated] it may be a text file cut in the middle
  /// of a character, which fails the same UTF-8 check.
  bool get unreadable => content == _binaryNotice;
}

/// One file as the daemon reads it now. Released with the last tab showing it,
/// so coming back to a tab reads the file again.
final workspaceFileProvider = FutureProvider.autoDispose
    .family<WorkspaceFile, String>((ref, path) async {
  final r = await ref
      .read(apiClientProvider)
      .get('/api/workspace/file', query: {'path': path});
  final m = r is Map ? r : const {};
  return WorkspaceFile(
    content: '${m['content'] ?? ''}',
    truncated: m['truncated'] == true,
  );
});

/// The files open in one chat's pane. [visible] is separate from [paths] so the
/// pane can step aside for the dock, or for the chat in a narrow window, without
/// the person losing their tabs.
class FilePaneState {
  const FilePaneState({
    this.paths = const [],
    this.active,
    this.visible = false,
    this.expanded = false,
  });
  final List<String> paths;
  final String? active;
  final bool visible;

  /// The pane has taken the whole chat area.
  final bool expanded;

  bool get isOpen => visible && active != null;

  FilePaneState copyWith({
    List<String>? paths,
    String? active,
    bool? visible,
    bool? expanded,
  }) =>
      FilePaneState(
        paths: paths ?? this.paths,
        active: active ?? this.active,
        visible: visible ?? this.visible,
        expanded: expanded ?? this.expanded,
      );
}

class FilePaneNotifier extends StateNotifier<FilePaneState> {
  FilePaneNotifier() : super(const FilePaneState());

  void open(String path) => state = state.copyWith(
        paths: state.paths.contains(path) ? null : [...state.paths, path],
        active: path,
        visible: true,
      );

  void activate(String path) => state = state.copyWith(active: path);

  /// Closing a tab lands on the one that took its place; closing the last one
  /// closes the pane.
  void close(String path) {
    final i = state.paths.indexOf(path);
    if (i < 0) return;
    final paths = [...state.paths]..removeAt(i);
    if (paths.isEmpty) {
      state = const FilePaneState();
      return;
    }
    state = state.copyWith(
      paths: paths,
      active: state.active == path ? paths[i.clamp(0, paths.length - 1)] : null,
    );
  }

  void hide() => state = state.copyWith(visible: false, expanded: false);

  void toggleExpanded() => state = state.copyWith(expanded: !state.expanded);
}

/// One pane per chat, so moving between chats brings each one's files back.
final filePaneProvider =
    StateNotifierProvider.family<FilePaneNotifier, FilePaneState, String>(
        (ref, jid) => FilePaneNotifier());

/// The width the person dragged the pane to; null until they do, when it takes
/// half of the room.
final filePaneWidthProvider = StateProvider<double?>((ref) => double.tryParse(
    ref.read(prefsHelperProvider).string('chat:filePaneWidth', '')));

/// Show [path] in [jid]'s pane. A file already open is read again: it is usually
/// the row of a newer edit that was clicked.
void openFileInPane(WidgetRef ref, {required String jid, required String path}) {
  ref.read(filePaneProvider(jid).notifier).open(path);
  ref.invalidate(workspaceFileProvider(path));
}

final _absolute = RegExp(r'^(?:[/\\~]|[A-Za-z]:[/\\])');

/// A refused call names its file as the model wrote it; the daemon reads only
/// absolute paths, so a relative one is taken from the chat's folder.
String resolveChatPath(String path, String? workDir) {
  if (workDir == null || workDir.isEmpty || _absolute.hasMatch(path)) {
    return path;
  }
  final sep = workDir.contains(r'\') ? r'\' : '/';
  final base = workDir.endsWith(sep)
      ? workDir.substring(0, workDir.length - 1)
      : workDir;
  final rel = path.startsWith('./') ? path.substring(2) : path;
  return '$base$sep$rel';
}

final _separator = RegExp(r'[/\\]');

List<String> _segments(String path) =>
    path.split(_separator).where((s) => s.isNotEmpty).toList();

String fileNameOf(String path) {
  final parts = _segments(path);
  return parts.isEmpty ? path : parts.last;
}

/// The path as a breadcrumb: from the chat's folder when the file is in it, the
/// whole way down otherwise.
List<String> pathCrumbs(String path, String? workDir) {
  final parts = _segments(path);
  final root = workDir == null ? const <String>[] : _segments(workDir);
  if (root.isEmpty || parts.length <= root.length) return parts;
  for (var i = 0; i < root.length; i++) {
    if (parts[i] != root[i]) return parts;
  }
  return parts.sublist(root.length - 1);
}

/// A tab's label: the file's name, with its folder when another open file has
/// the same name.
String tabLabel(String path, List<String> open) {
  final name = fileNameOf(path);
  final twin = open.any((p) => p != path && fileNameOf(p) == name);
  if (!twin) return name;
  final parts = _segments(path);
  return parts.length < 2 ? name : '${parts[parts.length - 2]}/$name';
}

bool isMarkdownPath(String path) {
  final name = fileNameOf(path).toLowerCase();
  return name.endsWith('.md') ||
      name.endsWith('.markdown') ||
      name.endsWith('.mdx');
}

bool isHtmlPath(String path) {
  final name = fileNameOf(path).toLowerCase();
  return name.endsWith('.html') || name.endsWith('.htm');
}
