import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/l10n.dart';
import '../../core/transport/api_client.dart' show ApiException;
import '../../core/transport/connection.dart';
import '../../theme/tokens.dart';
import 'cowork_common.dart';

const kSyncDirections = ['off', 'send', 'receive', 'both'];

/// What one SLink peer may do with one Space App's data on this machine
/// (`Peer.app_sync[app]` in the daemon's `src/sen_link/app_sync/`). Closed
/// until a person opens it; a daemon older than the feature sends none.
class SlAppPolicy {
  const SlAppPolicy({this.collections = const {}, this.secrets = false, this.adoptMatches = false});

  /// Collection id → `send` / `receive` / `both`; absent means off.
  final Map<String, String> collections;
  final bool secrets;
  final bool adoptMatches;

  factory SlAppPolicy.fromJson(Object? j) {
    if (j is! Map) return const SlAppPolicy();
    final c = j['collections'];
    return SlAppPolicy(
      collections: {
        if (c is Map)
          for (final e in c.entries)
            if (kSyncDirections.contains('${e.value}') && '${e.value}' != 'off') '${e.key}': '${e.value}',
      },
      secrets: j['secrets'] == true,
      adoptMatches: j['adoptMatches'] == true,
    );
  }

  Map<String, dynamic> toJson() => {'collections': collections, 'secrets': secrets, 'adoptMatches': adoptMatches};

  bool get open => collections.isNotEmpty;

  String direction(String collection) => collections[collection] ?? 'off';

  SlAppPolicy withDirection(String collection, String direction) {
    final next = {...collections};
    if (direction == 'off') {
      next.remove(collection);
    } else {
      next[collection] = direction;
    }
    return copyWith(collections: next);
  }

  SlAppPolicy copyWith({Map<String, String>? collections, bool? secrets, bool? adoptMatches}) =>
      SlAppPolicy(collections: collections ?? this.collections, secrets: secrets ?? this.secrets, adoptMatches: adoptMatches ?? this.adoptMatches);

  bool sameAs(SlAppPolicy o) {
    if (secrets != o.secrets || adoptMatches != o.adoptMatches || collections.length != o.collections.length) return false;
    return collections.entries.every((e) => o.collections[e.key] == e.value);
  }
}

/// The apps tab of one peer row in Settings → SLink: which Space Apps this
/// peer may sync with, per collection and direction, a preview of what a sync
/// would do on both machines, and the changes held back for a person.
/// A collection moves only when both machines allow it.
class SenLinkAppsPanel extends ConsumerStatefulWidget {
  const SenLinkAppsPanel({super.key, required this.peerId, required this.peerName, required this.canSend, required this.onChanged});

  final String peerId;
  final String peerName;
  final bool canSend;

  /// Called after a policy was saved, so the list above can refresh.
  final VoidCallback onChanged;

  @override
  ConsumerState<SenLinkAppsPanel> createState() => _SenLinkAppsPanelState();
}

class _SenLinkAppsPanelState extends ConsumerState<SenLinkAppsPanel> {
  Map<String, dynamic>? _list;
  String? _loadError;
  final Map<String, SlAppPolicy> _drafts = {};
  final Set<String> _confirmed = {};
  final Map<String, String> _busy = {};
  final Map<String, Map<String, dynamic>> _reports = {};
  final Map<String, String> _runErrors = {};

  String get _base => '/api/sen-link/peers/${widget.peerId}/app-sync';
  String _err(Object e) => e is ApiException ? e.message : '$e';

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  List<Map<String, dynamic>> get _apps => [for (final a in (_list?['apps'] as List? ?? const [])) (a as Map).cast<String, dynamic>()];

