/// Whether the OS started SenClaw because the user signed in (as opposed to
/// the user opening it). A login start lives in the tray and shows no window;
/// the window opens from the tray icon, like after closing it.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'launch_at_login.dart' show kAutostartArg;

/// Windows and Linux hand us [kAutostartArg] on the command line. macOS cannot
/// pass arguments to a login item, so the native side answers instead: it
/// reads the launch Apple event (and also honours [kAutostartArg], which is
/// how a build is launched hidden by hand).
///
/// Never throws: a runner without the native call simply opens the window.
Future<bool> launchedAtLogin(
  List<String> args, {
  MethodChannel channel = const MethodChannel('senclaw/app'),
}) async {
  if (args.contains(kAutostartArg)) return true;
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.macOS) return false;
  try {
    return await channel.invokeMethod<bool>('launchedAtLogin') ?? false;
  } catch (_) {
    return false;
  }
}

/// True when this run started hidden (see [launchedAtLogin]); overridden in
/// `main()`, read once by the app shell to know the window is not showing.
final startedHiddenProvider = Provider<bool>((_) => false);
