import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../core/i18n/l10n.dart';
import '../theme/tokens.dart';

/// Whether a fenced block with **no language tag** is a mermaid diagram.
///
/// Models write the fence both ways. Asked for a diagram they often produce
/// ```mermaid, but just as often a bare ``` whose first line is
/// `flowchart TD` — and a renderer that only trusts the tag shows that as raw
/// text, which is the one form a diagram is useless in.
///
/// Matched on the first non-empty line against mermaid's own diagram
/// keywords, not on "does it look drawable": a bare fence of Python that
/// mentions a graph must stay code. The keyword has to open the block, which
/// no other language does.
const _mermaidHeaders = <String>[
  'flowchart',
  'graph',
  'sequenceDiagram',
  'classDiagram',
  'stateDiagram-v2',
  'stateDiagram',
  'erDiagram',
  'journey',
  'gantt',
  'pie',
  'gitGraph',
  'mindmap',
  'timeline',
  'quadrantChart',
  'requirementDiagram',
  'sankey-beta',
  'xychart-beta',
  'block-beta',
  'packet-beta',
  'architecture-beta',
  'radar-beta',
  'treemap-beta',
  'zenuml',
  'C4Context',
  'C4Container',
  'C4Component',
  'C4Dynamic',
  'C4Deployment',
];

final _mermaidHeaderRe =
    RegExp('^(?:${_mermaidHeaders.join('|')})\\b');

/// True when an untagged fence body opens with a mermaid diagram keyword.
bool looksLikeMermaid(String body) {
  final first = body
      .split('\n')
      .map((l) => l.trim())
      // A leading `%%{init: …}%%` directive is mermaid's own and legal above
      // the diagram keyword.
      .where((l) => l.isNotEmpty && !l.startsWith('%%'))
      .cast<String?>()
      .firstWhere((_) => true, orElse: () => null);
  return first != null && _mermaidHeaderRe.hasMatch(first);
}

/// The mermaid source of a fenced block, or null when it is not one.
String? mermaidSource(String lang, String body) {
  final code = body.endsWith('\n') ? body.substring(0, body.length - 1) : body;
  if (lang.trim().toLowerCase() == 'mermaid') return code;
  if (lang.trim().isNotEmpty) return null;
  return looksLikeMermaid(code) ? code : null;
}

/// A ```mermaid fence, drawn as a diagram.
///
/// There is no Dart mermaid renderer, so this hosts the real one in a small
/// webview over a bundled copy of mermaid.js — no daemon, no network. The page
/// lives in `assets/mermaid/`; see its comment for the contract.
///
/// Two things this widget exists to get right:
///
/// **The view has to be the height of the diagram.** A webview has no
/// intrinsic size, so a fixed box either crops a tall flowchart or leaves a
/// gap under a short one. The page measures its own SVG and reports back, and
/// that measurement is the widget's height.
///
/// **A diagram that will not parse must still show its source.** While a
/// reply is streaming the fence is incomplete and mermaid rightly refuses it;
/// that is indistinguishable, from here, from a model getting the syntax
/// wrong. Both show the code, which is never worse than the raw text the user
/// would have seen before this existed.
///
/// Linux has no embedded webview in this app, so there the source is all it
/// can show — stated, not silently degraded.
class MermaidDiagram extends StatefulWidget {
  const MermaidDiagram({super.key, required this.code});

  final String code;

  /// Forced value for [supported]. Null in production.
  ///
  /// A widget test cannot build an InAppWebView — the plugin has no platform
  /// implementation off-device — so this is how the source-fallback path and
  /// the fence routing are exercised without one.
  @visibleForTesting
  static bool? debugSupportedOverride;

  /// Whether this platform can draw the diagram at all.
  static bool get supported =>
      debugSupportedOverride ?? (Platform.isMacOS || Platform.isWindows);

  @override
  State<MermaidDiagram> createState() => _MermaidDiagramState();
}

/// Serves the renderer page out of the app's own assets over loopback.
///
/// `initialFile` does not load the page on macOS — nothing arrives, no error
/// is raised, and the view sits blank forever. This is the package's own
/// mechanism for local content and it makes the page's relative
/// `<script src="mermaid.min.js">` resolve exactly as it would on the web.
///
/// One server for every diagram in the app, started on the first one. It
/// binds 127.0.0.1 (the package's own choice) and serves nothing but the
/// bundled assets.
class _RendererHost {
  /// Well outside the ranges SenClaw's daemon and Space Apps use, so a
  /// diagram cannot collide with a port the product already owns.
  static const int port = 19765;

