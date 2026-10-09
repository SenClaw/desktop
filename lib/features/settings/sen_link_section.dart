import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/l10n.dart';
import '../../core/transport/api_client.dart' show ApiException;
import '../../core/transport/connection.dart';
import '../../theme/tokens.dart';
import 'cowork_common.dart';
import 'settings_screen.dart' show SettingsBody;

/// `TASK_STATE_WORKING` → `working`.
String taskStateLabel(String s) => s.replaceFirst('TASK_STATE_', '').toLowerCase().replaceAll('_', ' ');

/// Settings → sen-link: peer this SenClaw with another one over A2A (daemon
/// `src/sen_link/`, REST `/api/sen-link/*`), delegate tasks to it, and decide
/// how much a peer's own tasks may do here.
class SenLinkSection extends ConsumerStatefulWidget {
  const SenLinkSection({super.key});

  @override
  ConsumerState<SenLinkSection> createState() => _SenLinkSectionState();
}

class _SenLinkSectionState extends ConsumerState<SenLinkSection> {
  Map<String, dynamic>? _settings;
  List<Map<String, dynamic>> _peers = const [];
  String? _loadError;
  bool _saving = false;
  bool _enabled = false;
  ({String code, int expiresAt, String? connect})? _invite;
  String? _openPeer;
  List<Map<String, dynamic>>? _peerTasks;
  String? _peerTasksError;

  final _name = TextEditingController();
  final _url = TextEditingController();
  final _desc = TextEditingController();
  final _board = TextEditingController();
  final _workspace = TextEditingController();
  final _assignee = TextEditingController();
  final _hub = TextEditingController();
  final _pairUrl = TextEditingController();
  final _pairCode = TextEditingController();
  final _connect = TextEditingController();

  @override
  void dispose() {
    for (final c in [_name, _url, _desc, _board, _workspace, _assignee, _hub, _pairUrl, _pairCode, _connect]) {
      c.dispose();
    }
    super.dispose();
  }

  String _err(Object e) => e is ApiException ? e.message : '$e';

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  List<Map<String, dynamic>> _maps(dynamic raw) =>
      ((raw as List?) ?? const []).whereType<Map>().map((m) => m.cast<String, dynamic>()).toList();

  Future<void> _load() async {
    try {
      final api = ref.read(apiClientProvider);
      final st = (await api.get('/api/sen-link/status') as Map).cast<String, dynamic>();
      final peers = (await api.get('/api/sen-link/peers') as Map);
      if (!mounted) return;
      setState(() {
        _apply((st['settings'] as Map).cast<String, dynamic>());
        _peers = _maps(peers['peers']);
        _loadError = null;
      });
    } catch (e) {
      if (mounted) setState(() => _loadError = _err(e));
    }
  }

  void _apply(Map<String, dynamic> s) {
    _settings = s;
    _enabled = s['enabled'] == true;
    _name.text = '${s['name'] ?? ''}';
    _url.text = '${s['publicUrl'] ?? ''}';
    _desc.text = '${s['description'] ?? ''}';
    _board.text = '${s['boardTitle'] ?? 'sen-link'}';
    _workspace.text = '${s['workspaceDir'] ?? ''}';
    _assignee.text = '${s['defaultAssignee'] ?? ''}';
    _hub.text = '${s['hubUrl'] ?? ''}';
  }

