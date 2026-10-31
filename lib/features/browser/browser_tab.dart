import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/i18n/l10n.dart';
import '../../theme/tokens.dart';
import '../../widgets/browser_web_view.dart';
import '../background/bg_processes.dart';
import '../dock/workbench_provider.dart';
import 'browser_provider.dart';

/// The right-dock **Browser** pane — a real address-bar browser that replaces
/// the old Workbench tab. It opens typed URLs, running dev servers (from
/// `/api/bg-tasks`), `workbench:new` url artifacts and local HTML files, in an
/// embedded WKWebView/WebView2 ([BrowserWebView], free navigation). Per chat
/// (`key: ValueKey(jid)` at the call site), so each session keeps its own page.
class BrowserTab extends ConsumerStatefulWidget {
  const BrowserTab({super.key, required this.jid});
  final String jid;

  @override
  ConsumerState<BrowserTab> createState() => _BrowserTabState();
}

class _BrowserTabState extends ConsumerState<BrowserTab> {
  final _addr = TextEditingController();
  final _addrFocus = FocusNode();

  BrowserWebController? _ctrl;
  BrowserNavState _nav = const BrowserNavState();

  /// The URL the webview was created with. Null until the first navigation —
  /// while null the pane shows the empty state.
  String? _bootUrl;
  bool get _booted => _bootUrl != null;

  /// A URL asked for after boot but before the controller was ready.
  String? _pending;

  /// Last external open-request seq we handled (from [browserProvider]).
  int _lastReqSeq = 0;

  @override
  void initState() {
    super.initState();
    // Seed from an open-request raised while the pane was closed, else from the
    // latest url artifact for this chat.
    final req = ref.read(browserProvider(widget.jid));
    if (req != null) {
      _bootUrl = req.url;
      _lastReqSeq = req.seq;
    } else {
      final art = ref.read(workbenchProvider)[widget.jid] ??
          ref.read(workbenchProvider)['_'];
      if (art?.url != null && art!.url!.isNotEmpty) _bootUrl = art.url;
    }
  }

  @override
  void dispose() {
    _addr.dispose();
    _addrFocus.dispose();
    super.dispose();
  }

  /// Turn whatever the user typed into a loadable URL. A bare `localhost:3000`
  /// becomes `http://…`; anything else with no scheme gets `https://`.
  String _normalize(String input) {
    final s = input.trim();
    if (s.isEmpty || s.contains('://')) return s;
    final local = s.startsWith('localhost') ||
        s.startsWith('127.0.0.1') ||
        s.startsWith('0.0.0.0') ||
        s.startsWith('[::1]');
    return '${local ? 'http' : 'https'}://$s';
  }

  void _go(String raw) {
    final url = _normalize(raw);
    if (url.isEmpty) return;
    if (!_booted) {
      setState(() => _bootUrl = url);
    } else if (_ctrl != null) {
      _ctrl!.loadUrl(url);
    } else {
      _pending = url;
    }
    _addrFocus.unfocus();
  }

  void _onControllerReady(BrowserWebController c) {
    _ctrl = c;
    if (_pending != null) {
      c.loadUrl(_pending!);
      _pending = null;
    }
  }

