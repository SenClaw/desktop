import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/l10n.dart';
import '../../core/transport/api_client.dart' show ApiException;
import '../../core/transport/connection.dart';
import '../../theme/tokens.dart';
import 'cowork_common.dart';
import 'sen_link_knowledge.dart';
import 'settings_screen.dart' show SettingsBody;

/// `TASK_STATE_WORKING` → `working`.
String taskStateLabel(String s) => s.replaceFirst('TASK_STATE_', '').toLowerCase().replaceAll('_', ' ');

/// `ip:port`, with an IPv6 address in brackets.
String slHostPort(String ip, int port) => ip.contains(':') ? '[$ip]:$port' : '$ip:$port';

/// Settings → SLink (code name sen-link): peer this SenClaw with another one
/// on the same network over A2A (daemon `src/sen_link/`, REST
/// `/api/sen-link/*`), delegate tasks to it, and decide how much a peer's own
/// tasks may do here.
class SenLinkSection extends ConsumerStatefulWidget {
  const SenLinkSection({super.key});

  @override
  ConsumerState<SenLinkSection> createState() => _SenLinkSectionState();
}

class _SenLinkSectionState extends ConsumerState<SenLinkSection> {
  Map<String, dynamic>? _settings;
  Map<String, dynamic> _status = const {};
  List<Map<String, dynamic>> _peers = const [];
  String? _loadError;
  bool _saving = false;
  bool _enabled = false;
  bool _discoverable = true;
  bool _migratedShown = true;
  ({String code, int expiresAt, int port, List<String> addresses, bool listening, String? listenError})? _invite;
  Map<String, dynamic>? _probe;
  bool _probing = false;
  List<Map<String, dynamic>> _discovered = const [];
  Map<String, dynamic>? _scan;
  // Polls start only while something is worth polling and end in dispose.
  Timer? _discoverTimer;
  Timer? _scanTimer;
  String? _openPeer;
  // Which of the open peer's two panels shows: `tasks` or `knowledge`.
  String _peerTab = 'tasks';
  List<Map<String, dynamic>>? _peerTasks;
  String? _peerTasksError;

  final _name = TextEditingController();
  final _desc = TextEditingController();
  final _board = TextEditingController();
  final _workspace = TextEditingController();
  final _assignee = TextEditingController();
  final _listenHost = TextEditingController();
  final _listenPort = TextEditingController();
  final _pairAddr = TextEditingController();
  final _pairCode = TextEditingController();