  Future<void> _save() async {
    final base = _settings;
    if (base == null) return;
    final saved = context.tr('Saved');
    setState(() => _saving = true);
    try {
      final s = (await ref.read(apiClientProvider).put('/api/sen-link/settings', body: {
        ...base,
        'enabled': _enabled,
        'name': _name.text.trim(),
        'publicUrl': orNull(_url.text),
        'description': _desc.text.trim(),
        'boardTitle': _board.text.trim(),
        'workspaceDir': orNull(_workspace.text),
        'defaultAssignee': orNull(_assignee.text),
        'hubUrl': orNull(_hub.text),
      }) as Map)
          .cast<String, dynamic>();
      if (mounted) setState(() => _apply(s));
      _snack(saved);
    } catch (e) {
      _snack(_err(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _createInvite() async {
    try {
      final r = (await ref.read(apiClientProvider).post('/api/sen-link/invites') as Map);
      if (mounted) {
        setState(() => _invite = (
              code: '${r['code']}',
              expiresAt: (r['expiresAt'] as num).toInt(),
              connect: r['connect'] as String?,
            ));
      }
    } catch (e) {
      _snack(_err(e));
    }
  }

  /// Pair directly (URL + code) or, with [viaHub], by a `senlink:` string.
  Future<void> _pair({bool viaHub = false}) async {
    final pairedWith = context.tr('Paired with');
    final body = viaHub
        ? {'connect': _connect.text.trim()}
        : {'url': _pairUrl.text.trim(), 'code': _pairCode.text.trim()};
    try {
      final p = (await ref.read(apiClientProvider).post('/api/sen-link/peers/pair', body: body) as Map);
      _pairCode.clear();
      _connect.clear();
      _snack('$pairedWith ${p['name']}');
      await _load();
    } catch (e) {
      _snack(_err(e));
    }
  }

  Future<void> _patch(String id, Map<String, dynamic> body) async {
    try {
      final p = (await ref.read(apiClientProvider).patch('/api/sen-link/peers/$id', body: body) as Map)
          .cast<String, dynamic>();
      if (mounted) setState(() => _peers = [for (final x in _peers) x['id'] == id ? p : x]);
    } catch (e) {
      _snack(_err(e));
    }
  }

  Future<void> _setAutoRun(Map<String, dynamic> p, bool on) async {
    if (on) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(ctx.tr('Run this peer\'s tasks without review?')),
          content: Text(ctx.tr('With assignee claude-code this gives the peer a shell on this machine.')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.tr('Cancel'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ctx.tr('Confirm'))),
          ],
        ),
      );
      if (ok != true) return;
    }
    await _patch('${p['id']}', {'autoRun': on});
  }

  Future<void> _togglePeerTasks(String id) async {
    if (_openPeer == id) {
      setState(() => _openPeer = null);
      return;
    }
    setState(() {
      _openPeer = id;
      _peerTasks = null;
      _peerTasksError = null;
    });
    try {
      final r = (await ref.read(apiClientProvider).get('/api/sen-link/peers/$id/tasks') as Map);
      if (mounted && _openPeer == id) setState(() => _peerTasks = _maps(r['tasks']));
    } catch (e) {
      if (mounted && _openPeer == id) setState(() => _peerTasksError = _err(e));
    }
  }

