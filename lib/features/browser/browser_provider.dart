import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A request to open a URL in a chat's Browser pane that comes from OUTSIDE the
/// pane: a click on a `:port` chip. Nothing opens here on its own, because a page
/// on a loopback port gets the daemon's trust, and that has to be a person's
/// choice. The [seq] makes each request distinct, so the pane re-navigates even
/// to a URL it already shows, and so a request raised while the dock was closed
/// is still honoured the moment the pane mounts.
class BrowserOpenRequest {
  const BrowserOpenRequest(this.url, this.seq);
  final String url;
  final int seq;
}

class BrowserNotifier extends StateNotifier<BrowserOpenRequest?> {
  BrowserNotifier() : super(null);
  int _seq = 0;
  void open(String url) => state = BrowserOpenRequest(url, ++_seq);
}

/// Per-chat pending open request for the Browser pane. Deliberately NOT
/// autoDispose: a click that arrives while the pane is unmounted must survive
/// until it mounts and reads it.
final browserProvider =
    StateNotifierProvider.family<BrowserNotifier, BrowserOpenRequest?, String>(
  (ref, jid) => BrowserNotifier(),
);
