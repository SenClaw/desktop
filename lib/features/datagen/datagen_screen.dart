import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/l10n.dart';
import '../../core/transport/connection.dart';
import '../../theme/tokens.dart';
import '../../widgets/section_scaffold.dart';
import 'datagen_api.dart';
import 'datagen_job_dialog.dart';

/// Datagen — the daemon's dataset-generation jobs (`/api/datagen/*`).
///
/// Same surface as the web page: start a job for any pipeline, watch it fill,
/// cancel it, read what it wrote, delete a dataset. Polls only while a job is
/// running, so an idle screen makes no requests.
class DatagenScreen extends ConsumerStatefulWidget {
  const DatagenScreen({super.key});

  @override
  ConsumerState<DatagenScreen> createState() => _DatagenScreenState();
}

class _DatagenScreenState extends ConsumerState<DatagenScreen> {
  Timer? _poll;

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  void _syncPolling(bool anyRunning) {
    if (anyRunning && _poll == null) {
      _poll = Timer.periodic(const Duration(seconds: 3), (_) => ref.invalidate(datagenOverviewProvider));
    } else if (!anyRunning && _poll != null) {
      _poll!.cancel();
      _poll = null;
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _cancel(DatagenJob j) async {
    try {
      await ref.read(apiClientProvider).post('/api/datagen/jobs/${Uri.encodeComponent(j.jobId)}/cancel');
      ref.invalidate(datagenOverviewProvider);
    } catch (e) {
      _toast('$e');
    }
  }

  Future<void> _delete(DatagenJob d) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('Delete this dataset?')),
        content: Text(d.name),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.tr('Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ctx.tr('Delete'))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(apiClientProvider).delete('/api/datagen/datasets/${Uri.encodeComponent(d.name)}');
      ref.invalidate(datagenOverviewProvider);
    } catch (e) {
      _toast('$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final overview = ref.watch(datagenOverviewProvider);
    final running = overview.valueOrNull?.jobs.any((j) => j.running) ?? false;
    // Start or stop the poll after this frame, never during build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncPolling(running);
    });

    return SectionScaffold(
      title: context.tr('Datagen'),
      subtitle: context.tr('Datasets built in the background'),
      actions: [
        IconButton(
          tooltip: context.tr('Refresh'),
          icon: const Icon(Icons.refresh, size: 18),
          onPressed: () => ref.invalidate(datagenOverviewProvider),
        ),
        const SizedBox(width: AppTokens.s8),
        FilledButton.icon(
          icon: const Icon(Icons.add, size: 16),
          label: Text(context.tr('New job')),
          onPressed: () async {
            if (await showDatagenJobDialog(context) == true) ref.invalidate(datagenOverviewProvider);
          },
        ),
      ],
      body: overview.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (o) => ListView(
          padding: const EdgeInsets.all(AppTokens.s16),
          children: [
            if (o.root.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: AppTokens.s12),
                child: SelectableText(o.root, style: TextStyle(fontSize: 12, color: context.colors.textMuted)),
              ),
            if (o.jobs.isNotEmpty) ...[
              _Heading(context.tr('Jobs in this daemon run')),
              ...o.jobs.map((j) => _JobRow(
                    job: j,
                    trailing: j.running
                        ? IconButton(
                            tooltip: context.tr('Cancel'),
                            icon: const Icon(Icons.stop_circle_outlined, size: 18),
                            onPressed: () => _cancel(j),
                          )
                        : null,
                  )),
              const SizedBox(height: AppTokens.s16),
            ],
            _Heading(context.tr('Datasets')),
            if (o.datasets.isEmpty)
              Padding(
                padding: const EdgeInsets.all(AppTokens.s24),
                child: Center(child: Text(context.tr('No datasets yet'))),
              )
            else
              ...o.datasets.map((d) => _JobRow(
                    job: d,
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(
                        tooltip: context.tr('View records'),
                        icon: const Icon(Icons.visibility_outlined, size: 18),
                        onPressed: () => showDialog<void>(context: context, builder: (_) => _RecordsDialog(name: d.name)),
                      ),
                      IconButton(
                        tooltip: context.tr('Delete'),
                        icon: const Icon(Icons.delete_outline, size: 18),
                        onPressed: () => _delete(d),
                      ),
                    ]),
                  )),
          ],
        ),
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: AppTokens.s8),
        child: Text(text, style: Theme.of(context).textTheme.titleMedium),
      );
}

/// Name, pipeline, state, progress and the rejection reasons of one run.
class _JobRow extends StatelessWidget {
  const _JobRow({required this.job, this.trailing});
  final DatagenJob job;
  final Widget? trailing;

