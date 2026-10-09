import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/l10n.dart';
import '../../core/transport/api_client.dart' show ApiException;
import '../../core/transport/connection.dart';
import '../../theme/tokens.dart';
import 'cowork_common.dart';
import 'settings_screen.dart' show SettingsBody;

const _modes = ['acceptEdits', 'default', 'plan', 'auto', 'dontAsk', 'bypassPermissions'];

/// Settings → Claude Code: kanban cards assigned to `claude-code` run in the
/// user's own Claude Code CLI and SenClaw verifies the result before the card
/// closes (daemon `src/claude_code/`, REST `/api/claude-code/*`). Also shows
/// how to connect Claude Code to SenClaw's MCP bridge.
class ClaudeCodeSection extends ConsumerStatefulWidget {
  const ClaudeCodeSection({super.key});

  @override
  ConsumerState<ClaudeCodeSection> createState() => _ClaudeCodeSectionState();
}

class _ClaudeCodeSectionState extends ConsumerState<ClaudeCodeSection> {
  Map<String, dynamic>? _status;
  Map<String, dynamic>? _settings;
  List<Map<String, dynamic>> _runs = const [];
  String? _loadError;
  bool _saving = false;
  Timer? _poll;

  final _verify = TextEditingController();
  final _tools = TextEditingController();
  final _maxTurns = TextEditingController();
  final _fixRounds = TextEditingController();
  final _model = TextEditingController();
  final _binary = TextEditingController();
  final _chat = TextEditingController();
  String _mode = 'acceptEdits';
  bool _review = true;

  @override
  void initState() {
    super.initState();
    _poll = Timer.periodic(const Duration(seconds: 5), (_) => _loadRuns());
  }

