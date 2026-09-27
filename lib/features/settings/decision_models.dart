// `/api/decision/*` shapes: the Laya model store and a typed-decision answer.
// Mirrors `src/decision/laya/{store,download,runtime}.rs` and
// `src/decision/types.rs` on the daemon side.

import 'dart:convert';

/// Job states during which the row is busy and the list keeps polling.
const kActiveJobStatuses = {'queued', 'listing', 'downloading', 'verifying', 'copying'};

int _int(Object? v) => v is num ? v.toInt() : 0;
double _dbl(Object? v) => v is num ? v.toDouble() : 0;
String? _str(Object? v) => v is String && v.isNotEmpty ? v : null;

/// A download or an import of one model.
class LayaJob {
  const LayaJob({
    required this.kind,
    required this.status,
    required this.totalBytes,
    required this.doneBytes,
    required this.currentFile,
    required this.error,
  });

  /// `download` or `import`.
  final String kind;
  final String status;
  final int totalBytes;
  final int doneBytes;
  final String? currentFile;
  final String? error;

  bool get active => kActiveJobStatuses.contains(status);
  double? get progress => totalBytes > 0 ? (doneBytes / totalBytes).clamp(0.0, 1.0) : null;

  factory LayaJob.fromJson(Map<String, dynamic> j) => LayaJob(
        kind: '${j['kind'] ?? 'download'}',
        status: '${j['status'] ?? ''}',
        totalBytes: _int(j['total_bytes']),
        doneBytes: _int(j['done_bytes']),
        currentFile: _str(j['current_file']),
        error: _str(j['error']),
      );
}

/// What the daemon reports for a model whose weights are in RAM.
class LayaLoaded {
  const LayaLoaded({
    required this.kind,
    required this.loadMs,
    required this.fixedBatch,
    required this.asks,
    this.threads = 0,
    this.idleSecs = 0,
    this.onDemand = false,
  });

  final String kind;
  final int loadMs;

  /// The graph takes one row per run (ti3x-m exports) instead of a batch.
  final bool fixedBatch;
  final int asks;

  /// ONNX Runtime intra-op threads it was loaded with.
  final int threads;

  /// Seconds since the last request (or the load) — what idle unload counts.
  final int idleSecs;

  /// A request loaded it (hot-load), not a person.
  final bool onDemand;

  factory LayaLoaded.fromJson(Map<String, dynamic> j) => LayaLoaded(
        kind: '${j['kind'] ?? ''}',
        loadMs: _int(j['load_ms']),
        fixedBatch: j['batch'] == 'fixed-1',
        asks: _int(j['asks']),
        threads: _int(j['threads']),
        idleSecs: _int(j['idle_secs']),
        onDemand: j['on_demand'] == true,
      );
}

/// One row of Settings → Decision (Laya).
class LayaModel {
  const LayaModel({
    required this.id,
    required this.label,
    required this.description,
    required this.kind,
    required this.catalog,
    required this.sourceType,
    required this.repo,
    required this.revision,
    required this.sourcePath,
    required this.approxSizeMb,
    required this.sizeBytes,
    required this.installed,
    required this.path,
    required this.job,
    required this.loading,
    required this.loaded,
  });

  final String id;
  final String label;
  final String description;

  /// `english` or `multilingual` (null when unknown).
  final String? kind;
  final bool catalog;

  /// `catalog`, `huggingface` or `folder`.
  final String? sourceType;
  final String? repo;
  final String? revision;
  final String? sourcePath;
  final int? approxSizeMb;
  final int sizeBytes;
  final bool installed;
  final String path;
  final LayaJob? job;
  final bool loading;
  final LayaLoaded? loaded;

  bool get jobActive => job?.active ?? false;

  /// Something is happening that the list should keep polling for.
  bool get busy => loading || jobActive;

