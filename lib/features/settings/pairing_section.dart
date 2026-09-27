import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/l10n.dart';
import '../../core/transport/api_client.dart' show ApiException;
import '../../core/transport/connection.dart';
import '../../theme/tokens.dart';

/// One chat asking to be let in, as `/api/pairings` reports it.
class PairingInfo {
  final int id;
  final String chatJid;
  final String chatType;
  final String senderName;
  final String channelName;
  final String code;
  final String status;
  final bool expired;

  const PairingInfo({
    required this.id,
    required this.chatJid,
    required this.chatType,
    required this.senderName,
    required this.channelName,
    required this.code,
    required this.status,
    required this.expired,
  });

  factory PairingInfo.fromJson(Map<String, dynamic> j) => PairingInfo(
        id: (j['id'] as num?)?.toInt() ?? 0,
        chatJid: '${j['chatJid'] ?? ''}',
        chatType: '${j['chatType'] ?? 'user'}',
        senderName: '${j['senderName'] ?? ''}',
        channelName: '${j['channelName'] ?? ''}',
        code: '${j['code'] ?? ''}',
        status: '${j['status'] ?? ''}',
        expired: j['expired'] == true,
      );

  bool get isGroup => chatType == 'group';
}

/// Slow enough to be free, fast enough that the person who just messaged the
/// bot sees their request without reloading.
const _refresh = Duration(seconds: 15);

/// Chats waiting to be let into a channel.
///
/// Before pairing existed, a Telegram message from an unknown chat completed
/// the channel's pending binding on sight — whoever messaged the bot first
/// owned it, with every tool a UI-created agent has. The bot now answers with a
/// code and stops; this panel is where a person turns that code into access.
///
/// The sender's name sits next to the code deliberately: approving is a
/// judgement about a person, and a bare `tg:…:user:812…` gives nothing to judge
/// with.
class PairingCard extends ConsumerStatefulWidget {
  const PairingCard({super.key});

  @override
  ConsumerState<PairingCard> createState() => _PairingCardState();
}

class _PairingCardState extends ConsumerState<PairingCard> {
  List<PairingInfo> _rows = const [];
  final _codeCtrl = TextEditingController();
  int? _busy;
  bool _approvingCode = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(_refresh, (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await ref.read(apiClientProvider).get('/api/pairings');
      final list = (r is Map ? r['pairings'] : null) as List?;
      if (!mounted) return;
      setState(() => _rows = (list ?? const [])
          .whereType<Map>()
          .map((m) => PairingInfo.fromJson(m.cast<String, dynamic>()))
          .toList());
    } catch (_) {
      // A failed poll is not worth a banner: the next one is 15s away.
    }
  }