  @override
  void dispose() {
    _poll?.cancel();
    for (final c in [_verify, _tools, _maxTurns, _fixRounds, _model, _binary, _chat]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final api = ref.read(apiClientProvider);
      final status = (await api.get('/api/claude-code/status') as Map).cast<String, dynamic>();
      final s = (await api.get('/api/claude-code/settings') as Map).cast<String, dynamic>();
      if (!mounted) return;
      setState(() {
        _status = status;
        _apply(s);
        _loadError = null;
      });
      _loadRuns();
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadError = e is ApiException ? e.message : '$e');
    }
  }

  Future<void> _loadRuns() async {
    try {
      final r = (await ref.read(apiClientProvider).get('/api/claude-code/runs') as Map);
      if (!mounted) return;
      setState(() => _runs = ((r['runs'] as List?) ?? const [])
          .whereType<Map>()
          .map((m) => m.cast<String, dynamic>())
          .toList());
    } catch (_) {
      // `_load` already reported an unreachable daemon.
    }
  }

  void _apply(Map<String, dynamic> s) {
    _settings = s;
    _verify.text = '${s['verifyCommand'] ?? ''}';
    _tools.text = ((s['allowedTools'] as List?) ?? const []).join(', ');
    _maxTurns.text = '${s['maxTurns'] ?? 80}';
    _fixRounds.text = '${s['maxFixRounds'] ?? 2}';
    _model.text = '${s['model'] ?? ''}';
    _binary.text = '${s['binary'] ?? 'claude'}';
    _chat.text = '${s['mcpChatJid'] ?? ''}';
    _mode = _modes.contains(s['permissionMode']) ? s['permissionMode'] as String : 'acceptEdits';
    _review = s['review'] != false;
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _save() async {
    final base = _settings;
    if (base == null) return;
    // PUT replaces the whole block: start from what the daemon sent so fields
    // this form does not show (timeouts, budget, stop-hook retries) survive.
    final body = <String, dynamic>{
      ...base,
      'verifyCommand': orNull(_verify.text),
      'allowedTools': _tools.text.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty).toList(),
      'maxTurns': int.tryParse(_maxTurns.text.trim()) ?? base['maxTurns'],
      'maxFixRounds': int.tryParse(_fixRounds.text.trim()) ?? base['maxFixRounds'],
      'model': orNull(_model.text),
      'binary': _binary.text.trim().isEmpty ? 'claude' : _binary.text.trim(),
      'mcpChatJid': orNull(_chat.text),
      'permissionMode': _mode,
      'review': _review,
    };
    final saved = context.tr('Saved');
    setState(() => _saving = true);
    try {
      final s = (await ref.read(apiClientProvider).put('/api/claude-code/settings', body: body) as Map)
          .cast<String, dynamic>();
      if (mounted) setState(() => _apply(s));
      _snack(saved);
    } catch (e) {
      _snack(e is ApiException ? e.message : '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final status = _status;
    return SettingsBody(
      title: 'Claude Code',
      onRefresh: _load,
      children: [
        if (_loadError != null) coworkNotice(context, _loadError!, color: AppTokens.danger),
        if (status == null && _loadError == null)
          const Center(child: CircularProgressIndicator())
        else if (status != null) ...[
          coworkCard(
            context,
            title: 'Claude Code',
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              status['installed'] == true
                  ? coworkNotice(
                      context,
                      '${context.tr('Found')} ${status['binary']} — ${status['version'] ?? ''}\n'
                      '${context.tr('Assign a kanban card to "claude-code" and move it to Ready: Claude Code does the work, SenClaw verifies it before the card is closed.')}',
                      color: AppTokens.success)
                  : coworkNotice(
                      context,
                      context.tr('Install Claude Code and sign in by running `claude` once, or set the binary path below.'),
                      color: AppTokens.warning),
              coworkNotice(context,
                  context.tr('The worker runs as you, with the tools allowed below (Bash by default). Its git worktree protects your checkout, not the machine. Only cards you trust should reach Ready.')),
            ]),
          ),
          coworkCard(
            context,
            title: context.tr('Connect Claude Code to SenClaw (MCP)'),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                '${context.tr('Run once in a terminal. SENCLAW_TOKEN is the daemon API token from')} ${(status['mcp'] as Map?)?['tokenFile'] ?? ''}',
                style: TextStyle(color: c.textMuted, fontSize: 12),
              ),
              const SizedBox(height: AppTokens.s8),
              for (final cmd in (((status['mcp'] as Map?)?['addCommands'] as List?) ?? const []))
                Padding(
                  padding: const EdgeInsets.only(bottom: AppTokens.s6),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                      child: SelectableText('$cmd',
                          style: TextStyle(fontFamily: AppTokens.fontMono, fontSize: 12, color: c.textPrimary)),
                    ),
                    IconButton(
                      tooltip: context.tr('Copy'),
                      icon: const Icon(Icons.copy, size: 16),
                      onPressed: () => Clipboard.setData(ClipboardData(text: '$cmd')),
                    ),
                  ]),
                ),
            ]),
          ),
          coworkCard(
            context,
            title: context.tr('Worker settings'),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              coworkField(context,
                  label: context.tr('Verify command'),
                  help: context.tr('Must exit 0 before a card may close, e.g. cargo test or npm test. Never read from card text. Without it, and without a worktree diff to review, a finished card waits for a person.'),
                  child: TextField(key: const Key('cc-verify'), controller: _verify, decoration: const InputDecoration(hintText: 'cargo test', isDense: true))),
              coworkField(context,
                  label: context.tr('Permission mode'),
                  child: DropdownButton<String>(
                    value: _mode,
                    items: [for (final m in _modes) DropdownMenuItem(value: m, child: Text(m))],
                    onChanged: (v) => setState(() => _mode = v ?? _mode),
                  )),
              coworkField(context,
                  label: context.tr('Allowed tools'),
                  help: context.tr('SenClaw MCP servers are added automatically.'),
                  child: TextField(controller: _tools, decoration: const InputDecoration(isDense: true))),
              Wrap(spacing: AppTokens.s16, children: [
                SizedBox(
                    width: 140,
                    child: coworkField(context,
                        label: context.tr('Max turns'),
                        child: TextField(controller: _maxTurns, keyboardType: TextInputType.number, decoration: const InputDecoration(isDense: true)))),
                SizedBox(
                    width: 140,
                    child: coworkField(context,
                        label: context.tr('Fix rounds'),
                        child: TextField(controller: _fixRounds, keyboardType: TextInputType.number, decoration: const InputDecoration(isDense: true)))),
                SizedBox(
                    width: 220,
                    child: coworkField(context,
                        label: context.tr('Model'),
                        help: context.tr('Empty = your Claude Code default.'),
                        child: TextField(controller: _model, decoration: const InputDecoration(isDense: true)))),
                SizedBox(
                    width: 220,
                    child: coworkField(context,
                        label: context.tr('Binary'),
                        child: TextField(controller: _binary, decoration: const InputDecoration(isDense: true)))),
              ]),
              coworkField(context,
                  label: context.tr('Chat for SenClaw tools'),
                  help: context.tr('Chat id (jid) whose schedule, memory and calendar tools Claude Code uses. Empty = the first chat.'),
                  child: TextField(controller: _chat, decoration: const InputDecoration(isDense: true))),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(context.tr('Review the diff before closing'), style: const TextStyle(fontSize: 13)),
                value: _review,
                onChanged: (v) => setState(() => _review = v),
              ),
              FilledButton(
                key: const Key('cc-save'),
                onPressed: _saving ? null : _save,
                child: Text(context.tr('Save')),
              ),
            ]),
          ),
          coworkCard(
            context,
            title: context.tr('Runs'),
            child: _runs.isEmpty
                ? Text(context.tr('No Claude Code runs yet'), style: TextStyle(color: c.textMuted))
                : Column(children: [for (final r in _runs) _runRow(r)]),
          ),
        ],
      ],
    );
  }

  Widget _runRow(Map<String, dynamic> r) {
    final c = context.colors;
    final phase = '${r['phase'] ?? ''}';
    final color = switch (phase) {
      'done' => AppTokens.success,
      'blocked' => AppTokens.warning,
      'failed' => AppTokens.danger,
      _ => c.accent,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTokens.s6),
      child: Row(children: [
        SizedBox(width: 56, child: Text('#${r['itemId']}', style: TextStyle(color: c.textPrimary))),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: AppTokens.s6, vertical: AppTokens.s2),
          decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(AppTokens.rSm)),
          child: Text(phase, style: TextStyle(color: color, fontSize: 12)),
        ),
        const SizedBox(width: AppTokens.s8),
        Expanded(
          child: Text('${r['lastActivity'] ?? ''}',
              maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: c.textMuted, fontSize: 12)),
        ),
        Text('\$${((r['costUsd'] as num?) ?? 0).toStringAsFixed(2)}', style: TextStyle(color: c.textMuted, fontSize: 12)),
      ]),
    );
  }
}
