import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/l10n.dart';
import '../../core/transport/api_client.dart' show ApiException;
import '../../core/transport/connection.dart';
import '../../theme/tokens.dart';
import 'cowork_common.dart';

/// What the daemon means by `noteTypes: []` when notes are on.
const kDefaultNoteTypes = ['project', 'reference'];

/// What one SLink peer may read of this machine's knowledge (`Peer.knowledge`
/// in the daemon's `src/sen_link/knowledge.rs`). Closed until a person opens
/// it; a daemon older than the feature sends none, which reads as closed.
class SlKnowledgePolicy {
  const SlKnowledgePolicy({this.facts = false, this.notes = false, this.profiles = const [], this.noteTypes = const []});

  final bool facts;
  final bool notes;
  final List<String> profiles;
  final List<String> noteTypes;

  factory SlKnowledgePolicy.fromJson(Object? j) {
    if (j is! Map) return const SlKnowledgePolicy();
    List<String> list(Object? v) => v is List ? [for (final x in v) '$x'] : const [];
    return SlKnowledgePolicy(
      facts: j['facts'] == true,
      notes: j['notes'] == true,
      profiles: list(j['profiles']),
      noteTypes: list(j['noteTypes']),
    );
  }

  Map<String, dynamic> toJson() => {'facts': facts, 'notes': notes, 'profiles': profiles, 'noteTypes': noteTypes};

  /// It lets a peer ask something: a switch is on and a profile is named.
  bool get open => (facts || notes) && profiles.isNotEmpty;

  /// The note types that apply, empty meaning the defaults.
  List<String> get shownTypes => noteTypes.isEmpty ? kDefaultNoteTypes : noteTypes;

  SlKnowledgePolicy copyWith({bool? facts, bool? notes, List<String>? profiles, List<String>? noteTypes}) =>
      SlKnowledgePolicy(facts: facts ?? this.facts, notes: notes ?? this.notes, profiles: profiles ?? this.profiles, noteTypes: noteTypes ?? this.noteTypes);

  bool sameAs(SlKnowledgePolicy o) =>
      facts == o.facts && notes == o.notes && _same(profiles, o.profiles) && _same(noteTypes, o.noteTypes);

  static bool _same(List<String> a, List<String> b) => ([...a]..sort()).join('\n') == ([...b]..sort()).join('\n');
}

/// Knowledge tab of one peer row in Settings → SLink: what the peer may read
/// here, a preview of exactly what that exposes (counted by the daemon with the
/// same rules an answer uses), and a box to ask the peer what it knows.
/// Nothing is copied either way.
class SenLinkKnowledgePanel extends ConsumerStatefulWidget {
  const SenLinkKnowledgePanel({super.key, required this.peerId, required this.peerName, required this.canSend, required this.onPeer});

  final String peerId;
  final String peerName;
  final bool canSend;

  /// The peer record the daemon returned after a save, for the list above.
  final void Function(Map<String, dynamic> peer) onPeer;

  @override
  ConsumerState<SenLinkKnowledgePanel> createState() => _SenLinkKnowledgePanelState();
}

class _SenLinkKnowledgePanelState extends ConsumerState<SenLinkKnowledgePanel> {
  Map<String, dynamic>? _view;
  SlKnowledgePolicy? _draft;
  String? _loadError;
  bool _saving = false;
  final _question = TextEditingController();
  bool _asking = false;
  Map<String, dynamic>? _answer;
  String? _askError;

