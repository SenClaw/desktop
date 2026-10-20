import 'launch_at_login.dart';

/// Stand-in for `launch_at_login_windows.dart` on targets without `dart:ffi`
/// (web); [launchAtLoginForPlatform] never builds it there.
class WindowsLaunchAtLogin implements LaunchAtLogin {
  WindowsLaunchAtLogin({required String executable});

  @override
  Future<LaunchAtLoginState> state() async => LaunchAtLoginState.unsupported;

  @override
  Future<void> setEnabled(bool enabled) async =>
      throw UnsupportedError('Launch at login needs a desktop build');
}
