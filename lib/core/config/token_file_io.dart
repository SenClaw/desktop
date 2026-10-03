import 'dart:io';

import 'package:path/path.dart' as p;

/// Read `<state folder>/api_token` — the token the daemon on this machine
/// auto-generated. Lets the desktop app talk to a LAN-exposed local daemon
/// with zero configuration. Null when absent/unreadable.
Future<String?> readLocalDaemonToken() async {
  try {
    final dir = senclawHomeDir(Platform.environment, Directory.current.path);
    if (dir == null) return null;
    final file = File(p.join(dir, 'api_token'));
    if (!await file.exists()) return null;
    final token = (await file.readAsString()).trim();
    return token.isEmpty ? null : token;
  } catch (_) {
    return null;
  }
}

/// The daemon's state folder, resolved the way the daemon resolves it
/// (`util::paths::senclaw_home`): `SENCLAW_HOME` — `~/` expanded, a relative
/// path anchored at [cwd] — else `~/.senclaw`. The daemon this app spawns
/// inherits the same environment, so both read the same folder.
String? senclawHomeDir(Map<String, String> env, String cwd) {
  final home = env['HOME'] ?? env['USERPROFILE'];
  final raw = (env['SENCLAW_HOME'] ?? '').trim();
  if (raw.isNotEmpty) {
    if (raw == '~') return home;
    if (raw.startsWith('~/')) {
      return home == null ? null : p.join(home, raw.substring(2));
    }
    return p.isAbsolute(raw) ? raw : p.join(cwd, raw);
  }
  if (home == null || home.isEmpty) return null;
  return p.join(home, '.senclaw');
}