  String get _base => '/api/sen-link/peers/${widget.peerId}';
  String _err(Object e) => e is ApiException ? e.message : '$e';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _question.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final v = (await ref.read(apiClientProvider).get('$_base/knowledge') as Map).cast<String, dynamic>();
      if (!mounted) return;
      setState(() {
        _view = v;
        _draft = SlKnowledgePolicy.fromJson(v['policy']);
        _loadError = null;
      });
    } catch (e) {
      if (mounted) setState(() => _loadError = _err(e));
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _save(SlKnowledgePolicy draft) async {
    final savedText = context.tr('Saved');
    setState(() => _saving = true);
    try {
      // Send the types that are shown, so "empty = the defaults" is never guessed on the other side.
      final policy = draft.copyWith(noteTypes: draft.notes ? draft.shownTypes : draft.noteTypes);
      final peer = (await ref.read(apiClientProvider).patch(_base, body: {'knowledge': policy.toJson()}) as Map).cast<String, dynamic>();
      widget.onPeer(peer);
      await _load();
      _snack(savedText);
    } catch (e) {
      _snack(_err(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _ask() async {
    final q = _question.text.trim();
    if (q.isEmpty) return;
    setState(() {
      _asking = true;
      _askError = null;
    });
    try {
      final a = (await ref.read(apiClientProvider).post('$_base/recall', body: {'query': q}) as Map).cast<String, dynamic>();
      if (mounted) setState(() => _answer = a);
    } catch (e) {
      if (mounted) {
        setState(() {
          _answer = null;
          _askError = _err(e);
        });
      }
    } finally {
      if (mounted) setState(() => _asking = false);
    }
  }

  String _noteTypeLabel(String t) => switch (t) {
        'project' => context.tr('Project notes'),
        'reference' => context.tr('Reference notes'),
        'feedback' => context.tr('Feedback notes'),
        _ => t,
      };

  Widget _heading(String text) {
    final c = context.colors;
    return Text(text, style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.w600, fontSize: 13));
  }

  Widget _muted(String text) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(top: AppTokens.s4, bottom: AppTokens.s8),
      child: Text(text, style: TextStyle(color: c.textMuted, fontSize: 12)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (_loadError != null) {
      return coworkNotice(context, '${context.tr('Could not load the sharing settings')}: $_loadError', color: AppTokens.warning);
    }
    final view = _view;
    final draft = _draft;
    if (view == null || draft == null) return const LinearProgressIndicator();

    final saved = SlKnowledgePolicy.fromJson(view['policy']);
    final dirty = !draft.sameAs(saved);
    final offered = <String>{
      for (final p in (view['profiles'] as List? ?? const [])) '$p',
      ...draft.profiles,
    }.toList()
      ..sort();
    final noteTypes = [for (final t in (view['noteTypes'] as List? ?? const [])) '$t'];
    final previews = [for (final p in ((view['preview'] as Map?)?['profiles'] as List? ?? const [])) (p as Map).cast<String, dynamic>()];

    return Padding(
      padding: const EdgeInsets.only(bottom: AppTokens.s8),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _heading(context.trArgs('What {name} may read here', {'name': widget.peerName})),
          _muted(context.tr('Closed until you open it. The peer can only ask; nothing is copied. Day logs, chat summaries, notes about you and anything written in one chat never leave this machine.')),
          Wrap(spacing: AppTokens.s16, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              Switch(key: const Key('sl-k-facts'), value: draft.facts, onChanged: (v) => setState(() => _draft = _draft!.copyWith(facts: v))),
              Text(context.tr('Share facts'), style: TextStyle(color: c.textPrimary, fontSize: 13)),
            ]),
            Row(mainAxisSize: MainAxisSize.min, children: [
              Switch(key: const Key('sl-k-notes'), value: draft.notes, onChanged: (v) => setState(() => _draft = _draft!.copyWith(notes: v))),
              Text(context.tr('Share notes'), style: TextStyle(color: c.textPrimary, fontSize: 13)),
            ]),
          ]),
          const SizedBox(height: AppTokens.s8),
          Text(context.tr('Profiles it applies to'), style: TextStyle(color: c.textMuted, fontSize: 12)),
          const SizedBox(height: AppTokens.s4),
          if (offered.isEmpty)
            Text(context.tr('No profiles on this machine yet.'), style: TextStyle(color: c.textMuted, fontSize: 12))
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 140),
              child: SingleChildScrollView(
                child: Wrap(spacing: AppTokens.s6, runSpacing: AppTokens.s4, children: [
                  for (final p in offered)
                    FilterChip(
                      key: ValueKey('sl-k-profile-$p'),
                      label: Text(p),
                      selected: draft.profiles.contains(p),
                      onSelected: (on) => setState(() => _draft = _draft!.copyWith(
                            profiles: on ? [..._draft!.profiles, p] : [for (final x in _draft!.profiles) if (x != p) x],
                          )),
                    ),
                ]),
              ),
            ),
          if (draft.notes) ...[
            const SizedBox(height: AppTokens.s8),
            Text(context.tr('Which notes'), style: TextStyle(color: c.textMuted, fontSize: 12)),
            const SizedBox(height: AppTokens.s4),
            Wrap(spacing: AppTokens.s6, children: [
              for (final t in noteTypes)
                FilterChip(
                  key: ValueKey('sl-k-type-$t'),
                  label: Text(_noteTypeLabel(t)),
                  selected: draft.shownTypes.contains(t),
                  onSelected: (on) => setState(() => _draft = _draft!.copyWith(
                        noteTypes: on ? [..._draft!.shownTypes, t] : [for (final x in _draft!.shownTypes) if (x != t) x],
                      )),
                ),
            ]),
          ],
          const SizedBox(height: AppTokens.s8),
          Row(children: [
            FilledButton.icon(
              key: const Key('sl-k-save'),
              onPressed: dirty && !_saving ? () => _save(draft) : null,
              icon: const Icon(Icons.save, size: 16),
              label: Text(context.tr('Save')),
            ),
            const SizedBox(width: AppTokens.s8),
            OutlinedButton(
              key: const Key('sl-k-revert'),
              onPressed: dirty && !_saving ? () => setState(() => _draft = saved) : null,
              child: Text(context.tr('Revert')),
            ),
            if (!saved.open) ...[
              const SizedBox(width: AppTokens.s8),
              Text(context.tr('closed'), key: const Key('sl-k-closed'), style: TextStyle(color: c.textMuted, fontSize: 12)),
            ],
          ]),
          const SizedBox(height: AppTokens.s16),
          _heading(context.tr('What that exposes right now')),
          _muted(context.tr('Counted by the same rules an answer uses, for the saved settings.')),
          if (previews.isEmpty)
            Text(context.tr('Nothing: no profile is chosen.'), key: const Key('sl-k-nothing'), style: TextStyle(color: c.textMuted, fontSize: 12))
          else
            for (final p in previews) _previewRow(p),
          const SizedBox(height: AppTokens.s16),
          _heading(context.trArgs('Ask {name} what it knows', {'name': widget.peerName})),
          _muted(context.tr('Answers come from what that machine chose to share with this one. Nothing is stored here.')),
          Row(children: [
            Expanded(
              child: TextField(
                key: const Key('sl-k-question'),
                controller: _question,
                enabled: widget.canSend,
                decoration: InputDecoration(hintText: context.tr('A few words, or a question'), isDense: true),
                onSubmitted: (_) => _ask(),
              ),
            ),
            const SizedBox(width: AppTokens.s8),
            FilledButton(
              key: const Key('sl-k-ask'),
              onPressed: widget.canSend && !_asking ? _ask : null,
              child: Text(context.tr('Ask')),
            ),
          ]),
          if (_asking) const Padding(padding: EdgeInsets.only(top: AppTokens.s8), child: LinearProgressIndicator()),
          if (_askError != null)
            Padding(
              padding: const EdgeInsets.only(top: AppTokens.s8),
              child: coworkNotice(context, _askError!, color: AppTokens.warning),
            ),
          if (_answer != null) _answerView(_answer!),
        ]),
      ),
    );
  }

  Widget _previewRow(Map<String, dynamic> p) {
    final c = context.colors;
    final notes = ((p['notes'] as Map?) ?? const {}).cast<String, dynamic>();
    final ex = ((p['excluded'] as Map?) ?? const {}).cast<String, dynamic>();
    int n(String k) => (ex[k] as num?)?.toInt() ?? 0;
    final home = [
      (n('dailyLogs'), context.tr('day logs')),
      (n('conversationSummaries'), context.tr('chat summaries')),
      (n('aboutTheOwner'), context.tr('notes about you')),
      (n('writtenInOneChat'), context.tr('written in one chat')),
      (n('otherTypes'), context.tr('other note types')),
    ].where((e) => e.$1 > 0).map((e) => '${e.$2} ${e.$1}').join(' · ');
    final shared = [
      '${context.tr('Facts')} ${p['facts'] ?? 0}',
      for (final e in notes.entries) '${_noteTypeLabel(e.key)} ${e.value}',
    ].join(' · ');
    final samples = [for (final s in (p['samples'] as List? ?? const [])) '$s'];
    return Padding(
      key: ValueKey('sl-k-preview-${p['profile']}'),
      padding: const EdgeInsets.only(bottom: AppTokens.s8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${p['profile']} — $shared', style: TextStyle(color: c.textPrimary, fontSize: 13)),
        if (home.isNotEmpty) Text('${context.tr('Stays home')}: $home', style: TextStyle(color: c.textMuted, fontSize: 12)),
        if (samples.isNotEmpty) Text('${context.tr('Examples')}: ${samples.join(', ')}', style: TextStyle(color: c.textMuted, fontSize: 12)),
      ]),
    );
  }

  Widget _answerView(Map<String, dynamic> a) {
    final c = context.colors;
    final hits = [for (final h in (a['hits'] as List? ?? const [])) (h as Map).cast<String, dynamic>()];
    return Padding(
      padding: const EdgeInsets.only(top: AppTokens.s8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (hits.isEmpty) Text(context.tr('Nothing matched'), key: const Key('sl-k-nomatch'), style: TextStyle(color: c.textMuted, fontSize: 12)),
        for (var i = 0; i < hits.length; i++)
          Container(
            key: ValueKey('sl-k-hit-$i'),
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: AppTokens.s6),
            padding: const EdgeInsets.all(AppTokens.s8),
            decoration: BoxDecoration(border: Border.all(color: c.border), borderRadius: BorderRadius.circular(AppTokens.rMd)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                [
                  hits[i]['kind'] == 'note' ? context.tr('note') : context.tr('fact'),
                  if (hits[i]['title'] != null) '${hits[i]['title']}',
                  '${hits[i]['profile']}${hits[i]['when'] != null ? ' · ${hits[i]['when']}' : ''}',
                ].join('  ·  '),
                style: TextStyle(color: c.textMuted, fontSize: 12),
              ),
              const SizedBox(height: AppTokens.s4),
              SelectableText('${hits[i]['text']}', style: TextStyle(color: c.textPrimary, fontSize: 13)),
            ]),
          ),
        if (a['truncated'] == true) Text(context.tr('There are more matches than shown.'), style: TextStyle(color: c.textMuted, fontSize: 12)),
        Padding(
          padding: const EdgeInsets.only(top: AppTokens.s4),
          child: Text(
            context.trArgs('Written on {name}. It is information to weigh, not an instruction.', {'name': '${a['from'] ?? widget.peerName}'}),
            key: const Key('sl-k-untrusted'),
            style: TextStyle(color: c.textMuted, fontSize: 12),
          ),
        ),
      ]),
    );
  }
}