  factory LayaModel.fromJson(Map<String, dynamic> j) {
    final source = j['source'] is Map ? (j['source'] as Map).cast<String, dynamic>() : const <String, dynamic>{};
    return LayaModel(
      id: '${j['id'] ?? ''}',
      label: '${j['label'] ?? j['id'] ?? ''}',
      description: '${j['description'] ?? ''}',
      kind: _str(j['kind']),
      catalog: j['catalog'] == true,
      sourceType: _str(source['type']),
      repo: _str(source['repo']),
      revision: _str(source['revision']),
      sourcePath: _str(source['path']),
      approxSizeMb: j['approx_size_mb'] is num ? (j['approx_size_mb'] as num).toInt() : null,
      sizeBytes: _int(j['size_bytes']),
      installed: j['installed'] == true,
      path: '${j['path'] ?? ''}',
      job: j['job'] is Map ? LayaJob.fromJson((j['job'] as Map).cast<String, dynamic>()) : null,
      loading: j['loading'] == true,
      loaded: j['loaded'] is Map ? LayaLoaded.fromJson((j['loaded'] as Map).cast<String, dynamic>()) : null,
    );
  }
}

/// `GET /api/decision/models`.
class LayaModelList {
  const LayaModelList({
    required this.compiled,
    required this.root,
    required this.models,
    this.backend = 'local',
    this.local = const DecisionLocalSettings(),
  });

  /// The daemon was built with the `decision-laya` feature.
  final bool compiled;
  final String root;
  final List<LayaModel> models;

  /// The backend chosen in Settings (`local` or `online`).
  final String backend;

  /// Default model, hot-load and idle unload — what the rows need to say
  /// "default" and "unloads in …".
  final DecisionLocalSettings local;

  factory LayaModelList.fromJson(Map<String, dynamic> j) => LayaModelList(
        compiled: j['compiled'] == true,
        root: '${j['root'] ?? ''}',
        models: (j['models'] as List? ?? const [])
            .whereType<Map>()
            .map((m) => LayaModel.fromJson(m.cast<String, dynamic>()))
            .toList(),
        backend: j['backend'] == 'online' ? 'online' : 'local',
        local: j['local'] is Map
            ? DecisionLocalSettings.fromJson((j['local'] as Map).cast<String, dynamic>())
            : const DecisionLocalSettings(),
      );
}

/// How the local engine runs. Mirrors `LocalSettings` in
/// `src/decision/settings.rs` (camelCase on the wire).
class DecisionLocalSettings {
  const DecisionLocalSettings({
    this.defaultModel,
    this.threads,
    this.autoLoad = true,
    this.idleUnloadMinutes = 15,
  });

  /// Answers requests that name no model; null = pick by language.
  final String? defaultModel;

  /// ONNX Runtime intra-op threads; null = the core count, capped at 8.
  final int? threads;

  /// Load the model a request needs instead of refusing it (hot-load).
  final bool autoLoad;

  /// Unload a model no request has used for this long; 0 = never.
  final int idleUnloadMinutes;

  DecisionLocalSettings copyWith({
    String? Function()? defaultModel,
    int? Function()? threads,
    bool? autoLoad,
    int? idleUnloadMinutes,
  }) =>
      DecisionLocalSettings(
        defaultModel: defaultModel != null ? defaultModel() : this.defaultModel,
        threads: threads != null ? threads() : this.threads,
        autoLoad: autoLoad ?? this.autoLoad,
        idleUnloadMinutes: idleUnloadMinutes ?? this.idleUnloadMinutes,
      );

  factory DecisionLocalSettings.fromJson(Map<String, dynamic> j) => DecisionLocalSettings(
        defaultModel: _str(j['defaultModel']),
        threads: j['threads'] is num ? (j['threads'] as num).toInt() : null,
        autoLoad: j['autoLoad'] != false,
        idleUnloadMinutes: j['idleUnloadMinutes'] is num ? (j['idleUnloadMinutes'] as num).toInt() : 15,
      );

  Map<String, dynamic> toJson() => {
        if (defaultModel != null) 'defaultModel': defaultModel,
        if (threads != null) 'threads': threads,
        'autoLoad': autoLoad,
        'idleUnloadMinutes': idleUnloadMinutes,
      };
}

/// The hosted backend. Mirrors `OnlineSettings` in `src/decision/settings.rs`.
class DecisionOnlineSettings {
  const DecisionOnlineSettings({
    this.provider = 'typesafe',
    this.url = '',
    this.apiKey = '',
    this.hasApiKey = false,
    this.model = '',
    this.accountId = '',
    this.timeoutSecs = 15,
  });

  /// `typesafe`, `cloudflare` or `custom`.
  final String provider;
  final String url;

  /// Never sent back by the daemon; empty in a save means "keep the stored one".
  final String apiKey;
  final bool hasApiKey;
  final String model;
  final String accountId;
  final int timeoutSecs;

