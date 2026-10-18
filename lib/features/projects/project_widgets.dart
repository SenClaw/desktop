// Pieces the project screens, the New Session page and the Kanban dialogs
// share: the project picker, the root-folder field that asks the daemon about
// what was typed, and the "where do facts go" choice.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/l10n.dart';
import '../../core/transport/api_client.dart';
import '../../models/project.dart';
import '../../theme/tokens.dart';
import 'projects_provider.dart';

/// The project's name for a label, or its id while the list has not loaded.
String projectLabel(Map<String, String> names, String id) => names[id] ?? id;

String _two(int n) => n.toString().padLeft(2, '0');

/// `2026-10-19 08:05` in local time, from milliseconds since the epoch.
String formatStamp(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${d.year}-${_two(d.month)}-${_two(d.day)} ${_two(d.hour)}:${_two(d.minute)}';
}

/// A root the daemon refused, in the app's language. The daemon's `code` is
/// stable; its `message` is English with the path in it, kept as the fallback
/// for a code this build does not know.
String rootReasonText(BuildContext context, RootReason r, {String? owner}) {
  switch (r.code) {
    case 'empty':
      return context.tr('Choose the project folder.');
    case 'not_absolute':
      return context.tr('The path must be absolute (start with / or ~).');
    case 'not_found':
      return context.tr('That folder does not exist.');
    case 'not_a_directory':
      return context.tr('That path is not a folder.');
    case 'unreadable':
      return context.tr('That folder cannot be read.');
    case 'filesystem_root':
      return context.tr('The top of the filesystem cannot be a project folder.');
    case 'home_dir':
      return context.tr(
          'The home folder is too broad for a project; pick a folder inside it.');
    case 'contains_home':
      return context.tr(
          'That folder contains your home folder, which is too broad for a project.');
    case 'senclaw_state':
      return context.tr(
          "That folder holds SenClaw's own data (tokens, databases, chats).");
    case 'senclaw_profiles':
      return context.tr('The agent profiles folder cannot be a project folder.');
    case 'senclaw_projects':
      return context.tr(
          'The folder where SenClaw keeps project contexts cannot be a project folder.');
    case 'root_in_use':
      return owner == null
          ? context.tr('Another project already uses this folder.')
          : context.trArgs(
              'The project “{name}” already uses this folder.', {'name': owner});
    default:
      return r.message;
  }
}

/// What to tell the person when a project request failed. Knows the shapes the
/// daemon refuses with; anything else is shown as it came.
String projectErrorText(BuildContext context, Object e) {
  if (e is ApiTimeout) {
    return context.tr('The daemon did not answer in time.');
  }
  if (e is! ApiException) return '$e';
  final body = e.body ?? const <String, dynamic>{};
  switch (e.message) {
    case 'invalid_root':
      final reasons = [
        for (final r in (body['reasons'] as List? ?? const []))
          if (r is Map) RootReason.fromJson(r.cast<String, dynamic>()),
      ];
      if (reasons.isNotEmpty) {
        return reasons.map((r) => rootReasonText(context, r)).join('\n');
      }
    case 'root_in_use':
      return rootReasonText(context, const RootReason('root_in_use', ''),
          owner: body['projectName'] as String?);
    case 'project_not_found':
      return context.tr('This project no longer exists.');
    case 'context_too_large':
      return context.trArgs('The context is too large (at most {kb} KB).',
          {'kb': ((body['maxBytes'] as num?)?.toInt() ?? 102400) ~/ 1024});
    case 'secret_in_fact':
      return context.trArgs(
          'That text looks like it holds a secret ({kinds}), so it was not saved.',
          {'kinds': (body['kinds'] as List?)?.join(', ') ?? '?'});
    case 'invalid_when':
      return context.tr('The date is like 2026-03 or 2026-03-02, or a range a/b.');
    case 'invalid_fact':
      return context.trArgs('A fact is {min} to {max} characters long.',
          {'min': kMinFactChars, 'max': kMaxFactChars});
    case 'invalid_project':
      final why = body['message'];
      if (why is String && why.isNotEmpty) return why;
  }
  return e.message;
}

