import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../transport/api_client.dart';
import '../transport/connection.dart';
import 'daemon_provider.dart';
import 'daemon_supervisor.dart';

/// The build identity of one senclaw core (daemon) binary.
///
/// The app's own version and the core's are different numbers: the desktop
/// release bundles whatever core the senclaw repo had at build time, and a
/// daemon the app ADOPTED on the UI port (started from a terminal, or left
/// over from another install) can be any release at all.
@immutable
class CoreBuild {
  const CoreBuild({
    required this.version,
    this.gitHash,
    this.buildTarget,
    this.installKind,
    this.exePath,
  });

  final String version;

  /// Short commit hash; null when the source could not say (a daemon from
  /// before `/api/system/version`, which reports only its version).
  final String? gitHash;
  final String? buildTarget;

  /// `desktop-bundle`, `standalone` or `dev`, as the daemon classifies itself.
  final String? installKind;
  final String? exePath;

  /// `GET /api/system/version`.
  static CoreBuild? fromSystemVersion(Object? raw) {
    if (raw is! Map) return null;
    final v = raw['version'];
    if (v is! String || v.isEmpty) return null;
    String? str(String k) {
      final x = raw[k];
      return x is String && x.isNotEmpty ? x : null;
    }

    return CoreBuild(
      version: v,
      gitHash: str('gitHash'),
      buildTarget: str('buildTarget'),
      installKind: str('installKind'),
      exePath: str('exePath'),
    );
  }

  /// What `senclaw --version` prints: `senclaw 0.2.8 (a05948a5c2e7)`.
  static CoreBuild? fromVersionLine(String out, {String? exePath}) {
    final m = RegExp(r'senclaw\s+(\S+)(?:\s+\(([0-9a-fA-F]+)\))?')
        .firstMatch(out);
    if (m == null) return null;
    return CoreBuild(version: m.group(1)!, gitHash: m.group(2), exePath: exePath);
  }

  /// Same release and, when both sides know it, same commit. A dev tree
  /// rebuilt between two runs keeps its version but not its hash.
  bool sameBuildAs(CoreBuild other) =>
      version == other.version &&
      (gitHash == null || other.gitHash == null || gitHash == other.gitHash);

  /// `0.2.8 (a05948a5c2e7)`, or just the version when the hash is unknown.
  String get label => gitHash == null ? version : '$version ($gitHash)';
}

/// The core the app is talking to right now, or null while no daemon is up
/// or when it would not say. Re-read whenever the supervisor's phase changes,
/// so a restart onto another binary shows the new one.
final runningCoreProvider = FutureProvider<CoreBuild?>((ref) async {
  final up = ref.watch(daemonSupervisorProvider.select((s) => s.isUp));
  ref.watch(daemonSupervisorProvider.select((s) => s.phase));
  if (!up) return null;
  final api = ref.read(apiClientProvider);
  try {
    return CoreBuild.fromSystemVersion(await api.get('/api/system/version'));
  } on ApiException catch (e) {
    // A daemon from before the route: its `/api/config` still names the
    // version, which is enough to tell two releases apart.
    if (e.status != 404) return null;
  } catch (_) {
    return null;
  }
  try {
    final cfg = await api.get('/api/config');
    return cfg is Map && cfg['version'] is String
        ? CoreBuild(version: cfg['version'] as String)
        : null;
  } catch (_) {
    return null;
  }
});

/// The core shipped inside this app (the binary the supervisor would spawn),
/// read with `senclaw --version`. Null on web, or when there is none to find.
/// Read once: the bundle only changes through the updater, which relaunches
/// the app.
final bundledCoreProvider = FutureProvider<CoreBuild?>((ref) async {
  if (kIsWeb) return null;
  final bin = await ref.read(daemonSupervisorProvider).resolveBinary();
  if (bin == null) return null;
  try {
    final res = await Process.run(bin.path, const ['--version'])
        .timeout(const Duration(seconds: 10));
    if (res.exitCode != 0) return null;
    return CoreBuild.fromVersionLine('${res.stdout}', exePath: bin.path);
  } catch (_) {
    return null;
  }
});

/// The adopted daemon and the bundled core, when they are different builds.
@immutable
class CoreMismatch {
  const CoreMismatch({required this.running, required this.bundled});
  final CoreBuild running;
  final CoreBuild bundled;

  /// Identifies the pair, so dismissing the warning about one pair does not
  /// silence a different one later.
  String get key => '${running.label}→${bundled.label}';
}

/// Non-null only when the app attached to a daemon it did not start AND that
/// daemon is another build than the one in this app. A daemon the app spawned
/// is its own bundled core by construction.
final coreMismatchProvider = Provider<CoreMismatch?>((ref) {
  final phase = ref.watch(daemonSupervisorProvider.select((s) => s.phase));
  if (phase != DaemonPhase.adopted) return null;
  final running = ref.watch(runningCoreProvider).valueOrNull;
  final bundled = ref.watch(bundledCoreProvider).valueOrNull;
  if (running == null || bundled == null) return null;
  return running.sameBuildAs(bundled)
      ? null
      : CoreMismatch(running: running, bundled: bundled);
});

/// The mismatch warning the person closed this session (its [CoreMismatch.key]).
final dismissedCoreMismatchProvider = StateProvider<String?>((ref) => null);
