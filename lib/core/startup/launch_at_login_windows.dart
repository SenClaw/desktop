import 'package:win32_registry/win32_registry.dart';

import 'launch_at_login.dart';

/// Windows: a `Run` value in the user's own hive — no admin rights, and it is
/// what Settings → Apps → Startup lists. Explorer keeps a separate on/off flag
/// per entry under `StartupApproved\Run`; a user who switched SenClaw off
/// there leaves our `Run` value in place, so that flag is read too.
class WindowsLaunchAtLogin implements LaunchAtLogin {
  WindowsLaunchAtLogin({required this.executable});

  final String executable;

  static const _name = 'SenClaw';
  static const _runPath = r'Software\Microsoft\Windows\CurrentVersion\Run';
  static const _approvedPath =
      r'Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run';

  @override
  Future<LaunchAtLoginState> state() async {
    final registered = _withKey(_runPath, (k) => k.getValue(_name) != null);
    if (registered != true) return LaunchAtLoginState.disabled;
    final flag = _withKey(
      _approvedPath,
      (k) => k.getBinaryValue(_name),
      optional: true,
    );
    return approvedFlagIsOff(flag)
        ? LaunchAtLoginState.disabled
        : LaunchAtLoginState.enabled;
  }

  @override
  Future<void> setEnabled(bool enabled) async {
    _withKey(_runPath, (k) {
      if (enabled) {
        k.createValue(
          RegistryValue.string(_name, windowsRunCommand(executable)),
        );
      } else if (k.getValue(_name) != null) {
        k.deleteValue(_name);
      }
    }, write: true);
    // Either way the Explorer flag is stale: drop it, so the entry is
    // approved the moment it is switched on again.
    _withKey(_approvedPath, (k) {
      if (k.getValue(_name) != null) k.deleteValue(_name);
    }, write: true, optional: true);
  }

  /// Runs [body] on [path] and always closes the key. [optional] keys may not
  /// exist (`StartupApproved\Run` is created lazily by Explorer) and then give
  /// null; any other failure to open a key is the caller's to see.
  T? _withKey<T>(
    String path,
    T Function(RegistryKey) body, {
    bool write = false,
    bool optional = false,
  }) {
    final RegistryKey key;
    try {
      key = Registry.openPath(
        RegistryHive.currentUser,
        path: path,
        desiredAccessRights: write
            ? AccessRights.allAccess
            : AccessRights.readOnly,
      );
    } catch (_) {
      if (optional) return null;
      rethrow;
    }
    try {
      return body(key);
    } finally {
      key.close();
    }
  }
}

/// The command stored in the `Run` key: the executable in quotes (the path
/// usually has spaces, e.g. `C:\Program Files\...`) plus [kAutostartArg].
String windowsRunCommand(String executable) => '"$executable" $kAutostartArg';

/// Explorer's `StartupApproved` value is 12 bytes whose first byte is even
/// (0x02 / 0x06) when the entry is on and odd (0x03 / 0x07) when the user
/// switched it off. No value at all means on.
bool approvedFlagIsOff(List<int>? flag) =>
    flag != null && flag.isNotEmpty && flag[0].isOdd;
