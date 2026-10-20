import 'dart:io';

import 'launch_at_login.dart';

/// Linux: an XDG autostart entry (`$XDG_CONFIG_HOME/autostart/*.desktop`),
/// which every mainstream desktop environment runs at login.
class LinuxLaunchAtLogin implements LaunchAtLogin {
  /// [configHome] defaults to `$XDG_CONFIG_HOME`, then `~/.config`.
  LinuxLaunchAtLogin({required this.executable, Directory? configHome})
    : _configHome = configHome ?? _defaultConfigHome();

  final String executable;
  final Directory _configHome;

  File get _entry =>
      File('${_configHome.path}/autostart/senclaw-desktop.desktop');

  @override
  Future<LaunchAtLoginState> state() async {
    if (!await _entry.exists()) return LaunchAtLoginState.disabled;
    // A desktop environment's own "startup applications" switch flips one of
    // these keys instead of deleting the file.
    final text = await _entry.readAsString();
    final off = RegExp(
      r'^(Hidden=true|X-GNOME-Autostart-enabled=false)\s*$',
      multiLine: true,
    ).hasMatch(text);
    return off ? LaunchAtLoginState.disabled : LaunchAtLoginState.enabled;
  }

  @override
  Future<void> setEnabled(bool enabled) async {
    if (!enabled) {
      if (await _entry.exists()) await _entry.delete();
      return;
    }
    await _entry.parent.create(recursive: true);
    await _entry.writeAsString(desktopEntry(executable));
  }

  static Directory _defaultConfigHome() {
    final env = Platform.environment;
    final xdg = env['XDG_CONFIG_HOME'];
    if (xdg != null && xdg.isNotEmpty) return Directory(xdg);
    return Directory('${env['HOME'] ?? ''}/.config');
  }
}

/// The autostart entry that runs [executable] with [kAutostartArg].
String desktopEntry(String executable) =>
    '[Desktop Entry]\n'
    'Type=Application\n'
    'Name=SenClaw\n'
    'Comment=Start SenClaw in the tray when you sign in\n'
    'Exec=${_execArg(executable)} $kAutostartArg\n'
    'Terminal=false\n'
    'X-GNOME-Autostart-enabled=true\n';

/// Desktop Entry `Exec=` quoting: an argument with a space or shell character
/// goes in double quotes, and `"` `` ` `` `$` `\` inside them are backslash-
/// escaped; the file format then unescapes backslashes once more, so each
/// backslash is doubled again. A literal `%` is `%%`.
String _execArg(String arg) {
  final s = arg.replaceAll('%', '%%');
  if (!RegExp(r'''[\s"'\\<>~|&;$*?#()`]''').hasMatch(s)) return s;
  final quoted = s
      .replaceAllMapped(RegExp(r'["`$\\]'), (m) => '\\${m[0]}')
      .replaceAll(r'\', r'\\');
  return '"$quoted"';
}
