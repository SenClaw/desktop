// Data model + providers for Settings → Runtime (runtime-protocol.md §5.1):
// `GET /api/runtimes` (platform, settings, slots, installed, processes) and
// `GET /api/runtimes/catalog` (the runtime index merged with install state).
// Consumed by runtime_section.dart (Runtime Selections / updates channel /
// Running) and runtime_catalog.dart (Engines & Frameworks), and by
// local_models_section.dart for the shared candidate/process shapes.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/transport/connection.dart';

Map<String, dynamic> _asMap(dynamic v) => v is Map ? v.cast<String, dynamic>() : {};
List<Map<String, dynamic>> _asMapList(dynamic v) => (v as List? ?? const [])
    .whereType<Map>()
    .map((e) => e.cast<String, dynamic>())
    .toList();
List<String> _asStrings(dynamic v) =>
    (v as List? ?? const []).map((e) => '$e').toList();

/// One engine+version a slot could run — `slots[].selected` / `.candidates[]`.
class RuntimeCandidate {
  const RuntimeCandidate({required this.id, required this.version, required this.name});
  final String id;
  final String version;
  final String name;

  factory RuntimeCandidate.fromJson(Map<String, dynamic> j) => RuntimeCandidate(
        id: '${j['id'] ?? ''}',
        version: '${j['version'] ?? ''}',
        name: '${j['name'] ?? j['id'] ?? ''}',
      );
}

/// What a runtime is selected FOR — a model format (`gguf`, `mlx`) or a
/// capability (`decision`, `ocr`, `asr`, `tts`). One selection per slot
/// (runtime-protocol.md §1).
class RuntimeSlot {
  const RuntimeSlot({
    required this.slot,
    required this.label,
    required this.kind,
    required this.selected,
    required this.candidates,
  });
  final String slot;
  final String label;
  final String kind; // 'format' | 'capability'
  final RuntimeCandidate? selected;
  final List<RuntimeCandidate> candidates;

  factory RuntimeSlot.fromJson(Map<String, dynamic> j) => RuntimeSlot(
        slot: '${j['slot'] ?? ''}',
        label: '${j['label'] ?? j['slot'] ?? ''}',
        kind: '${j['kind'] ?? ''}',
        selected: j['selected'] is Map
            ? RuntimeCandidate.fromJson(_asMap(j['selected']))
            : null,
        candidates:
            _asMapList(j['candidates']).map(RuntimeCandidate.fromJson).toList(),
      );
}

/// One installed runtime package (any version) — `GET /api/runtimes` `installed[]`.
class InstalledRuntime {
  const InstalledRuntime({
    required this.id,
    required this.name,
    required this.version,
    required this.versions,
    required this.type,
    required this.slots,
    required this.formats,
    required this.capabilities,
    required this.platforms,
    required this.accelerator,
    required this.mode,
    required this.compatible,
    required this.source,
    required this.description,
    required this.releaseNotesUrl,
    required this.warnings,
  });
  final String id;
  final String name;
  final String version; // newest installed
  final List<String> versions; // all, newest first
  final String type;
  final List<String> slots;
  final List<String> formats;
  final List<String> capabilities;
  final List<String> platforms;
  final String? accelerator;
  final String mode; // 'service' | 'model'
  final bool compatible;
  final String source; // 'index' | 'local' | 'bundled'
  final String description;
  final String? releaseNotesUrl;
  final List<String> warnings;

  factory InstalledRuntime.fromJson(Map<String, dynamic> j) => InstalledRuntime(
        id: '${j['id'] ?? ''}',
        name: '${j['name'] ?? j['id'] ?? ''}',
        version: '${j['version'] ?? ''}',
        versions: _asStrings(j['versions']),
        type: '${j['type'] ?? ''}',
        slots: _asStrings(j['slots']),
        formats: _asStrings(j['formats']),
        capabilities: _asStrings(j['capabilities']),
        platforms: _asStrings(j['platforms']),
        accelerator: j['accelerator'] as String?,
        mode: '${j['mode'] ?? ''}',
        compatible: j['compatible'] != false,
        source: '${j['source'] ?? 'index'}',
        description: '${j['description'] ?? ''}',
        releaseNotesUrl: j['releaseNotesUrl'] as String?,
        warnings: _asStrings(j['warnings']),
      );
}