  @override
  void dispose() {
    _discoverTimer?.cancel();
    _scanTimer?.cancel();
    for (final c in [_name, _desc, _board, _workspace, _assignee, _listenHost, _listenPort, _pairAddr, _pairCode]) {
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
        _status = st;
        _apply((st['settings'] as Map).cast<String, dynamic>());
        _peers = _maps(peers['peers']);
        _loadError = null;
      });
      _syncDiscoveryPolling();
    } catch (e) {
      if (mounted) setState(() => _loadError = _err(e));
    }
  }

  /// What the network shows changes by itself, so look again every few seconds
  /// while SLink is on and this screen is open.
  void _syncDiscoveryPolling() {
    final on = _settings?['enabled'] == true;
    if (on && _discoverTimer == null) {
      _discoverTimer = Timer.periodic(const Duration(seconds: 5), (_) => _loadDiscovered());
      _loadDiscovered();
    } else if (!on) {
      _discoverTimer?.cancel();
      _discoverTimer = null;
    }
  }

  Future<void> _loadDiscovered() async {
    try {
      final r = (await ref.read(apiClientProvider).get('/api/sen-link/discovered') as Map);
      if (mounted) setState(() => _discovered = _maps(r['discovered']));
    } catch (_) {
      // The list is a convenience; a missed look is simply retried.
    }
  }

  Future<void> _startScan() async {
    try {
      final r = (await ref.read(apiClientProvider).post('/api/sen-link/scan', body: <String, dynamic>{}) as Map).cast<String, dynamic>();
      if (!mounted) return;
      setState(() => _scan = r);
      _scanTimer?.cancel();
      _scanTimer = Timer.periodic(const Duration(milliseconds: 700), (_) => _pollScan());
    } catch (e) {
      _snack(_err(e));
    }
  }

  Future<void> _pollScan() async {
    final id = _scan?['scanId'];
    if (id == null) return;
    try {
      final r = (await ref.read(apiClientProvider).get('/api/sen-link/scan/$id') as Map).cast<String, dynamic>();
      if (!mounted) return;
      setState(() => _scan = r);
      if (r['state'] != 'running') {
        _scanTimer?.cancel();
        _scanTimer = null;
        await _loadDiscovered();
      }
    } catch (e) {
      _scanTimer?.cancel();
      _scanTimer = null;
      _snack(_err(e));
    }
  }

  Future<void> _cancelScan() async {
    final id = _scan?['scanId'];
    if (id == null) return;
    try {
      final r = (await ref.read(apiClientProvider).post('/api/sen-link/scan/$id/cancel') as Map).cast<String, dynamic>();
      if (mounted) setState(() => _scan = r);
    } catch (e) {
      _snack(_err(e));
    }
  }

  /// Put a discovered SLink's address in the form and check it.
  Future<void> _use(Map<String, dynamic> d) async {
    final addrs = (d['addrs'] as List?) ?? const [];
    if (addrs.isEmpty) return;
    setState(() {
      _pairAddr.text = slHostPort('${addrs.first}', (d['port'] as num).toInt());
      _probe = null;
    });
    await _check();
  }

  void _apply(Map<String, dynamic> s) {
    _settings = s;
    _enabled = s['enabled'] == true;
    _discoverable = s['discoverable'] != false;
    _name.text = '${s['name'] ?? ''}';
    _desc.text = '${s['description'] ?? ''}';
    _board.text = '${s['boardTitle'] ?? 'SLink'}';
    _workspace.text = '${s['workspaceDir'] ?? ''}';
    _assignee.text = '${s['defaultAssignee'] ?? ''}';
    _listenHost.text = '${s['listenHost'] ?? '0.0.0.0'}';
    _listenPort.text = '${s['listenPort'] ?? 18791}';
  }

  Future<void> _save() async {
    final base = _settings;
    if (base == null) return;
    final saved = context.tr('Saved');
    final port = int.tryParse(_listenPort.text.trim());
    if (port == null || port < 1 || port > 65535) {
      _snack(context.tr('Listen port must be 1-65535.'));
      return;
    }
    setState(() => _saving = true);
    try {
      final s = (await ref.read(apiClientProvider).put('/api/sen-link/settings', body: {
        ...base,
        'enabled': _enabled,
        'name': _name.text.trim(),
        'description': _desc.text.trim(),
        'listenHost': _listenHost.text.trim(),
        'listenPort': port,
        'discoverable': _discoverable,
        'boardTitle': _board.text.trim(),
        'workspaceDir': orNull(_workspace.text),
        'defaultAssignee': orNull(_assignee.text),
      }) as Map)
          .cast<String, dynamic>();
      if (mounted) setState(() => _apply(s));
      _snack(saved);
      // The daemon opens, moves or closes its LAN socket a moment after the save.
      await Future<void>.delayed(const Duration(milliseconds: 600));
      if (mounted) await _load();
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
              port: (r['port'] as num?)?.toInt() ?? 18791,
              addresses: [for (final a in (r['addresses'] as List?) ?? const []) '$a'],
              listening: r['listening'] != false,
              listenError: r['listenError'] as String?,
            ));
      }
    } catch (e) {
      _snack(_err(e));
    }
  }

  /// Where the typed IP or name lands, and whether a SLink answers there.
  Future<void> _check() async {
    setState(() => _probing = true);
    try {
      final r = (await ref.read(apiClientProvider).post('/api/sen-link/probe', body: {'addr': _pairAddr.text.trim()}) as Map)
          .cast<String, dynamic>();
      if (mounted) setState(() => _probe = r);
    } catch (e) {
      _snack(_err(e));
    } finally {
      if (mounted) setState(() => _probing = false);
    }
  }

  /// Pair with the daemon at the typed IP or DNS name, using its invite code.
  Future<void> _pair() async {
    final pairedWith = context.tr('Paired with');
    try {
      final p = (await ref
          .read(apiClientProvider)
          .post('/api/sen-link/peers/pair', body: {'addr': _pairAddr.text.trim(), 'code': _pairCode.text.trim()}) as Map);
      _pairCode.clear();
      if (mounted) setState(() => _probe = null);
      _snack('$pairedWith ${p['name']}');
      await _load();
    } catch (e) {
      _snack(_err(e));
    }
  }

  /// The SLinks the network has shown, a scan button, and each found one a tap away from the form.
  Widget _nearby() {
    final c = context.colors;
    final enabled = _settings?['enabled'] == true;
    final scan = _scan;
    final running = scan?['state'] == 'running';
    final notes = [for (final n in (scan?['notes'] as List?) ?? const []) '$n'].join(' ');
    final ranges = [for (final r in (scan?['ranges'] as List?) ?? const []) '$r'].join(', ');
    final found = ((scan?['found'] as List?) ?? const []).length;
    final discovery = (_status['discovery'] as Map?) ?? const {};
    final discoveryError = discovery['error'] as String?;
    final notAnnouncing = enabled && _discoverable && _status['listening'] != null && discovery['advertising'] != true;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: AppTokens.s8, runSpacing: AppTokens.s8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Text(context.tr('Nearby SenClaws'), style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.w600, fontSize: 13)),
        Tooltip(
          message: context.tr('A scan tries to connect to the SLink port on every address of this machine\'s networks. Some company networks flag that.'),
          child: OutlinedButton(
            key: const Key('sl-scan'),
            onPressed: enabled && !running ? _startScan : null,
            child: Text(context.tr('Scan network')),
          ),
        ),
        if (running)
          OutlinedButton(key: const Key('sl-scan-cancel'), onPressed: _cancelScan, child: Text(context.tr('Cancel'))),
      ]),
      if (running && scan != null) ...[
        const SizedBox(height: AppTokens.s8),
        LinearProgressIndicator(
          key: const Key('sl-scan-progress'),
          value: ((scan['total'] as num?) ?? 0) > 0 ? ((scan['scanned'] as num).toDouble() / (scan['total'] as num).toDouble()) : null,
        ),
        Text('${scan['scanned']}/${scan['total']}', style: TextStyle(color: c.textMuted, fontSize: 12)),
      ],
      if (notes.isNotEmpty) ...[const SizedBox(height: AppTokens.s8), coworkNotice(context, notes)],
      if (scan != null && !running)
        Padding(
          padding: const EdgeInsets.only(top: AppTokens.s8),
          child: Text(
            key: const Key('sl-scan-summary'),
            scan['state'] == 'canceled'
                ? context.tr('Scan canceled.')
                : found == 0
                    ? context.trArgs('Scan finished: no SenClaw on {ranges}.', {'ranges': ranges})
                    : context.trArgs('Scan finished: {n} found on {ranges}.', {'n': found, 'ranges': ranges}),
            style: TextStyle(color: c.textMuted, fontSize: 12),
          ),
        ),
      if (discoveryError != null && enabled) ...[
        const SizedBox(height: AppTokens.s8),
        coworkNotice(context, context.trArgs('Finding SenClaws by announcement is not working: {error}', {'error': discoveryError}), color: AppTokens.warning),
      ],
      const SizedBox(height: AppTokens.s8),
      if (_discovered.isEmpty)
        Text(
          enabled
              ? context.tr('No other SenClaw seen yet. They show up here when they announce themselves on this network; or scan, or type an address.')
              : context.tr('Enable SLink to find other SenClaws.'),
          style: TextStyle(color: c.textMuted, fontSize: 12),
        )
      else
        for (final d in _discovered)
          Padding(
            padding: const EdgeInsets.only(bottom: AppTokens.s4),
            child: Wrap(spacing: AppTokens.s8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text('${d['name']}', style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.w600)),
              Text(slHostPort('${((d['addrs'] as List?) ?? const ['']).first}', (d['port'] as num).toInt()),
                  style: TextStyle(fontFamily: AppTokens.fontMono, fontSize: 12, color: c.textMuted)),
              if (d['pairable'] == true) Text(context.tr('has an invite'), style: const TextStyle(color: AppTokens.success, fontSize: 12)),
              for (final src in (d['sources'] as List?) ?? const [])
                Text(src == 'mdns' ? context.tr('announced') : context.tr('scan'), style: TextStyle(color: c.textMuted, fontSize: 12)),
              TextButton(key: Key('sl-use-${d['daemonId']}'), onPressed: () => _use(d), child: Text(context.tr('Use'))),
            ]),
          ),
      if (notAnnouncing)
        Text(context.tr('This SenClaw is not announcing itself, so others will not find it by listening.'), style: TextStyle(color: c.textMuted, fontSize: 12)),
    ]);
  }

  /// What a probe found, in a sentence a person can act on.
  Widget _probeResult() {
    final r = _probe!;
    final card = r['card'] as Map?;
    final addr = '${r['addr']}';
    if (r['ok'] == true && card != null) {
      final pairable = card['pairable'] == true;
      final resolved = ((r['resolved'] as List?) ?? const []).join(', ');
      return coworkNotice(
        context,
        [
          context.trArgs('Found {name} at {addr}', {'name': card['name'], 'addr': addr}),
          if (resolved.isNotEmpty) resolved,
          if (!pairable) context.tr('It has no invite right now. Create one on that SenClaw and type its code here.'),
        ].join('\n'),
        color: pairable ? AppTokens.success : null,
      );
    }
    if (r['ok'] == true && r['hidden'] == true) {
      return coworkNotice(
        context,
        context.trArgs('A SLink answers at {addr}, but it hides its name. You can still pair with a code.', {'addr': addr}),
        color: AppTokens.success,
      );
    }
    return coworkNotice(context, '${r['error'] ?? context.tr('Nothing answered.')}', color: AppTokens.warning);
  }

  /// A value in monospace with a copy button.
  Widget _copyable(String text, {double size = 13}) {
    final c = context.colors;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      SelectableText(text, style: TextStyle(fontFamily: AppTokens.fontMono, fontSize: size, color: c.textPrimary)),
      IconButton(
        visualDensity: VisualDensity.compact,
        icon: const Icon(Icons.copy, size: 14),
        onPressed: () => Clipboard.setData(ClipboardData(text: text)),
      ),
    ]);
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

  /// Open or close a peer's panels. Tasks come first, unless the peer cannot be sent any.
  Future<void> _togglePeer(String id, {required bool canSend}) async {
    if (_openPeer == id) {
      setState(() => _openPeer = null);
      return;
    }
    setState(() {
      _openPeer = id;
      _peerTab = canSend ? 'tasks' : 'knowledge';
    });
    if (canSend) await _loadPeerTasks(id);
  }

  Future<void> _pickPeerTab(String id, String tab) async {
    setState(() => _peerTab = tab);
    if (tab == 'tasks') await _loadPeerTasks(id);
  }

  Future<void> _loadPeerTasks(String id) async {
    setState(() {
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
    final migrated = [for (final n in (_status['migrated'] as List?) ?? const []) '$n'];
    final listening = _status['listening'] as String?;
    final addresses = [for (final a in (_status['addresses'] as List?) ?? const []) '$a'];
    final port = int.tryParse(_listenPort.text.trim()) ?? 18791;
    return SettingsBody(
      title: 'SLink',
      onRefresh: _load,
      children: [
        if (_loadError != null) coworkNotice(context, _loadError!, color: AppTokens.danger),
        if (_settings == null && _loadError == null)
          const Center(child: CircularProgressIndicator())
        else if (_settings != null) ...[
          if (migrated.isNotEmpty && _migratedShown)
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: coworkNotice(
                  context,
                  context.trArgs('Peers that only a hub reached were removed: {names}. Pair them again over the LAN.', {'names': migrated.join(', ')}),
                  color: AppTokens.warning,
                ),
              ),
              IconButton(
                key: const Key('sl-migrated-close'),
                tooltip: context.tr('Close'),
                icon: const Icon(Icons.close, size: 16),
                onPressed: () => setState(() => _migratedShown = false),
              ),
            ]),
          coworkCard(
            context,
            title: 'SLink',
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                context.tr('Connect this SenClaw to another one on the same network (A2A protocol) to hand tasks back and forth. Tasks a peer sends land on a kanban board.'),
                style: TextStyle(color: c.textMuted, fontSize: 12),
              ),
              SwitchListTile(
                key: const Key('sl-enabled'),
                contentPadding: EdgeInsets.zero,
                title: Text(context.tr('Enabled'), style: const TextStyle(fontSize: 13)),
                value: _enabled,
                onChanged: (v) => setState(() => _enabled = v),
              ),
              if (_settings?['enabled'] == true)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppTokens.s8),
                  child: Text(
                    key: const Key('sl-listening'),
                    listening != null
                        ? context.trArgs('Listening on {addr}', {'addr': listening})
                        : '${_status['listenError'] ?? context.tr('Not listening')}',
                    style: TextStyle(color: listening != null ? AppTokens.success : AppTokens.danger, fontSize: 12),
                  ),
                ),
              coworkField(context, label: context.tr('Name shown to peers'), child: TextField(controller: _name, decoration: const InputDecoration(isDense: true))),
              Wrap(spacing: AppTokens.s16, children: [
                SizedBox(
                    width: 220,
                    child: coworkField(context,
                        label: context.tr('Listen address'),
                        help: context.tr('Which network interface SLink listens on; 0.0.0.0 is all of them. Only connections from a private network are accepted either way.'),
                        child: TextField(key: const Key('sl-listen-host'), controller: _listenHost, decoration: const InputDecoration(hintText: '0.0.0.0', isDense: true)))),
                SizedBox(
                    width: 140,
                    child: coworkField(context,
                        label: context.tr('Listen port'),
                        child: TextField(
                            key: const Key('sl-listen-port'),
                            controller: _listenPort,
                            keyboardType: TextInputType.number,
                            onChanged: (_) => setState(() {}),
                            decoration: const InputDecoration(isDense: true)))),
              ]),
              SwitchListTile(
                key: const Key('sl-discoverable'),
                contentPadding: EdgeInsets.zero,
                title: Text(context.tr('Visible to others'), style: const TextStyle(fontSize: 13)),
                subtitle: Text(
                  context.tr('Off: another SenClaw cannot find this one by checking or scanning its address. Pairing with a typed address and a code still works.'),
                  style: TextStyle(color: c.textMuted, fontSize: 12),
                ),
                value: _discoverable,
                onChanged: (v) => setState(() => _discoverable = v),
              ),
              if (addresses.isNotEmpty)
                coworkField(context,
                    label: context.tr('Addresses of this machine'),
                    help: context.tr('Type one of these on the other SenClaw to pair with this one.'),
                    child: Wrap(spacing: AppTokens.s12, children: [for (final a in addresses) _copyable(slHostPort(a, port))])),
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
              if (_settings?['enabled'] != true) coworkNotice(context, context.tr('Enable SLink and save first.')),
              Wrap(spacing: AppTokens.s12, runSpacing: AppTokens.s8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                OutlinedButton(
                  key: const Key('sl-invite'),
                  onPressed: _settings?['enabled'] == true ? _createInvite : null,
                  child: Text(context.tr('Create invite code')),
                ),
                if (_invite != null) ...[
                  _copyable(_invite!.code, size: 18),
                  Text(
                    '${context.tr('valid until')} ${TimeOfDay.fromDateTime(DateTime.fromMillisecondsSinceEpoch(_invite!.expiresAt * 1000)).format(context)} · ${context.tr('use it once on the other SenClaw')}',
                    style: TextStyle(color: c.textMuted, fontSize: 12),
                  ),
                ],
              ]),
              if (_invite != null)
                Padding(
                  padding: const EdgeInsets.only(top: AppTokens.s4),
                  child: Text(context.tr('Only the newest code works. It stops working after three wrong tries.'),
                      key: const Key('sl-invite-note'), style: TextStyle(color: c.textMuted, fontSize: 12)),
                ),
              if (_invite != null && !_invite!.listening)
                coworkNotice(context, _invite!.listenError ?? context.tr('SLink is not listening, so the other SenClaw cannot reach this one.'),
                    color: AppTokens.warning),
              if (_invite != null && _invite!.addresses.isNotEmpty) ...[
                const SizedBox(height: AppTokens.s8),
                Wrap(spacing: AppTokens.s12, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  Text(context.tr('Type this on the other SenClaw:'), style: TextStyle(color: c.textMuted, fontSize: 12)),
                  for (final a in _invite!.addresses) _copyable(slHostPort(a, _invite!.port)),
                ]),
              ],
              const SizedBox(height: AppTokens.s12),
              _nearby(),
              const SizedBox(height: AppTokens.s12),
              Wrap(spacing: AppTokens.s8, runSpacing: AppTokens.s8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                SizedBox(
                    width: 340,
                    child: TextField(
                        key: const Key('sl-pair-addr'),
                        controller: _pairAddr,
                        onChanged: (_) => setState(() => _probe = null),
                        onSubmitted: (v) => v.trim().isEmpty ? null : _check(),
                        decoration: InputDecoration(
                            hintText: context.tr('IP or name of the other SenClaw, e.g. 192.168.1.20 or mac-mini.local'), isDense: true))),
                OutlinedButton(
                  key: const Key('sl-check'),
                  onPressed: _probing || _pairAddr.text.trim().isEmpty ? null : _check,
                  child: Text(context.tr('Check')),
                ),
                SizedBox(
                    width: 160,
                    child: TextField(
                        key: const Key('sl-pair-code'),
                        controller: _pairCode,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(hintText: context.tr('Invite code'), isDense: true))),
                FilledButton.icon(
                  key: const Key('sl-pair'),
                  onPressed: _settings?['enabled'] == true && _pairAddr.text.trim().isNotEmpty && _pairCode.text.trim().isNotEmpty ? _pair : null,
                  icon: const Icon(Icons.link, size: 16),
                  label: Text(context.tr('Pair')),
                ),
              ]),
              if (_probe != null) ...[
                const SizedBox(height: AppTokens.s8),
                _probeResult(),
              ],
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

  /// The tasks sent to the open peer, read back from it.
  Widget _peerTasksView() {
    final c = context.colors;
    if (_peerTasksError != null) {
      return coworkNotice(context, '${context.tr('Could not reach this peer')}: $_peerTasksError', color: AppTokens.warning);
    }
    if (_peerTasks == null) return const LinearProgressIndicator();
    if (_peerTasks!.isEmpty) {
      return Text(context.tr('No tasks sent to this peer yet'), style: TextStyle(color: c.textMuted, fontSize: 12));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (final t in _peerTasks!)
        Padding(
          padding: const EdgeInsets.only(bottom: AppTokens.s6),
          child: Text(
            '#${t['id']}  ${(t['metadata'] as Map?)?['title'] ?? ''}  — ${taskStateLabel('${(t['status'] as Map?)?['state'] ?? ''}')}',
            style: TextStyle(color: c.textPrimary, fontSize: 12),
          ),
        ),
    ]);
  }

  Widget _peerRow(Map<String, dynamic> p) {
    final c = context.colors;
    final id = '${p['id']}';
    final canSend = p['canSend'] == true;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              Flexible(child: Text('${p['name']}', overflow: TextOverflow.ellipsis, style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.w600))),
              if (SlKnowledgePolicy.fromJson(p['knowledge']).open) ...[
                const SizedBox(width: AppTokens.s8),
                Tooltip(
                  message: context.tr('This peer may ask what you know. Open the Knowledge panel to see what.'),
                  child: Text(context.tr('shares knowledge'), key: const Key('sl-shares'), style: const TextStyle(color: AppTokens.brandAlt, fontSize: 12)),
                ),
              ],
            ]),
            Row(children: [
              Flexible(child: Text('${p['addr'] ?? '—'}', overflow: TextOverflow.ellipsis, style: TextStyle(color: c.textMuted, fontSize: 12))),
              if (p['online'] == true) ...[
                const SizedBox(width: AppTokens.s8),
                Text(context.tr('Online'), key: const Key('sl-online'), style: const TextStyle(color: AppTokens.success, fontSize: 12)),
              ],
              if (p['legacy'] == true) ...[
                const SizedBox(width: AppTokens.s8),
                Tooltip(
                  message: context.tr('Paired by an older version. Pair again over the LAN.'),
                  child: Text(context.tr('re-pair'), key: const Key('sl-legacy'), style: const TextStyle(color: AppTokens.warning, fontSize: 12)),
                ),
              ],
            ]),
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
          key: ValueKey('sl-expand-$id'),
          tooltip: context.tr('Tasks and knowledge'),
          icon: Icon(_openPeer == id ? Icons.expand_less : Icons.expand_more, size: 18),
          onPressed: () => _togglePeer(id, canSend: canSend),
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
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SegmentedButton<String>(
              key: ValueKey('sl-tabs-$id'),
              showSelectedIcon: false,
              segments: [
                ButtonSegment(value: 'tasks', label: Text(context.tr('Tasks')), enabled: canSend),
                ButtonSegment(value: 'knowledge', label: Text(context.tr('Knowledge'))),
              ],
              selected: {_peerTab},
              onSelectionChanged: (s) => _pickPeerTab(id, s.first),
            ),
            const SizedBox(height: AppTokens.s8),
            if (_peerTab == 'knowledge')
              SenLinkKnowledgePanel(
                peerId: id,
                peerName: '${p['name']}',
                canSend: canSend,
                onPeer: (u) => setState(() => _peers = [for (final x in _peers) x['id'] == id ? u : x]),
              )
            else
              _peerTasksView(),
          ]),
        ),
      Divider(color: c.border, height: 1),
    ]);
  }
}
