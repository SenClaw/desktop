import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/l10n.dart';
import '../../core/transport/api_client.dart' show ApiException;
import '../../core/transport/connection.dart';
import '../../theme/tokens.dart';
import 'settings_screen.dart' show SettingsBody;

// `/api/lsp/status` shapes. Records, not classes — these are read-only
// snapshots with no behavior of their own, so a parse function beats four
// boilerplate constructors.
typedef LspServer = ({
  String workspace,
  String language,
  String command,
  bool alive,
  int idleSecs
});
typedef LspDisabled = ({String workspace, String language, String reason});
typedef LspAvailable = ({String language, String? command, bool installed});
typedef LspStatus = ({
  bool enabled,
  int timeoutMs,
  String settingsPath,
  List<LspServer> servers,
  List<LspDisabled> disabled,
  List<LspAvailable> available
});

List<T> _list<T>(dynamic raw, T Function(Map<String, dynamic>) parse) =>
    ((raw as List?) ?? const [])
        .whereType<Map>()
        .map((m) => parse(m.cast<String, dynamic>()))
        .toList();

LspStatus _parseStatus(Map<String, dynamic> j) => (
      enabled: j['enabled'] == true,
      timeoutMs: (j['timeoutMs'] as num?)?.toInt() ?? 5000,
      settingsPath: '${j['settingsPath'] ?? ''}',
      servers: _list(j['servers'], (m) => (
            workspace: '${m['workspace'] ?? ''}',
            language: '${m['language'] ?? ''}',
            command: '${m['command'] ?? ''}',
            alive: m['alive'] == true,
            idleSecs: (m['idleSecs'] as num?)?.toInt() ?? 0,
          )),
      disabled: _list(j['disabled'], (m) => (
            workspace: '${m['workspace'] ?? ''}',
            language: '${m['language'] ?? ''}',
            reason: '${m['reason'] ?? ''}',
          )),
      available: _list(j['available'], (m) => (
            language: '${m['language'] ?? ''}',
            command: m['command'] as String?,
            installed: m['installed'] == true,
          )),
    );

/// Editable row for a per-language `servers` override — three controllers
/// (language id, command, args-as-one-string) so the whole row disposes
/// together and TextFields keep their own cursor/selection state.
class _OverrideRow {
  final String key;
  final TextEditingController language;
  final TextEditingController command;
  final TextEditingController argsText;

  _OverrideRow(this.key,
      {String language = '', String command = '', String argsText = ''})
      : language = TextEditingController(text: language),
        command = TextEditingController(text: command),
        argsText = TextEditingController(text: argsText);

  void dispose() {
    language.dispose();
    command.dispose();
    argsText.dispose();
  }
}

// Suggested install for a language not found on this machine — the daemon
// only reports `installed: false`, it does not know the user's package
// manager, so this is a hint, never a command run on the user's behalf.
const Map<String, String> _installHint = {
  'rust': 'install rust-analyzer to enable',
  'typescript': 'install typescript-language-server to enable',
  'python': 'install pyright to enable',
  'go': 'install gopls to enable',
  'dart': 'install the Dart SDK (dart language-server) to enable',
  'c': 'install clangd to enable',
};

String _basename(String p) {
  final parts =
      p.replaceAll(RegExp(r'[\\/]+$'), '').split(RegExp(r'[\\/]'));
  return parts.isEmpty ? p : parts.last;
}

/// Language servers (LSP) — after every Edit/Write the agent gets the file's
/// real compiler/linter diagnostics from a language server already installed
/// on this machine. Nothing is downloaded here; this section only toggles the
/// feature, its timeout, and per-language command overrides.
class LspSection extends ConsumerStatefulWidget {
  const LspSection({super.key});

  @override
  ConsumerState<LspSection> createState() => _LspSectionState();
}

class _LspSectionState extends ConsumerState<LspSection> {
  LspStatus? _status;
  bool _loading = true;
  bool _saving = false;
  String? _loadError;

  bool _enabled = true;
  final _timeoutCtrl = TextEditingController(text: '5000');
  int _rowSeq = 0;
  final List<_OverrideRow> _rows = [];