  static final InAppLocalhostServer _server =
      InAppLocalhostServer(port: port, shared: true);
  static Future<bool>? _starting;

  /// The page's URL once the server is up, or null when it could not start.
  static Future<String?> url() {
    _starting ??= _server.start().then((_) => true).catchError((Object e) {
      // A port already taken is the realistic failure. Reported, not
      // swallowed: without it the diagram is a blank box with no cause.
      debugPrint('[mermaid] renderer host failed to start on $port: $e');
      return false;
    });
    return _starting!.then(
        (ok) => ok ? 'http://127.0.0.1:$port/assets/mermaid/index.html' : null);
  }
}

class _MermaidDiagramState extends State<MermaidDiagram> {
  InAppWebViewController? _ctrl;

  /// Null until the renderer host is up; the webview is only built after.
  String? _pageUrl;

  /// Reported by the page once it has drawn. Null until then.
  ///
  /// A failed render reports a height too: the page shows the source and the
  /// parse error itself, so there is nothing for the Dart side to decide.
  double? _height;
  bool _ready = false;
  String? _renderedFor;

  /// The page never answered. Only then does Dart show the source itself.
  bool _timedOut = false;
  Timer? _deadline;

  /// Height to give the view before the page has measured itself.
  ///
  /// **Not ~0.** A webview sized to a pixel is not laid out by WebKit, so its
  /// JavaScript never runs, so it never reports a height — and a view whose
  /// height waits on that report stays a pixel tall forever. That deadlock is
  /// what made every diagram render as a hairline above its own source.
  static const double _provisionalHeight = 180;

  /// How long the page gets before Dart concludes it will not answer. Loading
  /// 5 MB of parser off disk is not instant on a cold start.
  static const Duration _answerDeadline = Duration(seconds: 12);

  @override
  void initState() {
    super.initState();
    if (!MermaidDiagram.supported) return;
    _armDeadline();
    _RendererHost.url().then((u) {
      if (mounted) setState(() => _pageUrl = u);
    });
  }

  void _armDeadline() {
    _deadline?.cancel();
    _deadline = Timer(_answerDeadline, () {
      if (!mounted || _height != null) return;
      // Say it in the log too: a silent hairline is impossible to diagnose
      // from a screenshot.
      debugPrint('[mermaid] page did not answer in ${_answerDeadline.inSeconds}s'
          ' — falling back to source');
      setState(() => _timedOut = true);
    });
  }

  @override
  void didUpdateWidget(covariant MermaidDiagram old) {
    super.didUpdateWidget(old);
    if (old.code != widget.code) _render();
  }

