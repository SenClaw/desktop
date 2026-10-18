// Projects: client of `/api/projects*` (the daemon's
// `src/gateway/ui_server/projects.rs`).
//
// There is no push event for projects, so what is on screen is refreshed after
// every action of this window's own and when the window comes back to the
// front — a project edited from a second window shows up at the next refresh.

import 'package:file_picker/file_picker.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/transport/api_client.dart';
import '../../core/transport/connection.dart';
import '../../models/project.dart';
import '../chat/groups_provider.dart';
import '../cognitive/facts_panel.dart' show MemoryFact;
import '../kanban/kanban_providers.dart' show kanbanBoardsProvider;

/// How long the daemon may take to delete a project outright. Its fact bank is
/// removed a slice at a time and the cost per row grows with the whole text
/// index: 20 000 facts took about 23 s on a measured run, so the usual 30 s
/// request ceiling is too close.
const kProjectPurgeTimeout = Duration(minutes: 5);

/// Facts per project listing; the daemon caps a page at 200.
const kProjectFactsLimit = 100;

/// A fact is 8–600 characters (the daemon's `extract::{MIN,MAX}_FACT_CHARS`).
const kMinFactChars = 8;
const kMaxFactChars = 600;

/// Every project, archived ones included; the screens filter.
final projectsProvider = FutureProvider<List<Project>>((ref) async {
  final r = await ref
      .read(apiClientProvider)
      .get('/api/projects', query: {'archived': 'all'});
  final list = (r is Map ? r['projects'] : null) as List? ?? const [];
  final projects = list
      .whereType<Map>()
      .map((m) => Project.fromJson(m.cast<String, dynamic>()))
      .toList();
  // Active first, then A–Z, so a list does not reshuffle after every refresh.
  projects.sort((a, b) {
    if (a.archived != b.archived) return a.archived ? 1 : -1;
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });
  return projects;
});

/// Projects a new session or board may join.
final activeProjectsProvider = Provider<List<Project>>((ref) {
  final all = ref.watch(projectsProvider).valueOrNull ?? const <Project>[];
  return all.where((p) => !p.archived).toList();
});

/// `id → name` for labels (a session's group, a fact bank). Empty while the
/// list is loading or when it failed — a label then falls back to the id.
final projectNamesProvider = Provider<Map<String, String>>((ref) {
  final all = ref.watch(projectsProvider).valueOrNull ?? const <Project>[];
  return {for (final p in all) p.id: p.name};
});

/// Which project the Projects screen has open (null = the list).
final openProjectProvider = StateProvider<String?>((ref) => null);

/// Whether the list also shows archived projects.
final showArchivedProjectsProvider = StateProvider<bool>((ref) => false);

/// A project to preselect when the New Session page opens (the "New session
/// in this project" button). The page reads it once and clears it.
final newChatProjectProvider = StateProvider<String?>((ref) => null);

final projectProvider =
    FutureProvider.autoDispose.family<Project, String>((ref, id) async {
  final r = await ref.read(apiClientProvider).get('/api/projects/$id');
  return Project.fromJson((r as Map).cast<String, dynamic>());
});

final projectContextProvider = FutureProvider.autoDispose
    .family<ProjectContext, String>((ref, id) async {
  final r = await ref.read(apiClientProvider).get('/api/projects/$id/context');
  return ProjectContext.fromJson((r as Map).cast<String, dynamic>());
});

final projectChatsProvider = FutureProvider.autoDispose
    .family<List<ProjectChat>, String>((ref, id) async {
  final r = await ref.read(apiClientProvider).get('/api/projects/$id/chats');
  final list = (r is Map ? r['chats'] : null) as List? ?? const [];
  return list
      .whereType<Map>()
      .map((m) => ProjectChat.fromJson(m.cast<String, dynamic>()))
      .toList();
});

final projectBoardsProvider = FutureProvider.autoDispose
    .family<List<ProjectBoard>, String>((ref, id) async {
  final r = await ref.read(apiClientProvider).get('/api/projects/$id/boards');
  final list = (r is Map ? r['boards'] : null) as List? ?? const [];
  return list
      .whereType<Map>()
      .map((m) => ProjectBoard.fromJson(m.cast<String, dynamic>()))
      .toList();
});

/// What a facts listing asks for. A record, so two equal queries share one
/// provider.
typedef ProjectFactsQuery = ({String id, String q, bool history});

class ProjectFactList {
  /// Facts in the bank, replaced ones not counted.
  final int total;
  final List<MemoryFact> facts;
  const ProjectFactList(this.total, this.facts);
}

final projectFactsProvider = FutureProvider.autoDispose
    .family<ProjectFactList, ProjectFactsQuery>((ref, query) async {
  final q = query.q.trim();
  final r = await ref.read(apiClientProvider).get(
    '/api/projects/${query.id}/facts',
    query: {
      'limit': kProjectFactsLimit,
      if (q.isNotEmpty) 'q': q,
      if (query.history) 'history': 'true',
    },
  );
  final map = r is Map ? r : const {};
  return ProjectFactList(
    (map['total'] as num?)?.toInt() ?? 0,
    [
      for (final f in (map['facts'] as List? ?? const []))
        if (f is Map) MemoryFact.fromJson(f.cast<String, dynamic>()),
    ],
  );
});

