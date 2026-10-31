import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/i18n/l10n.dart';
import '../theme/tokens.dart';

/// Live navigation state reported up to the browser chrome (address bar, nav
/// buttons) so it can reflect the current page.
class BrowserNavState {
  const BrowserNavState({
    this.url = '',
    this.title = '',
    this.isLoading = false,
    this.progress = 0,
    this.canGoBack = false,
    this.canGoForward = false,
  });
  final String url;
  final String title;
  final bool isLoading;
  final double progress; // 0..1
  final bool canGoBack;
  final bool canGoForward;

  BrowserNavState copyWith({
    String? url,
    String? title,
    bool? isLoading,
    double? progress,
    bool? canGoBack,
    bool? canGoForward,
  }) =>
      BrowserNavState(
        url: url ?? this.url,
        title: title ?? this.title,
        isLoading: isLoading ?? this.isLoading,
        progress: progress ?? this.progress,
        canGoBack: canGoBack ?? this.canGoBack,
        canGoForward: canGoForward ?? this.canGoForward,
      );
}

/// Imperative handle the chrome uses to drive the page. Wraps the webview
/// controller so the chrome never touches `flutter_inappwebview` directly.
class BrowserWebController {
  BrowserWebController._(this._c);
  final InAppWebViewController _c;

  Future<void> loadUrl(String url) =>
      _c.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
  Future<void> goBack() => _c.goBack();
  Future<void> goForward() => _c.goForward();
  Future<void> reload() => _c.reload();
  Future<void> stop() => _c.stopLoading();
}

/// A **free-navigation** embedded browser view — a real WKWebView/WebView2 on
/// macOS & Windows that the user can navigate anywhere. This is deliberately
/// NOT [embeddedWebView], which pins a Space App/widget to its own origin and
/// kicks every cross-origin navigation out to the system browser; a browser
/// pane must do the opposite and follow links in place. Linux (no embedded
/// webview) falls back to an "open in browser" card.
class BrowserWebView extends StatefulWidget {
  const BrowserWebView({
    super.key,
    required this.initialUrl,
    this.onStateChanged,
    this.onControllerReady,
    this.instanceKey,
  });
  final String initialUrl;
  final void Function(BrowserNavState)? onStateChanged;
  final void Function(BrowserWebController)? onControllerReady;

  /// Distinguishes two webviews that would otherwise share a key (e.g. the same
  /// URL in two chats). Changing it rebuilds the underlying webview.
  final String? instanceKey;

  /// Whether this platform can host the embedded browser at all.
  static bool get supported => Platform.isMacOS || Platform.isWindows;

  @override
  State<BrowserWebView> createState() => _BrowserWebViewState();
}

class _BrowserWebViewState extends State<BrowserWebView> {
  InAppWebViewController? _ctrl;
  BrowserNavState _state = const BrowserNavState();

  void _emit(BrowserNavState next) {
    _state = next;
    widget.onStateChanged?.call(next);
  }

  Future<void> _refreshNavFlags() async {
    final c = _ctrl;
    if (c == null) return;
    final back = await c.canGoBack();
    final fwd = await c.canGoForward();
    if (!mounted) return;
    _emit(_state.copyWith(canGoBack: back, canGoForward: fwd));
  }

  @override
  Widget build(BuildContext context) {
    if (!BrowserWebView.supported) {
      return _OpenInBrowserFallback(url: widget.initialUrl);
    }
    return InAppWebView(
      key: ValueKey('${widget.instanceKey ?? ''}-${widget.initialUrl}'),
      initialUrlRequest: URLRequest(url: WebUri(widget.initialUrl)),
      initialSettings: InAppWebViewSettings(
        transparentBackground: true,
        // Let the page open popups; onCreateWindow sends them to a real tab
        // inside the pane's host is out of scope, so route to the OS browser.
        javaScriptCanOpenWindowsAutomatically: true,
        supportMultipleWindows: true,
      ),
      onWebViewCreated: (c) {
        _ctrl = c;
        widget.onControllerReady?.call(BrowserWebController._(c));
      },
      onLoadStart: (c, url) {
        _emit(_state.copyWith(
            url: url?.toString() ?? _state.url, isLoading: true, progress: 0));
      },
      onLoadStop: (c, url) async {
        _emit(_state.copyWith(
            url: url?.toString() ?? _state.url, isLoading: false, progress: 1));
        await _refreshNavFlags();
      },
      onReceivedError: (c, req, err) {
        if (req.isForMainFrame ?? false) {
          _emit(_state.copyWith(isLoading: false));
        }
      },
      onProgressChanged: (c, p) {
        _emit(_state.copyWith(
            progress: p / 100.0, isLoading: p < 100));
      },
      onTitleChanged: (c, title) {
        if (title != null && title.isNotEmpty) {
          _emit(_state.copyWith(title: title));
        }
      },
      onUpdateVisitedHistory: (c, url, isReload) async {
        if (url != null) _emit(_state.copyWith(url: url.toString()));
        await _refreshNavFlags();
      },
      // A browser follows links in place; only window.open / target=_blank
      // popups (which would be a broken in-webview window) go to the OS browser.
      onCreateWindow: (controller, createWindowAction) async {
        final url = createWindowAction.request.url;
        if (url != null) {
          await launchUrl(url, mode: LaunchMode.externalApplication);
        }
        return false;
      },
    );
  }
}

/// Linux (and anywhere without an embedded webview): offer to open externally.
class _OpenInBrowserFallback extends StatelessWidget {
  const _OpenInBrowserFallback({required this.url});
  final String url;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.public, size: 40, color: c.textMuted),
          const SizedBox(height: AppTokens.s12),
          Text(context.tr('Web content'),
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
            onPressed: () => launchUrl(Uri.parse(url),
                mode: LaunchMode.externalApplication),
            icon: const Icon(Icons.open_in_new, size: 16),
            label: Text(context.tr('Open in browser')),
          ),
        ],
      ),
    );
  }
}

/// Renders a single HTML document's CONTENT (not a URL) — used by the file pane
/// to show a `.html` file rendered instead of as source. macOS/Windows only;
/// callers gate on [BrowserWebView.supported] and keep the source view
/// elsewhere. WKWebView grants no sibling-asset read access from `loadData`, so
/// multi-file pages still won't pull in local css/js — same limit as the web
/// client's srcdoc.
class EmbeddedHtmlContent extends StatelessWidget {
  const EmbeddedHtmlContent({super.key, required this.html, this.baseUrl});
  final String html;
  final String? baseUrl;

  @override
  Widget build(BuildContext context) {
    if (!BrowserWebView.supported) return const SizedBox.shrink();
    return InAppWebView(
      initialData: InAppWebViewInitialData(
        data: html,
        mimeType: 'text/html',
        encoding: 'utf8',
        baseUrl: baseUrl != null ? WebUri(baseUrl!) : null,
      ),
      initialSettings: InAppWebViewSettings(transparentBackground: true),
      // A preview, not a browser: a link the page follows opens in the OS
      // browser rather than navigating the preview away.
      onCreateWindow: (controller, action) async {
        final url = action.request.url;
        if (url != null) {
          await launchUrl(url, mode: LaunchMode.externalApplication);
        }
        return false;
      },
    );
  }
}
