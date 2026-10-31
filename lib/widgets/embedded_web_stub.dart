import 'dart:collection';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../core/i18n/l10n.dart';
import '../theme/tokens.dart';
import 'browser_url.dart';

/// Desktop embed: a real in-app WKWebView/WebView2 on macOS & Windows;
/// Linux (no embedded webview support) falls back to opening the browser.
/// The host's [theme] is delivered to the page via the SenClaw `postMessage`
/// bridge (`senclaw:init` on load, `senclaw:theme` on change).
Widget embeddedWebView(String url,
    {String? title, String theme = 'light', String? instanceKey}) {
  if (Platform.isMacOS || Platform.isWindows) {
    return _DesktopWebView(
        url: url, theme: theme, instanceKey: instanceKey);
  }
  return _OpenInBrowser(url: url, title: title);
}

class _DesktopWebView extends StatefulWidget {
  const _DesktopWebView(
      {required this.url, required this.theme, this.instanceKey});
  final String url;
  final String theme;
  final String? instanceKey;
  @override
  State<_DesktopWebView> createState() => _DesktopWebViewState();
}

class _DesktopWebViewState extends State<_DesktopWebView> {
  InAppWebViewController? _ctrl;

  // Injected at document-start so the listener exists BEFORE the embedded app
  // mounts and posts `senclaw:ready` — otherwise the handshake races and the
  // app never learns the host theme (falls back to its own dark default).
  static final _readyBridge = UnmodifiableListView([
    UserScript(
      source: "window.addEventListener('message', function(e){"
          "  if (e.data && e.data.type === 'senclaw:ready') {"
          "    window.flutter_inappwebview.callHandler('senclawReady');"
          "  }"
          "});",
      injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
    ),
  ]);

  void _post(String type) {
    _ctrl?.evaluateJavascript(
        source: "window.postMessage("
            "{type:'$type',theme:'${widget.theme}'},'*')");
  }

  @override
  void didUpdateWidget(covariant _DesktopWebView old) {
    super.didUpdateWidget(old);
    if (old.theme != widget.theme) _post('senclaw:theme');
  }

  /// Served from this machine, as Space Apps and widgets are.
  bool get _local => isLoopbackUrl(widget.url);

  @override
  Widget build(BuildContext context) {
    return InAppWebView(
      key: ValueKey('${widget.instanceKey ?? ''}-${widget.url}'),
      initialUrlRequest: URLRequest(url: WebUri(widget.url)),
      initialSettings: InAppWebViewSettings(
        transparentBackground: true,
        // window.open / target=_blank surface via onCreateWindow, which sends
        // them to the system browser. A Space App on this machine may do that
        // after an await (an OAuth link it had to fetch first). A remote page,
        // such as a video embed from a model reply, needs a click.
        javaScriptCanOpenWindowsAutomatically: _local,
        supportMultipleWindows: true,
        // Route every top-frame navigation through shouldOverrideUrlLoading so
        // plain <a href> links (no target=_blank) can't hijack the embed.
        useShouldOverrideUrlLoading: true,
      ),
      initialUserScripts: _readyBridge,
      onWebViewCreated: (c) {
        _ctrl = c;
        // The app announces it's ready → (re)send the current theme.
        c.addJavaScriptHandler(
            handlerName: 'senclawReady', callback: (_) => _post('senclaw:init'));
        // The app asks us to open a URL in the REAL browser (OAuth, docs). A
        // Space App can't do Facebook OAuth inside this embedded webview, so it
        // calls flutter_inappwebview.callHandler('senclawOpenExternal', url).
        c.addJavaScriptHandler(
            handlerName: 'senclawOpenExternal',
            callback: (args) {
              final url = args.isNotEmpty ? args.first?.toString() : null;
              if (url != null && url.isNotEmpty) {
                openLinkExternally(Uri.tryParse(url));
              }
            });
      },
      // Safety net #2: plain <a href> links (no target=_blank) fire a top-frame
      // navigation, not onCreateWindow. Keep the embed pinned to its own origin
      // and push everything external to the system browser. Sub-frame (iframe)
      // navigations pass through untouched — drawio & co. embed same-origin
      // iframes that must keep working.
      shouldOverrideUrlLoading: (controller, action) async {
        if (action.isForMainFrame == false) {
          return NavigationActionPolicy.ALLOW;
        }
        final uri = action.request.url;
        if (uri == null) return NavigationActionPolicy.ALLOW;
        final scheme = uri.scheme.toLowerCase();
        // Internal page mechanics — never leave the webview for these.
        if (scheme == 'about' ||
            scheme == 'data' ||
            scheme == 'blob' ||
            scheme == 'javascript' ||
            scheme.isEmpty) {
          return NavigationActionPolicy.ALLOW;
        }
        if (scheme == 'http' || scheme == 'https') {
          final origin = Uri.tryParse(widget.url);
          final sameOrigin = origin != null &&
              uri.host == origin.host &&
              uri.port == origin.port &&
              scheme == origin.scheme.toLowerCase();
          if (sameOrigin) return NavigationActionPolicy.ALLOW;
        }
        // An external http(s) origin, mailto: or tel: goes to the OS. Any other
        // scheme is refused: this page can be remote, and a scheme's handler is
        // another program.
        await openLinkExternally(uri);
        return NavigationActionPolicy.CANCEL;
      },
      // Safety net: any window.open / target=_blank (e.g. an app that didn't use
      // the bridge) opens in the system browser rather than a broken in-webview
      // popup. Same-webview navigations (the app's own pages) are unaffected.
      // True keeps it out of this webview. WebView2 alone reports a popup with
      // no click (its blocker is off), so a remote page's one is dropped here.
      onCreateWindow: (controller, action) async {
        if (_local || action.hasGesture != false) {
          await openLinkExternally(action.request.url);
        }
        return true;
      },
      onLoadStop: (_, _) => _post('senclaw:init'),
    );
  }
}

class _OpenInBrowser extends StatelessWidget {
  const _OpenInBrowser({required this.url, this.title});
  final String url;
  final String? title;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.public, size: 40, color: c.textMuted),
          const SizedBox(height: AppTokens.s12),
          Text(title ?? context.tr('Web content'),
              style: TextStyle(color: c.textSecondary, fontSize: 14)),
          const SizedBox(height: AppTokens.s4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: SelectableText(url,
                textAlign: TextAlign.center,
                style: TextStyle(color: c.textMuted, fontSize: 12)),
          ),
          const SizedBox(height: AppTokens.s16),
          FilledButton.icon(
            onPressed: () => openLinkExternally(Uri.tryParse(url)),
            icon: const Icon(Icons.open_in_new, size: 16),
            label: Text(context.tr('Open in browser')),
          ),
        ],
      ),
    );
  }
}
