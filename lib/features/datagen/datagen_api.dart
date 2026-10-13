import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/transport/connection.dart';

/// The five pipelines the daemon runs (`../senclaw/docs/datagen.md`).
const datagenPipelines = <String>[
  'expand_seeds',
  'doc_qa',
  'reasoning_traces',
  'executable_qa',
  'export_logs',
];

/// One job or dataset manifest — the daemon serves both in this shape.
class DatagenJob {
  const DatagenJob({
    required this.jobId,
    required this.name,
    required this.pipeline,
    required this.state,
    required this.target,
    required this.accepted,
    required this.llmCalls,
    required this.maxLlmCalls,
    required this.rejected,
    this.model,
    this.note,
    this.error,
    this.startedAt,
  });

  final String jobId;
  final String name;
  final String pipeline;
  final String state;
  final int target;
  final int accepted;
  final int llmCalls;
  final int maxLlmCalls;
  final Map<String, int> rejected;
  final String? model;
  final String? note;
  final String? error;
  final int? startedAt;

  bool get running => state == 'running';

  /// "3 duplicate, 1 too_long" — the reasons a run produced fewer records.
  String get rejectedText => rejected.entries.map((e) => '${e.value} ${e.key}').join(', ');

  factory DatagenJob.fromJson(Map<String, dynamic> j) {
    int n(Object? v) => v is num ? v.toInt() : 0;
    final rej = <String, int>{};
    (j['rejected'] as Map?)?.forEach((k, v) => rej['$k'] = n(v));
    return DatagenJob(
      jobId: '${j['jobId'] ?? ''}',
      name: '${j['name'] ?? ''}',
      pipeline: '${j['pipeline'] ?? ''}',
      state: '${j['state'] ?? ''}',
      target: n(j['target']),
      accepted: n(j['accepted']),
      llmCalls: n(j['llmCalls']),
      maxLlmCalls: n(j['maxLlmCalls']),
      rejected: rej,
      model: j['model'] as String?,
      note: j['note'] as String?,
      error: j['error'] as String?,
      startedAt: j['startedAt'] is num ? (j['startedAt'] as num).toInt() : null,
    );
  }
}

class DatagenOverview {
  const DatagenOverview({required this.jobs, required this.datasets, required this.root});
  final List<DatagenJob> jobs;
  final List<DatagenJob> datasets;
  final String root;
}

List<DatagenJob> _list(dynamic body, String key) => ((body is Map ? body[key] : null) as List? ?? const [])
    .whereType<Map>()
    .map((m) => DatagenJob.fromJson(Map<String, dynamic>.from(m)))
    .toList();

/// Jobs of this daemon run plus every dataset on disk. Not scoped to a chat:
/// the per-chat scoping is for the agent's tools, not for the person.
final datagenOverviewProvider = FutureProvider.autoDispose<DatagenOverview>((ref) async {
  final api = ref.watch(apiClientProvider);
  final results = await Future.wait([api.get('/api/datagen/jobs'), api.get('/api/datagen/datasets')]);
  return DatagenOverview(
    jobs: _list(results[0], 'jobs'),
    datasets: _list(results[1], 'datasets'),
    root: '${(results[1] as Map?)?['root'] ?? ''}',
  );
});

/// Non-empty trimmed lines.
List<String> _lines(String? s) =>
    (s ?? '').split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();

/// `left<sep>right` → (left, right); no separator → (line, null).
(String, String?) _split(String line, String sep) {
  final i = line.indexOf(sep);
  return i < 0 ? (line, null) : (line.substring(0, i).trim(), line.substring(i + sep.length).trim());
}

/// Form text → the daemon's camelCase job body. Same line formats as the web
/// page, so a seed list pasted into either client means the same thing:
/// `label | request`, `problem || answer`, documents split by a `---` line.
Map<String, dynamic> buildDatagenBody(String pipeline, Map<String, Object?> f) {
  final body = <String, dynamic>{'pipeline': pipeline};
  void put(String k, Object? v) {
    if (v == null) return;
    if (v is String && v.trim().isEmpty) return;
    body[k] = v is String ? v.trim() : v;
  }

  int? num(Object? v) => v is int ? v : int.tryParse('${v ?? ''}'.trim());
  double? dec(Object? v) => v is double ? v : double.tryParse('${v ?? ''}'.trim());

  put('name', f['name']);
  if (pipeline != 'export_logs') {
    put('language', f['language']);
    put('maxLlmCalls', num(f['maxLlmCalls']));
    put('profile', f['profile']);
  }
  switch (pipeline) {
    case 'expand_seeds':
      body['seeds'] = _lines(f['seeds'] as String?).map((l) {
        final (a, b) = _split(l, ' | ');
        return b == null ? a : {'label': a, 'text': b};
      }).toList();
      final labels = <String, String>{};
      for (final l in _lines(f['labels'] as String?)) {
        final (k, d) = _split(l, ':');
        if (d != null && d.isNotEmpty) labels[k] = d;
      }
      if (labels.isNotEmpty) body['labels'] = labels;
      put('mode', f['mode']);
      put('target', num(f['target']));
      final check = f['checkLabel'];
      if (check == 'on' || check == 'off') body['checkLabel'] = check == 'on';
    case 'doc_qa':
      body['texts'] = '${f['texts'] ?? ''}'
          .split(RegExp(r'\n-{3,}\n'))
          .map((t) => t.trim())
          .where((t) => t.isNotEmpty)
          .toList();
      body['paths'] = _lines(f['paths'] as String?);
      put('target', num(f['target']));
      put('perPassage', num(f['perPassage']));
      put('multiHop', f['multiHop']);
      put('verify', f['verify']);
    case 'reasoning_traces':
      body['problems'] = _lines(f['problems'] as String?).map((l) {
        final (p, a) = _split(l, ' || ');
        return a == null ? p : {'problem': p, 'answer': a};
      }).toList();
      put('target', num(f['target']));
      put('maxIterations', num(f['maxIterations']));
      put('threshold', dec(f['threshold']));
    case 'executable_qa':
      body['seeds'] = _lines(f['seeds'] as String?).map((l) {
        final (q, a) = _split(l, ' || ');
        return a == null ? q : {'question': q, 'answer': a};
      }).toList();
      put('target', num(f['target']));
      put('timeoutMs', num(f['timeoutMs']));
    case 'export_logs':
      body['chats'] = _lines(f['chats'] as String?);
      put('format', f['format']);
      put('maxRecords', num(f['maxRecords']));
  }
  return body;
}
