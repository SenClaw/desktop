import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/transport/connection.dart';

/// The generating pipelines the new-job dialog offers
/// (`../senclaw/docs/datagen.md`). `import` has its own dialog.
const datagenPipelines = <String>[
  'expand_seeds',
  'doc_qa',
  'reasoning_traces',
  'executable_qa',
  'export_logs',
];

/// The record shapes an import normalises to, and each one's fields,
/// required first — the daemon's `mapping::Kind::fields`.
const datagenKindFields = <String, List<(String, bool)>>{
  'labeled_text': [('text', true), ('label', false)],
  'qa_context': [('question', true), ('answer', true), ('context', true)],
  'problem_answer': [('problem', true), ('answer', false)],
  'chat': [('user', true), ('assistant', true), ('system', false)],
};

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
    this.attempts = 0,
    this.model,
    this.note,
    this.error,
    this.startedAt,
    this.provenance,
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
  final int attempts;

  /// `import` only: where the records came from and under what license.
  final Map<String, dynamic>? provenance;

  bool get running => state == 'running';

  Map<String, dynamic>? get _source => provenance?['source'] as Map<String, dynamic>?;

  /// The catalog entry an import came from.
  String? get catalogId => _source?['catalog'] as String?;

  String? get license => provenance?['license'] as String?;

  String? get kind => provenance?['kind'] as String?;

  /// "massive-vi", "openai/gsm8k · main · test", a URL's host, a file name.
  String? get sourceLabel {
    final s = _source;
    if (s == null) return null;
    if (s['catalog'] is String) return s['catalog'] as String;
    switch (s['type']) {
      case 'hf':
        return [s['dataset'], s['config'], s['split']].whereType<String>().join(' · ');
      case 'url':
        return Uri.tryParse('${s['url'] ?? ''}')?.host ?? 'url';
      default:
        return (s['name'] ?? s['type']) as String?;
    }
  }

  /// Can feed `expand_seeds` (labelled text, or a run of it).
  bool get feedsSeeds => kind == 'labeled_text' || pipeline == 'expand_seeds';

  /// Can feed `reasoning_traces` (problems, or a run of them).
  bool get feedsProblems =>
      kind == 'problem_answer' || pipeline == 'reasoning_traces' || pipeline == 'executable_qa';

  /// Progress as 0–1. An import's target is a ceiling, not a goal: its
  /// progress is the rows read out of the rows its source has.
  double get progress {
    if (pipeline != 'import') return target > 0 ? (accepted / target).clamp(0, 1).toDouble() : 0;
    final rows = provenance?['sourceRows'];
    final of = rows is num && rows > 0 ? (rows.toInt() < target ? rows.toInt() : target) : target;
    if (!running) return 1;
    return of > 0 ? (attempts / of).clamp(0, 1).toDouble() : 0;
  }

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
      attempts: n(j['attempts']),
      model: j['model'] as String?,
      note: j['note'] as String?,
      error: j['error'] as String?,
      startedAt: j['startedAt'] is num ? (j['startedAt'] as num).toInt() : null,
      provenance: j['provenance'] is Map ? Map<String, dynamic>.from(j['provenance'] as Map) : null,
    );
  }
}

/// One entry of `GET /api/datagen/catalog`: a dataset people wrote, ready to
/// install as an `import` job.
class DatagenCatalogEntry {
  const DatagenCatalogEntry({
    required this.id,
    required this.title,
    required this.description,
    required this.kind,
    required this.lang,
    required this.rows,
    required this.license,
    required this.attribution,
    required this.flags,
    required this.needsConsent,
    required this.bundled,
    required this.installed,
    this.homepage,
    this.notice,
    this.dataset,
    this.kit,
    this.fromUrl = false,
  });

  final String id;
  final String title;
  final String description;
  final String kind;
  final String lang;
  final int rows;
  final String license;
  final String attribution;
  final Set<String> flags;
  final bool needsConsent;
  final bool bundled;
  final bool installed;
  final String? homepage;
  final String? notice;

  /// The dataset an install wrote, when installed.
  final String? dataset;

  /// The Zen Kit that registered this entry; `null` for SenClaw's own.
  final String? kit;

  /// Downloads a file from a URL rather than a Hugging Face split.
  final bool fromUrl;