  static const _stateColor = {
    'running': Colors.blue,
    'done': Colors.green,
    'failed': Colors.red,
    'cancelled': Colors.grey,
    'interrupted': Colors.orange,
  };

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final j = job;
    final color = _stateColor[j.state] ?? Colors.grey;
    final detail = j.error ?? j.note;
    return Container(
      margin: const EdgeInsets.only(bottom: AppTokens.s8),
      padding: const EdgeInsets.all(AppTokens.s12),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(spacing: AppTokens.s8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  Text(j.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                  _Chip(context.tr(j.pipeline), c.textSecondary),
                  _Chip(context.tr(j.state), color),
                ]),
                const SizedBox(height: AppTokens.s8),
                Row(children: [
                  SizedBox(
                    width: 180,
                    child: LinearProgressIndicator(
                      value: j.target > 0 ? (j.accepted / j.target).clamp(0, 1).toDouble() : 0,
                      color: color,
                    ),
                  ),
                  const SizedBox(width: AppTokens.s8),
                  Text('${j.accepted}/${j.target}', style: TextStyle(fontSize: 12, color: c.textSecondary)),
                  if (j.maxLlmCalls > 0) ...[
                    const SizedBox(width: AppTokens.s12),
                    Text(
                      context.trArgs('LLM calls: {n}/{max}', {'n': j.llmCalls, 'max': j.maxLlmCalls}),
                      style: TextStyle(fontSize: 12, color: c.textMuted),
                    ),
                  ],
                ]),
                if (j.rejectedText.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: AppTokens.s4),
                    child: Text(
                      context.trArgs('Rejected: {r}', {'r': j.rejectedText}),
                      style: TextStyle(fontSize: 12, color: c.textMuted),
                    ),
                  ),
                if (detail != null && detail.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: AppTokens.s4),
                    child: Text(detail,
                        style: TextStyle(fontSize: 12, color: j.error != null ? Colors.red : c.textSecondary)),
                  ),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.label, this.color);
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(label, style: TextStyle(fontSize: 11, color: color)),
      );
}

/// A page of a dataset's records, ten at a time, as pretty JSON.
class _RecordsDialog extends ConsumerStatefulWidget {
  const _RecordsDialog({required this.name});
  final String name;

  @override
  ConsumerState<_RecordsDialog> createState() => _RecordsDialogState();
}

class _RecordsDialogState extends ConsumerState<_RecordsDialog> {
  static const _pageSize = 10;
  int _offset = 0;
  int _total = 0;
  List<dynamic> _records = const [];
  String? _error;
  bool _loading = true;
  // Pages can come back out of order; only the latest request lands.
  int _req = 0;

  @override
  void initState() {
    super.initState();
    _load(0);
  }

  Future<void> _load(int offset) async {
    final req = ++_req;
    setState(() => _loading = true);
    try {
      final body = await ref.read(apiClientProvider).get(
        '/api/datagen/datasets/${Uri.encodeComponent(widget.name)}/records',
        query: {'offset': offset, 'limit': _pageSize},
      );
      if (!mounted || req != _req) return;
      setState(() {
        _offset = offset;
        _records = (body is Map ? body['records'] as List? : null) ?? const [];
        _total = body is Map && body['total'] is num ? (body['total'] as num).toInt() : 0;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || req != _req) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    const pretty = JsonEncoder.withIndent('  ');
    return AlertDialog(
      title: Text(widget.name),
      content: SizedBox(
        width: 720,
        height: 520,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Text(_error!))
                : _records.isEmpty
                    ? Center(child: Text(context.tr('No records')))
                    : ListView.separated(
                        itemCount: _records.length,
                        separatorBuilder: (_, _) => const SizedBox(height: AppTokens.s8),
                        itemBuilder: (_, i) => Container(
                          padding: const EdgeInsets.all(AppTokens.s8),
                          decoration: BoxDecoration(color: c.surfaceAlt, borderRadius: BorderRadius.circular(6)),
                          child: SelectableText(pretty.convert(_records[i]),
                              style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                        ),
                      ),
      ),
      actions: [
        Text(
          context.trArgs('{from}–{to} of {total}', {
            'from': _total == 0 ? 0 : _offset + 1,
            'to': _offset + _records.length,
            'total': _total,
          }),
          style: TextStyle(fontSize: 12, color: c.textMuted),
        ),
        IconButton(
          tooltip: context.tr('Previous'),
          icon: const Icon(Icons.chevron_left),
          onPressed: _offset > 0 ? () => _load((_offset - _pageSize).clamp(0, _offset)) : null,
        ),
        IconButton(
          tooltip: context.tr('Next'),
          icon: const Icon(Icons.chevron_right),
          onPressed: _offset + _records.length < _total ? () => _load(_offset + _pageSize) : null,
        ),
        TextButton(onPressed: () => Navigator.pop(context), child: Text(context.tr('Close'))),
      ],
    );
  }
}
