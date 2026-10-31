// Cross-platform embedded web content.
//
//  • Web build        → a real <iframe> via HtmlElementView (embedded_web_web.dart).
//  • macOS / Windows  → an in-app WKWebView/WebView2 via flutter_inappwebview
//    (embedded_web_stub.dart), origin-pinned for Space Apps and widgets. The
//    free-navigation Browser pane is lib/widgets/browser_web_view.dart.
//  • Linux            → an "Open in browser" card (no embedded webview there).
export 'embedded_web_stub.dart'
    if (dart.library.js_interop) 'embedded_web_web.dart';