  factory DatagenCatalogEntry.fromJson(Map<String, dynamic> j) => DatagenCatalogEntry(
        id: '${j['id'] ?? ''}',
        title: '${j['title'] ?? ''}',
        description: '${j['description'] ?? ''}',
        kind: '${j['kind'] ?? ''}',
        lang: '${j['lang'] ?? ''}',
        rows: j['rows'] is num ? (j['rows'] as num).toInt() : 0,
        license: '${j['license'] ?? ''}',
        attribution: '${j['attribution'] ?? ''}',
        flags: {
          for (final e in ((j['flags'] as Map?) ?? const {}).entries)
            if (e.value == true) '${e.key}',
        },
        needsConsent: j['needsConsent'] == true,
        bundled: j['bundled'] == true,
        installed: j['installed'] == true,
        homepage: j['homepage'] as String?,
        notice: j['notice'] as String?,
        dataset: j['dataset'] as String?,
        kit: j['kit'] as String?,
        fromUrl: (j['source'] as Map?)?['url'] is String,
      );
}

class DatagenOverview {
  const DatagenOverview({required this.jobs, required this.datasets, required this.root, this.catalog = const []});
  final List<DatagenJob> jobs;
  final List<DatagenJob> datasets;
  final String root;
  final List<DatagenCatalogEntry> catalog;
}

List<DatagenJob> _list(dynamic body, String key) => ((body is Map ? body[key] : null) as List? ?? const [])
    .whereType<Map>()
    .map((m) => DatagenJob.fromJson(Map<String, dynamic>.from(m)))
    .toList();

/// Jobs of this daemon run, every dataset on disk and the dataset catalog.
/// Not scoped to a chat: the per-chat scoping is for the agent's tools, not
/// for the person.
final datagenOverviewProvider = FutureProvider.autoDispose<DatagenOverview>((ref) async {
  final api = ref.watch(apiClientProvider);
  final results = await Future.wait([
    api.get('/api/datagen/jobs'),
    api.get('/api/datagen/datasets'),
    api.get('/api/datagen/catalog'),
  ]);
  return DatagenOverview(
    jobs: _list(results[0], 'jobs'),
    datasets: _list(results[1], 'datasets'),
    root: '${(results[1] as Map?)?['root'] ?? ''}',
    catalog: ((results[2] is Map ? results[2]['entries'] : null) as List? ?? const [])
        .whereType<Map>()
        .map((m) => DatagenCatalogEntry.fromJson(Map<String, dynamic>.from(m)))
        .toList(),
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

  /// A dataset picked instead of typed lines: `{dataset, perLabel?}`.
  Map<String, dynamic>? from(String key) {
    final name = '${f[key] ?? ''}'.trim();
    if (name.isEmpty) return null;
    final per = num(f['perLabel']);
    return {'dataset': name, 'perLabel': ?per};
  }

  put('name', f['name']);
  if (pipeline != 'export_logs') {
    put('language', f['language']);
    put('maxLlmCalls', num(f['maxLlmCalls']));
    put('profile', f['profile']);
  }
  switch (pipeline) {
    case 'expand_seeds':
      final seedsFrom = from('seedsFrom');
      if (seedsFrom != null) {
        body['seedsFrom'] = seedsFrom;
      } else {
        body['seeds'] = _lines(f['seeds'] as String?).map((l) {
          final (a, b) = _split(l, ' | ');
          return b == null ? a : {'label': a, 'text': b};
        }).toList();
      }
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
      final problemsFrom = from('problemsFrom');
      if (problemsFrom != null) {
        body['problemsFrom'] = problemsFrom;
      } else {
        body['problems'] = _lines(f['problems'] as String?).map((l) {
          final (p, a) = _split(l, ' || ');
          return a == null ? p : {'problem': p, 'answer': a};
        }).toList();
      }
      put('target', num(f['target']));
      put('maxIterations', num(f['maxIterations']));
      put('threshold', dec(f['threshold']));
    case 'executable_qa':
      final seedsFrom = from('seedsFrom');
      if (seedsFrom != null) {
        body['seedsFrom'] = seedsFrom;
      } else {
        body['seeds'] = _lines(f['seeds'] as String?).map((l) {
          final (q, a) = _split(l, ' || ');
          return a == null ? q : {'question': q, 'answer': a};
        }).toList();
      }
      put('target', num(f['target']));
      put('timeoutMs', num(f['timeoutMs']));
    case 'export_logs':
      body['chats'] = _lines(f['chats'] as String?);
      put('format', f['format']);
      put('maxRecords', num(f['maxRecords']));
  }
  return body;
}
