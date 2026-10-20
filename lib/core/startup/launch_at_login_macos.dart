import 'package:flutter/services.dart';

import 'launch_at_login.dart';

/// macOS: the native `loginItemStatus` / `setLoginItem` calls wrap
/// `SMAppService.mainApp` (macOS 13+; older systems answer `unsupported`).
class MacLaunchAtLogin implements LaunchAtLogin {
  MacLaunchAtLogin([MethodChannel? channel])
    : _channel = channel ?? const MethodChannel('senclaw/app');

  final MethodChannel _channel;

  @override
  Future<LaunchAtLoginState> state() async {
    final s = await _channel.invokeMethod<String>('loginItemStatus');
    return switch (s) {
      'enabled' => LaunchAtLoginState.enabled,
      'disabled' => LaunchAtLoginState.disabled,
      'requiresApproval' => LaunchAtLoginState.needsApproval,
      _ => LaunchAtLoginState.unsupported,
    };
  }

  @override
  Future<void> setEnabled(bool enabled) =>
      _channel.invokeMethod('setLoginItem', {'enabled': enabled});
}

/// Where the user turns a login item back on once macOS has it switched off.
final loginItemsSettingsUri = Uri.parse(
  'x-apple.systempreferences:com.apple.LoginItems-Settings.extension',
);
