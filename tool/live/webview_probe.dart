// A live check of the Browser pane's webview on this Mac: real WKWebView, no
// mouse and no one watching. The page does the unsafe things itself, and the
// result is what happened to it, written to PROBE_OUT, plus the test server's
// own log. See the page in PROBE_URL: on load it tries a popup with no click and
// a jump to an unknown scheme, then follows a plain link.
//
//   flutter build macos --debug -t tool/live/webview_probe.dart
//   open -n "build/macos/Build/Products/Debug/SenClaw Desktop.app" \
//     --env PROBE_URL=http://127.0.0.1:<port>/ --env PROBE_OUT=<file>
//
// It talks to no daemon and leaves when it has its answer. Not part of
// `flutter test`, which has no webview.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:senclaw_desktop/widgets/browser_web_view.dart';
import 'package:senclaw_desktop/widgets/embedded_web.dart';

void main() => runApp(const _Probe());

class _Probe extends StatefulWidget {
  const _Probe();
  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  final _url = Platform.environment['PROBE_URL'] ?? '';
  final _seen = <String>[];
  BrowserNavState _nav = const BrowserNavState();

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(const Duration(seconds: 12), () {
      File(Platform.environment['PROBE_OUT']!).writeAsStringSync(jsonEncode({
        'finalUrl': _nav.url,
        'title': _nav.title,
        'urls': _seen,
      }));
      exit(0);
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Row(
          children: [
            Expanded(
              child: BrowserWebView(
                initialUrl: _url,
                onStateChanged: (s) {
                  _nav = s;
                  if (s.url.isNotEmpty && !_seen.contains(s.url)) _seen.add(s.url);
                },
              ),
            ),
            Expanded(
              child: EmbeddedHtmlContent(
                html: '<img src="${_url}preview-ping.png">',
                baseUrl: 'file:///tmp/',
              ),
            ),
            Expanded(child: embeddedWebView('${_url}embed.html')),
          ],
        ),
      ),
    );
  }
}
