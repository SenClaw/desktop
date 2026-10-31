import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../background/bg_processes.dart';
import '../chat/mini_chat_screen.dart' show subWindowIdProvider;
import '../dock/right_dock.dart' show dockVisibleProvider, dockTabProvider;
import 'browser_provider.dart';

/// Browser tab index in the right dock (see [RightDock]'s tab switch).
const _browserTab = 1;

/// Watches this chat's dev servers and opens the Browser pane to one the moment
/// it starts listening — the "auto-open when a dev server starts" behaviour.
/// Invisible; mount once per chat (in the main window only). The pane also shows
/// a one-click list, and the `:port` chips open here too, so this is just the
/// hands-free path.
class DevServerAutoOpen extends ConsumerStatefulWidget {
  const DevServerAutoOpen({super.key, required this.jid});
  final String jid;

  @override
  ConsumerState<DevServerAutoOpen> createState() => _DevServerAutoOpenState();
}

class _DevServerAutoOpenState extends ConsumerState<DevServerAutoOpen> {
  /// Ports already reacted to while they stay up — so one server opens once,
  /// but a server that stops and restarts on the same port opens again.
  final Set<int> _seen = {};
  bool _primed = false;

  @override
  Widget build(BuildContext context) {
    // No auto-open in the mini window — it has no right dock.
    if (ref.watch(subWindowIdProvider) != null) return const SizedBox.shrink();

    ref.listen<AsyncValue<List<BgProcess>>>(bgProcessesProvider, (_, next) {
      final list = next.valueOrNull;
      if (list == null) return;
      final ports = <int>{
        for (final p in list)
          if (p.running && p.chatJid == widget.jid) ...p.ports,
      };
      // First poll after mount: remember what is already up without hijacking
      // the pane for a server that was running before this chat was opened.
      if (!_primed) {
        _seen
          ..clear()
          ..addAll(ports);
        _primed = true;
        return;
      }
      final fresh = ports.difference(_seen);
      _seen
        ..retainWhere(ports.contains)
        ..addAll(ports);
      if (fresh.isEmpty) return;
      // Lowest port is the likeliest web port (vite/CRA advertise it first).
      final port = fresh.reduce((a, b) => a < b ? a : b);
      ref
          .read(browserProvider(widget.jid).notifier)
          .open('http://127.0.0.1:$port/');
      ref.read(dockVisibleProvider.notifier).state = true;
      ref.read(dockTabProvider.notifier).state = _browserTab;
    });
    return const SizedBox.shrink();
  }
}