  void _onNav(BrowserNavState s) {
    if (!mounted) return;
    setState(() => _nav = s);
    if (!_addrFocus.hasFocus && s.url.isNotEmpty && s.url != _addr.text) {
      _addr.text = s.url;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Honour open-requests raised from outside the pane (auto-open, chips).
    ref.listen<BrowserOpenRequest?>(browserProvider(widget.jid), (_, next) {
      if (next != null && next.seq != _lastReqSeq) {
        _lastReqSeq = next.seq;
        _go(next.url);
      }
    });

    return Column(
      children: [
        _AddressBar(
          controller: _addr,
          focusNode: _addrFocus,
          nav: _nav,
          booted: _booted,
          onSubmit: _go,
          onBack: _nav.canGoBack ? () => _ctrl?.goBack() : null,
          onForward: _nav.canGoForward ? () => _ctrl?.goForward() : null,
          onReload: _booted ? () => _ctrl?.reload() : null,
          onHome: _booted
              ? () => setState(() {
                    _bootUrl = null;
                    _ctrl = null;
                    _nav = const BrowserNavState();
                    _addr.clear();
                  })
              : null,
          onExternal: () {
            final u = _nav.url.isNotEmpty ? _nav.url : _normalize(_addr.text);
            if (u.isNotEmpty) {
              launchUrl(Uri.parse(u), mode: LaunchMode.externalApplication);
            }
          },
        ),
        if (_nav.isLoading)
          LinearProgressIndicator(
              value: _nav.progress > 0 ? _nav.progress : null, minHeight: 2),
        Expanded(
          child: _booted
              ? BrowserWebView(
                  instanceKey: widget.jid,
                  initialUrl: _bootUrl!,
                  onControllerReady: _onControllerReady,
                  onStateChanged: _onNav,
                )
              : _BrowserEmptyState(jid: widget.jid, onOpen: _go),
        ),
      ],
    );
  }
}

/// `[◀ ▶ ⟳ ⌂]  [ address ... ]  [⧉]`
class _AddressBar extends StatelessWidget {
  const _AddressBar({
    required this.controller,
    required this.focusNode,
    required this.nav,
    required this.booted,
    required this.onSubmit,
    required this.onBack,
    required this.onForward,
    required this.onReload,
    required this.onHome,
    required this.onExternal,
  });
  final TextEditingController controller;
  final FocusNode focusNode;
  final BrowserNavState nav;
  final bool booted;
  final void Function(String) onSubmit;
  final VoidCallback? onBack;
  final VoidCallback? onForward;
  final VoidCallback? onReload;
  final VoidCallback? onHome;
  final VoidCallback onExternal;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: AppTokens.s8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.border)),
      ),
      child: Row(
        children: [
          _navButton(context,
              icon: Icons.arrow_back, tip: context.tr('Back'), onTap: onBack),
          _navButton(context,
              icon: Icons.arrow_forward,
              tip: context.tr('Forward'),
              onTap: onForward),
          _navButton(context,
              icon: nav.isLoading ? Icons.close : Icons.refresh,
              tip: nav.isLoading ? context.tr('Stop') : context.tr('Reload'),
              onTap: onReload),
          _navButton(context,
              icon: Icons.home_outlined,
              tip: context.tr('Home'),
              onTap: onHome),
          const SizedBox(width: AppTokens.s4),
          Expanded(
            child: SizedBox(
              height: 30,
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                style: TextStyle(
                    fontSize: 12,
                    fontFamily: AppTokens.fontMono,
                    color: c.textPrimary),
                textInputAction: TextInputAction.go,
                onSubmitted: onSubmit,
                decoration: InputDecoration(
                  isDense: true,
                  filled: true,
                  fillColor: c.surfaceAlt,
                  hintText: context.tr('Type a URL'),
                  hintStyle: TextStyle(color: c.textMuted, fontSize: 12),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: AppTokens.s12, vertical: AppTokens.s6),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppTokens.rLg),
                      borderSide: BorderSide(color: c.border)),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppTokens.rLg),
                      borderSide: BorderSide(color: c.border)),
                ),
              ),
            ),
          ),
          const SizedBox(width: AppTokens.s4),
          _navButton(context,
              icon: Icons.open_in_new,
              tip: context.tr('Open externally'),
              onTap: booted || controller.text.isNotEmpty ? onExternal : null),
        ],
      ),
    );
  }

  Widget _navButton(BuildContext context,
      {required IconData icon, required String tip, VoidCallback? onTap}) {
    return IconButton(
      tooltip: tip,
      icon: Icon(icon, size: 16),
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 30, height: 30),
      onPressed: onTap,
    );
  }
}

/// Globe + hint + a one-click list of the dev servers this chat is running.
class _BrowserEmptyState extends ConsumerWidget {
  const _BrowserEmptyState({required this.jid, required this.onOpen});
  final String jid;
  final void Function(String) onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final all = ref.watch(bgProcessesProvider).valueOrNull ?? const <BgProcess>[];
    // This chat's running servers first, then the rest — each listed port is a
    // one-click open in this pane.
    final mine = all.where((p) => p.running && p.chatJid == jid).toList();
    final others = all.where((p) => p.running && p.chatJid != jid).toList();
    final servers = [...mine, ...others];

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppTokens.s24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.public, size: 44, color: c.textMuted),
            const SizedBox(height: AppTokens.s12),
            Text(context.tr('Browse the web'),
                style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: AppTokens.s6),
            Text(
              context.tr(
                  'Type a URL above, or open a running dev server below.'),
              textAlign: TextAlign.center,
              style: TextStyle(color: c.textMuted, fontSize: 12),
            ),
            if (servers.isNotEmpty) ...[
              const SizedBox(height: AppTokens.s20),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(context.tr('Dev servers'),
                    style: TextStyle(
                        color: c.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w700)),
              ),
              const SizedBox(height: AppTokens.s8),
              for (final p in servers)
                for (final port in p.ports)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppTokens.s6),
                    child: OutlinedButton.icon(
                      onPressed: () => onOpen('http://127.0.0.1:$port/'),
                      icon: const Icon(Icons.play_circle_outline, size: 16),
                      label: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          ':$port · ${p.title}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(220, 34),
                        alignment: Alignment.centerLeft,
                      ),
                    ),
                  ),
            ],
          ],
        ),
      ),
    );
  }
}
