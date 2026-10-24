import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/i18n/l10n.dart';
import '../../core/transport/api_client.dart' show ApiException;
import '../../core/transport/connection.dart';
import '../../theme/tokens.dart';

/// A program an agent started from a chat and left running — a dev server, a
/// watcher — as the daemon's `/api/bg-tasks` reports it. Not the scheduled
/// background tasks of `BackgroundScreen`: those are agent runs on a timer, these
/// are OS processes with a pid, a port and a log.
class BgProcess {
  final String id;
  final String chatJid;
  final String description;
  final String command;
  final String cwd;

  /// `running`, `done`, `failed` or `stopped`.
  final String status;

  /// `spawned` (run_in_background), `adopted` (left by a foreground command) or
  /// `restored` (found after a daemon restart).
  final String origin;

  /// `seatbelt` / `bubblewrap` / … when the command ran in the OS sandbox.
  final String isolation;
  final int? pid;
  final int? exitCode;
  final List<int> pids;
  final List<int> ports;
  final int uptimeSecs;

  const BgProcess({
    required this.id,
    this.chatJid = '',
    this.description = '',
    this.command = '',
    this.cwd = '',
    this.status = 'running',
    this.origin = 'spawned',
    this.isolation = '',
    this.pid,
    this.exitCode,
    this.pids = const [],
    this.ports = const [],
    this.uptimeSecs = 0,
  });

  bool get running => status == 'running';

  /// What the agent said it was doing, else the command's first line.
  String get title =>
      description.isNotEmpty ? description : bgCommandLine(command, max: 70);

  factory BgProcess.fromJson(Map<String, dynamic> j) => BgProcess(
        id: '${j['id'] ?? ''}',
        chatJid: '${j['chatJid'] ?? ''}',
        description: '${j['description'] ?? ''}',
        command: '${j['command'] ?? ''}',
        cwd: '${j['cwd'] ?? ''}',
        status: '${j['status'] ?? 'running'}',
        origin: '${j['origin'] ?? 'spawned'}',
        isolation: '${j['isolation'] ?? ''}',
        pid: (j['pid'] as num?)?.toInt(),
        exitCode: (j['exitCode'] as num?)?.toInt(),
        pids: ((j['pids'] as List?) ?? const [])
            .whereType<num>()
            .map((n) => n.toInt())
            .toList(),
        ports: ((j['ports'] as List?) ?? const [])
            .whereType<num>()
            .map((n) => n.toInt())
            .toList(),
        uptimeSecs: (j['uptimeSecs'] as num?)?.toInt() ?? 0,
      );
}

/// The first non-empty line of a command, cut to [max] characters.
String bgCommandLine(String command, {int max = 80}) {
  final line = command
      .split('\n')
      .map((l) => l.trim())
      .firstWhere((l) => l.isNotEmpty, orElse: () => command.trim());
  return line.length > max ? '${line.substring(0, max - 1)}…' : line;
}

/// `1h 02m`, `3m 05s`, `42s`.
String bgUptime(int secs) {
  if (secs < 60) return '${secs}s';
  final m = secs ~/ 60;
  if (m < 60) return '${m}m ${(secs % 60).toString().padLeft(2, '0')}s';
  return '${m ~/ 60}h ${(m % 60).toString().padLeft(2, '0')}m';
}

const _poll = Duration(seconds: 3);

/// Every process the daemon knows of, finished ones included (the daemon keeps
/// the last 50 for six hours). Polled, like the watch strip: the chat socket
/// carries no task events. A failed read keeps the last list, so a blip does not
/// make a running server look gone — and an older daemon without the route just
/// shows nothing.
final bgProcessesProvider = StreamProvider.autoDispose<List<BgProcess>>((ref) {
  final api = ref.watch(apiClientProvider);
  final out = StreamController<List<BgProcess>>();
  Timer? timer;

  Future<void> load() async {
    try {
      final r = await api.get('/api/bg-tasks', query: {'includeFinished': 'true'});
      final list = (r is Map ? r['tasks'] : null) as List?;
      final tasks = (list ?? const [])
          .whereType<Map>()
          .map((m) => BgProcess.fromJson(m.cast<String, dynamic>()))
          .toList();
      if (!out.isClosed) out.add(tasks);
    } on ApiException catch (e) {
      // A daemon that predates the route has nothing to poll for.
      if (e.status == 404) timer?.cancel();
    } catch (_) {
      // Keep the last list.
    }
  }

  timer = Timer.periodic(_poll, (_) => load());
  load();
  ref.onDispose(() {
    timer?.cancel();
    out.close();
  });
  return out.stream;
});

/// How many processes are running now — the badge on the Background rail item.
final bgRunningCountProvider = Provider.autoDispose<int>((ref) {
  final all = ref.watch(bgProcessesProvider).valueOrNull ?? const <BgProcess>[];
  return all.where((p) => p.running).length;
});

Future<void> _stop(WidgetRef ref, BuildContext context, BgProcess p) async {
  try {
    await ref.read(apiClientProvider).post('/api/bg-tasks/${p.id}/stop');
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }
  ref.invalidate(bgProcessesProvider);
}