/// Opens the system folder chooser; null when the person cancels. A provider
/// so tests can answer without a native dialog.
typedef FolderPicker = Future<String?> Function(String dialogTitle);

final folderPickerProvider = Provider<FolderPicker>(
  (ref) =>
      (title) => FilePicker.platform.getDirectoryPath(dialogTitle: title),
);

/// What adding a fact by hand came to.
class AddedFact {
  final MemoryFact fact;

  /// The same words were already in the project; that fact is now the typed one.
  final bool existing;
  const AddedFact(this.fact, this.existing);
}

/// Mutations. Each one refreshes what it changed.
class ProjectsApi {
  ProjectsApi(this._ref);
  final Ref _ref;

  ApiClient get _api => _ref.read(apiClientProvider);

  void _refresh([String? id]) {
    _ref.invalidate(projectsProvider);
    if (id != null) _ref.invalidate(projectProvider(id));
  }

  Future<Project> create({
    required String name,
    required String root,
    String description = '',
    String factsWrite = 'project',
    bool inheritCommon = true,
  }) async {
    final r = await _api.post('/api/projects', body: {
      'name': name,
      'root': root,
      if (description.isNotEmpty) 'description': description,
      'factsWrite': factsWrite,
      'inheritCommon': inheritCommon,
    });
    _refresh();
    return Project.fromJson((r as Map).cast<String, dynamic>());
  }

  Future<RootCheck> validateRoot(String path, {String? projectId}) async {
    final r = await _api.post('/api/projects/validate-root', body: {
      'path': path,
      'projectId': ?projectId,
    });
    return RootCheck.fromJson((r as Map).cast<String, dynamic>());
  }

  /// PATCH with only the fields given.
  Future<Project> update(String id, Map<String, Object?> patch) async {
    final r = await _api.patch('/api/projects/$id', body: patch);
    _refresh(id);
    return Project.fromJson((r as Map).cast<String, dynamic>());
  }

  /// Archive hides the project and stops it taking new sessions; the sessions
  /// and boards it has keep working. Restoring undoes it.
  Future<Project> setArchived(String id, bool archived) =>
      update(id, {'archived': archived});

  /// Delete for good: its fact bank, its context file, and every session and
  /// board is detached from it (they keep running where they ran). Never
  /// touches a file in the root.
  Future<ProjectPurge> purge(String id) async {
    final r = await ApiClient.withTimeout(
      kProjectPurgeTimeout,
      () => _api.delete('/api/projects/$id?purge=true'),
    );
    _afterPurge(id);
    return ProjectPurge.fromJson((r as Map).cast<String, dynamic>());
  }

  /// A purge that outlived the request: the daemon carries on without us, so
  /// the screens reload to show where it got to.
  void refreshAfterPurge(String id) => _afterPurge(id);

  void _afterPurge(String id) {
    _refresh(id);
    _ref.invalidate(projectChatsProvider);
    _ref.invalidate(projectBoardsProvider);
    _ref.invalidate(projectFactsProvider);
    _ref.invalidate(kanbanBoardsProvider);
    // Sessions left the project; the sidebar groups them from this list.
    _ref.read(groupsProvider.notifier).refresh();
  }

  /// PUT the context. [updatedAt] is the version the text was edited from; a
  /// copy changed since then is refused with a 409 [ApiException] whose `body`
  /// is the context as it is now.
  Future<ProjectContext> saveContext(
      String id, String content, int updatedAt) async {
    final r = await _api.put('/api/projects/$id/context',
        body: {'content': content, 'updatedAt': updatedAt});
    _ref.invalidate(projectContextProvider(id));
    return ProjectContext.fromJson((r as Map).cast<String, dynamic>());
  }

  Future<AddedFact> addFact(String id, String text,
      {String kind = 'world', String? when}) async {
    final r = await _api.post('/api/projects/$id/facts', body: {
      'text': text,
      if (kind != 'world') 'kind': kind,
      if (when != null && when.trim().isNotEmpty) 'when': when.trim(),
    });
    _ref.invalidate(projectFactsProvider);
    final map = (r as Map).cast<String, dynamic>();
    return AddedFact(
      MemoryFact.fromJson((map['fact'] as Map).cast<String, dynamic>()),
      map['existing'] == true,
    );
  }

  Future<void> deleteFact(String id, String factId) async {
    await _api.delete(
        '/api/projects/$id/facts/${Uri.encodeComponent(factId)}');
    _ref.invalidate(projectFactsProvider);
  }
}

final projectsApiProvider = Provider<ProjectsApi>((ref) => ProjectsApi(ref));

class _ResumeObserver with WidgetsBindingObserver {
  _ResumeObserver(this.onResume);
  final VoidCallback onResume;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) onResume();
  }
}

/// Reloads the project data on screen when the window gets focus back. Watch
/// it from a screen that shows projects; it lives as long as the app.
final projectsFocusRefreshProvider = Provider<void>((ref) {
  final observer = _ResumeObserver(() {
    ref.invalidate(projectsProvider);
    ref.invalidate(projectProvider);
    ref.invalidate(projectContextProvider);
    ref.invalidate(projectChatsProvider);
    ref.invalidate(projectBoardsProvider);
    ref.invalidate(projectFactsProvider);
  });
  WidgetsBinding.instance.addObserver(observer);
  ref.onDispose(() => WidgetsBinding.instance.removeObserver(observer));
});