/// A running launch of a runtime — `GET /api/runtimes` `processes[]`.
class RuntimeProcessInfo {
  const RuntimeProcessInfo({
    required this.key,
    required this.runtimeId,
    required this.version,
    required this.slot,
    required this.modelKey,
    required this.pid,
    required this.port,
    required this.state,
    required this.startedAt,
    required this.lastUsedAt,
    required this.launches,
    required this.error,
  });
  final String key;
  final String runtimeId;
  final String version;
  final String slot;
  final String? modelKey;
  final int pid;
  final int port;
  final String state; // starting | ready | stopping | failed
  final int startedAt;
  final int? lastUsedAt;
  final int launches;
  final String? error;

  factory RuntimeProcessInfo.fromJson(Map<String, dynamic> j) => RuntimeProcessInfo(
        key: '${j['key'] ?? ''}',
        runtimeId: '${j['runtimeId'] ?? ''}',
        version: '${j['version'] ?? ''}',
        slot: '${j['slot'] ?? ''}',
        modelKey: j['modelKey'] as String?,
        pid: (j['pid'] as num?)?.toInt() ?? 0,
        port: (j['port'] as num?)?.toInt() ?? 0,
        state: '${j['state'] ?? ''}',
        startedAt: (j['startedAt'] as num?)?.toInt() ?? 0,
        lastUsedAt: (j['lastUsedAt'] as num?)?.toInt(),
        launches: (j['launches'] as num?)?.toInt() ?? 0,
        error: j['error'] as String?,
      );
}

class RuntimeIdleTimeouts {
  const RuntimeIdleTimeouts({required this.service, required this.model});
  final int service;
  final int model;

  factory RuntimeIdleTimeouts.fromJson(Map<String, dynamic> j) => RuntimeIdleTimeouts(
        service: (j['service'] as num?)?.toInt() ?? 300,
        model: (j['model'] as num?)?.toInt() ?? 900,
      );
}

class RuntimeSettings {
  const RuntimeSettings({
    required this.autoUpdate,
    required this.channel,
    required this.idleTimeoutSecs,
  });
  final bool autoUpdate;
  final String channel; // 'stable' | 'beta'
  final RuntimeIdleTimeouts idleTimeoutSecs;

  factory RuntimeSettings.fromJson(Map<String, dynamic> j) => RuntimeSettings(
        autoUpdate: j['autoUpdate'] == true,
        channel: '${j['channel'] ?? 'stable'}',
        idleTimeoutSecs: RuntimeIdleTimeouts.fromJson(_asMap(j['idleTimeoutSecs'])),
      );
}

/// `GET /api/runtimes` — the whole Runtime screen's data in one call.
class RuntimesState {
  const RuntimesState({
    required this.platform,
    required this.settings,
    required this.slots,
    required this.installed,
    required this.processes,
  });
  final String platform;
  final RuntimeSettings settings;
  final List<RuntimeSlot> slots;
  final List<InstalledRuntime> installed;
  final List<RuntimeProcessInfo> processes;

  factory RuntimesState.fromJson(Map<String, dynamic> j) => RuntimesState(
        platform: '${j['platform'] ?? ''}',
        settings: RuntimeSettings.fromJson(_asMap(j['settings'])),
        slots: _asMapList(j['slots']).map(RuntimeSlot.fromJson).toList(),
        installed: _asMapList(j['installed']).map(InstalledRuntime.fromJson).toList(),
        processes: _asMapList(j['processes']).map(RuntimeProcessInfo.fromJson).toList(),
      );
}

final runtimesProvider = FutureProvider<RuntimesState>((ref) async {
  final r = await ref.read(apiClientProvider).get('/api/runtimes');
  return RuntimesState.fromJson(_asMap(r));
});

/// One row of `GET /api/runtimes/catalog` `entries[]` — the index merged with
/// install state (server-side). [fromInstalled] synthesizes the same shape for
/// an `installed[]` runtime with no catalog entry (a `source: "local"` sideload).
class CatalogEntry {
  const CatalogEntry({
    required this.id,
    required this.name,
    required this.description,
    required this.type,
    required this.slots,
    required this.formats,
    required this.capabilities,
    required this.accelerator,
    required this.platforms,
    required this.compatible,
    required this.available,
    required this.latestVersion,
    required this.installedVersion,
    required this.updateAvailable,
    required this.releaseNotesUrl,
    required this.downloadSize,
  });
  final String id;
  final String name;
  final String description;
  final String type;
  final List<String> slots;
  final List<String> formats;
  final List<String> capabilities;
  final String? accelerator;
  final List<String> platforms;
  final bool compatible;
  final bool available;
  final String latestVersion;
  final String? installedVersion;
  final bool updateAvailable;
  final String? releaseNotesUrl;
  final int? downloadSize;