  Future<void> _sendTask(Map<String, dynamic> p) async {
    final taskLabel = context.tr('Task');
    final text = TextEditingController();
    var worktree = true;
    final send = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text('${ctx.tr('Send a task to')} ${p['name']}'),
          content: SizedBox(
            width: 480,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                controller: text,
                maxLines: 6,
                decoration: InputDecoration(hintText: ctx.tr('What should the other SenClaw do?')),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: worktree,
                onChanged: (v) => setD(() => worktree = v ?? true),
                title: Text(ctx.tr('Ask it to work on its own git branch (worktree)'), style: const TextStyle(fontSize: 13)),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.tr('Cancel'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ctx.tr('Send'))),
          ],
        ),
      ),
    );
    final body = text.text.trim();
    text.dispose();
    if (send != true || body.isEmpty) return;
    try {
      final r = (await ref.read(apiClientProvider)
          .post('/api/sen-link/peers/${p['id']}/messages', body: {'text': body, 'worktree': worktree}) as Map);
      final t = (r['task'] as Map);
      _snack('$taskLabel #${t['id']}: ${taskStateLabel('${(t['status'] as Map)['state']}')}');
    } catch (e) {
      _snack(_err(e));
    }
  }

  Future<void> _remove(String id) async {
    try {
      await ref.read(apiClientProvider).delete('/api/sen-link/peers/$id');
      await _load();
    } catch (e) {
      _snack(_err(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SettingsBody(
      title: 'sen-link',
      onRefresh: _load,
      children: [
        if (_loadError != null) coworkNotice(context, _loadError!, color: AppTokens.danger),
        if (_settings == null && _loadError == null)
          const Center(child: CircularProgressIndicator())
        else if (_settings != null) ...[
          coworkCard(
            context,
            title: 'sen-link',
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                context.tr('Connect this SenClaw to another one (A2A protocol) to hand tasks back and forth. Tasks a peer sends land on a kanban board.'),
                style: TextStyle(color: c.textMuted, fontSize: 12),
              ),
              SwitchListTile(
                key: const Key('sl-enabled'),
                contentPadding: EdgeInsets.zero,
                title: Text(context.tr('Enabled'), style: const TextStyle(fontSize: 13)),
                value: _enabled,
                onChanged: (v) => setState(() => _enabled = v),
              ),
              coworkField(context, label: context.tr('Name shown to peers'), child: TextField(controller: _name, decoration: const InputDecoration(isDense: true))),
              coworkField(context,
                  label: context.tr('Public URL'),
                  help: context.tr('How peers reach this daemon, e.g. a Tailscale address. The daemon must be bound beyond loopback (Settings → General → Network access).'),
                  child: TextField(controller: _url, decoration: const InputDecoration(hintText: 'http://100.64.0.2:18788', isDense: true))),
              coworkField(context,
                  label: context.tr('Hub URL'),
                  help: context.tr('A SenClaw hub for peers that cannot reach each other directly (NAT). Each invite then gets its own encrypted hub channel.'),
                  child: TextField(key: const Key('sl-hub'), controller: _hub, decoration: const InputDecoration(hintText: 'https://hub.example.com', isDense: true))),
              coworkField(context, label: context.tr('Description'), child: TextField(controller: _desc, decoration: const InputDecoration(isDense: true))),
              Wrap(spacing: AppTokens.s16, children: [
                SizedBox(width: 200, child: coworkField(context, label: context.tr('Board for incoming tasks'), child: TextField(controller: _board, decoration: const InputDecoration(isDense: true)))),
                SizedBox(
                    width: 280,
                    child: coworkField(context,
                        label: context.tr('Workspace folder'),
                        help: context.tr('Where workers for incoming tasks run.'),
                        child: TextField(controller: _workspace, decoration: const InputDecoration(isDense: true)))),
                SizedBox(width: 180, child: coworkField(context, label: context.tr('Default assignee'), child: TextField(controller: _assignee, decoration: const InputDecoration(hintText: 'claude-code', isDense: true)))),
              ]),
              FilledButton(key: const Key('sl-save'), onPressed: _saving ? null : _save, child: Text(context.tr('Save'))),
            ]),
          ),
          coworkCard(
            context,
            title: context.tr('Pair with another SenClaw'),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (_settings?['enabled'] != true) coworkNotice(context, context.tr('Enable sen-link and save first.')),
              Row(children: [
                OutlinedButton(
                  key: const Key('sl-invite'),
                  onPressed: _settings?['enabled'] == true ? _createInvite : null,
                  child: Text(context.tr('Create invite code')),
                ),
                if (_invite?.connect != null) ...[
                  const SizedBox(width: AppTokens.s12),
                  Expanded(
                    child: SelectableText(_invite!.connect!,
                        maxLines: 2, style: TextStyle(fontFamily: AppTokens.fontMono, fontSize: 12, color: c.textPrimary)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy, size: 16),
                    onPressed: () => Clipboard.setData(ClipboardData(text: _invite!.connect!)),
                  ),
                ] else if (_invite != null) ...[
                  const SizedBox(width: AppTokens.s12),
                  SelectableText(_invite!.code,
                      style: TextStyle(fontFamily: AppTokens.fontMono, fontSize: 18, color: c.textPrimary)),
                  IconButton(
                    icon: const Icon(Icons.copy, size: 16),
                    onPressed: () => Clipboard.setData(ClipboardData(text: _invite!.code)),
                  ),
                  Flexible(
                    child: Text(
                      '${context.tr('valid until')} ${TimeOfDay.fromDateTime(DateTime.fromMillisecondsSinceEpoch(_invite!.expiresAt * 1000)).format(context)} · ${context.tr('use it once on the other SenClaw')}',
                      style: TextStyle(color: c.textMuted, fontSize: 12),
                    ),
                  ),
                ],
              ]),
              const SizedBox(height: AppTokens.s12),
              Wrap(spacing: AppTokens.s8, runSpacing: AppTokens.s8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                SizedBox(
                    width: 300,
                    child: TextField(controller: _pairUrl, decoration: InputDecoration(hintText: context.tr('Other SenClaw URL, e.g. http://100.64.0.3:18788'), isDense: true))),
                SizedBox(
                    width: 160,
                    child: TextField(controller: _pairCode, decoration: InputDecoration(hintText: context.tr('Invite code'), isDense: true))),
                FilledButton.icon(
                  onPressed: _settings?['enabled'] == true ? _pair : null,
                  icon: const Icon(Icons.link, size: 16),
                  label: Text(context.tr('Pair')),
                ),
              ]),
              const SizedBox(height: AppTokens.s8),
              Wrap(spacing: AppTokens.s8, runSpacing: AppTokens.s8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                SizedBox(
                    width: 470,
                    child: TextField(
                        key: const Key('sl-connect'),
                        controller: _connect,
                        decoration: InputDecoration(hintText: context.tr('…or paste a senlink: connection string (hub invite)'), isDense: true))),
                OutlinedButton.icon(
                  key: const Key('sl-pair-hub'),
                  onPressed: _settings?['enabled'] == true ? () => _pair(viaHub: true) : null,
                  icon: const Icon(Icons.hub_outlined, size: 16),
                  label: Text(context.tr('Pair via hub')),
                ),
              ]),
            ]),
          ),
          coworkCard(
            context,
            title: context.tr('Peers'),
            child: _peers.isEmpty
                ? Text(context.tr('No peers yet'), style: TextStyle(color: c.textMuted))
                : Column(children: [for (final p in _peers) _peerRow(p)]),
          ),
        ],
      ],
    );
  }

  Widget _peerRow(Map<String, dynamic> p) {
    final c = context.colors;
    final id = '${p['id']}';
    final canSend = p['canSend'] == true;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${p['name']}', style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.w600)),
            Text(p['viaRelay'] == true ? 'hub' : '${p['url'] ?? '—'}', style: TextStyle(color: c.textMuted, fontSize: 12)),
          ]),
        ),
        Text(context.tr('Their tasks run'), style: TextStyle(color: c.textMuted, fontSize: 12)),
        const SizedBox(width: AppTokens.s4),
        Switch(value: p['autoRun'] == true, onChanged: (v) => _setAutoRun(p, v)),
        Text(p['autoRun'] == true ? context.tr('auto') : context.tr('triage'), style: TextStyle(color: c.textMuted, fontSize: 12)),
        const SizedBox(width: AppTokens.s12),
        SizedBox(
          width: 140,
          child: TextFormField(
            initialValue: '${p['assignee'] ?? ''}',
            decoration: InputDecoration(hintText: context.tr('Assignee'), isDense: true),
            onFieldSubmitted: (v) => _patch(id, {'assignee': v.trim()}),
          ),
        ),
        IconButton(
          tooltip: context.tr('Send task'),
          icon: const Icon(Icons.send, size: 18),
          onPressed: canSend ? () => _sendTask(p) : null,
        ),
        IconButton(
          tooltip: context.tr('Tasks'),
          icon: Icon(_openPeer == id ? Icons.expand_less : Icons.expand_more, size: 18),
          onPressed: canSend ? () => _togglePeerTasks(id) : null,
        ),
        IconButton(
          tooltip: context.tr('Remove this peer?'),
          icon: const Icon(Icons.delete_outline, size: 18, color: AppTokens.danger),
          onPressed: () => _remove(id),
        ),
      ]),
      if (_openPeer == id)
        Padding(
          padding: const EdgeInsets.only(left: AppTokens.s12, bottom: AppTokens.s8),
          child: _peerTasksError != null
              ? coworkNotice(context, '${context.tr('Could not reach this peer')}: $_peerTasksError', color: AppTokens.warning)
              : _peerTasks == null
                  ? const LinearProgressIndicator()
                  : _peerTasks!.isEmpty
                      ? Text(context.tr('No tasks sent to this peer yet'), style: TextStyle(color: c.textMuted, fontSize: 12))
                      : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          for (final t in _peerTasks!)
                            Padding(
                              padding: const EdgeInsets.only(bottom: AppTokens.s6),
                              child: Text(
                                '#${t['id']}  ${(t['metadata'] as Map?)?['title'] ?? ''}  — ${taskStateLabel('${(t['status'] as Map?)?['state'] ?? ''}')}',
                                style: TextStyle(color: c.textPrimary, fontSize: 12),
                              ),
                            ),
                        ]),
        ),
      Divider(color: c.border, height: 1),
    ]);
  }
}