/// The log of one process, re-read while it runs.
class _BgLog extends ConsumerStatefulWidget {
  const _BgLog({required this.process});
  final BgProcess process;

  @override
  ConsumerState<_BgLog> createState() => _BgLogState();
}

class _BgLogState extends ConsumerState<_BgLog> {
  String? _text;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _read();
    _timer = Timer.periodic(_poll, (_) {
      if (widget.process.running) _read();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _read() async {
    try {
      final r = await ref
          .read(apiClientProvider)
          .get('/api/bg-tasks/${widget.process.id}', query: {'tail': '8000'});
      String out = '';
      if (r is Map) {
        final task = r['task'];
        if (task is Map) out = '${task['output'] ?? ''}';
      }
      if (mounted) setState(() => _text = out);
    } catch (_) {
      // The next poll will try again.
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = _text;
    return Container(
      margin: const EdgeInsets.only(top: AppTokens.s6),
      padding: const EdgeInsets.symmetric(
          horizontal: AppTokens.s8, vertical: AppTokens.s6),
      constraints: const BoxConstraints(maxHeight: 200),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(AppTokens.rSm),
      ),
      child: SingleChildScrollView(
        child: SelectableText(
          text == null
              ? '…'
              : text.isEmpty
                  ? context.tr(
                      'Nothing printed yet. If the command sent its output to a file, it is not shown here.')
                  : text,
          style: TextStyle(
            color: c.textSecondary,
            fontSize: 11,
            height: 1.45,
            fontFamily: AppTokens.fontMono,
          ),
        ),
      ),
    );
  }
}

/// One process: what it is, where it listens, how long it has run, and the buttons.
class BgProcessRow extends ConsumerStatefulWidget {
  const BgProcessRow({super.key, required this.process, this.showChat = false});
  final BgProcess process;
  final bool showChat;

  @override
  ConsumerState<BgProcessRow> createState() => _BgProcessRowState();
}

class _BgProcessRowState extends ConsumerState<BgProcessRow> {
  bool _open = false;
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = widget.process;
    final detail = [
      if (p.description.isNotEmpty) bgCommandLine(p.command, max: 60),
      if (p.running)
        bgUptime(p.uptimeSecs)
      else
        '${context.tr(_statusLabel(p.status))}${p.exitCode != null ? ' (${p.exitCode})' : ''}',
      if (p.pids.length > 1) '${p.pids.length} pids',
      if (p.pid != null) 'pid ${p.pid}',
    ].join(' · ');

    return Container(
      margin: const EdgeInsets.only(top: AppTokens.s6),
      padding: const EdgeInsets.symmetric(
          horizontal: AppTokens.s8, vertical: AppTokens.s6),
      decoration: BoxDecoration(
        color: c.surfaceAlt,
        borderRadius: BorderRadius.circular(AppTokens.rSm),
        border: Border.all(color: c.border),
      ),
      child: Opacity(
        opacity: p.running ? 1 : 0.75,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.terminal,
                    size: 14, color: p.running ? c.accent : c.textMuted),
                const SizedBox(width: AppTokens.s8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: c.textPrimary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600),
                      ),
                      Text(
                        detail,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: c.textMuted,
                            fontSize: 11,
                            fontFamily: AppTokens.fontMono),
                      ),
                      if (widget.showChat && p.chatJid.isNotEmpty)
                        InkWell(
                          onTap: () => context.go('/chat'),
                          child: Text(
                            p.chatJid,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: c.accent, fontSize: 11),
                          ),
                        ),
                    ],
                  ),
                ),
                if (p.isolation.isNotEmpty)
                  Tooltip(
                    message: context.trArgs(
                        'Runs inside the OS sandbox ({name})',
                        {'name': p.isolation}),
                    child: Icon(Icons.lock_outline,
                        size: 13, color: c.textMuted),
                  ),
                if (p.origin == 'restored')
                  Padding(
                    padding: const EdgeInsets.only(left: AppTokens.s6),
                    child: Tooltip(
                      message: context.tr(
                          'Found after the daemon restarted; its output was not kept.'),
                      child: Text(context.tr('Restored'),
                          style: TextStyle(color: c.textMuted, fontSize: 11)),
                    ),
                  ),
                if (p.running)
                  for (final port in p.ports)
                    Padding(
                      padding: const EdgeInsets.only(left: AppTokens.s6),
                      child: Tooltip(
                        message: context.trArgs(
                            'Open port {port} in a new tab', {'port': port}),
                        child: ActionChip(
                          label: Text(':$port',
                              style: TextStyle(
                                  color: c.accent,
                                  fontSize: 11,
                                  fontFamily: AppTokens.fontMono)),
                          visualDensity: VisualDensity.compact,
                          onPressed: () => launchUrl(
                              Uri.parse('http://127.0.0.1:$port/'),
                              mode: LaunchMode.externalApplication),
                        ),
                      ),
                    ),
                TextButton(
                  onPressed: () => setState(() => _open = !_open),
                  style: _smallButton(),
                  child: Text(context.tr('Log'),
                      style: const TextStyle(fontSize: 12)),
                ),
                if (p.running)
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () async {
                            setState(() => _busy = true);
                            await _stop(ref, context, p);
                            if (mounted) setState(() => _busy = false);
                          },
                    style: _smallButton(color: AppTokens.danger),
                    child: Text(context.tr('Stop'),
                        style: const TextStyle(fontSize: 12)),
                  )
                else
                  IconButton(
                    tooltip: context.tr('Remove from the list'),
                    icon: const Icon(Icons.delete_outline, size: 16),
                    visualDensity: VisualDensity.compact,
                    onPressed: () async {
                      try {
                        await ref
                            .read(apiClientProvider)
                            .delete('/api/bg-tasks/${p.id}');
                      } catch (_) {}
                      ref.invalidate(bgProcessesProvider);
                    },
                  ),
              ],
            ),
            if (_open) _BgLog(process: p),
          ],
        ),
      ),
    );
  }

  ButtonStyle _smallButton({Color? color}) => TextButton.styleFrom(
        foregroundColor: color,
        padding: const EdgeInsets.symmetric(horizontal: AppTokens.s8),
        minimumSize: const Size(0, 28),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      );
}