  /// The daemon words its refusals for a person — an expired code, a request
  /// somebody already handled, and a channel with no agent are three different
  /// problems with three different fixes. Show what it said, never a generic
  /// "action failed" that just makes the user click again.
  void _report(Object e) {
    final msg = e is ApiException ? e.message : '$e';
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _ok(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _act(PairingInfo p, String action) async {
    // Resolved before the await: reading `context` after one is only valid
    // while still mounted, and the widget can be disposed mid-request.
    final approved = context.tr('Approved');
    final rejected = context.tr('Rejected');
    setState(() => _busy = p.id);
    try {
      final r = await ref
          .read(apiClientProvider)
          .post('/api/pairings/${p.id}/$action');
      final folder = (r is Map ? r['agentFolder'] : null) ?? '?';
      _ok(action == 'approve' ? '$approved → $folder' : rejected);
      await _load();
    } catch (e) {
      _report(e);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _approveByCode() async {
    final code = _codeCtrl.text.trim();
    if (code.isEmpty) return;
    final approved = context.tr('Approved');
    setState(() => _approvingCode = true);
    try {
      final r = await ref
          .read(apiClientProvider)
          .post('/api/pairings/approve-code', body: {'code': code});
      final folder = (r is Map ? r['agentFolder'] : null) ?? '?';
      _codeCtrl.clear();
      _ok('$approved → $folder');
      await _load();
    } catch (e) {
      _report(e);
    } finally {
      if (mounted) setState(() => _approvingCode = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final pending = _rows.where((p) => p.status == 'pending').toList();

    return Container(
      margin: const EdgeInsets.only(bottom: AppTokens.s16),
      padding: const EdgeInsets.all(AppTokens.s12),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(AppTokens.rMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.verified_user_outlined, size: 16),
              const SizedBox(width: AppTokens.s8),
              Expanded(
                child: Text(
                  context.tr('Pairing — chats waiting to connect'),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              if (pending.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppTokens.s8, vertical: AppTokens.s2),
                  decoration: BoxDecoration(
                    color: AppTokens.warning.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(AppTokens.rSm),
                  ),
                  child: Text('${pending.length}',
                      style: const TextStyle(fontSize: 11)),
                ),
              IconButton(
                icon: const Icon(Icons.refresh, size: 16),
                onPressed: _load,
                tooltip: context.tr('Refresh'),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: AppTokens.s12),
            child: Text(
              context.tr(
                  'An unknown chat that messages the bot gets an 8-character code and is not answered further until you approve it here. Codes expire after 1 hour.'),
              style: TextStyle(fontSize: 12, color: c.textMuted),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _codeCtrl,
                  onSubmitted: (_) => _approveByCode(),
                  style: const TextStyle(fontFamily: 'monospace'),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: context.tr('Paste the code they sent you'),
                  ),
                ),
              ),
              const SizedBox(width: AppTokens.s8),
              FilledButton(
                onPressed: _approvingCode ? null : _approveByCode,
                child: Text(context.tr('Approve code')),
              ),
            ],
          ),
          const SizedBox(height: AppTokens.s12),
          if (pending.isEmpty)
            Text(context.tr('No chats waiting.'),
                style: TextStyle(fontSize: 12, color: c.textMuted))
          else
            for (final p in pending) _row(p, c),
          if (_rows.any((p) => p.expired && p.status != 'approved'))
            Padding(
              padding: const EdgeInsets.only(top: AppTokens.s8),
              child: Text(
                context.tr(
                    'Some codes expired — ask the user to message the bot again for a new one.'),
                style: TextStyle(fontSize: 11, color: c.textMuted),
              ),
            ),
        ],
      ),
    );
  }

  Widget _row(PairingInfo p, dynamic c) => Container(
        margin: const EdgeInsets.only(bottom: AppTokens.s8),
        padding: const EdgeInsets.all(AppTokens.s8),
        decoration: BoxDecoration(
          border: Border.all(color: c.border),
          borderRadius: BorderRadius.circular(AppTokens.rSm),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 96,
              child: SelectableText(
                p.code,
                style: const TextStyle(
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.senderName.isEmpty
                      ? context.tr('(unknown name)')
                      : p.senderName),
                  Text(
                    '${p.chatJid}  ·  ${p.channelName}',
                    style: TextStyle(
                        fontSize: 11,
                        color: c.textMuted,
                        fontFamily: 'monospace'),
                  ),
                ],
              ),
            ),
            // A group approval admits every member of that group, not one
            // person. That difference has to be visible before the click.
            if (p.isGroup)
              Container(
                margin: const EdgeInsets.only(right: AppTokens.s8),
                padding: const EdgeInsets.symmetric(
                    horizontal: AppTokens.s6, vertical: AppTokens.s2),
                decoration: BoxDecoration(
                  color: AppTokens.danger.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(AppTokens.rSm),
                ),
                child: const Text('GROUP', style: TextStyle(fontSize: 10)),
              ),
            FilledButton(
              onPressed: _busy == p.id ? null : () => _confirm(p),
              child: Text(context.tr('Approve')),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 16),
              onPressed: _busy == p.id ? null : () => _act(p, 'reject'),
              tooltip: context.tr('Reject'),
            ),
          ],
        ),
      );

  Future<void> _confirm(PairingInfo p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('Approve this chat?')),
        content: Text(p.isGroup
            ? context.tr(
                'This is a group. Approving lets every member of that group use the agent.')
            : '${p.senderName.isEmpty ? p.chatJid : p.senderName}\n${p.chatJid}'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(context.tr('Cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(context.tr('Approve'))),
        ],
      ),
    );
    if (ok == true) await _act(p, 'approve');
  }
}
