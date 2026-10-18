// A project's Facts tab: the facts of the project's own bank — what its chats
// and kanban workers picked up, and what a person typed in. Everything here is
// read by every chat and worker of the project.
//
// Client of `/api/projects/:id/facts*`. Adding a fact calls no model; a fact
// typed by hand is never replaced by what a conversation says, so changing one
// is deleting it and adding another.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/l10n.dart';
import '../../models/project.dart';
import '../../theme/tokens.dart';
import '../cognitive/facts_panel.dart' show FactRow, MemoryFact;
import 'project_widgets.dart';
import 'projects_provider.dart';

class ProjectFactsTab extends ConsumerStatefulWidget {
  const ProjectFactsTab({super.key, required this.project});
  final Project project;

  @override
  ConsumerState<ProjectFactsTab> createState() => _ProjectFactsTabState();
}

class _ProjectFactsTabState extends ConsumerState<ProjectFactsTab>
    with AutomaticKeepAliveClientMixin {
  final _text = TextEditingController();
  final _when = TextEditingController();
  final _search = TextEditingController();
  String _kind = 'world';
  String _submitted = '';
  bool _history = false;
  bool _busy = false;
  String? _error;

  String get _id => widget.project.id;

  // The half-typed fact survives a visit to another tab.
  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _text.dispose();
    _when.dispose();
    _search.dispose();
    super.dispose();
  }

  int get _len => _text.text.trim().split(RegExp(r'\s+')).join(' ').runes.length;

  Future<void> _add() async {
    final len = _len;
    if (len < kMinFactChars || len > kMaxFactChars) {
      setState(() => _error = context.trArgs(
          'A fact is {min} to {max} characters long.',
          {'min': kMinFactChars, 'max': kMaxFactChars}));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    final added = context.tr('Fact added');
    final already = context.tr(
        'That fact was already there; it is now marked as typed by hand.');
    try {
      final r = await ref.read(projectsApiProvider).addFact(
            _id,
            _text.text.trim(),
            kind: _kind,
            when: _when.text,
          );
      if (!mounted) return;
      setState(() {
        _busy = false;
        _text.clear();
        _when.clear();
      });
      messenger.showSnackBar(SnackBar(content: Text(r.existing ? already : added)));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = projectErrorText(context, e);
      });
    }
  }

  Future<void> _forget(MemoryFact fact) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.colors.surface,
        title: Text(ctx.tr('Forget this fact?')),
        content: Text(ctx.tr('The agent will stop recalling it.')),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(ctx.tr('Cancel'))),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(ctx.tr('Forget'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final done = context.tr('Forgotten');
    try {
      await ref.read(projectsApiProvider).deleteFact(_id, fact.id);
      messenger.showSnackBar(SnackBar(content: Text(done)));
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
          content: Text(context.trArgs('Forget failed: {error}',
              {'error': projectErrorText(context, e)}))));
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final c = context.colors;
    final p = widget.project;
    final query = (id: _id, q: _submitted, history: _history);
    final facts = ref.watch(projectFactsProvider(query));
    final total = facts.valueOrNull?.total;

    return Padding(
      padding: const EdgeInsets.all(AppTokens.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
              context.tr(
                  'Facts of this project: every session and kanban worker of the project recalls them. Add what they should always know.'),
              style: TextStyle(color: c.textMuted, fontSize: 12.5)),
          const SizedBox(height: AppTokens.s4),
          // A fact about the person, said in a project chat, is kept here and
          // not in the agent's common facts; the tab says so rather than let
          // it be a surprise.
          Text(
              context.tr(
                  'Personal facts you mention in a chat of this project stay in this bank for now — they are not shared with your other chats. Put lasting facts about yourself in the agent’s profile.'),
              style: TextStyle(color: c.textMuted, fontSize: 12.5)),
          if (p.factsWrite != 'project')
            Padding(
              padding: const EdgeInsets.only(top: AppTokens.s4),
              child: Text(
                  p.factsWrite == 'chat'
                      ? context.tr(
                          'Chats of this project keep their own facts, so only facts typed here appear in this bank.')
                      : context.tr(
                          'Facts are not being kept from this project’s chats; only facts typed here appear in this bank.'),
                  style: const TextStyle(
                      color: AppTokens.warning, fontSize: 12.5)),
            ),
          if (!p.inheritCommon)
            Padding(
              padding: const EdgeInsets.only(top: AppTokens.s4),
              child: Text(
                  context.tr(
                      'The agent’s common facts are not read in this project.'),
                  style: TextStyle(color: c.textMuted, fontSize: 12.5)),
            ),
          const SizedBox(height: AppTokens.s12),
          _addForm(context),
          const SizedBox(height: AppTokens.s12),
          Wrap(
            spacing: AppTokens.s12,
            runSpacing: AppTokens.s8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 280,
                child: TextField(
                  controller: _search,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    isDense: true,
                    prefixIcon: const Icon(Icons.search, size: 18),
                    hintText: context.tr('Search facts…'),
                  ),
                  onSubmitted: (v) => setState(() => _submitted = v),
                ),
              ),
              Tooltip(
                message: context.tr(
                    'Also list facts that were replaced. A keyword search never shows them.'),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Switch(
                    value: _history,
                    onChanged: _submitted.trim().isNotEmpty
                        ? null
                        : (v) => setState(() => _history = v),
                  ),
                  Text(context.tr('Show replaced'),
                      style: TextStyle(color: c.textPrimary, fontSize: 12.5)),
                ]),
              ),
              if (total != null)
                Text(context.trArgs('{n} facts', {'n': total}),
                    style: TextStyle(color: c.textMuted, fontSize: 12.5)),
              IconButton(
                tooltip: context.tr('Refresh'),
                icon: const Icon(Icons.refresh, size: 18),
                onPressed: () => ref.invalidate(projectFactsProvider),
              ),
            ],
          ),
          const SizedBox(height: AppTokens.s8),
          Expanded(
            child: facts.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Text(
                    context.trArgs('Load failed: {error}',
                        {'error': projectErrorText(context, e)}),
                    style: TextStyle(color: c.textMuted)),
              ),
              data: (list) {
                if (list.facts.isEmpty) {
                  return Center(
                    child: Text(
                        _submitted.trim().isNotEmpty
                            ? context.tr('No fact matches that search.')
                            : context.tr('This project has no facts.'),
                        style: TextStyle(color: c.textMuted)),
                  );
                }
                return ListView.separated(
                  itemCount: list.facts.length,
                  separatorBuilder: (_, _) => Divider(height: 1, color: c.border),
                  itemBuilder: (_, i) => FactRow(
                    fact: list.facts[i],
                    onForget: () => _forget(list.facts[i]),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _addForm(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(AppTokens.s12),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(AppTokens.rLg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _text,
            minLines: 1,
            maxLines: 3,
            onChanged: (_) => setState(() => _error = null),
            decoration: InputDecoration(
              isDense: true,
              hintText: context.tr(
                  'A fact as a full sentence, e.g. “The API listens on port 7421.”'),
              counterText: '$_len / $kMaxFactChars',
            ),
          ),
          const SizedBox(height: AppTokens.s8),
          Row(children: [
            DropdownButton<String>(
              value: _kind,
              isDense: true,
              underline: const SizedBox.shrink(),
              style: TextStyle(color: c.textPrimary, fontSize: 12.5),
              items: [
                DropdownMenuItem(
                    value: 'world',
                    child: Text(context.tr('About the project or the world'))),
                DropdownMenuItem(
                    value: 'experience',
                    child: Text(context.tr('Something the agent did'))),
              ],
              onChanged: (v) => setState(() => _kind = v ?? 'world'),
            ),
            const SizedBox(width: AppTokens.s12),
            SizedBox(
              width: 200,
              child: TextField(
                controller: _when,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: context.tr('When (optional): 2026-03'),
                ),
              ),
            ),
            const Spacer(),
            FilledButton.icon(
              onPressed: _busy || _len == 0 ? null : _add,
              icon: _busy
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.add, size: 16),
              label: Text(context.tr('Add fact')),
            ),
          ]),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: AppTokens.s8),
              child: Text(_error!,
                  style:
                      const TextStyle(color: AppTokens.danger, fontSize: 12)),
            ),
        ],
      ),
    );
  }
}