  Future<void> _load({bool reset = false}) async {
    try {
      final l = (await ref.read(apiClientProvider).get(_base) as Map).cast<String, dynamic>();
      if (!mounted) return;
      setState(() {
        _list = l;
        if (reset) _drafts.clear();
        for (final a in _apps) {
          _drafts.putIfAbsent('${a['app']}', () => SlAppPolicy.fromJson(a['policy']));
        }
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

  String _failure(Object e) {
    if (e is ApiException) {
      if (e.code == 'not_open') return context.tr('Open at least one collection for this peer and save, then try again.');
      if (e.code == 'busy') return context.tr('Too many requests. Try again in a minute.');
    }
    return _err(e);
  }

  Future<void> _save(String app) async {
    final savedText = context.tr('Saved');
    setState(() => _busy[app] = 'save');
    try {
      await ref.read(apiClientProvider).put('$_base/$app', body: {'policy': _drafts[app]!.toJson(), 'confirmSecrets': _confirmed.contains(app)});
      _confirmed.remove(app);
      await _load();
      widget.onChanged();
      _snack(savedText);
    } catch (e) {
      _snack(_failure(e));
    } finally {
      if (mounted) setState(() => _busy.remove(app));
    }
  }

  Future<void> _run(String app, String kind, {Map<String, String>? approve}) async {
    setState(() {
      _busy[app] = kind;
      _runErrors.remove(app);
    });
    try {
      final body = approve == null
          ? <String, dynamic>{}
          : {
              'approve': [approve]
            };
      final r = (await ref.read(apiClientProvider).post('$_base/$app/${kind == 'preview' ? 'preview' : 'run'}', body: body) as Map).cast<String, dynamic>();
      if (!mounted) return;
      setState(() => _reports[app] = r);
      await _load();
    } catch (e) {
      if (mounted) setState(() => _runErrors[app] = _failure(e));
    } finally {
      if (mounted) setState(() => _busy.remove(app));
    }
  }

  Future<void> _askSecrets(String app, List<Map<String, dynamic>> collections) async {
    final holding = [
      for (final c in collections)
        if ((c['secretFields'] as List? ?? const []).isNotEmpty) '${c['id']}: ${(c['secretFields'] as List).join(', ')}',
    ];
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.trArgs('Send passwords and keys to {name}?', {'name': widget.peerName})),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(ctx.trArgs('They cross only if {name} also allows it. On the other machine they are stored as plain text, as they are here.', {'name': widget.peerName})),
          const SizedBox(height: AppTokens.s8),
          for (final h in holding) Text(h, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
        ]),
        actions: [
          TextButton(key: const Key('sl-a-secrets-cancel'), onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.tr('Cancel'))),
          FilledButton(key: const Key('sl-a-secrets-allow'), onPressed: () => Navigator.pop(ctx, true), child: Text(ctx.tr('Allow'))),
        ],
      ),
    );
    if (ok == true && mounted) {
      setState(() {
        _confirmed.add(app);
        _drafts[app] = _drafts[app]!.copyWith(secrets: true);
      });
    }
  }

  Future<void> _approve(String app, Map<String, dynamic> held) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('Apply this change?')),
        content: Text(_reason('${held['reason']}')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.tr('Cancel'))),
          FilledButton(key: const Key('sl-a-approve-yes'), onPressed: () => Navigator.pop(ctx, true), child: Text(ctx.tr('Approve'))),
        ],
      ),
    );
    if (ok == true) await _run(app, 'run', approve: {'collection': '${held['collection']}', 'id': '${held['id']}'});
  }

  String _direction(String d) => switch (d) {
        'send' => context.tr('Send'),
        'receive' => context.tr('Receive'),
        'both' => context.tr('Both'),
        _ => context.tr('Off'),
      };

  String _status(String k) => switch (k) {
        'added' => context.tr('added'),
        'updated' => context.tr('updated'),
        'unchanged' => context.tr('unchanged'),
        'deleted' || 'tombstoned' => context.tr('deleted'),
        'adopted' => context.tr('merged'),
        'skipped' => context.tr('skipped'),
        'held' => context.tr('waiting'),
        'duplicate' => context.tr('duplicate'),
        'rejected' => context.tr('refused'),
        'error' => context.tr('failed'),
        _ => k,
      };

  Color _statusColor(String k) => switch (k) {
        'added' || 'updated' || 'deleted' || 'tombstoned' || 'adopted' => AppTokens.success,
        'held' || 'duplicate' => AppTokens.warning,
        'rejected' || 'error' => AppTokens.danger,
        _ => context.colors.textMuted,
      };

  String _why(String? w) => switch (w) {
        null => '',
        'not_on_peer' => context.tr('not on the peer'),
        'schema_differs' => context.tr('versions differ'),
        'off_here' => context.tr('off here'),
        'off_on_peer' => context.tr('off on the peer'),
        _ => w,
      };

  String _reason(String? r) {
    if (r == null || r.isEmpty || r == 'null') return '';
    if (r.startsWith('waiting_for:')) return context.tr('Waits for the record it points at');
    return switch (r) {
      'credential_target_changed' => context.tr('Would send a saved password or key to a different address'),
      'same_key_other_id' => context.tr('The same thing under another id — allow merging to take it'),
      'local_in_use' => context.tr('In use on this machine (an open tunnel)'),
      'not_receiving' => context.tr('This machine does not receive that collection'),
      'clock_skew' => context.tr("The other machine's clock is too far ahead"),
      'bad_id' || 'bad_stamp' || 'bad_data' || 'unknown_collection' => context.tr('Not a valid record'),
      'local_newer' => context.tr('Already newer here'),
      'same' => context.tr('Already up to date'),
      'secrets_filled' => context.tr('Passwords and keys filled in'),
      'risky' => context.tr('Needs your approval'),
      _ => r,
    };
  }

  /// `added 2 · updated 1`, without the entries that changed nothing.
  String _summary(Object? s) {
    if (s is! Map) return '';
    return [
      for (final e in s.entries)
        if (e.key != 'skipped' && e.key != 'unchanged') '${_status('${e.key}')} ${e.value}',
    ].join(' · ');
  }

  String _when(num at) => DateTime.fromMillisecondsSinceEpoch((at < 1e12 ? at * 1000 : at).toInt()).toString().substring(0, 16);

  /// The draft as it is now. A handler must not use the one captured when its widget was built:
  /// two quick changes would then undo the first.
  SlAppPolicy _cur(String app, SlAppPolicy fallback) => _drafts[app] ?? fallback;

  Widget _muted(String text, {double size = 12}) => Text(text, style: TextStyle(color: context.colors.textMuted, fontSize: size));

  @override
  Widget build(BuildContext context) {
    if (_loadError != null) {
      return coworkNotice(context, '${context.tr('Could not load the app sync settings')}: $_loadError', color: AppTokens.warning);
    }
    if (_list == null) return const LinearProgressIndicator();
    final apps = _apps;
    if (apps.isEmpty) {
      return _muted(context.tr('No installed Space App can sync its data yet. Update the app to a version that supports it.'), size: 13);
    }
    final remote = _list!['remote'];
    final remoteApps = remote is Map && remote['apps'] is List ? [for (final a in remote['apps'] as List) (a as Map).cast<String, dynamic>()] : null;
    final remoteError = remote is Map && remote['error'] != null ? '${remote['error']}' : null;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppTokens.s8),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _muted(context.trArgs(
              'Closed until you open it. A collection moves only when one side sends it and the other receives it, and {name} has its own setting. Machine-local state (such as an open tunnel) never moves.',
              {'name': widget.peerName})),
          const SizedBox(height: AppTokens.s8),
          if (remoteError != null)
            coworkNotice(context, '${context.trArgs('Could not ask {name} what it has opened', {'name': widget.peerName})}: $remoteError', color: AppTokens.warning),
          for (final a in apps) _appCard(a, remoteApps),
        ]),
      ),
    );
  }

  Widget _appCard(Map<String, dynamic> a, List<Map<String, dynamic>>? remoteApps) {
    final c = context.colors;
    final app = '${a['app']}';
    final saved = SlAppPolicy.fromJson(a['policy']);
    final draft = _drafts[app] ?? saved;
    final dirty = !draft.sameAs(saved);
    final collections = [for (final x in (a['collections'] as List? ?? const [])) (x as Map).cast<String, dynamic>()];
    final hasSecrets = collections.any((x) => (x['secretFields'] as List? ?? const []).isNotEmpty);
    final status = ((a['status'] as Map?) ?? const {}).cast<String, dynamic>();
    final pending = [for (final h in (status['pending'] as List? ?? const [])) (h as Map).cast<String, dynamic>()];
    final last = status['last'] is Map ? (status['last'] as Map).cast<String, dynamic>() : null;
    final report = _reports[app];
    final working = _busy.containsKey(app);
    final canSync = widget.canSend && saved.open && !dirty && !working;
    final theirs = remoteApps?.any((x) => x['app'] == app);
    final hint = dirty ? context.tr('Save your changes first') : (!saved.open ? context.tr('Open at least one collection first') : null);

    return Container(
      key: ValueKey('sl-a-card-$app'),
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: AppTokens.s12),
      padding: const EdgeInsets.all(AppTokens.s12),
      decoration: BoxDecoration(border: Border.all(color: c.border), borderRadius: BorderRadius.circular(AppTokens.rMd)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: AppTokens.s8, runSpacing: AppTokens.s4, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text(app, style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.w600, fontSize: 14)),
          if (a['version'] != null) _muted('${a['version']}'),
          if (theirs != null)
            Text(
              theirs ? context.trArgs('{name} has opened it', {'name': widget.peerName}) : context.trArgs('{name} has not opened it', {'name': widget.peerName}),
              key: ValueKey('sl-a-remote-$app'),
              style: TextStyle(color: theirs ? AppTokens.success : c.textMuted, fontSize: 12),
            ),
          if (!saved.open) Text(context.tr('closed'), key: ValueKey('sl-a-closed-$app'), style: TextStyle(color: c.textMuted, fontSize: 12)),
        ]),
        const SizedBox(height: AppTokens.s8),
        for (final col in collections) _collectionRow(app, col, draft),
        const SizedBox(height: AppTokens.s4),
        if (hasSecrets)
          Row(children: [
            Switch(
              key: ValueKey('sl-a-secrets-$app'),
              value: draft.secrets,
              onChanged: (on) {
                if (on) {
                  _askSecrets(app, collections);
                } else {
                  setState(() {
                    _confirmed.remove(app);
                    _drafts[app] = _cur(app, draft).copyWith(secrets: false);
                  });
                }
              },
            ),
            Expanded(child: Text(context.tr('Also send and accept passwords and keys'), style: TextStyle(color: c.textPrimary, fontSize: 13))),
          ]),
        Row(children: [
          Switch(
            key: ValueKey('sl-a-adopt-$app'),
            value: draft.adoptMatches,
            onChanged: (on) => setState(() => _drafts[app] = _cur(app, draft).copyWith(adoptMatches: on)),
          ),
          Expanded(
            child: Text('${context.tr('Merge records that mean the same thing')} ${context.tr('(same host and user, same name). Off: they are listed as duplicates and nothing is added.')}',
                style: TextStyle(color: c.textPrimary, fontSize: 13)),
          ),
        ]),
        const SizedBox(height: AppTokens.s8),
        Wrap(spacing: AppTokens.s8, runSpacing: AppTokens.s6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          FilledButton.icon(
            key: ValueKey('sl-a-save-$app'),
            onPressed: dirty && !working ? () => _save(app) : null,
            icon: const Icon(Icons.save, size: 16),
            label: Text(context.tr('Save')),
          ),
          OutlinedButton(
            key: ValueKey('sl-a-revert-$app'),
            onPressed: dirty && !working
                ? () => setState(() {
                      _drafts[app] = saved;
                      _confirmed.remove(app);
                    })
                : null,
            child: Text(context.tr('Revert')),
          ),
          Tooltip(
            message: hint ?? '',
            child: OutlinedButton.icon(
              key: ValueKey('sl-a-preview-$app'),
              onPressed: canSync ? () => _run(app, 'preview') : null,
              icon: const Icon(Icons.visibility_outlined, size: 16),
              label: Text(context.tr('Preview')),
            ),
          ),
          Tooltip(
            message: hint ?? '',
            child: OutlinedButton.icon(
              key: ValueKey('sl-a-run-$app'),
              onPressed: canSync ? () => _run(app, 'run') : null,
              icon: const Icon(Icons.sync, size: 16),
              label: Text(context.tr('Sync now')),
            ),
          ),
          if (last != null && last['at'] is num) _muted(context.trArgs('Last synced {when}', {'when': _when(last['at'] as num)})),
        ]),
        if (working) const Padding(padding: EdgeInsets.only(top: AppTokens.s8), child: LinearProgressIndicator()),
        if (_runErrors[app] != null)
          Padding(padding: const EdgeInsets.only(top: AppTokens.s8), child: coworkNotice(context, _runErrors[app]!, color: AppTokens.warning)),
        if (pending.isNotEmpty) _heldView(app, pending),
        if (report != null) _reportView(app, report, pending.isEmpty),
      ]),
    );
  }

  Widget _collectionRow(String app, Map<String, dynamic> col, SlAppPolicy draft) {
    final c = context.colors;
    final id = '${col['id']}';
    final secret = [for (final f in (col['secretFields'] as List? ?? const [])) '$f'];
    final local = [for (final f in (col['localFields'] as List? ?? const [])) '$f'];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppTokens.s4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(id, style: TextStyle(color: c.textPrimary, fontSize: 13, fontFamily: 'monospace')),
            if (secret.isNotEmpty) _muted('${context.tr('Holds secrets')}: ${secret.join(', ')}'),
            if (local.isNotEmpty) _muted('${context.tr('Stays on this machine')}: ${local.join(', ')}'),
          ]),
        ),
        SegmentedButton<String>(
          key: ValueKey('sl-a-dir-$app-$id'),
          showSelectedIcon: false,
          style: const ButtonStyle(visualDensity: VisualDensity.compact),
          segments: [for (final d in kSyncDirections) ButtonSegment(value: d, label: Text(_direction(d), style: const TextStyle(fontSize: 12)))],
          selected: {draft.direction(id)},
          onSelectionChanged: (s) => setState(() => _drafts[app] = _cur(app, draft).withDirection(id, s.first)),
        ),
      ]),
    );
  }

  Widget _heldView(String app, List<Map<String, dynamic>> held) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(top: AppTokens.s12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(context.tr('Waiting for you'), style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.w600, fontSize: 13)),
        _muted(context.tr('These changes were held back. Nothing is applied until you approve it here.')),
        for (final h in held)
          Padding(
            key: ValueKey('sl-a-held-${h['collection']}-${h['id']}'),
            padding: const EdgeInsets.symmetric(vertical: AppTokens.s4),
            child: Row(children: [
              Expanded(
                child: Text(
                  '${h['collection']} · ${h['name'] ?? '${h['id']}'.substring(0, ('${h['id']}'.length < 8 ? '${h['id']}'.length : 8))} — ${_reason('${h['reason']}')}',
                  style: TextStyle(color: c.textPrimary, fontSize: 13),
                ),
              ),
              TextButton(
                key: ValueKey('sl-a-approve-${h['collection']}-${h['id']}'),
                onPressed: widget.canSend && !_busy.containsKey(app) ? () => _approve(app, h) : null,
                child: Text(context.tr('Approve')),
              ),
            ]),
          ),
      ]),
    );
  }

  Widget _reportView(String app, Map<String, dynamic> r, bool showHeld) {
    final c = context.colors;
    final dry = r['dryRun'] == true;
    final plan = [for (final p in (r['plan'] as List? ?? const [])) (p as Map).cast<String, dynamic>()];
    final pull = (r['pull'] as Map?)?.cast<String, dynamic>() ?? const {};
    final push = (r['push'] as Map?)?.cast<String, dynamic>() ?? const {};
    final rows = <(String, Map<String, dynamic>)>[
      for (final x in (pull['results'] as List? ?? const [])) ('↓', (x as Map).cast<String, dynamic>()),
      for (final x in (push['results'] as List? ?? const [])) ('↑', (x as Map).cast<String, dynamic>()),
    ].where((e) => e.$2['status'] != 'skipped' && e.$2['status'] != 'unchanged').toList();
    final held = [for (final h in (r['held'] as List? ?? const [])) (h as Map).cast<String, dynamic>()];
    final pullText = _summary(pull['summary']);
    final pushText = _summary(push['summary']);
    final tint = dry ? c.accent : AppTokens.success;
    return Padding(
      key: ValueKey('sl-a-report-$app'),
      padding: const EdgeInsets.only(top: AppTokens.s12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppTokens.s12),
          decoration: BoxDecoration(
            color: tint.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(AppTokens.rMd),
            border: Border.all(color: tint.withValues(alpha: 0.3)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(dry ? context.tr('Preview: nothing was changed') : context.tr('Synced'), style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: AppTokens.s4),
            Wrap(spacing: AppTokens.s8, runSpacing: AppTokens.s2, children: [
              for (final p in plan)
                Text(
                  [
                    [
                      '${p['collection']}',
                      '${p['pull'] == true ? '↓' : ''}${p['push'] == true ? '↑' : ''}',
                    ].where((s) => s.isNotEmpty).join(' '),
                    _why(p['why'] as String?),
                  ].where((s) => s.isNotEmpty).join(' · '),
                  style: TextStyle(color: p['pull'] == true || p['push'] == true ? c.accent : c.textMuted, fontSize: 12),
                ),
            ]),
            const SizedBox(height: AppTokens.s4),
            Text('${context.trArgs('Taken from {name}', {'name': widget.peerName})}: ${pullText.isEmpty ? context.tr('nothing') : pullText}',
                key: ValueKey('sl-a-pull-$app'), style: TextStyle(color: c.textPrimary, fontSize: 13)),
            Text('${context.trArgs('Sent to {name}', {'name': widget.peerName})}: ${pushText.isEmpty ? context.tr('nothing') : pushText}',
                key: ValueKey('sl-a-push-$app'), style: TextStyle(color: c.textPrimary, fontSize: 13)),
          ]),
        ),
        for (final e in rows)
          Padding(
            padding: const EdgeInsets.only(top: AppTokens.s4),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(width: 20, child: Text(e.$1, style: TextStyle(color: c.textMuted, fontSize: 13))),
              SizedBox(width: 130, child: Text('${e.$2['collection']}', style: TextStyle(color: c.textPrimary, fontSize: 12, fontFamily: 'monospace'))),
              SizedBox(width: 72, child: Text('${e.$2['id']}'.substring(0, '${e.$2['id']}'.length < 8 ? '${e.$2['id']}'.length : 8), style: TextStyle(color: c.textMuted, fontSize: 12))),
              SizedBox(width: 90, child: Text(_status('${e.$2['status']}'), style: TextStyle(color: _statusColor('${e.$2['status']}'), fontSize: 12))),
              Expanded(
                child: Text(
                  [
                    _reason(e.$2['reason'] as String?),
                    for (final w in (e.$2['warnings'] as List? ?? const [])) '$w',
                  ].where((s) => s.isNotEmpty).join(' · '),
                  style: TextStyle(color: c.textMuted, fontSize: 12),
                ),
              ),
            ]),
          ),
        if (showHeld && held.isNotEmpty) _heldView(app, held),
      ]),
    );
  }
}