/// "No project" first, then the projects a new session or board may join.
class ProjectPicker extends ConsumerWidget {
  const ProjectPicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final String? value;
  final ValueChanged<String?> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final projects = ref.watch(activeProjectsProvider);
    return DropdownButtonHideUnderline(
      child: DropdownButton<String?>(
        // `DropdownButton` throws when `value` matches no item: a project that
        // was archived since it was picked reads as "no project".
        value: projects.any((p) => p.id == value) ? value : null,
        isDense: true,
        isExpanded: true,
        style: TextStyle(color: c.textPrimary, fontSize: 13),
        items: [
          DropdownMenuItem<String?>(
            value: null,
            child: Text(context.tr('No project'),
                style: TextStyle(color: c.textSecondary, fontSize: 13)),
          ),
          for (final p in projects)
            DropdownMenuItem<String?>(
              value: p.id,
              child: Text(p.name, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: enabled ? onChanged : null,
      ),
    );
  }
}

enum RootStatus { idle, checking, valid, invalid, failed }

/// What the root field currently knows about its text.
class RootFieldState {
  final RootStatus status;
  final RootCheck? check;
  final Object? error;
  const RootFieldState(this.status, {this.check, this.error});

  static const idle = RootFieldState(RootStatus.idle);
  bool get valid => status == RootStatus.valid;
}

/// The root-folder field: the typed or browsed path is sent to
/// `validate-root` as it changes, and the reasons the daemon gives are shown
/// under it. The parent reads [state] to know when the form may be sent.
///
/// [projectId] is set when editing a project, so its own root is not "in use".
/// [unchanged] is a root that needs no check (the project's current one — it
/// may have gone missing and the person is only renaming).
class ProjectRootField extends ConsumerStatefulWidget {
  const ProjectRootField({
    super.key,
    required this.controller,
    required this.state,
    this.projectId,
    this.unchanged,
    this.onPicked,
    this.autofocus = false,
  });

  final TextEditingController controller;
  final ValueNotifier<RootFieldState> state;
  final String? projectId;
  final String? unchanged;

  /// Called with the folder chosen in the system dialog (the create dialog uses
  /// it to propose a name).
  final ValueChanged<String>? onPicked;
  final bool autofocus;

  @override
  ConsumerState<ProjectRootField> createState() => _ProjectRootFieldState();
}

class _ProjectRootFieldState extends ConsumerState<ProjectRootField> {
  Timer? _debounce;
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onText);
    // After the first frame: the parent listens to `state` and may be
    // mid-build, where a notification would be a setState-during-build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scheduleCheck(immediately: true);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    widget.controller.removeListener(_onText);
    super.dispose();
  }

  String _lastText = '';

  void _onText() {
    final text = widget.controller.text;
    if (text == _lastText) return;
    _lastText = text;
    _scheduleCheck();
  }

  void _scheduleCheck({bool immediately = false}) {
    _debounce?.cancel();
    final text = widget.controller.text.trim();
    _lastText = widget.controller.text;
    final seq = ++_seq;
    if (text.isEmpty) {
      widget.state.value = RootFieldState.idle;
      return;
    }
    if (widget.unchanged != null && text == widget.unchanged) {
      widget.state.value = const RootFieldState(RootStatus.valid);
      return;
    }
    widget.state.value = const RootFieldState(RootStatus.checking);
    _debounce = Timer(
      immediately ? Duration.zero : const Duration(milliseconds: 350),
      () => _check(text, seq),
    );
  }

  Future<void> _check(String text, int seq) async {
    try {
      final check = await ref
          .read(projectsApiProvider)
          .validateRoot(text, projectId: widget.projectId);
      if (!mounted || seq != _seq) return;
      widget.state.value = RootFieldState(
        check.ok ? RootStatus.valid : RootStatus.invalid,
        check: check,
      );
    } catch (e) {
      if (!mounted || seq != _seq) return;
      widget.state.value = RootFieldState(RootStatus.failed, error: e);
    }
  }

