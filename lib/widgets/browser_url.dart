import 'dart:io' show InternetAddress;

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

/// What a Space App, a widget or a chat link may hand to the OS: web pages, plus
/// the two schemes that only start a draft a person still has to send.
bool isExternalLink(Uri? url) =>
    isWebUrl(url) ||
    (url != null && (url.isScheme('mailto') || url.isScheme('tel')));

/// [url] is served from this machine. A page there passes the daemon's
/// local-Origin check and can read its provider keys, so the Browser pane opens
/// one only from a person's click. A host written as a bare number (`127.1`,
/// `2130706433`) counts too: the engine resolves it to the same place.
bool isLoopbackUrl(String url) {
  // As the pane would load it: a bare `localhost:5173` has no host until then.
  final host = Uri.tryParse(browserUrlFrom(url) ?? url)?.host.toLowerCase() ?? '';
  if (host == 'localhost') return true;
  final ip = InternetAddress.tryParse(host);
  if (ip != null) return ip.isLoopback || host == '0.0.0.0';
  return RegExp(r'^(0x)?[0-9a-f.x]+$').hasMatch(host) &&
      RegExp(r'^[0-9]|^0x').hasMatch(host);
}

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

/// Open [url] with the OS if it is an [isExternalLink]; drop anything else.
Future<void> openLinkExternally(Uri? url) async {
  if (isExternalLink(url)) {
    await launchUrl(url!, mode: LaunchMode.externalApplication);
  }
}

/// Open [url] in the system browser if it is a web page; drop anything else.
Future<void> openWebUrlExternally(Uri? url) async {
  if (isWebUrl(url)) {
    await launchUrl(url!, mode: LaunchMode.externalApplication);
  }
}
