/// "Launch at login": start SenClaw Desktop when the user signs in to the OS.
///
/// One seam, one implementation per platform:
///   * macOS    — `SMAppService.mainApp` (Login Items), behind the existing
///                `senclaw/app` channel — see `AppDelegate.swift`.
///   * Windows  — a value under `HKCU\...\CurrentVersion\Run`.
///   * Linux    — an XDG autostart entry in `~/.config/autostart`.
///
/// The app supervises the daemon, so starting the app starts the daemon too —
/// nothing else has to be registered.
library;

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show MissingPluginException;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'launch_at_login_linux.dart';
import 'launch_at_login_macos.dart';
// The registry binding is dart:ffi, which the web build cannot compile.
import 'launch_at_login_windows_stub.dart'
    if (dart.library.ffi) 'launch_at_login_windows.dart';

/// Argument the OS-started launch carries (the Windows registry value and the
/// Linux `Exec=` line). macOS login items cannot carry arguments, so the
/// native side detects that launch on its own — see `launch_origin.dart`.
const kAutostartArg = '--autostart';

enum LaunchAtLoginState {
  enabled,
  disabled,

  /// macOS only: SenClaw is registered, but the user switched it off in
  /// System Settings → Login Items. Only they can switch it back on there.
  needsApproval,

  /// This platform (or this OS version) has no way to do it; the setting is
  /// not shown.
  unsupported,
}

abstract class LaunchAtLogin {
  Future<LaunchAtLoginState> state();
  Future<void> setEnabled(bool enabled);
}

/// The implementation for the platform we are running on, or null where there
/// is none (web, mobile).
LaunchAtLogin? launchAtLoginForPlatform() {
  if (kIsWeb) return null;
  if (Platform.isMacOS) return MacLaunchAtLogin();
  if (Platform.isWindows) {
    return WindowsLaunchAtLogin(executable: Platform.resolvedExecutable);
  }
  if (Platform.isLinux) {
    return LinuxLaunchAtLogin(executable: Platform.resolvedExecutable);
  }
  return null;
}

/// Overridable so a widget test never touches the real registry / Login Items.
final launchAtLoginProvider = Provider<LaunchAtLogin?>(
  (_) => launchAtLoginForPlatform(),
);

/// The current state; invalidate after [LaunchAtLogin.setEnabled].
final launchAtLoginStateProvider =
    FutureProvider.autoDispose<LaunchAtLoginState>((ref) async {
      final svc = ref.watch(launchAtLoginProvider);
      if (svc == null) return LaunchAtLoginState.unsupported;
      try {
        return await svc.state();
      } on MissingPluginException {
        // A native runner built before this feature: there is no bridge to ask.
        return LaunchAtLoginState.unsupported;
      }
    });
