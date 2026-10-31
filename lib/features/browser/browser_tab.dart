import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/l10n.dart';
import '../../theme/tokens.dart';
import '../../widgets/browser_url.dart';
import '../../widgets/browser_web_view.dart';
import '../background/bg_processes.dart';
import '../dock/workbench_provider.dart';
import 'artifact_panel.dart';
import 'browser_provider.dart';

/// The right-dock **Browser** pane — a real address-bar browser that replaces
/// the old Workbench tab. It opens typed URLs, running dev servers (from
/// `/api/bg-tasks`), `workbench:new` url artifacts and local HTML files, in an
/// embedded WKWebView/WebView2 ([BrowserWebView], free navigation). A static
/// artifact takes the empty state's place, so typing a URL still works and Home
/// comes back to it. Per chat (`key: ValueKey(jid)` at the call site).
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

  /// The artifact this pane has reacted to, so a new one is told from a rebuild.
  String? _lastArtifactId;

  WorkbenchArtifact? _artifactIn(Map<String, WorkbenchArtifact> all) =>
      all[widget.jid] ?? all['_'];

  @override
  void initState() {
    super.initState();
    // Seed from an open-request raised while the pane was closed, else from the
    // latest url artifact for this chat.
    final req = ref.read(browserProvider(widget.jid));
    final art = _artifactIn(ref.read(workbenchProvider));
    _lastArtifactId = art?.id;
    if (req != null) {
      _bootUrl = browserUrlFrom(req.url);
      _lastReqSeq = req.seq;
    } else if (art?.url != null) {
      _bootUrl = browserUrlFrom(art!.url!);
    }
  }

  @override
  void dispose() {
    _addr.dispose();
    _addrFocus.dispose();
    super.dispose();
  }

  void _go(String raw) {
    if (raw.trim().isEmpty) return;
    final url = browserUrlFrom(raw);
    if (url == null) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
          content: Text(context.tr('Only http and https pages open here.'))));
      return;
    }
    if (!_booted) {
      setState(() => _bootUrl = url);
    } else if (_ctrl != null) {
      _ctrl!.loadUrl(url);
    } else {
      _pending = url;
    }
    _addrFocus.unfocus();
  }

  void _goHome() => setState(() {
        _bootUrl = null;
        _ctrl = null;
        _nav = const BrowserNavState();
        _addr.clear();
      });

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
    // Honour open-requests raised from outside the pane (a `:port` chip).
    ref.listen<BrowserOpenRequest?>(browserProvider(widget.jid), (_, next) {
      if (next != null && next.seq != _lastReqSeq) {
        _lastReqSeq = next.seq;
        _go(next.url);
      }
    });

    // A new artifact shows at once: a url one here, a static one in the empty
    // state's place.
    ref.listen<Map<String, WorkbenchArtifact>>(workbenchProvider, (_, all) {
      final art = _artifactIn(all);
      if (art?.id == _lastArtifactId) return;
      _lastArtifactId = art?.id;
      if (art == null) return;
      final url = art.url;
      if (url != null && url.isNotEmpty) {
        _go(url);
      } else {
        _goHome();
      }
    });

    final art = _artifactIn(ref.watch(workbenchProvider));
    final workbench = ref.read(workbenchProvider.notifier);

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
          onHome: _booted ? _goHome : null,
          onExternal: () {
            final u = _nav.url.isNotEmpty ? _nav.url : _addr.text;
            openWebUrlExternally(Uri.tryParse(browserUrlFrom(u) ?? ''));
          },
        ),
        if (_nav.isLoading)
          LinearProgressIndicator(
              value: _nav.progress > 0 ? _nav.progress : null, minHeight: 2),
        if (art != null)
          ArtifactHeader(
            artifact: art,
            onClose: () => workbench.close(widget.jid, art.id),
          ),
        Expanded(
          child: _booted
              ? BrowserWebView(
                  instanceKey: widget.jid,
                  initialUrl: _bootUrl!,
                  onControllerReady: _onControllerReady,
                  onStateChanged: _onNav,
                )
              : art != null && (art.url ?? '').isEmpty
                  ? ArtifactFiles(
                      key: ValueKey(art.id),
                      files: art.files,
                      readFile: (path) =>
                          workbench.readFile(widget.jid, art.id, path),
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