  @override
  void dispose() {
    _timeoutCtrl.dispose();
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  String _nextKey() => 'row-${++_rowSeq}';

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final api = ref.read(apiClientProvider);
      final statusJson = await api.get('/api/lsp/status');
      final settingsJson = await api.get('/api/lsp/settings');
      final status = _parseStatus((statusJson as Map).cast<String, dynamic>());
      final cfg = (settingsJson as Map).cast<String, dynamic>();
      final servers =
          ((cfg['servers'] as Map?) ?? const {}).cast<String, dynamic>();
      if (!mounted) return;
      for (final r in _rows) {
        r.dispose();
      }
      _rows.clear();
      servers.forEach((lang, ov) {
        final m = (ov as Map).cast<String, dynamic>();
        final args = ((m['args'] as List?) ?? const []).map((e) => '$e').join(' ');
        _rows.add(_OverrideRow(_nextKey(),
            language: lang, command: '${m['command'] ?? ''}', argsText: args));
      });
      setState(() {
        _status = status;
        _enabled = cfg['enabled'] == true;
        _timeoutCtrl.text = '${cfg['timeout_ms'] ?? 5000}';
        _loading = false;
      });
    } catch (e) {
      final msg = e is ApiException ? e.message : '$e';
      if (!mounted) return;
      setState(() {
        _loadError = msg;
        _loading = false;
      });
    }
  }

  void _addRow() => setState(() => _rows.add(_OverrideRow(_nextKey())));

  void _removeRow(String key) => setState(() {
        final idx = _rows.indexWhere((r) => r.key == key);
        if (idx >= 0) _rows.removeAt(idx).dispose();
      });

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _save() async {
    final timeoutMs = int.tryParse(_timeoutCtrl.text.trim()) ?? -1;
    if (timeoutMs < 500 || timeoutMs > 60000) {
      _snack(context.tr('Timeout must be between 500 and 60000 ms'));
      return;
    }
    final servers = <String, dynamic>{};
    for (final row in _rows) {
      final language = row.language.text.trim();
      final command = row.command.text.trim();
      if (language.isEmpty || command.isEmpty) continue;
      final argsText = row.argsText.text.trim();
      final args = argsText.isEmpty ? <String>[] : argsText.split(RegExp(r'\s+'));
      servers[language] = {'command': command, 'args': args};
    }
    // Resolved before the await: reading `context` after one is only valid
    // while still mounted, and the widget can be disposed mid-request.
    final saved = context.tr('Language server settings saved');
    setState(() => _saving = true);
    try {
      await ref.read(apiClientProvider).put('/api/lsp/settings', body: {
        'enabled': _enabled,
        'timeout_ms': timeoutMs,
        'servers': servers,
      });
      _snack(saved);
      await _load();
    } catch (e) {
      final msg = e is ApiException ? e.message : '$e';
      _snack(msg);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SettingsBody(
      title: context.tr('Language servers (LSP)'),
      onRefresh: _load,
      children: [
        Text(
          context.tr(
              'After every Edit/Write the agent gets the file\'s real compiler/linter diagnostics from a language server already installed on this machine. Nothing is downloaded here.'),
          style: TextStyle(color: c.textMuted, fontSize: 12),
        ),
        const SizedBox(height: AppTokens.s16),
        if (_loadError != null)
          Container(
            margin: const EdgeInsets.only(bottom: AppTokens.s12),
            padding: const EdgeInsets.all(AppTokens.s12),
            decoration: BoxDecoration(
              color: AppTokens.danger.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(AppTokens.rMd),
              border: Border.all(color: AppTokens.danger.withValues(alpha: 0.3)),
            ),
            child: Text(_loadError!, style: const TextStyle(color: AppTokens.danger)),
          ),
        if (_loading && _status == null)
          const Center(child: CircularProgressIndicator())
        else ...[
          _card(c, title: context.tr('Configuration'), child: _configCard(c)),
          _card(
            c,
            title: context.tr('Available language servers'),
            child: _list$(c, _status?.available, context.tr('Nothing to report.'),
                (a) => _availableRow(c, a)),
          ),
          _card(
            c,
            title: context.tr('Running'),
            child: _list$(c, _status?.servers, context.tr('No servers running.'),
                (s) => _runningRow(c, s)),
          ),
          if ((_status?.disabled ?? const []).isNotEmpty)
            _card(
              c,
              title: context.tr('Disabled'),
              child: Column(
                  children: [for (final d in _status!.disabled) _disabledRow(c, d)]),
            ),
          _card(
            c,
            title: context.tr('Per-language overrides'),
            trailing: TextButton.icon(
              onPressed: _addRow,
              icon: const Icon(Icons.add, size: 16),
              label: Text(context.tr('Add')),
            ),
            child: _overridesCard(c),
          ),
          Row(
            children: [
              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(context.tr('Save')),
              ),
              const SizedBox(width: AppTokens.s12),
              OutlinedButton.icon(
                onPressed: _loading ? null : _load,
                icon: const Icon(Icons.refresh, size: 16),
                label: Text(context.tr('Refresh')),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _configCard(dynamic c) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Switch(value: _enabled, onChanged: (v) => setState(() => _enabled = v)),
            const SizedBox(width: AppTokens.s8),
            Text(context.tr('Enabled')),
          ]),
          const SizedBox(height: AppTokens.s8),
          Row(children: [
            SizedBox(width: 140, child: Text(context.tr('Timeout (ms)'))),
            SizedBox(
              width: 140,
              child: TextField(
                controller: _timeoutCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(isDense: true),
              ),
            ),
          ]),
          if (_status?.settingsPath.isNotEmpty == true) ...[
            const SizedBox(height: AppTokens.s8),
            Text(_status!.settingsPath,
                style: TextStyle(fontSize: 11, color: c.textMuted, fontFamily: 'monospace')),
          ],
        ],
      );

  Widget _overridesCard(dynamic c) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.tr(
                'Set a custom command/args for a language, overriding the daemon default. Args are separated by spaces.'),
            style: TextStyle(color: c.textMuted, fontSize: 12),
          ),
          const SizedBox(height: AppTokens.s8),
          if (_rows.isEmpty)
            Text(context.tr('No overrides.'), style: TextStyle(color: c.textMuted, fontSize: 12))
          else
            for (final row in _rows) _overrideRow(c, row),
        ],
      );

  /// Renders a list of rows, or an empty-state message when there are none.
  Widget _list$<T>(dynamic c, List<T>? items, String emptyText, Widget Function(T) row) =>
      (items ?? const []).isEmpty
          ? Text(emptyText, style: TextStyle(color: c.textMuted, fontSize: 12))
          : Column(children: [for (final it in items!) row(it)]);

  Widget _card(dynamic c, {required String title, required Widget child, Widget? trailing}) {
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
          Row(children: [
            Expanded(
              child: Text(title,
                  style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.w600)),
            ),
            ?trailing,
          ]),
          const SizedBox(height: AppTokens.s8),
          child,
        ],
      ),
    );
  }

  Widget _availableRow(dynamic c, LspAvailable a) => Padding(
        padding: const EdgeInsets.only(bottom: AppTokens.s8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 100, child: Text(a.language)),
            Expanded(
              child: Text(a.command ?? '—',
                  style: TextStyle(fontFamily: 'monospace', fontSize: 12, color: c.textMuted)),
            ),
            SizedBox(
              width: 220,
              child: a.installed
                  ? Row(children: [
                      const Icon(Icons.check_circle, size: 14, color: AppTokens.success),
                      const SizedBox(width: AppTokens.s6),
                      Text(context.tr('Installed')),
                    ])
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          const Icon(Icons.cancel_outlined, size: 14, color: AppTokens.danger),
                          const SizedBox(width: AppTokens.s6),
                          Text(context.tr('Not installed')),
                        ]),
                        Text(
                          context.tr(_installHint[a.language] ?? 'not installed on this machine'),
                          style: TextStyle(fontSize: 11, color: c.textMuted),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      );

  Widget _runningRow(dynamic c, LspServer s) => Padding(
        padding: const EdgeInsets.only(bottom: AppTokens.s8),
        child: Row(
          children: [
            SizedBox(width: 90, child: Text(s.language)),
            Expanded(
              child: Text(s.command,
                  style: TextStyle(fontFamily: 'monospace', fontSize: 12, color: c.textMuted)),
            ),
            SizedBox(width: 140, child: Text(_basename(s.workspace))),
            SizedBox(
              width: 70,
              child: Text(s.alive ? context.tr('alive') : context.tr('stopped'),
                  style: TextStyle(
                      color: s.alive ? AppTokens.success : c.textMuted, fontSize: 12)),
            ),
            SizedBox(width: 60, child: Text('${s.idleSecs}s')),
          ],
        ),
      );

  Widget _disabledRow(dynamic c, LspDisabled d) => Padding(
        padding: const EdgeInsets.only(bottom: AppTokens.s8),
        child: Row(
          children: [
            SizedBox(width: 90, child: Text(d.language)),
            SizedBox(width: 140, child: Text(_basename(d.workspace))),
            Expanded(child: Text(d.reason, style: TextStyle(color: c.textMuted, fontSize: 12))),
          ],
        ),
      );

  Widget _overrideRow(dynamic c, _OverrideRow row) => Padding(
        padding: const EdgeInsets.only(bottom: AppTokens.s8),
        child: Row(
          children: [
            SizedBox(
              width: 140,
              child: TextField(
                controller: row.language,
                decoration:
                    InputDecoration(isDense: true, hintText: context.tr('language (e.g. rust)')),
              ),
            ),
            const SizedBox(width: AppTokens.s8),
            SizedBox(
              width: 220,
              child: TextField(
                controller: row.command,
                decoration: InputDecoration(
                    isDense: true, hintText: context.tr('command (e.g. rust-analyzer)')),
              ),
            ),
            const SizedBox(width: AppTokens.s8),
            Expanded(
              child: TextField(
                controller: row.argsText,
                decoration:
                    InputDecoration(isDense: true, hintText: context.tr('args (space-separated)')),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 16, color: AppTokens.danger),
              onPressed: () => _removeRow(row.key),
              tooltip: context.tr('Remove'),
            ),
          ],
        ),
      );
}
