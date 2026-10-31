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
}