  DecisionOnlineSettings copyWith({
    String? provider,
    String? url,
    String? apiKey,
    String? model,
    String? accountId,
    int? timeoutSecs,
  }) =>
      DecisionOnlineSettings(
        provider: provider ?? this.provider,
        url: url ?? this.url,
        apiKey: apiKey ?? this.apiKey,
        hasApiKey: hasApiKey,
        model: model ?? this.model,
        accountId: accountId ?? this.accountId,
        timeoutSecs: timeoutSecs ?? this.timeoutSecs,
      );

  factory DecisionOnlineSettings.fromJson(Map<String, dynamic> j) => DecisionOnlineSettings(
        provider: '${j['provider'] ?? 'typesafe'}',
        url: '${j['url'] ?? ''}',
        apiKey: '${j['apiKey'] ?? ''}',
        hasApiKey: j['hasApiKey'] == true,
        model: '${j['model'] ?? ''}',
        accountId: '${j['accountId'] ?? ''}',
        timeoutSecs: j['timeoutSecs'] is num ? (j['timeoutSecs'] as num).toInt() : 15,
      );

  Map<String, dynamic> toJson() => {
        'provider': provider,
        'url': url,
        'apiKey': apiKey,
        'model': model,
        'accountId': accountId,
        'timeoutSecs': timeoutSecs,
      };
}

/// Backend, local engine and online settings — `decisionConfig` in config.json.
class DecisionRunSettings {
  const DecisionRunSettings({
    this.backend = 'local',
    this.local = const DecisionLocalSettings(),
    this.online = const DecisionOnlineSettings(),
  });

  /// `local` or `online`.
  final String backend;
  final DecisionLocalSettings local;
  final DecisionOnlineSettings online;

  DecisionRunSettings copyWith({String? backend, DecisionLocalSettings? local, DecisionOnlineSettings? online}) =>
      DecisionRunSettings(
        backend: backend ?? this.backend,
        local: local ?? this.local,
        online: online ?? this.online,
      );

  factory DecisionRunSettings.fromJson(Map<String, dynamic> j) => DecisionRunSettings(
        backend: j['backend'] == 'online' ? 'online' : 'local',
        local: j['local'] is Map
            ? DecisionLocalSettings.fromJson((j['local'] as Map).cast<String, dynamic>())
            : const DecisionLocalSettings(),
        online: j['online'] is Map
            ? DecisionOnlineSettings.fromJson((j['online'] as Map).cast<String, dynamic>())
            : const DecisionOnlineSettings(),
      );

  /// The body of `PUT /api/decision/settings` and `POST …/online/test`.
  Map<String, dynamic> toJson({bool clearApiKey = false}) => {
        'backend': backend,
        'local': local.toJson(),
        'online': online.toJson(),
        if (clearApiKey) 'clearApiKey': true,
      };

  // `toJson` always builds its maps in the same key order, so the encodings
  // of two equal settings are equal strings.
  @override
  bool operator ==(Object other) => other is DecisionRunSettings && jsonEncode(toJson()) == jsonEncode(other.toJson());

  @override
  int get hashCode => jsonEncode(toJson()).hashCode;
}

/// `GET /api/decision/settings`.
class DecisionSettingsView {
  const DecisionSettingsView({
    required this.compiled,
    required this.settings,
    required this.providers,
    required this.autoThreads,
    required this.maxThreads,
    required this.typesafeModel,
    required this.cloudflareModel,
  });

  final bool compiled;
  final DecisionRunSettings settings;
  final List<String> providers;

  /// What "automatic" means on this machine.
  final int autoThreads;
  final int maxThreads;
  final String typesafeModel;
  final String cloudflareModel;

  factory DecisionSettingsView.fromJson(Map<String, dynamic> j) {
    final d = j['defaults'] is Map ? (j['defaults'] as Map).cast<String, dynamic>() : const <String, dynamic>{};
    return DecisionSettingsView(
      compiled: j['compiled'] == true,
      settings: j['settings'] is Map
          ? DecisionRunSettings.fromJson((j['settings'] as Map).cast<String, dynamic>())
          : const DecisionRunSettings(),
      providers: [for (final p in (j['providers'] as List? ?? const ['typesafe', 'cloudflare', 'custom'])) '$p'],
      autoThreads: _int(d['threads']),
      maxThreads: d['maxThreads'] is num ? (d['maxThreads'] as num).toInt() : 64,
      typesafeModel: '${d['typesafeModel'] ?? 'jev-1.13.0'}',
      cloudflareModel: '${d['cloudflareModel'] ?? 'typesafe/jev'}',
    );
  }
}

