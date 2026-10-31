import 'package:flutter_test/flutter_test.dart';
import 'package:senclaw_desktop/widgets/browser_url.dart';

void main() {
  group('browserUrlFrom', () {
    test('adds a scheme to a bare host', () {
      expect(browserUrlFrom('example.com'), 'https://example.com');
      expect(browserUrlFrom('example.com:8080/a'), 'https://example.com:8080/a');
      expect(browserUrlFrom('  example.com/a?b=1  '), 'https://example.com/a?b=1');
    });

    test('a loopback host stays http, and only a real one does', () {
      expect(browserUrlFrom('localhost:3000'), 'http://localhost:3000');
      expect(browserUrlFrom('127.0.0.1:5173/x'), 'http://127.0.0.1:5173/x');
      expect(browserUrlFrom('[::1]:8080'), 'http://[::1]:8080');
      expect(browserUrlFrom('localhost.evil.com'), 'https://localhost.evil.com');
      expect(browserUrlFrom('127.0.0.1.evil.com'), 'https://127.0.0.1.evil.com');
    });

    test('keeps http and https as given', () {
      expect(browserUrlFrom('http://example.com/'), 'http://example.com/');
      expect(browserUrlFrom('HTTPS://example.com/'), startsWith('https://'));
    });

    test('a :// inside a query is not a scheme', () {
      expect(browserUrlFrom('example.com/?next=http://a.b'),
          'https://example.com/?next=http://a.b');
    });

    test('refuses every other scheme, however it is written', () {
      for (final bad in const [
        'javascript:alert(1)',
        'JavaScript:alert(1)',
        'javascript://%0aalert(1)',
        '  javascript:alert(1)',
        'file:///etc/passwd',
        'file://server/x.exe',
        'data:text/html,<script>1</script>',
        'about:blank',
        'blob:http://a.b/1',
        'ms-msdt:/id',
        'search-ms:query=x',
        'smb://attacker/x',
        'vscode://file/x',
        'ssh://host',
      ]) {
        expect(browserUrlFrom(bad), isNull, reason: bad);
      }
    });

    test('refuses what has no host, and empty input', () {
      expect(browserUrlFrom(''), isNull);
      expect(browserUrlFrom('   '), isNull);
      expect(browserUrlFrom('http://'), isNull);
      expect(browserUrlFrom('//'), isNull);
    });
  });

  test('isWebUrl lets only http and https out to the OS', () {
    expect(isWebUrl(Uri.parse('https://example.com')), isTrue);
    expect(isWebUrl(Uri.parse('http://127.0.0.1:3000')), isTrue);
    expect(isWebUrl(null), isFalse);
    for (final bad in const [
      'ms-msdt:/id',
      'smb://attacker/x',
      'file:///Applications/x.app',
      'javascript:alert(1)',
      'vscode://file/x',
    ]) {
      expect(isWebUrl(Uri.parse(bad)), isFalse, reason: bad);
    }
  });

  test('isExternalLink adds only mailto and tel to the web', () {
    expect(isExternalLink(Uri.parse('https://example.com')), isTrue);
    expect(isExternalLink(Uri.parse('mailto:a@b.c')), isTrue);
    expect(isExternalLink(Uri.parse('tel:+84123')), isTrue);
    expect(isExternalLink(null), isFalse);
    for (final bad in const ['ms-msdt:/id', 'smb://a/x', 'file:///x', 'vscode://f']) {
      expect(isExternalLink(Uri.parse(bad)), isFalse, reason: bad);
    }
  });

  test('isLoopbackUrl covers every spelling of this machine', () {
    for (final local in const [
      'http://localhost:3000/',
      'http://LOCALHOST:3000/',
      'http://127.0.0.1:5173/',
      'http://127.8.8.8/',
      'http://0.0.0.0:8080/',
      'http://[::1]:8080/',
      'http://127.1:3000/',
      'http://2130706433/',
      'http://0x7f.0.0.1/',
    ]) {
      expect(isLoopbackUrl(local), isTrue, reason: local);
    }
    for (final remote in const [
      'https://example.com/',
      'https://localhost.evil.com/',
      'https://127.0.0.1.evil.com/',
      'http://8.8.8.8/',
      'https://cafe.example/',
    ]) {
      expect(isLoopbackUrl(remote), isFalse, reason: remote);
    }
  });
}