  factory CatalogEntry.fromJson(Map<String, dynamic> j) => CatalogEntry(
        id: '${j['id'] ?? ''}',
        name: '${j['name'] ?? j['id'] ?? ''}',
        description: '${j['description'] ?? ''}',
        type: '${j['type'] ?? ''}',
        slots: _asStrings(j['slots']),
        formats: _asStrings(j['formats']),
        capabilities: _asStrings(j['capabilities']),
        accelerator: j['accelerator'] as String?,
        platforms: _asStrings(j['platforms']),
        compatible: j['compatible'] != false,
        available: j['available'] != false,
        latestVersion: '${j['latestVersion'] ?? ''}',
        installedVersion: j['installedVersion'] as String?,
        updateAvailable: j['updateAvailable'] == true,
        releaseNotesUrl: j['releaseNotesUrl'] as String?,
        downloadSize: (j['downloadSize'] as num?)?.toInt(),
      );

  /// A locally-sideloaded runtime the index doesn't (yet, or ever) list —
  /// `install-local` accepts any manifest, catalog-less by construction.
  factory CatalogEntry.fromInstalled(InstalledRuntime r) => CatalogEntry(
        id: r.id,
        name: r.name,
        description: r.description,
        type: r.type,
        slots: r.slots,
        formats: r.formats,
        capabilities: r.capabilities,
        accelerator: r.accelerator,
        platforms: r.platforms,
        compatible: r.compatible,
        available: true,
        latestVersion: r.version,
        installedVersion: r.version,
        updateAvailable: false,
        releaseNotesUrl: r.releaseNotesUrl,
        downloadSize: null,
      );
}

class RuntimeCatalog {
  const RuntimeCatalog({
    required this.channel,
    required this.fetchedAt,
    required this.source,
    required this.error,
    required this.entries,
  });
  final String channel;
  final int fetchedAt;
  final String? source;
  final String? error;
  final List<CatalogEntry> entries;

  factory RuntimeCatalog.fromJson(Map<String, dynamic> j) => RuntimeCatalog(
        channel: '${j['channel'] ?? 'stable'}',
        fetchedAt: (j['fetchedAt'] as num?)?.toInt() ?? 0,
        source: j['source'] as String?,
        error: j['error'] as String?,
        entries: _asMapList(j['entries']).map(CatalogEntry.fromJson).toList(),
      );
}

final runtimeCatalogProvider = FutureProvider<RuntimeCatalog>((ref) async {
  final r = await ref.read(apiClientProvider).get('/api/runtimes/catalog');
  return RuntimeCatalog.fromJson(_asMap(r));
});

/// `GET /api/runtimes/jobs/:jobId` — polled ~1s while [active] to drive a
/// row's progress spinner.
class RuntimeInstallJob {
  const RuntimeInstallJob({
    required this.jobId,
    required this.id,
    required this.version,
    required this.state,
    required this.receivedBytes,
    required this.totalBytes,
    required this.percent,
    required this.error,
    required this.startedAt,
    required this.finishedAt,
  });
  final String jobId;
  final String id;
  final String version;
  final String state; // queued|downloading|verifying|extracting|done|failed|cancelled
  final int receivedBytes;
  final int? totalBytes;
  final double? percent;
  final String? error;
  final int startedAt;
  final int? finishedAt;

  factory RuntimeInstallJob.fromJson(Map<String, dynamic> j) => RuntimeInstallJob(
        jobId: '${j['jobId'] ?? ''}',
        id: '${j['id'] ?? ''}',
        version: '${j['version'] ?? ''}',
        state: '${j['state'] ?? ''}',
        receivedBytes: (j['receivedBytes'] as num?)?.toInt() ?? 0,
        totalBytes: (j['totalBytes'] as num?)?.toInt(),
        percent: (j['percent'] as num?)?.toDouble(),
        error: j['error'] as String?,
        startedAt: (j['startedAt'] as num?)?.toInt() ?? 0,
        finishedAt: (j['finishedAt'] as num?)?.toInt(),
      );

  bool get active =>
      state == 'queued' ||
      state == 'downloading' ||
      state == 'verifying' ||
      state == 'extracting';
}
