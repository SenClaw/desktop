import 'package:url_launcher/url_launcher.dart';

/// A scheme the user or a page spelled out. The digit check keeps a bare
/// `example.com:8080` a host and port, and a scheme it lets through is only ever
/// http or https by the time [browserUrlFrom] returns.
final _explicitScheme =
    RegExp(r'^[a-z][a-z0-9+.-]*:(?!\d)', caseSensitive: false);

/// Ends at the host, so `localhost.evil.com` is not mistaken for this machine.
final _loopbackHost = RegExp(
    r'^(localhost|127\.0\.0\.1|0\.0\.0\.0|\[::1\])(?=[:/?#]|$)',
    caseSensitive: false);

/// The Browser pane loads, and hands to the OS, http and https and nothing
/// else. The URLs come from a person, from a page and from agent tool calls: a
/// `file:` or `javascript:` one reads local data, and on the OS side `ms-msdt:`,
/// `smb:` or `vscode:` start another program.
bool isWebUrl(Uri? url) =>
    url != null &&
    (url.isScheme('http') || url.isScheme('https')) &&
    url.host.isNotEmpty;

/// What [input] loads in the Browser pane, or null when the pane must not load
/// it. A bare `localhost:3000` becomes `http://…`, any other host `https://…`.
String? browserUrlFrom(String input) {
  final s = input.trim();
  if (s.isEmpty) return null;
  final parsed = Uri.tryParse(_explicitScheme.hasMatch(s)
      ? s
      : '${_loopbackHost.hasMatch(s) ? 'http' : 'https'}://$s');
  return isWebUrl(parsed) ? parsed.toString() : null;
}

/// Open [url] in the system browser if it is a web page; drop anything else.
Future<void> openWebUrlExternally(Uri? url) async {
  if (isWebUrl(url)) {
    await launchUrl(url!, mode: LaunchMode.externalApplication);
  }
}