  Future<void> _browse() async {
    final dir = await ref
        .read(folderPickerProvider)(context.tr('Choose the project folder'));
    if (dir == null || !mounted) return;
    widget.controller.text = dir;
    widget.onPicked?.call(dir);
    _scheduleCheck(immediately: true);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(context.tr('Project folder'),
            style: TextStyle(color: c.textMuted, fontSize: 11)),
        const SizedBox(height: 2),
        Row(children: [
          Expanded(
            child: TextField(
              key: const ValueKey('project-root-field'),
              controller: widget.controller,
              autofocus: widget.autofocus,
              style: const TextStyle(
                  fontSize: 13, fontFamily: AppTokens.fontMono),
              decoration: InputDecoration(
                isDense: true,
                hintText: context.tr('~/work/my-project'),
              ),
            ),
          ),
          const SizedBox(width: AppTokens.s8),
          OutlinedButton.icon(
            onPressed: _browse,
            icon: const Icon(Icons.folder_open, size: 16),
            label: Text(context.tr('Browse…')),
          ),
        ]),
        const SizedBox(height: AppTokens.s4),
        ValueListenableBuilder<RootFieldState>(
          valueListenable: widget.state,
          builder: (context, s, _) => _Status(state: s),
        ),
      ],
    );
  }
}

class _Status extends StatelessWidget {
  const _Status({required this.state});
  final RootFieldState state;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    switch (state.status) {
      case RootStatus.idle:
        return const SizedBox(height: 16);
      case RootStatus.checking:
        return Row(children: [
          const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: AppTokens.s8),
          Text(context.tr('Checking the folder…'),
              style: TextStyle(color: c.textMuted, fontSize: 12)),
        ]);
      case RootStatus.valid:
        final check = state.check;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.check_circle,
                  size: 14, color: AppTokens.success),
              const SizedBox(width: AppTokens.s4),
              Text(context.tr('The folder can be used.'),
                  style: const TextStyle(
                      color: AppTokens.success, fontSize: 12)),
            ]),
            if (check?.canonical != null)
              Text(check!.canonical!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: c.textMuted,
                      fontSize: 11,
                      fontFamily: AppTokens.fontMono)),
            if (check?.hasClaudeMd == true)
              Text(
                  context.tr(
                      'It already has a CLAUDE.md — the project context adds to it.'),
                  style: TextStyle(color: c.textMuted, fontSize: 11)),
          ],
        );
      case RootStatus.invalid:
        final owner = state.check?.inUseByName;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final r in state.check?.reasons ?? const <RootReason>[])
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.error_outline,
                        size: 14, color: AppTokens.danger),
                    const SizedBox(width: AppTokens.s4),
                    Expanded(
                      child: Text(
                          rootReasonText(context, r, owner: owner),
                          style: const TextStyle(
                              color: AppTokens.danger, fontSize: 12)),
                    ),
                  ],
                ),
              ),
          ],
        );
      case RootStatus.failed:
        return Text(
            context.trArgs('Could not check the folder: {error}',
                {'error': projectErrorText(context, state.error!)}),
            style: const TextStyle(color: AppTokens.warning, fontSize: 12));
    }
  }
}

/// Where facts picked out of a project's chats are kept.
class FactsWriteField extends StatelessWidget {
  const FactsWriteField({super.key, required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget option(String v, String title, String sub) => RadioListTile<String>(
          value: v,
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text(context.tr(title), style: const TextStyle(fontSize: 13)),
          subtitle: Text(context.tr(sub),
              style: TextStyle(color: c.textMuted, fontSize: 11.5)),
        );
    return RadioGroup<String>(
      groupValue: value,
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.tr('Facts picked out of the project’s chats'),
              style: TextStyle(color: c.textMuted, fontSize: 11)),
          option(
              'project',
              'Kept in the project',
              'One bank for the project, read by all its chats and kanban workers.'),
          option('chat', 'Kept per chat',
              'As outside a project. Only facts you type by hand are shared.'),
          option('off', 'Not kept',
              'Nothing is extracted from the project’s chats.'),
        ],
      ),
    );
  }
}