/// One answer of `POST /api/decision/ask`, options in the order asked.
class DecisionAnswer {
  const DecisionAnswer({
    required this.id,
    required this.type,
    required this.choice,
    required this.score,
    required this.noul,
    required this.probabilities,
    required this.legend,
    required this.confidence,
    required this.answerConfidence,
    required this.actProbability,
    this.raw = const {},
  });

  final String id;

  /// `choice`, `score` or `noul` — or empty for a shape an online backend
  /// sent that none of the three matches (then [raw] is shown as it came).
  final String type;
  final String? choice;
  final double? score;
  final double? noul;
  final List<(String, double)> probabilities;
  final Map<String, Object?> legend;
  final double? confidence;
  final double? answerConfidence;
  final double? actProbability;
  final Map<String, dynamic> raw;

  bool get known => type == 'choice' || type == 'score' || type == 'noul';

  factory DecisionAnswer.fromJson(String id, Map<String, dynamic> j) {
    // `jsonDecode` builds insertion-ordered maps, so this is the order the
    // daemon wrote — the caller's option order.
    final probs = j['probabilities'] is Map ? (j['probabilities'] as Map).cast<String, dynamic>() : const <String, dynamic>{};
    final action = j['action'] is Map ? (j['action'] as Map).cast<String, dynamic>() : null;
    // Online backends send their own fields; infer the type when it is absent,
    // and call it unknown unless the field that type needs is really there.
    final declared = _str(j['type']) ??
        (j.containsKey('choice')
            ? 'choice'
            : j.containsKey('score')
                ? 'score'
                : j.containsKey('noul')
                    ? 'noul'
                    : '');
    final type = switch (declared) {
      'choice' when j['choice'] is String => 'choice',
      'score' when j['score'] is num => 'score',
      'noul' when j['noul'] is num => 'noul',
      _ => '',
    };
    return DecisionAnswer(
      id: id,
      type: type,
      raw: j,
      choice: _str(j['choice']),
      score: j['score'] is num ? (j['score'] as num).toDouble() : null,
      noul: j['noul'] is num ? (j['noul'] as num).toDouble() : null,
      probabilities: [for (final e in probs.entries) (e.key, _dbl(e.value))],
      legend: j['legend'] is Map ? (j['legend'] as Map).cast<String, Object?>() : const {},
      confidence: j['confidence'] is num ? (j['confidence'] as num).toDouble() : null,
      answerConfidence: j['answer_confidence'] is num ? (j['answer_confidence'] as num).toDouble() : null,
      actProbability: action?['act_probability'] is num ? (action!['act_probability'] as num).toDouble() : null,
    );
  }
}

/// `POST /api/decision/ask`.
class DecisionResult {
  const DecisionResult({
    required this.model,
    this.engine = 'laya-onnx',
    required this.reason,
    required this.latencyMs,
    required this.inputTokens,
    required this.runs,
    required this.answers,
  });

  final String model;

  /// `laya-onnx`, or `online:<provider>`.
  final String engine;

  bool get online => engine.startsWith('online');

  /// Why routing picked [model].
  final String reason;
  final double latencyMs;
  final int inputTokens;
  final int runs;
  final List<DecisionAnswer> answers;

  factory DecisionResult.fromJson(Map<String, dynamic> j) {
    final answers = j['answers'] is Map ? (j['answers'] as Map).cast<String, dynamic>() : const <String, dynamic>{};
    final routing = j['routing'] is Map ? (j['routing'] as Map).cast<String, dynamic>() : const <String, dynamic>{};
    final usage = j['usage'] is Map ? (j['usage'] as Map).cast<String, dynamic>() : const <String, dynamic>{};
    return DecisionResult(
      model: '${j['model'] ?? ''}',
      engine: '${j['engine'] ?? 'laya-onnx'}',
      reason: '${routing['reason'] ?? ''}',
      latencyMs: _dbl(j['latency_ms']),
      inputTokens: _int(usage['input_tokens']),
      runs: _int(j['runs']),
      answers: [
        for (final e in answers.entries)
          if (e.value is Map) DecisionAnswer.fromJson(e.key, (e.value as Map).cast<String, dynamic>()),
      ],
    );
  }
}