  /// Send the current source to the page. Cheap enough to call on every
  /// streamed update; the page replaces its own content each time.
  void _render() {
    final ctrl = _ctrl;
    if (ctrl == null || !_ready) return;
    final code = widget.code;
    if (code == _renderedFor) return;
    _renderedFor = code;
    debugPrint('[mermaid] rendering ${code.length} chars');
    final c = context.colors;
    final theme = Theme.of(context).brightness == Brightness.dark ? 'dark' : 'default';
    // jsonEncode, never string interpolation: the source is arbitrary text
    // with quotes and newlines in it, and concatenating it into a script is
    // both broken and an injection.
    // Wrapped in a void statement: `senclawRender` is async, and handing the
    // bridge a Promise logs "result of an unsupported type" on every render.
    ctrl.evaluateJavascript(
      source: 'void window.senclawRender('
          '${jsonEncode(code)},'
          '${jsonEncode(theme)},'
          '${jsonEncode('#${(c.textMuted.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}')}'
          ');',
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    if (!MermaidDiagram.supported) {
      return _SourceBlock(
        code: widget.code,
        note: context.tr('Diagrams need macOS or Windows to draw here.'),
      );
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: AppTokens.s6),
      decoration: BoxDecoration(
        color: c.surfaceAlt,
        borderRadius: BorderRadius.circular(AppTokens.rSm),
        border: Border.all(color: c.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // Given a real height from the start: see [_provisionalHeight] for
          // why a placeholder-sized view can never report back.
          SizedBox(
            height: _height ?? _provisionalHeight,
            child: _pageUrl == null
                ? const SizedBox.shrink()
                : InAppWebView(
              initialUrlRequest: URLRequest(url: WebUri(_pageUrl!)),
              initialSettings: InAppWebViewSettings(
                transparentBackground: true,
                // A local page with a local script: no navigation anywhere.
                useShouldOverrideUrlLoading: true,
                disableVerticalScroll: true,
                disableHorizontalScroll: false,
                supportZoom: false,
              ),
              onWebViewCreated: (ctrl) {
                _ctrl = ctrl;
                ctrl.addJavaScriptHandler(
                  handlerName: 'senclawMermaidReady',
                  callback: (_) {
                    _ready = true;
                    _render();
                    return null;
                  },
                );
                ctrl.addJavaScriptHandler(
                  handlerName: 'senclawMermaid',
                  callback: (args) {
                    final m = args.isNotEmpty && args.first is Map
                        ? (args.first as Map).cast<String, dynamic>()
                        : const <String, dynamic>{};
                    final h = (m['height'] as num?)?.toDouble() ?? 0;
                    debugPrint('[mermaid] reported ok=${m['ok']} h=$h '
                        'err=${m['error']}');
                    if (!mounted) return null;
                    _deadline?.cancel();
                    setState(() {
                      _timedOut = false;
                      // A hard ceiling: a runaway graph must not take over the
                      // whole conversation.
                      _height = h.clamp(24, 1400);
                    });
                    return null;
                  },
                );
              },
              // A webview that fails quietly is the whole difficulty here: the
              // panel just keeps showing source and nothing says why. These
              // three surface the cause in the app log.
              onConsoleMessage: (_, msg) => debugPrint(
                  '[mermaid] console ${msg.messageLevel}: ${msg.message}'),
              onReceivedError: (_, req, err) => debugPrint(
                  '[mermaid] load error ${req.url}: ${err.description}'),
              onReceivedHttpError: (_, req, res) => debugPrint(
                  '[mermaid] http error ${req.url}: ${res.statusCode}'),
              onLoadStop: (ctrl, _) {
                // Belt and braces: some builds deliver the handler call before
                // Dart has attached, so ask again once the page has settled.
                debugPrint('[mermaid] page loaded');
                _ready = true;
                _render();
              },
              // The page is local and self-contained; nothing may navigate it.
              shouldOverrideUrlLoading: (_, action) async {
                // The page is served from our own loopback root; nothing may
                // navigate it anywhere else.
                final u = action.request.url?.toString() ?? '';
                if (action.isForMainFrame != true) {
                  return NavigationActionPolicy.ALLOW;
                }
                return u == _pageUrl
                    ? NavigationActionPolicy.ALLOW
                    : NavigationActionPolicy.CANCEL;
              },
            ),
          ),
          // Only when the page never answered. A block that is merely
          // unparsable — still streaming, or wrong syntax — is shown as
          // source *by the page*, together with the reason, so duplicating
          // it here would stack two copies.
          if (_timedOut && _height == null)
            Positioned.fill(
              child: ColoredBox(
                color: c.surfaceAlt,
                child: _SourceBlock(
                  code: widget.code,
                  note: context.tr('The diagram renderer did not respond.'),
                  bare: true,
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _deadline?.cancel();
    _ctrl = null;
    super.dispose();
  }
}

/// The fence as plain code — the fallback everywhere a diagram cannot be drawn.
class _SourceBlock extends StatelessWidget {
  const _SourceBlock({required this.code, this.note, this.bare = false});

  final String code;
  final String? note;
  /// Inside an already-decorated container (no border or margin of its own).
  final bool bare;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Text(
            code,
            style: TextStyle(
              fontFamily: AppTokens.fontMono,
              fontSize: 12,
              height: 1.45,
              color: c.textPrimary,
            ),
          ),
        ),
        if (note != null) ...[
          const SizedBox(height: AppTokens.s6),
          Text(note!, style: TextStyle(fontSize: 11, color: c.textMuted)),
        ],
      ],
    );

    if (bare) {
      return Padding(padding: const EdgeInsets.all(AppTokens.s12), child: body);
    }
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: AppTokens.s6),
      padding: const EdgeInsets.all(AppTokens.s12),
      decoration: BoxDecoration(
        color: c.surfaceAlt,
        borderRadius: BorderRadius.circular(AppTokens.rSm),
        border: Border.all(color: c.border),
      ),
      child: body,
    );
  }
}