String _statusLabel(String status) => switch (status) {
      'running' => 'Running',
      'done' => 'Done',
      'failed' => 'Failed',
      _ => 'Stopped',
    };

/// What this chat's agent left running, above the composer.
///
/// A dev server started from a chat used to outlive the turn with nothing to
/// show it and nothing to end it. Also says when *other* chats have processes
/// running: the one you forgot is rarely in the chat that is open.
class BgProcessStrip extends ConsumerWidget {
  const BgProcessStrip({super.key, required this.jid});
  final String jid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = (ref.watch(bgProcessesProvider).valueOrNull ?? const <BgProcess>[])
        .where((p) => p.running)
        .toList();
    final mine = all.where((p) => p.chatJid == jid).toList();
    final others = all.length - mine.length;
    if (all.isEmpty) return const SizedBox.shrink();
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppTokens.s16, 0, AppTokens.s16, AppTokens.s6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final p in mine) BgProcessRow(key: ValueKey(p.id), process: p),
          if (others > 0)
            Padding(
              padding: const EdgeInsets.only(top: AppTokens.s6),
              child: Row(
                children: [
                  Text(
                    context.trArgs(
                        '{n} more running in other chats', {'n': others}),
                    style: TextStyle(color: c.textMuted, fontSize: 11),
                  ),
                  const SizedBox(width: AppTokens.s6),
                  InkWell(
                    onTap: () => context.go('/background'),
                    child: Text(context.tr('Manage'),
                        style: TextStyle(color: c.accent, fontSize: 11)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Every process of every chat — the Processes card of the Background screen.
class BgProcessesPanel extends ConsumerStatefulWidget {
  const BgProcessesPanel({super.key});

  @override
  ConsumerState<BgProcessesPanel> createState() => _BgProcessesPanelState();
}

class _BgProcessesPanelState extends ConsumerState<BgProcessesPanel> {
  bool _finished = false;

  Future<void> _stopAll() async {
    try {
      await ref.read(apiClientProvider).post('/api/bg-tasks/stop-all');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
    ref.invalidate(bgProcessesProvider);
  }

  Future<void> _clearFinished() async {
    try {
      await ref.read(apiClientProvider).post('/api/bg-tasks/clear-finished');
    } catch (_) {}
    ref.invalidate(bgProcessesProvider);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final all = ref.watch(bgProcessesProvider).valueOrNull ?? const <BgProcess>[];
    final running = all.where((p) => p.running).toList();
    final shown = _finished ? all : running;
    return Container(
      margin: const EdgeInsets.only(bottom: AppTokens.s12),
      padding: const EdgeInsets.all(AppTokens.s12),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(AppTokens.rMd),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  context.trArgs('Processes ({n} running)', {'n': running.length}),
                  style: TextStyle(
                      color: c.textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
              Text(context.tr('Show finished'),
                  style: TextStyle(color: c.textMuted, fontSize: 11)),
              Switch(
                value: _finished,
                onChanged: (v) => setState(() => _finished = v),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              if (_finished && all.any((p) => !p.running))
                TextButton(
                    onPressed: _clearFinished,
                    child: Text(context.tr('Clear finished'))),
              if (running.length > 1)
                TextButton(
                  onPressed: _stopAll,
                  style: TextButton.styleFrom(foregroundColor: AppTokens.danger),
                  child: Text(context.tr('Stop all')),
                ),
            ],
          ),
          Text(
            context.tr(
                'Servers and other programs an agent started and left running on this machine.'),
            style: TextStyle(color: c.textMuted, fontSize: 11),
          ),
          if (shown.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: AppTokens.s8),
              child: Text(context.tr('Nothing is running in the background'),
                  style: TextStyle(color: c.textSecondary, fontSize: 12)),
            )
          else
            for (final p in shown)
              BgProcessRow(key: ValueKey(p.id), process: p, showChat: true),
        ],
      ),
    );
  }
}
